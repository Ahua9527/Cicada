# Cicada GUI 实施计划

> 架构师：高见远（Gao）｜交付总监：齐活林
> 基础文档：`docs/Design.md`（SwiftUI 设计规范）、`design-previews/2026-07-15-cicada-redesign/index.html`（高保真预览）
> 代码基线：`apps/agent/swift/`（SwiftPM 后端包）、`apps/agent/native/sentinel-app/`（现有 Xcode 原生应用）
> 产出日期：2026-07-15

---

## 0. 关键发现（必读前置）

在深入探查后，我发现一个**对实施路径有决定性影响的事实**，需在展开六方面计划前首先声明：

### 0.1 现有原生 GUI 已存在

`apps/agent/native/sentinel-app/Sentry/` 是一个**已存在的 Xcode SwiftUI 应用**（前身为开源 Sentry，MIT，作者 Lakr233，现品牌化为 Cicada），并非空白。它已经实现了 Design.md 描述的**绝大部分功能**，只是视觉与架构是"旧版"：

| Design.md 章节 | 现有原生应用对应文件 | 实现状态 |
|---|---|---|
| §1 架构总览 / Scene | `App.swift`（WindowGroup + MenuBarExtra） | 已有，但用 `@NSApplicationDelegateAdaptor`，非纯 SwiftUI 状态分层 |
| §3 控制中心双栏 | `SentryControlCenterView.swift`（NavigationSplitView + overview/settings/maintenance 三 Pane） | 已有，但用 `GroupBox` + 系统语义色，**非设计令牌** |
| §5 警戒全屏 | `SentryView.swift` + `EyeView.swift` + `Sentry.swift`（AlarmEngine） | 已有，但用 `ColorfulView(.sunset)`（ColorfulX 第三方）+ `SkyLightWindow`（第三方 NSWindow） |
| §6 NotchDrop | `NotchDrop/`（25 个文件，含 NotchWindowController/NotchViewModel/TrayDrop/AirDrop） | 已有，但重度 AppKit（NSWindow/NSViewController） |
| §7 菜单栏下拉 | `SentinelMenuBarView.swift` | 已有，极简 |
| §8 帮助面板 | `HelpPanelView.swift` | 已有 |
| §9 数据模型 | `SentryConfigurationManager`（`@PublishedPersist` → UserDefaults）+ `SentinelController` + `ViewModel` | 已有，但配置模型是 `SentryConfiguration`，**与 SwiftPM 的 `CicadaConfig` 不统一** |
| §11 设置页 5 Tab | `SentrySettingsPane`（Connection/Protection/Alerts/Recording/NotchDrop） | 已有，GroupBox 风格 |
| §12 维护页 | `SentryMaintenancePane`（Runtime/Folders/SleepHold/Diagnostics） | 已有 |
| §2 设计令牌 | ❌ 无 | **完全待实现**（现有用系统色 + GroupBox） |
| §4 组件规范（14 个） | ❌ 无自定义组件 | **完全待实现** |
| §10 动画/reduceMotion | `EyeView` 有旋转/脉动，**无 reduceMotion 兜底** | 需补 |

### 0.2 现有原生应用的技术栈与 Design.md 约束冲突点

| 维度 | 现有原生应用 | Design.md 约束（§13） |
|---|---|---|
| 窗口层级 | `SkyLightWindow` 第三方库 + `NSWindowController` | 仅允许 `WindowAccessor` 取 `NSWindow` 设 level，不承载视图 |
| sunset 渐变 | `ColorfulView(color: .sunset)`（ColorfulX） | 自绘 `SunsetGradient`（LinearGradient + RadialGradient） |
| 配置存储 | `SentryConfiguration` → UserDefaults（`@PublishedPersist`） | 复用 `CicadaCore.ConfigStore` → `~/.cicada/config.json` |
| 状态分层 | `SentinelController.shared` 单例 + `ViewModel.shared` + `SentryConfigurationManager.shared` | `AppModel` 聚合 `SentinelsModel/ConfigModel/SleepHoldModel/AlarmModel` |
| AppKit 依赖 | 重度（NSWindow/NSView/NSViewController/NSAnimationContext） | "无 UIKit/AppKit 视图内容" |
| 第三方依赖 | SkyLightWindow、ColorfulX、Pow、LaunchAtLogin、MSDisplayLink | Design.md 未声明依赖，倾向纯 SwiftUI |
| 部署目标 | macOS 13（README） | macOS 13 对齐，14+ 组件 `@available` 分支 |

### 0.3 SwiftPM 后端包与原生应用的关系

`apps/agent/swift/` 的模块**被原生应用部分复用**，但存在并行/重叠：

| SwiftPM 模块 | 原生应用是否使用 | 说明 |
|---|---|---|
| `CicadaCore`（ConfigStore/Models/RuntimePaths） | 原生应用有**独立的** `CicadaRelayConfigStore.swift`、`CicadaSentinelPaths.swift`，部分重叠 | 未直接依赖 SwiftPM 包 |
| `CicadaIPC`（UdsSentinelControlClient/UdsNotifier） | 原生应用有**独立的** `SentinelIPC.swift`、`SentinelNotifierServer.swift` | 并行实现 |
| `CicadaSystem` | 未使用 | — |
| `CicadaSleepHoldCore` | 原生应用有**独立的** `SleepHoldServiceClient.swift` | 并行实现 |

> **结论**：原生应用（Xcode）与 SwiftPM 后端包目前是**两套并行代码**，存在重复。Design.md 的"复用 `CicadaCore.ConfigStore` / `UdsSentinelControlClient`"愿景，意味着新 GUI 应拉近与 SwiftPM 后端的距离，而非继续沿用原生应用的独立实现。

### 0.4 命名冲突警示

`RuntimePaths.sentinelAppName = "Cicada.app"`，`sentinelAppPath = /Applications/Cicada.app`。Design.md 也称新 GUI 为 `Cicada.app`。两者指的**可能是同一个 app**（即原生应用就是 GUI 宿主），也可能被解读为两个独立 app。这一点必须在动工前与主理人确认（见 §C 决策 D-1）。

---

## A. 现有设计内容的评估与总结

### A.1 Design.md 完整性评估

| 维度 | 评分 | 说明 |
|---|---|---|
| 视觉规范完整性 | ★★★★★ | 21 个 Color Set + 字体 token + `DesignMetrics` 间距/圆角/阴影，覆盖全面，可直接落地 |
| 组件规范 | ★★★★☆ | 14 个组件均有代码骨架，强可落地；扣分点：§4.7 `GhostButtonStyle` 存在 typo（`.cicadaTextSecondaryondary`，应为 `.cicadaTextSecondary`） |
| 架构清晰度 | ★★★★☆ | Scene 三类 + 状态四子模型 + IPC 桥接方案明确；扣分点：未充分说明与现有原生应用引擎层（相机/报警/NotchDrop 引擎）的关系 |
| 数据模型对齐 | ★★★☆☆ | §9.1 假设 `ReadinessItem/Diagnostic` 展示模型，但与实际 `SentinelStatusSnapshot` 字段不直接对应，需映射层；§12 假设 `config.draft.autoConnectAtLogin` 字段不存在于 `CicadaConfig` |
| 落地清单 | ★★★★☆ | 13 步顺序合理，但未标注与现有原生代码的整合路径 |
| 约束声明 | ★★★★★ | §13 边界清晰，AppKit 例外（WindowAccessor）说明得当 |

### A.2 强项

1. **设计令牌系统化**：颜色全部走 Asset Catalog Color Set（支持 Light/Dark），`cicadaXxx` 别名避免与系统语义色冲突，`.tint(.cicadaAccent)` 统一控件色调——工程友好度高。
2. **纯 SwiftUI 倾向**：明确禁用 UIKit/AppKit 视图内容、Storyboard、Combine 驱动，降低长期维护成本。
3. **IPC 桥接方案**：`Task.detached` 包装同步阻塞 UDS client → `@MainActor` `@Published`，是现有同步 IPC 与 SwiftUI 异步世界的正确桥接。
4. **无障碍兜底**：§10.1 `reduceMotion` 分支 + VoiceOver `accessibilityLabel`，符合 macOS 应用规范。
5. **窗口策略务实**：§1.1 明确 NotchDrop/警戒可用 `WindowAccessor` 设 `NSWindow.level`，保留贴合度，不算违规。

### A.3 弱项

1. **与现有代码的整合路径缺失**：Design.md 通篇假设"全新 SwiftUI App"，未提及 `apps/agent/native/sentinel-app/` 已有的引擎代码（相机录制 `CameraSessionController`、报警引擎 `AlarmEngine`/`Sentry`、监控运行时 `SentryMonitorRuntime`、NotchDrop 文件引擎 `TrayDrop`）。这些引擎逻辑在新 GUI 中必须存在，否则功能空心化。
2. **配置 schema 不对应**：§12 用 `autoConnectAtLogin`，实际 `CicadaConfig` 只有 `autoConnect`；§11 ProtectionCard 的合盖/断网/断电 Toggle 绑定的是 `SentryConfiguration.sentryTriggersLidEnabled` 等字段，**不在 `CicadaConfig` 内**——要么扩展 `CicadaConfig`，要么保留 `SentryConfiguration` 并明确两者边界。
3. **警戒触发通道未澄清**：§1.1 说"daemon 通过 IPC 通知 App 后 App 调 `openWindow`"，但现有 IPC 全是请求-响应式 UDS，**无 daemon→App 主动推送通道**。实际警戒触发在原生应用内由 `SentryMonitorRuntime` 的 `onAlarm` 回调驱动（同进程），不跨 IPC。
4. **macOS 13/14 兼容细节零散**：`tracking()`、`NavigationSplitView` 侧栏宽度记忆等 14+ API 散落各处，缺统一兼容策略表。
5. **typo**：§4.7 `.cicadaTextSecondaryondary`。

### A.4 设计与现有后端契合度

| Design.md 假设 | 现有代码实况 | 契合度 |
|---|---|---|
| 复用 `CicadaCore.ConfigStore` | `ConfigStore` 已实现 load/save/validate，`CicadaConfig` 已 Codable | ★★★★☆ 可直接复用，但字段需扩展（见 C-6） |
| 复用 `UdsSentinelControlClient` | 已实现，同步阻塞，`status()/start()/stop()/unlock()/open()` | ★★★★★ 直接复用 + `Task.detached` 包装 |
| `SentinelStatusSnapshot` → readiness 展示 | 实际字段：`state/activityHint/recordingEnabled/sleepHoldActive/sleepHoldSessionId` | ★★★☆☆ 需 `toReadiness` 映射层 |
| daemon→App 警戒推送 | 无推送通道，现有是同进程 `SentryMonitorRuntime.onAlarm` | ★★☆☆☆ 需新建通道或保持同进程 |
| `BarkClient`（HTTP） | 原生应用 `Sentry.swift` 已有 `defaultBarkRequestSender`（URLSession dataTask） | ★★★★☆ 可参考移植 |
| SleepHold IPC | `CicadaSleepHoldCore.SleepHoldControlClient` + 原生 `SleepHoldServiceClient` 并行 | ★★★☆☆ 需统一到 SwiftPM 版本 |

---

## B. 已实现部分与待实现部分识别

### B.1 按设计章节对照表

| Design.md 章节 | 现有实现状态 | 现有实现位置 | 差距说明 |
|---|---|---|---|
| §1.1 Scene 结构 | 🟡 部分 | `native/.../App.swift` | 现有用 `@NSApplicationDelegateAdaptor`，无独立 `AppModel`；警戒用 SkyLightWindow 而非 `WindowGroup(id:"alarm")` |
| §1.2 状态分层 | 🔴 待实现 | — | 无 `AppModel/SentinelsModel/ConfigModel/SleepHoldModel/AlarmModel` 分层 |
| §2 设计令牌 | 🔴 待实现 | — | 无 Assets.xcassets Color Set、无 `DesignMetrics`、无 `Color.cicadaXxx` |
| §3.1 ControlCenterRoot | 🟡 部分 | `SentryControlCenterView.swift` | NavigationSplitView 已有，但 `NavRow` 样式、`PaneHeader` 不符合设计 |
| §3.2 OverviewPane | 🟡 部分 | `SentryOverviewPane` | 有 Hero/Readiness/diagnostics，但用 GroupBox，非 `StatusHeroCard/ReadinessCard/DiagnosticStrip` |
| §4.1 StatusHeroCard | 🔴 待实现 | — | — |
| §4.2 ReadinessCard + ProgressRing | 🔴 待实现 | — | 现有无进度环 |
| §4.3 DiagnosticStrip | 🟡 部分 | 现有用 `Label` + `.orange` | 非自定义琥珀条 |
| §4.4 Card / CardHeader | 🔴 待实现 | — | 现有用 GroupBox 替代 |
| §4.5 SettingRow | 🔴 待实现 | — | 现有用 `LabeledContent`/`Toggle` 直排 |
| §4.6 Toggle | 🟢 可直接用系统 | — | 加 `.tint(.cicadaAccent)` 即可 |
| §4.7 ButtonStyle ×4 | 🔴 待实现 | — | — |
| §4.8 CicadaTextField | 🔴 待实现 | — | 现有用 `.roundedBorder` 系统样式 |
| §4.9 Picker | 🟢 系统够用 | — | `.pickerStyle(.menu)` |
| §4.10 InlineMessage | 🔴 待实现 | — | 现有用 `Text` + `.foregroundStyle` |
| §4.11 FolderGridButton | 🔴 待实现 | — | 现有维护页是纵向 Button 列表 |
| §4.12 SleepHoldCell | 🔴 待实现 | — | 现有用 `SentryStatusRow` |
| §4.13 VersionTag | 🟡 部分 | 现有有 `versionText` | 样式不符（非 mono + 分割线） |
| §4.14 CameraPreview | 🟡 部分 | `SentryRecordingSettingsSection` 的 `CameraPreviewView` | 有相机预览，未授权占位样式不符 |
| §5 AlarmOverlay | 🟡 部分 | `SentryView.swift` + `EyeView.swift` | sunset 用 ColorfulX（需替换为自绘）；eye 有旋转/脉动但**无 reduceMotion**；窗口用 SkyLightWindow（需换 SwiftUI WindowGroup） |
| §5.2 AlarmEye Canvas | 🟡 部分 | `EyeView.swift` 用 `ForEach` + `Rectangle` 旋转 | Design.md 建议 `Canvas` 画 36 条径向线（性能更好） |
| §6 NotchPanel | 🟡 部分 | `NotchDrop/NotchContentView.swift` 等 | UI 重度 AppKit，需 SwiftUI 重写；引擎 `TrayDrop`/`AirDrop` 可保留 |
| §6.2 NotchMenu | 🟡 部分 | `NotchDrop/NotchMenuView.swift` | 同上 |
| §7 MenuBarDropdown | 🟡 部分 | `SentinelMenuBarView.swift` | 极简，需扩展为 `MenuBarStatusCard` + 按钮列表 |
| §8 HelpSheet | 🟡 部分 | `HelpPanelView.swift` | 样式不符设计 |
| §9.1 展示模型 | 🔴 待实现 | — | 需新增 `ReadinessItem/Diagnostic/SleepHoldCellData/FolderAction` |
| §9.2 ViewModel | 🟡 部分 | `SentryConfigurationManager`/`SentinelController`/`ViewModel` | 存在但分层不符，且配置源是 UserDefaults 而非 ConfigStore |
| §9.3 IPC async wrapper | 🔴 待实现 | — | 需为 `UdsSentinelControlClient` 加 `statusAsync()` 等扩展 |
| §9.3 BarkClient | 🟡 部分 | `Sentry.swift` 的 `defaultBarkRequestSender` | 需封装为独立 `BarkClient` struct |
| §10 动画 | 🟡 部分 | `EyeView` 有动画 | 缺 reduceMotion 兜底、缺进场/hover 动画规范 |
| §11 SettingsPane + 5 Card | 🟡 部分 | `SentrySettingsPane` + 5 section | 功能齐备，视觉与组件需重写 |
| §12 MaintenancePane | 🟡 部分 | `SentryMaintenancePane` | 功能齐备，视觉与组件需重写 |
| §13 约束 | — | — | 需在重构中遵守 |

### B.2 三类分类汇总

**🟢 后端就绪可直接复用（SwiftPM 包）**：
- `CicadaCore.ConfigStore` / `CicadaConfig` / `RuntimePaths`
- `CicadaIPC.UdsSentinelControlClient` / `SentinelControlClienting` / `SentinelStatusSnapshot`
- `CicadaIPC.UdsDaemonControlClient` / `DaemonControlResponse`
- `CicadaSleepHoldCore.SleepHoldControlClient` / `SleepHoldControlResponse`
- `CicadaSystem.SleepHoldServiceManager` / `SentinelAppManager`（进程管理）

**🟡 需要扩展或重构（现有原生应用，引擎层保留 + UI 层重写）**：
- 引擎层（保留）：`AlarmEngine`（音频设备/音量）、`CameraSessionController`（相机录制）、`SentryMonitorRuntime`（lid/network/power 触发检测）、`Sentry`（报警状态机）、`TrayDrop`/`AirDrop`（NotchDrop 文件引擎）、`DeviceCheck`（锁屏检测）
- UI 层（重写）：`SentryControlCenterView`、`SentryView`、`EyeView`、`SentinelMenuBarView`、`HelpPanelView`、`NotchDrop/*View`、`ContentView`、`FormView`
- 窗口层（重构）：`NotchWindowController` → SwiftUI Window + WindowAccessor；`SkyLightOperator` → `WindowGroup(id:"alarm")`
- 配置层（统一）：`SentryConfiguration`（UserDefaults）→ 接入 `CicadaConfig`（ConfigStore），或明确双轨制

**🔴 完全待实现（新增）**：
- 设计令牌（Assets.xcassets + DesignMetrics + Color 扩展）
- 14 个通用组件
- `AppModel` + 四子 ViewModel 分层
- IPC async wrapper 扩展
- `BarkClient` 独立封装
- `toReadiness` 映射层
- reduceMotion 无障碍兜底
- 警戒触发推送通道（若选择跨进程方案）

---

## C. 关键技术决策与架构分析

### C-1. 宿主工程决策（D-1，最高优先级）

**问题**：新 GUI 代码放在哪里？

| 方案 | 描述 | 优点 | 缺点 |
|---|---|---|---|
| **方案 A：在现有 Xcode 原生应用内重构** | 在 `apps/agent/native/sentinel-app/Sentry/` 内替换 UI 层，保留引擎层，逐步迁移 | 引擎代码零移植成本；相机/报警/NotchDrop 立即可用；风险最低 | Xcode 工程与 SwiftPM 并行，依赖管理混合；AppKit 引入量仍较高 |
| **方案 B：SwiftPM 新增 GUI executable target** | 在 `apps/agent/swift/` 新增 `CicadaGUIApp` target，纯 SwiftUI | 统一到 SwiftPM；依赖清晰；符合 Design.md 纯 SwiftUI 倾向 | 需将相机/报警/监控运行时/NotchDrop 引擎从 Xcode 移植为 SwiftPM library，工作量大；`AVFoundation`/`CoreAudio` 在 SwiftPM 可用但需配置 |
| **方案 C：混合——SwiftPM UI 库 + Xcode 宿主** | 新增 SwiftPM `CicadaUI` library（设计令牌+组件+ViewModel），Xcode 原生应用依赖它；引擎留在 Xcode | UI 层可复用、可测试；引擎零移植；渐进式 | 跨 SwiftPM/Xcode 依赖需 XCFramework 或本地 package 引用，配置略复杂 |

**🎯 推荐：方案 C（混合）**

理由：
1. Design.md 的设计令牌与组件是**可独立成库的纯 SwiftUI**，放进 SwiftPM `CicadaUI` library 后可单测、可被未来其他 target 复用。
2. 引擎层（相机/报警/监控运行时/NotchDrop 文件引擎）与 AppKit/AVFoundation 强耦合，移植到 SwiftPM 收益低、风险高，留在 Xcode 宿主最稳。
3. 状态分层（`AppModel` 等）可放 `CicadaUI`，通过依赖注入接收引擎协议（定义在 `CicadaUI`，实现在 Xcode 宿主），实现解耦。
4. 渐进式：先建 `CicadaUI` → Xcode 宿主引入 → 逐屏替换 → 最后再评估是否把引擎也迁 SwiftPM。

> **需主理人确认**：是否认可方案 C？若坚持纯 SwiftPM（方案 B），需追加"引擎移植"子计划（见 §F 风险 R-1）。

### C-2. SwiftUI App 结构（三类 Scene）可行性

Design.md §1.1 的三类 Scene 完全可行：

- **主窗口 `WindowGroup("Cicada 控制中心")`**：`NavigationSplitView` 双栏，macOS 13+ 原生支持。✅
- **菜单栏 `MenuBarExtra(.window)`**：macOS 13+ 原生支持 `.menuBarExtraStyle(.window)`。✅
- **警戒全屏 `WindowGroup(id: "alarm")`**：`openWindow(id:)` / `dismissWindow` macOS 13+ 支持。`.windowStyle(.hiddenTitleBar)` 可用。✅

**与现有 `App.swift` 差异**：现有用 `@NSApplicationDelegateAdaptor`（因 AppDelegate 持有 `startupDiagnostics`/`runStartupChecks` 等）。方案 C 下可保留 AppDelegate 作为引擎宿主，`AppModel` 通过协议拿引擎状态，不冲突。

### C-3. 状态分层与同步 IPC 桥接

Design.md §1.2 + §9.2 的方案正确且可落地：

```
AppModel (@StateObject, @MainActor)
 ├─ SentinelsModel  → UdsSentinelControlClient（Task.detached 包装）
 ├─ ConfigModel     → ConfigStore（load/save 同步，UI 线程调，文件小可接受）
 ├─ SleepHoldModel  → SleepHoldControlClient（Task.detached 包装）
 └─ AlarmModel      → 引擎协议（Xcode 宿主注入 Sentry/SentryMonitorRuntime 桥接）
```

- **IPC 桥接**：`extension SentinelControlClienting { func statusAsync() async throws -> … { try await Task.detached(priority: .userInitiated) { try self.status() }.value } }`——正确，避免阻塞主线程。
- **轮询**：`AppModel` 启动 `Task` + `try await Task.sleep(for: .seconds(N))` 循环调 `sentinels.refresh()`，N 建议 2-3 秒（状态变化低频）。
- **AlarmModel 桥接**（关键）：现有警戒触发是 `SentryMonitorRuntime.onAlarm` 同进程回调。方案 C 下，`AlarmModel` 定义协议 `AlarmEngineDelegate`，Xcode 宿主的 `Sentry` 实现该协议，触发时 `await MainActor.run { alarmModel.activate(reason: …) }`，`ControlCenterRoot` 观察 `alarmModel.isActive` 调 `openWindow("alarm")`。**无需新建跨进程推送通道**。

### C-4. macOS 13 vs 14 兼容策略

Package.swift platforms 是 `.macOS(.v13)`，Design.md 要求 14+ 组件做 `@available` 分支。统一策略表：

| API | 最低版本 | 兼容方案 |
|---|---|---|
| `NavigationSplitView` | 13+ | ✅ 直接用 |
| `MenuBarExtra(.window)` | 13+ | ✅ 直接用 |
| `openWindow(id:)` / `dismissWindow` | 13+ | ✅ 直接用 |
| `.tracking()` | 14+ | 13 用 `.kern(0.08)` 替代（§2.2 已注） |
| `NavigationSplitView` 侧栏宽度记忆 | 14+ 更好 | 13 用 `.navigationSplitViewColumnWidth(min:ideal:max:)` 显式指定 |
| `.textCase(.uppercase)` | 13+ | ✅ |
| `Canvas` | 15+ | ⚠️ 13/14 用 `ForEach` + `Rectangle` 旋转替代（EyeView 现有做法），14+ 可选 Canvas 优化 |
| `.symbolEffect` | 14+ | 13 不用，降级静态 SF Symbol |
| `@Observable`（Swift 5.9 Observation） | 14+ | 统一用 `ObservableObject` + `@Published`（13 兼容） |

**建议**：`CicadaUI` library 的 `Package.swift` 声明 `.macOS(.v13)`，所有 14+ API 用 `if #available(macOS 14, *)` 分支。警戒眼睛 Canvas 优先级低，首版用 `ForEach` + `Rectangle`（现有 EyeView 已验证可用）。

### C-5. NotchDrop / 警戒全屏窗口层级

Design.md §1.1 + §13 的策略合理：

- **警戒全屏**：用 `WindowGroup(id:"alarm")` + `.windowStyle(.hiddenTitleBar)` + `.defaultSize(700, 400)`。若需覆盖全屏/置顶，用 `WindowAccessor` 取 `NSWindow` 设 `.level = .floating`（或 `.screenSaver` 级别）+ `.collectionBehavior`。**仅设层级，不写视图内容**——符合 §13 约束。
- **NotchDrop**：现有 `NotchWindowController` 是重度 AppKit（`NotchWindow.swift` 自定义 NSWindow）。方案 C 下可两条路：
  - **短期**：保留现有 `NotchWindowController` 引擎，仅把 `NotchContentView` 换成新设计令牌的 SwiftUI 视图（通过 `NSHostingView` 承载——这是必要的 AppKit 桥接，NotchDrop 的刘海贴合度必须靠 NSWindow 自定义）。
  - **长期**：评估是否能用 SwiftUI `Window` + `WindowAccessor` 覆盖现有 NSWindow 逻辑（风险较高，刘海动画/事件监控是 AppKit 强项）。
- **`WindowAccessor` 实现**：一个通用 `NSViewRepresentable`，`updateNSView` 里拿 `window` 设 `level`/`collectionBehavior`，不承载其他 UI。放 `CicadaUI` 的 `Support/WindowAccessor.swift`。

### C-6. Config schema 扩展决策

**问题**：Design.md §12 用 `config.draft.autoConnectAtLogin`，§11 ProtectionCard 用合盖/断网/断电 Toggle。

**现状**：
- `CicadaConfig`（SwiftPM）字段：`relayURL/deviceId/autoConnect/showNotifications/enableAutoReconnect/reconnectInterval/maxReconnectAttempts/heartbeatInterval/connectionTimeout`——**无触发器、无录音、无 Bark、无登录启动**。
- `SentryConfiguration`（原生）字段：`sentryTriggersLidEnabled/sentryTriggersInternetEnabled/sentryTriggersPowerEnabled/sentryAlarmsSoundsEnabled/sentryAlarmsNotificationType/sentryNotificationConfigBark/sentryRecordingEnabled/sentryRecordingDevice`——**有 GUI 需要的防护/告警/录像字段**。

**🎯 推荐决策：双轨制 + 统一 ViewModel**

- `CicadaConfig`（连接层）保持不变，继续走 `ConfigStore` → `~/.cicada/config.json`。
- `SentryConfiguration`（防护/告警/录像层）保留，但存储迁移到 `~/.cicada/sentry-config.json`（`CicadaUI` 内新建 `SentryConfigStore`，复用 ConfigStore 的原子写模式），不再用 UserDefaults（便于多进程一致 + 备份）。
- `ConfigModel`（Design.md §9.2）聚合两者：`@Published var draft: CicadaConfig` + `@Published var sentry: SentryConfiguration`，`save()` 分别落盘。
- `autoConnectAtLogin`：用 `LaunchAtLogin` 第三方库（现有已用）或直接写 `~/Library/LaunchAgents/com.cicada.sentinel.plist`，**不进 config schema**，作为独立 `@AppStorage` 或 `MaintenanceModel` 字段。

> **不推荐**把 `SentryConfiguration` 全部塞进 `CicadaConfig`——`CicadaConfig` 是 daemon/relay 连接契约，改字段会影响 daemon 解析；防护配置是 GUI 专属，解耦更安全。

### C-7. daemon→App 警戒触发通知通道

**结论：不需要新建跨进程通道。**

现有架构中，警戒监控运行时 `SentryMonitorRuntime` 与 GUI 在**同一进程**（原生应用进程）内，`onAlarm` 回调直接进 `Sentry.triggerAlarm`。方案 C 保持这一架构：`AlarmModel`（`CicadaUI`）定义协议，Xcode 宿主注入回调，同进程触发 `openWindow("alarm")`。

若未来 GUI 与监控分进程（方案 B 倾向），则需新建 daemon→App 推送：可选 (a) `UdsNotifier` 反向用（daemon → App 的 notifier socket，但当前 notifier 是 App→daemon 方向）；(b) `DistributedNotificationCenter`；(c) `CFNotificationCenter`（Darwin 通知）。**首版不走此路**。

### C-8. 是否新增 GUI executable target 到 Package.swift

- **方案 C 下**：`apps/agent/swift/Package.swift` 新增 `CicadaUI` **library target**（非 executable），依赖 `CicadaCore`/`CicadaIPC`/`CicadaSleepHoldCore`。Xcode 原生应用通过本地 package 引用 `CicadaUI`。
- **不新增** GUI executable target 到 SwiftPM（除非走方案 B）。

---

## D. 实施步骤详细规划

> 基于 Design.md §14 的 13 步清单，结合现状细化为 7 个阶段、13 个步骤。
> 标注：⏩ 可并行 / 🔗 必须串行（依赖前置）/ 🎯 验收标准 / ⚙️ 复杂度（低/中/高）

### 阶段 P0：基础设施（步骤 1-2）

#### 步骤 1：建立 CicadaUI library + 设计令牌
- **目标**：SwiftPM 新增 `CicadaUI` library target，建立 Assets.xcassets + DesignMetrics + Color 扩展
- **涉及文件**：
  - `apps/agent/swift/Package.swift`（新增 `.target(name: "CicadaUI", dependencies: ["CicadaCore","CicadaIPC","CicadaSleepHoldCore"])`，platforms 维持 `.macOS(.v13)`）
  - `apps/agent/swift/Sources/CicadaUI/DesignMetrics.swift`（Spacing/Radius/Shadow 常量）
  - `apps/agent/swift/Sources/CicadaUI/DesignTokens/Color+Cicada.swift`（`cicadaXxx` 扩展）
  - `apps/agent/swift/Sources/CicadaUI/Resources/Assets.xcassets/`（21 个 Color Set，每个含 Light/Dark）
  - `apps/agent/swift/Sources/CicadaUI/Support/WindowAccessor.swift`（NSViewRepresentable 取 NSWindow 设 level）
- **依赖**：无
- **验收**：`swift build` 通过；`Color.cicadaAccent` 在 Preview 可渲染；Xcode 原生应用能引用 `CicadaUI`
- **复杂度**：中（Assets.xcassets 在 SwiftPM 内需 `resources: [.copy("Resources/Assets.xcassets")]` 配置，注意 bundle 处理）
- **并行性**：⏩ 可与步骤 2 并行

#### 步骤 2：IPC async wrapper + BarkClient + 展示模型
- **目标**：为现有 IPC client 加 async 扩展；封装 BarkClient；定义 §9.1 展示模型 + `toReadiness` 映射
- **涉及文件**：
  - `apps/agent/swift/Sources/CicadaUI/IPC/SentinelControl+Async.swift`（`extension SentinelControlClienting`）
  - `apps/agent/swift/Sources/CicadaUI/IPC/SleepHoldControl+Async.swift`
  - `apps/agent/swift/Sources/CicadaUI/Net/BarkClient.swift`
  - `apps/agent/swift/Sources/CicadaUI/Models/ReadinessItem.swift`（+ Diagnostic/SleepHoldCellData/FolderAction）
  - `apps/agent/swift/Sources/CicadaUI/Models/SentinelState.swift`（`.running/.warning/.idle` 枚举 + title/description）
  - `apps/agent/swift/Sources/CicadaUI/Models/SnapshotMapper.swift`（`toReadiness(_ snap: SentinelStatusSnapshot) -> [ReadinessItem]`）
- **依赖**：无（仅依赖 CicadaCore/CicadaIPC 已有类型）
- **验收**：单元测试 `toReadiness` 映射正确；async wrapper 不阻塞主线程
- **复杂度**：中
- **并行性**：⏩ 与步骤 1 并行

### 阶段 P1：状态层 + 通用组件（步骤 3-4）

#### 步骤 3：AppModel + 四子 ViewModel
- **目标**：实现 §1.2 状态分层
- **涉及文件**：
  - `apps/agent/swift/Sources/CicadaUI/State/AppModel.swift`（聚合 + 轮询 Task）
  - `apps/agent/swift/Sources/CicadaUI/State/SentinelsModel.swift`
  - `apps/agent/swift/Sources/CicadaUI/State/ConfigModel.swift`（聚合 CicadaConfig + SentryConfiguration）
  - `apps/agent/swift/Sources/CicadaUI/State/SleepHoldModel.swift`
  - `apps/agent/swift/Sources/CicadaUI/State/AlarmModel.swift`（+ `AlarmEngineDelegate` 协议，供 Xcode 宿主注入）
  - `apps/agent/swift/Sources/CicadaUI/Config/SentryConfigStore.swift`（SentryConfiguration → `~/.cicada/sentry-config.json`）
- **依赖**：步骤 2（展示模型 + async wrapper）
- **验收**：`AppModel` init 后能 `sentinels.refresh()` 拿到状态；`ConfigModel.load()` 读两份配置
- **复杂度**：高（AlarmModel 协议设计需与 Xcode 引擎对齐）
- **并行性**：🔗 依赖步骤 2

#### 步骤 4：14 个通用组件 + ButtonStyle
- **目标**：实现 §4 全部组件
- **涉及文件**：
  - `apps/agent/swift/Sources/CicadaUI/Components/StatusHeroCard.swift`（+ StatusIcon/StatusBadge）
  - `apps/agent/swift/Sources/CicadaUI/Components/ReadinessCard.swift`（+ ReadinessRow/ProgressRing/Ring）
  - `apps/agent/swift/Sources/CicadaUI/Components/DiagnosticStrip.swift`
  - `apps/agent/swift/Sources/CicadaUI/Components/Card.swift`
  - `apps/agent/swift/Sources/CicadaUI/Components/SettingRow.swift`
  - `apps/agent/swift/Sources/CicadaUI/Components/CicadaTextField.swift`
  - `apps/agent/swift/Sources/CicadaUI/Components/InlineMessage.swift`
  - `apps/agent/swift/Sources/CicadaUI/Components/FolderGridButton.swift`（+ FolderButton）
  - `apps/agent/swift/Sources/CicadaUI/Components/SleepHoldCell.swift`
  - `apps/agent/swift/Sources/CicadaUI/Components/VersionTag.swift`
  - `apps/agent/swift/Sources/CicadaUI/Components/CameraPreviewPlaceholder.swift`
  - `apps/agent/swift/Sources/CicadaUI/Components/PaneHeader.swift`（+ HelpButton）
  - `apps/agent/swift/Sources/CicadaUI/Components/ButtonStyles.swift`（Primary/Ghost/Danger/Small，**修复 §4.7 typo**）
  - `apps/agent/swift/Sources/CicadaUI/Components/NavRow.swift`
- **依赖**：步骤 1（设计令牌）
- **验收**：每个组件有 `#Preview`；视觉与 HTML 预览一致；`GhostButtonStyle` 无 typo
- **复杂度**：中高（14 个组件，但均有代码骨架）
- **并行性**：⏩ 依赖步骤 1 后可并行；组件间相互独立

### 阶段 P2：主窗口三 Pane（步骤 5-8）

#### 步骤 5：ControlCenterRoot + NavRow + Pane 骨架
- **目标**：§3.1 主窗口双栏
- **涉及文件**：
  - `apps/agent/swift/Sources/CicadaUI/Views/ControlCenterRoot.swift`（NavigationSplitView + NavSection 枚举）
  - `apps/agent/swift/Sources/CicadaUI/Views/PaneHeader.swift`（若未在步骤 4 建）
- **依赖**：步骤 3、4
- **验收**：侧栏三选项可切换；选中态视觉正确
- **复杂度**：低
- **并行性**：🔗 依赖步骤 3、4

#### 步骤 6：OverviewPane 全部子视图
- **目标**：§3.2 概览页
- **涉及文件**：
  - `apps/agent/swift/Sources/CicadaUI/Views/OverviewPane.swift`（StatusHeroCard + ReadinessCard + DiagnosticStrip + VersionTag）
- **依赖**：步骤 3、4、5
- **验收**：`SentinelsModel.refresh()` 后 UI 更新；视觉与 HTML overview 一致
- **复杂度**：中
- **并行性**：⏩ 与步骤 7、8 并行（三 Pane 独立）

#### 步骤 7：SettingsPane + TabBar + 5 Card
- **目标**：§11 设置页
- **涉及文件**：
  - `apps/agent/swift/Sources/CicadaUI/Views/SettingsPane.swift`（+ SettingsTabBar/SettingsTabChip）
  - `apps/agent/swift/Sources/CicadaUI/Views/SettingsCards/ConnectionCard.swift`
  - `apps/agent/swift/Sources/CicadaUI/Views/SettingsCards/ProtectionCard.swift`
  - `apps/agent/swift/Sources/CicadaUI/Views/SettingsCards/AlertsCard.swift`
  - `apps/agent/swift/Sources/CicadaUI/Views/SettingsCards/RecordingCard.swift`
  - `apps/agent/swift/Sources/CicadaUI/Views/SettingsCards/NotchDropCard.swift`
- **依赖**：步骤 3、4、5
- **验收**：5 Tab 可切换；Toggle 绑定 `ConfigModel.sentry.*`；保存后 `InlineMessage` 显示
- **复杂度**：中高（5 个 Card，ProtectionCard/AlertsCard 涉及配置写入）
- **并行性**：⏩ 与步骤 6、8 并行

#### 步骤 8：MaintenancePane + FolderGrid + SleepHoldCells
- **目标**：§12 维护页
- **涉及文件**：
  - `apps/agent/swift/Sources/CicadaUI/Views/MaintenancePane.swift`（4 个 Card：运行时/文件夹/SleepHold/诊断）
  - `apps/agent/swift/Sources/CicadaUI/Views/Maintenance/FolderGrid.swift`
  - `apps/agent/swift/Sources/CicadaUI/Views/Maintenance/SleepHoldCells.swift`
- **依赖**：步骤 3、4、5
- **验收**：SleepHold 状态实时；文件夹按钮可打开；诊断可运行
- **复杂度**：中
- **并行性**：⏩ 与步骤 6、7 并行

### 阶段 P3：Feature 视图（步骤 9-12）

#### 步骤 9：AlarmOverlay + SunsetGradient + AlarmEye
- **目标**：§5 警戒全屏
- **涉及文件**：
  - `apps/agent/swift/Sources/CicadaUI/Views/Alarm/AlarmOverlay.swift`
  - `apps/agent/swift/Sources/CicadaUI/Views/Alarm/SunsetGradient.swift`（自绘，替代 ColorfulX）
  - `apps/agent/swift/Sources/CicadaUI/Views/Alarm/AlarmEye.swift`（+ reduceMotion 兜底）
  - `apps/agent/swift/Sources/CicadaUI/Views/Alarm/AlarmLeftPanel.swift`
  - Xcode 宿主：替换 `SentryView.swift` 调用为 `AlarmOverlay`，`App.swift` 加 `WindowGroup(id:"alarm")`
- **依赖**：步骤 3（AlarmModel）、步骤 4（ButtonStyle）
- **验收**：`openWindow("alarm")` 可触发；sunset 渐变视觉与 HTML 一致；reduceMotion 开启时眼睛静止；`dismissWindow` 可关闭
- **复杂度**：高（Canvas/ForEach 旋转 + 脉动 + reduceMotion 三态）
- **并行性**：⏩ 与步骤 10、11、12 并行

#### 步骤 10：NotchPanel + NotchMenu + 拖放
- **目标**：§6 NotchDrop UI 重写
- **涉及文件**：
  - `apps/agent/swift/Sources/CicadaUI/Views/NotchDrop/NotchPanel.swift`（SwiftUI 视图，`.onDrop`）
  - `apps/agent/swift/Sources/CicadaUI/Views/NotchDrop/NotchMenu.swift`
  - `apps/agent/swift/Sources/CicadaUI/Views/NotchDrop/NotchSection.swift`（+ DashedBorder）
  - Xcode 宿主：`NotchViewController` 用 `NSHostingView` 承载新 `NotchPanel`，保留 `NotchWindow`/`TrayDrop`/`AirDrop` 引擎
- **依赖**：步骤 1、4
- **验收**：拖放文件有视觉反馈；菜单按钮可点击；引擎落盘正常
- **复杂度**：中高（NSHostingView 桥接 + `.onDrop` 协议）
- **并行性**：⏩ 与步骤 9、11、12 并行

#### 步骤 11：MenuBarDropdown
- **目标**：§7 菜单栏下拉
- **涉及文件**：
  - `apps/agent/swift/Sources/CicadaUI/Views/MenuBar/MenuBarDropdown.swift`（+ MenuBarStatusCard/MenuBarButton）
  - Xcode 宿主：`App.swift` 的 `MenuBarExtra` 内容替换为 `MenuBarDropdown`
- **依赖**：步骤 3、4
- **验收**：下拉显示状态卡 + 4 按钮；"打开控制中心"能 `openWindow`
- **复杂度**：低
- **并行性**：⏩ 与步骤 9、10、12 并行

#### 步骤 12：HelpSheet
- **目标**：§8 帮助面板
- **涉及文件**：
  - `apps/agent/swift/Sources/CicadaUI/Views/Help/HelpSheet.swift`（+ HelpSection/HelpNumberedList/HelpBulletList）
  - Xcode 宿主：替换 `HelpPanelView.swift`
- **依赖**：步骤 1、4
- **验收**：触发器列表 + 注意事项显示正确
- **复杂度**：低
- **并行性**：⏩ 与步骤 9、10、11 并行

### 阶段 P4：联调与打磨（步骤 13）

#### 步骤 13：集成联调 + 引擎桥接 + 视觉校准
- **目标**：Design.md §14 第 13 步
- **涉及文件**：
  - Xcode 宿主 `AppDelegate.swift`：注入 `AlarmEngineDelegate` / `SentryMonitorRuntime` 到 `AppModel.alarm`
  - Xcode 宿主 `App.swift`：三类 Scene 全部接入 `AppModel`，移除旧 `ContentView`/`SentryControlCenterView`
  - `CicadaUI` 各视图：与 HTML 预览逐屏视觉校准（截图比对）
  - 全局：`.tint(.cicadaAccent)`、`.preferredColorScheme(nil)`、AlarmOverlay `.dark`
- **依赖**：步骤 5-12 全部
- **验收**：
  - IPC 状态轮询 → UI 刷新闭环
  - 警戒触发（合盖/断网/断电）→ `openWindow("alarm")` → 眼睛动画 → 停止关闭
  - 配置保存 → `InlineMessage` → 重启后配置持久
  - NotchDrop 拖放 → 落盘 → 清空
  - 菜单栏 → 打开控制中心
  - reduceMotion 开启 → 眼睛静止
  - 视觉与 HTML 预览一致（逐屏截图）
- **复杂度**：高
- **并行性**：🔗 依赖所有前置

---

## E. 各阶段优先级排序

| 阶段 | 内容 | 优先级 | 交付目标 | 推荐顺序理由 |
|---|---|---|---|---|
| **P0** | 基础设施（步骤 1-2） | P0 | `CicadaUI` 可构建；设计令牌 + IPC wrapper + 展示模型就绪 | 一切前置，无依赖 |
| **P1** | 状态层 + 通用组件（步骤 3-4） | P0 | `AppModel` 可轮询；14 组件可用 | Pane 视图的前置 |
| **P2** | 主窗口三 Pane（步骤 5-8） | P1 | 控制中心可用（概览/设置/维护） | 用户可见价值最早产出 |
| **P3** | Feature 视图（步骤 9-12） | P1 | 警戒/NotchDrop/菜单栏/帮助 | 可与 P2 后半并行 |
| **P4** | 联调打磨（步骤 13） | P0 | 全功能闭环 + 视觉校准 | 收尾必须 |

**推荐实施顺序**：P0 → P1 → P2（步骤 5 后 6/7/8 并行）→ P3（9/10/11/12 并行）→ P4

**并行机会图**：

```
P0:  [步骤1 ━━━] [步骤2 ━━━]
P1:              [步骤3 ━━━━━] [步骤4 ━━━━━━━]
P2:                            [步骤5 ━] [步骤6 ━━━][步骤7 ━━━━━][步骤8 ━━━]
P3:                                      [步骤9 ━━━━━━][步骤10 ━━━━━][步骤11 ━][步骤12 ━]
P4:                                                                  [步骤13 ━━━━━━━━]
```

---

## F. 潜在风险与应对方案

### F.1 技术风险

| ID | 风险 | 概率 | 影响 | 应对方案 |
|---|---|---|---|---|
| R-1 | 方案 C 的 SwiftPM `CicadaUI` 与 Xcode 工程混合依赖配置复杂（XCFramework/本地 package 引用） | 中 | 高 | 首版用 Xcode "Add Local Package" 引用 `apps/agent/swift/`；Assets.xcassets 在 SwiftPM 用 `resources: [.copy(...)]` + `Bundle.module` 访问；提前做一个最小 demo 验证链路 |
| R-2 | Assets.xcassets 在 SwiftPM library 内的 Color Set 加载失败（`Color("Accent")` 找不到 bundle） | 中 | 高 | `Color` 扩展改为 `Color("Accent", bundle: .module)`；写 Preview 验证每个色值；备选：不放 xcassets，用 `Color(red:green:blue:)` 硬编码暗色值（牺牲 Light 映射） |
| R-3 | 警戒眼睛 Canvas 在 macOS 13 不可用（Canvas 需 15+） | 高 | 中 | 首版用 `ForEach` + `Rectangle` 旋转（现有 `EyeView` 已验证）；14+ 用 `if #available` 切 Canvas 优化 |
| R-4 | NotchDrop 从 AppKit NSWindow 迁 SwiftUI 丢失刘海贴合度 | 中 | 高 | **不迁窗口层**，只换内容为 SwiftUI（`NSHostingView` 承载 `NotchPanel`）；窗口/事件监控保留 AppKit |
| R-5 | IPC 同步阻塞包装不当导致主线程卡顿 | 低 | 中 | 严格 `Task.detached(priority:.userInitiated)` 包装；轮询间隔 ≥2s；`ConfigModel.save` 文件小可主线程，但加 `Task.detached` 更稳 |
| R-6 | `AlarmModel` 与 Xcode 引擎桥接协议设计不当导致状态不同步 | 中 | 高 | 协议最小化（仅 `activate(reason:)`/`stop()`/`isActive`）；所有状态变更 `@MainActor`；引擎侧用 `MainActor.run` 回主线程 |

### F.2 设计-代码差异风险

| ID | 风险 | 应对方案 |
|---|---|---|
| R-7 | §4.7 `.cicadaTextSecondaryondary` typo | 步骤 4 实现时修正为 `.cicadaTextSecondary` |
| R-8 | §12 `autoConnectAtLogin` 字段不存在于 `CicadaConfig` | 按 C-6 决策：用 `LaunchAtLogin` 库或独立 `@AppStorage`，不进 config schema |
| R-9 | §9.1 `SentinelStatusSnapshot` 字段与 readiness 展示模型不对应 | 步骤 2 建 `SnapshotMapper.toReadiness`：`state=="running"&&recordingEnabled` → camera ok；`sleepHoldActive` → activation readiness；`activityHint` → diagnostic |
| R-10 | §11 ProtectionCard Toggle 绑定的触发器字段不在 `CicadaConfig` | 按 C-6：`ConfigModel` 聚合 `SentryConfiguration`，Toggle 绑 `configModel.sentry.sentryTriggersLidEnabled` 等 |
| R-11 | §1.1 假设 daemon→App 警戒推送，实际无此通道 | 按 C-7：同进程桥接，不建跨进程通道 |

### F.3 工程风险

| ID | 风险 | 应对方案 |
|---|---|---|
| R-12 | SwiftPM 加 `CicadaUI` library target 后 `swift build` 资源处理报错 | `Package.swift` 用 `resources: [.copy("Resources/Assets.xcassets")]`；`Bundle.module` 访问；先跑 `swift build` 验证再写代码 |
| R-13 | Xcode 原生应用引用 `CicadaUI` 后构建产物冲突（模块名/链接） | `CicadaUI` 仅 library，不链接可执行；Xcode 工程加 "Local Package" 引用；避免与原生 `SentinelIPC`/`CicadaRelayConfigStore` 符号冲突（命名空间隔离） |
| R-14 | 测试覆盖不足，`toReadiness`/IPC wrapper/ConfigModel 无单测 | 步骤 2、3 同步写 `CicadaUITests`；`toReadiness` 用 fixture `SentinelStatusSnapshot` 覆盖各 state；IPC wrapper 用 mock client |
| R-15 | 现有原生应用与 CicadaUI 配置双写冲突（UserDefaults vs 文件） | 迁移期 `SentryConfigStore.load()` 首次读取时检测 UserDefaults 旧值并迁移到文件，迁移后清 UserDefaults |
| R-16 | 视觉与 HTML 预览偏差（间距/圆角/阴影微调耗时） | 步骤 13 预留视觉校准时间；每屏截图比对；`DesignMetrics` 集中调参，避免散落魔数 |

---

## 附录：关键文件清单（新增）

```
apps/agent/swift/
├── Package.swift                                    # 修改：新增 CicadaUI target
└── Sources/CicadaUI/
    ├── DesignMetrics.swift                          # 间距/圆角/阴影常量
    ├── DesignTokens/
    │   └── Color+Cicada.swift                       # cicadaXxx 扩展
    ├── Resources/
    │   └── Assets.xcassets/                         # 21 个 Color Set
    ├── Support/
    │   └── WindowAccessor.swift                     # NSWindow level 设置
    ├── IPC/
    │   ├── SentinelControl+Async.swift
    │   └── SleepHoldControl+Async.swift
    ├── Net/
    │   └── BarkClient.swift
    ├── Models/
    │   ├── ReadinessItem.swift                      # + Diagnostic/SleepHoldCellData/FolderAction
    │   ├── SentinelState.swift
    │   └── SnapshotMapper.swift                     # toReadiness 映射
    ├── Config/
    │   └── SentryConfigStore.swift                  # SentryConfiguration 文件持久化
    ├── State/
    │   ├── AppModel.swift
    │   ├── SentinelsModel.swift
    │   ├── ConfigModel.swift
    │   ├── SleepHoldModel.swift
    │   └── AlarmModel.swift                          # + AlarmEngineDelegate 协议
    ├── Components/
    │   ├── StatusHeroCard.swift                     # + StatusIcon/StatusBadge
    │   ├── ReadinessCard.swift                      # + ReadinessRow/ProgressRing
    │   ├── DiagnosticStrip.swift
    │   ├── Card.swift
    │   ├── SettingRow.swift
    │   ├── CicadaTextField.swift
    │   ├── InlineMessage.swift
    │   ├── FolderGridButton.swift
    │   ├── SleepHoldCell.swift
    │   ├── VersionTag.swift
    │   ├── CameraPreviewPlaceholder.swift
    │   ├── PaneHeader.swift                          # + HelpButton
    │   ├── ButtonStyles.swift                        # Primary/Ghost(修复typo)/Danger/Small
    │   └── NavRow.swift
    └── Views/
        ├── ControlCenterRoot.swift
        ├── OverviewPane.swift
        ├── SettingsPane.swift
        ├── SettingsCards/
        │   ├── ConnectionCard.swift
        │   ├── ProtectionCard.swift
        │   ├── AlertsCard.swift
        │   ├── RecordingCard.swift
        │   └── NotchDropCard.swift
        ├── MaintenancePane.swift
        ├── Maintenance/
        │   ├── FolderGrid.swift
        │   └── SleepHoldCells.swift
        ├── Alarm/
        │   ├── AlarmOverlay.swift
        │   ├── SunsetGradient.swift
        │   ├── AlarmEye.swift
        │   └── AlarmLeftPanel.swift
        ├── NotchDrop/
        │   ├── NotchPanel.swift
        │   ├── NotchMenu.swift
        │   └── NotchSection.swift
        ├── MenuBar/
        │   └── MenuBarDropdown.swift
        └── Help/
            └── HelpSheet.swift
```

**Xcode 宿主修改**（`apps/agent/native/sentinel-app/Sentry/`）：
- `App.swift`：三类 Scene 接入 `AppModel`，加 `WindowGroup(id:"alarm")`
- `AppDelegate.swift`：注入 `AlarmEngineDelegate` 到 `AppModel.alarm`
- 删除/替换：`SentryControlCenterView.swift`、`SentryView.swift`、`EyeView.swift`、`SentinelMenuBarView.swift`、`HelpPanelView.swift`、`ContentView.swift`、`FormView.swift`
- 保留引擎：`AlarmEngine.swift`、`CameraSessionController.swift`、`SentryMonitorRuntime.swift`、`Sentry.swift`、`SentinelController.swift`、`DeviceCheck.swift`、`NotchDrop/`（引擎文件）、`NotchViewController.swift`（改用 NSHostingView 承载新 NotchPanel）

---

## 附录：待主理人确认事项

1. **D-1 宿主方案**：是否认可"方案 C（SwiftPM CicadaUI library + Xcode 宿主保留引擎）"？若否，请指定方案 A 或 B。
2. **D-2 命名冲突**：`/Applications/Cicada.app` 是指现有原生应用即新 GUI 宿主，还是另起一个独立 app？
3. **D-3 配置双轨制**：是否认可 `CicadaConfig`（连接层）+ `SentryConfiguration`（防护层）双轨，后者迁文件存储？
4. **D-4 第三方依赖去留**：`ColorfulX`/`SkyLightWindow`/`Pow`/`LaunchAtLogin` 是否在重构中移除？（Design.md 倾向移除 ColorfulX/SkyLightWindow；LaunchAtLogin 可保留）
5. **D-5 部署目标**：是否维持 macOS 13，还是提升到 14？（提升到 14 可省去多处 `@available` 分支，但会缩小兼容范围）