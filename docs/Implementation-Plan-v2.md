# Cicada GUI 实施计划 v2（基于 5 项决策的增量调整版）

> 架构师：高见远（Gao）｜交付总监：齐活林
> 基线文档：`docs/Implementation-Plan.md`（v1）、`docs/Design.md`（设计规范）
> 本文件是对 v1 的增量调整，**不覆盖** v1，仅记录因华哥 5 项决策（D-1~D-5）带来的变更。
> 产出日期：2026-07-16

---

## 1. 决策落实声明

| 决策 | 内容 | 对计划的影响 | 落实位置 |
|---|---|---|---|
| **D-1** | 宿主方案 = 方案 C：SwiftPM 新增 `CicadaUI` library（设计令牌+组件+ViewModel）+ Xcode 原生应用保留引擎层作为宿主 | v1 已推荐方案 C，无需改向；确认 `CicadaUI` 为 library target | §3 Package.swift / §5 P0 spec |
| **D-2** | 现有原生应用即 Cicada.app 宿主，不另起独立 app，在 `apps/agent/native/sentinel-app/Sentry/` 上改造 | 引擎层零移植；UI 层在 Xcode 工程内替换为引用 `CicadaUI` | §5 P0/P1 spec、§6 步骤 9/10 |
| **D-3** | 配置双轨制：`CicadaConfig`（连接层，ConfigStore→`~/.cicada/config.json`）+ `SentryConfiguration`（防护层，迁文件存储→`~/.cicada/sentry-config.json`） | v1 C-6 决策直接落实；新增 `SentryConfigStore`；`ConfigModel` 聚合两者 | §5 P1 spec（ConfigModel/SentryConfigStore） |
| **D-4** | 保留 ColorfulX、SkyLightWindow、Pow、LaunchAtLogin 全部 | **重大简化**：步骤 9 不自绘 SunsetGradient，复用 `ColorfulView(.sunset)`；步骤 10 保留 NotchWindow/NotchWindowController；警戒窗口继续用 SkyLightWindow | §2 约束修订、§4 步骤 9/10 |
| **D-5** | 部署目标提升到 macOS 14（Sonoma） | Package.swift platforms `.macOS(.v14)`；Canvas/.tracking()/.symbolEffect 直接用；删除全部 `@available` 分支 | §3 API 表、§5 Package.swift spec |

---

## 2. 约束声明修订（对应 Design.md §13）

v1 原样沿用 Design.md §13 的"无 AppKit 视图内容"约束。D-4 保留 SkyLightWindow/ColorfulX 后，需重新界定边界。

### 2.1 修订后的约束分层

| 层 | 约束 | 说明 |
|---|---|---|
| **主窗口 + 菜单栏** | ✅ 纯 SwiftUI | `WindowGroup` + `MenuBarExtra(.window)`，内容全部 SwiftUI 视图，无 NSViewRepresentable |
| **警戒全屏窗口层** | 🔄 保留 AppKit（SkyLightWindow） | 窗口创建/层级/关闭动画继续用 `SkyLightOperator.shared.delegateView`；**内容**换成 `CicadaUI` 的 `AlarmOverlay`（SwiftUI），通过 `AnyView` 注入 |
| **NotchDrop 窗口层** | 🔄 保留 AppKit（NotchWindow/NotchWindowController） | `NotchWindow`（自定义 NSWindow）+ `NotchWindowController` 保留；`NotchViewController` 改为 `NSHostingController<新NotchPanel>` 承载 SwiftUI 内容；引擎 TrayDrop/AirDrop 保留 |
| **NSViewRepresentable** | 🔄 仅允许两处 | (1) `WindowAccessor`（取 NSWindow 设 level，不承载视图）；(2) NotchDrop 的 `NSHostingController` 桥接（系统提供，非手写） |
| **渐变背景** | 🔄 保留 ColorfulX | `ColorfulView(.sunset)` 直接复用，不自绘 SunsetGradient |
| **Storyboard/XIB** | ❌ 禁用 | 不变 |
| **Combine 驱动 UI** | ❌ 禁用 | 不变；现有 IPC 同步阻塞统一 `Task.detached` 桥接 `@Published` |

### 2.2 Design.md §13 条款对照

| §13 原条款 | 状态 | 说明 |
|---|---|---|
| 无 UIKit/AppKit 视图内容 | **放宽** | 窗口层（警戒/NotchDrop）保留 AppKit；内容层纯 SwiftUI |
| WindowAccessor 仅设 level | ✅ 保留 | 仍适用主窗口需调层级的场景 |
| 无 UIViewRepresentable/NSViewRepresentable | **放宽** | 允许 `WindowAccessor` + NotchDrop 的 `NSHostingController` |
| 无 Storyboard/XIB | ✅ 保留 | — |
| 不引入 Combine 驱动 UI | ✅ 保留 | — |

> **原则**：AppKit 只存在于"窗口外壳 + 引擎"，SwiftUI 负责所有"可见 UI 内容"。工程师实现时，`CicadaUI` library 内部不得 import AppKit/Cocoa（保持可单测、可复用）；AppKit 桥接集中在 Xcode 宿主层。

---

## 3. macOS 14 API 可用性更新表（替换 v1 C-4）

D-5 提升到 macOS 14 后，v1 C-4 兼容表的 `@available` 分支全部删除。

| API | v1 状态 | v2 状态 | 采用决策 |
|---|---|---|---|
| `NavigationSplitView` | 13+ ✅ | 14+ ✅ | 直接用 |
| `MenuBarExtra(.window)` | 13+ ✅ | 14+ ✅ | 直接用 |
| `openWindow(id:)`/`dismissWindow` | 13+ ✅ | 14+ ✅ | 直接用 |
| `.tracking()` | 14+ 用 .kern 替代 | **直接用** | 删除 .kern 分支 |
| `NavigationSplitView` 侧栏宽度记忆 | 14+ 更好 | **原生支持** | 删除显式 `navigationSplitViewColumnWidth` hack（保留一处作为 fallback 下限即可） |
| `Canvas` | 15+ 用 ForEach 替代 | **直接用**（Canvas macOS 13+ 即可用，v1 误标 15+） | 警戒眼睛 36 条径向线用 Canvas |
| `.symbolEffect` | 14+ 降级 | **直接用** | 可选，不强制 |
| `@Observable`（Swift 5.9 Observation） | 14+ 用 ObservableObject | **可用但不采用** | 决策见下 |

### 3.1 @Observable 决策：继续用 `ObservableObject` + `@Published`

**理由**：
1. `@Observable` 与 `@StateObject`/`@ObservedObject`/`@EnvironmentObject` 语义不同，混用易错；`AppModel` 在 App 入口用 `@StateObject` 创建，子模型由 AppModel 持有——这套模式与 `ObservableObject` 天然契合。
2. `@Observable` 的优势在细粒度依赖追踪，但 Cicada 的 ViewModel 字段较少（state/readiness/diagnostic 等），`@Published` 整体刷新的性能损耗可忽略。
3. 统一性：全部 ViewModel 用同一套模式，降低工程师认知负担。
4. 现有 Xcode 宿主的 `Sentry: ObservableObject`、`SentryConfigurationManager: ObservableObject` 已是此模式，桥接一致。

> 工程师注意：**不要**用 `@Observable` 宏，全部 ViewModel 声明为 `@MainActor final class XxxModel: ObservableObject`。

---

## 4. 简化后的步骤 9/10 规格

### 4.1 步骤 9：AlarmOverlay（保留 ColorfulX，重写布局 + 眼睛 + reduceMotion）

**变更要点**：
- ❌ 删除 `SunsetGradient.swift`（v1 原步骤 9 要自绘，现在保留 `ColorfulView(.sunset)`）
- ✅ 保留 `ColorfulView(color: .sunset, noise: .constant(64))` 作为渐变背景
- ✅ 重写 `AlarmLeftPanel`（装饰图标 + 标题 + 描述 + 停止按钮，按 Design.md §5.1 布局）
- ✅ 重写 `AlarmEye`：用 `Canvas` 画 36 条径向线（替代现有 EyeView 的 `ForEach`+`Rectangle`）+ 24 条内层线 + 瞳孔脉动 + **reduceMotion 兜底**
- ✅ 停止按钮用 `PrimaryButtonStyle`（反色）或自定义大按钮

**文件清单**：

| 文件 | 动作 | 核心职责 |
|---|---|---|
| `Sources/CicadaUI/Views/Alarm/AlarmOverlay.swift` | 新建 | 整体布局：`ColorfulView(.sunset)` 背景 + `ultraThinMaterial` + HStack(AlarmLeftPanel + 分隔条 + AlarmEye) |
| `Sources/CicadaUI/Views/Alarm/AlarmEye.swift` | 新建 | Canvas 画径向线 + 脉动 + reduceMotion 兜底 |
| `Sources/CicadaUI/Views/Alarm/AlarmLeftPanel.swift` | 新建 | 装饰图标 + 标题 + 描述 + 停止按钮 |
| ~~`Sources/CicadaUI/Views/Alarm/SunsetGradient.swift`~~ | ❌ 不建 | 复用 ColorfulX |
| Xcode 宿主 `SentryView.swift` | **修改** | 内容替换为 `AlarmOverlay()`；保留 `ColorfulView` import；或直接删除 SentryView，由 `Sentry.makeDefaultWindowController` 改为 `SkyLightOperator.shared.delegateView(AnyView(AlarmOverlay().environmentObject(appModel)))` |
| Xcode 宿主 `EyeView.swift` | **删除** | 被 `CicadaUI/AlarmEye.swift` 取代 |
| Xcode 宿主 `Sentry.swift` | **修改** | `makeDefaultWindowController` 注入 `AlarmOverlay`；`onAlarmingActivaty` 回调改为触发 `appModel.alarm.activate(reason:)` |

**AlarmOverlay 关键要点**：
```
ZStack {
    ColorfulView(color: .sunset, noise: .constant(64))   // 复用 ColorfulX
        .ignoresSafeArea()
    Rectangle().fill(.ultraThinMaterial).opacity(0.5)     // 毛玻璃
    HStack(spacing: 0) {
        AlarmLeftPanel(reason: appModel.alarm.reason) {   // 停止闭包
            Task { await appModel.alarm.stop(); dismissWindow() }
        }
        Rectangle().fill(Color.black.opacity(0.5)).frame(width: 10)
        AlarmEye()
    }
}
.clipShape(RoundedRectangle(cornerRadius: 32))
.background(.black)
.preferredColorScheme(.dark)   // 警戒固定深色
```

**AlarmEye 关键要点（Canvas 版）**：
- 外层 36 条径向线：`Canvas { ctx in for i in 0..<36 { ctx.rotate... } }` 整体 `.rotationEffect(.degrees(rot))` + `.animation(.linear(duration:20).repeatForever(autoreverses:false))`
- 内层 24 条红色线：同 Canvas，半径缩小 25%
- 瞳孔：`Circle().fill(RadialGradient)` + `scaleEffect(pulse ? 0.8 : 1)` + `.animation(.easeInOut(2).repeatForever(autoreverses:true))`
- 反光点：`Circle().opacity(shimmer ? 0.8 : 0.3)` 同上
- **reduceMotion**：`@Environment(\.accessibilityReduceMotion) var reduceMotion`；`reduceMotion == true` 时所有 `.animation(...)` 传 `nil`，`.onAppear` 内 `guard !reduceMotion` 才设动画驱动值；旋转/脉动停在静态构图

**验收**：
- `ColorfulView(.sunset)` 渐变视觉与现有 SentryView 一致（不退化）
- reduceMotion 开启时眼睛静止，瞳孔不脉动
- 停止按钮可关闭警戒窗口
- `dismissWindow` 或 `SkyLightOperator` 关闭均可用

### 4.2 步骤 10：NotchPanel（保留 NotchWindow，只换内容为 SwiftUI）

**变更要点**：
- ❌ 不迁窗口层：保留 `NotchWindow`/`NotchWindowController`/`NotchViewModel`（引擎+窗口动画）
- ✅ 保留 `TrayDrop`/`AirDrop`（文件落盘引擎）
- ✅ 新建 SwiftUI `NotchPanel`/`NotchMenu`/`NotchSection`（按 Design.md §6 设计令牌重写内容）
- ✅ `NotchViewController` 改为 `NSHostingController<NotchPanel>`（当前已是 `NSHostingController<NotchView>`，只需换 rootView）

**文件清单**：

| 文件 | 动作 | 核心职责 |
|---|---|---|
| `Sources/CicadaUI/Views/NotchDrop/NotchPanel.swift` | 新建 | 打开态主体：NotchHeader + HStack(两个 NotchSection 拖放区) |
| `Sources/CicadaUI/Views/NotchDrop/NotchMenu.swift` | 新建 | 横向 5 方块按钮（关闭/AirDrop/GitHub/赞助/设置/清空） |
| `Sources/CicadaUI/Views/NotchDrop/NotchSection.swift` | 新建 | 单个拖放区：图标 + 文字 + 虚线边框 + `.onDrop` |
| Xcode 宿主 `NotchDrop/NotchViewController.swift` | **修改** | `NSHostingController<NotchView>` → `NSHostingController<NotchPanel>`，注入 NotchViewModel |
| Xcode 宿主 `NotchDrop/NotchView.swift` | **修改/保留** | 刘海形状 mask 逻辑保留（窗口外壳）；内容区 `NotchContentView` 调用换为 `NotchPanel` |
| Xcode 宿主 `NotchDrop/NotchWindowController.swift` | ✅ 保留 | 不变 |
| Xcode 宿主 `NotchDrop/NotchWindow.swift` | ✅ 保留 | 不变 |
| Xcode 宿主 `NotchDrop/TrayDrop.swift` 等 | ✅ 保留 | 引擎不变 |
| Xcode 宿主 `NotchDrop/NotchContentView.swift` | **删除/替换** | 被 `CicadaUI/NotchPanel.swift` 取代 |
| Xcode 宿主 `NotchDrop/NotchMenuView.swift` | **删除/替换** | 被 `CicadaUI/NotchMenu.swift` 取代 |

**桥接要点**：
- `NotchViewController` 当前 `init(_ vm: NotchViewModel)` → 改为 `init(_ vm: NotchViewModel)` 内 `super.init(rootView: NotchPanel(vm: vm))`
- `NotchPanel` 接收 `NotchViewModel`（@StateObject/@ObservedObject），读 `vm.status`/`vm.contentType` 决定显示 NotchPanel/NotchMenu/通知
- `.onDrop(of: [.fileURL], isTargeted:)` 在 `NotchSection` 内实现，拖放视觉反馈用 `$isTargeted` 切边框色；实际落盘调 `vm` 的 TrayDrop 引擎方法
- `NotchViewModel` 保持 `ObservableObject` + Combine（现有），`CicadaUI` 内视图通过 `@ObservedObject` 读它——这是 NotchDrop 唯一保留 Combine 的例外（历史代码，不强行改）

**验收**：
- 拖放文件进刘海区，NotchPanel 展开 + 边框高亮
- 文件落盘到 TrayDrop 暂存目录
- 菜单按钮可切换 NotchMenu / 打开设置 / 清空

---

## 5. P0 + P1 详细实施 spec（工程师照此实现）

> 阶段 P0 = 步骤 1（CicadaUI library + 设计令牌）+ 步骤 2（IPC async wrapper + 展示模型）
> 阶段 P1 = 步骤 3（AppModel + 四子 ViewModel + SentryConfigStore）+ 步骤 4（14 个组件）

### ════════ P0 · 步骤 1：CicadaUI library 基础设施 ════════

#### 5.1.1 `apps/agent/swift/Package.swift`（修改）

**核心职责**：声明 `CicadaUI` library target，提升 platforms 到 macOS 14

**关键改动**：
```swift
platforms: [.macOS(.v14)],   // 原 .macOS(.v13)

// products 新增
.library(name: "CicadaUI", targets: ["CicadaUI"]),

// targets 新增
.target(
    name: "CicadaUI",
    dependencies: ["CicadaCore", "CicadaIPC", "CicadaSleepHoldCore"],
    resources: [.copy("Resources/Assets.xcassets")]
),
.testTarget(name: "CicadaUITests", dependencies: ["CicadaUI", "CicadaCore", "CicadaIPC"]),
```

**要点**：
- `swift-tools-version` 维持 5.9（支持 macOS 14 + Observation，但我们不用 @Observable）
- `CicadaUI` 依赖 `CicadaCore`（ConfigStore/CicadaConfig/RuntimePaths）、`CicadaIPC`（SentinelControlClienting/SentinelStatusSnapshot）、`CicadaSleepHoldCore`（SleepHoldControlClient/SleepHoldControlResponse）
- resources 用 `.copy("Resources/Assets.xcassets")` —— 注意是 `.copy` 不是 `.process`（xcassets 需完整目录结构保留）
- **不要**在 `CicadaUI` target 里 import AppKit/Cocoa（保持纯 SwiftUI + Foundation）

**依赖**：无
**验收**：`swift build` 通过；`swift build --target CicadaUI` 无错误

---

#### 5.1.2 `Sources/CicadaUI/DesignMetrics.swift`（新建）

**核心职责**：间距/圆角/阴影常量集中定义

**关键要点**：
```swift
enum DesignMetrics {
    enum Spacing { static let s1: CGFloat = 4; s2 = 8; s3 = 12; s4 = 16; s5 = 20; s6 = 24; s8 = 32; s10 = 40; s12 = 48 }
    enum Radius  { static let sm = 6; md = 10; lg = 14; xl = 20; x2l = 28 }
    enum Shadow  { static let sm = (radius:2,x:0,y:1,opacity:0.3); md = (12,0,4,0.25); lg = (32,0,12,0.35); diff = (20,0,2,0.15); accent = (20,0,0,0.15, color: .cicadaAccent) }
    static let sidebarWidth: CGFloat = 240
    static let progressRingSize: CGFloat = 56
}
```
- 按 Design.md §2.3 原样实现，全部 `static let`
- `Shadow.accent` 的 color 用 `.cicadaAccent`（依赖步骤 1 的 Color 扩展）

**依赖**：`Color+Cicada.swift`（Shadow.accent 引用 .cicadaAccent）
**验收**：编译通过；常量值与 Design.md §2.3 完全一致

---

#### 5.1.3 `Sources/CicadaUI/DesignTokens/Color+Cicada.swift`（新建）

**核心职责**：`Color.cicadaXxx` 扩展，从 bundle 加载 Color Set

**关键要点**：
```swift
import SwiftUI

extension Color {
    static let cicadaAccent        = Color("Accent", bundle: .module)
    static let cicadaAccentHover   = Color("AccentHover", bundle: .module)
    static let cicadaBgBase        = Color("BGBase", bundle: .module)
    static let cicadaBgSurface     = Color("BGSurface", bundle: .module)
    static let cicadaBgSurface2    = Color("BGSurface2", bundle: .module)
    static let cicadaBGElevated    = Color("BGElevated", bundle: .module)
    static let cicadaBgHover       = Color("BGHover", bundle: .module)
    static let cicadaBorderSubtle  = Color("BorderSubtle", bundle: .module)
    static let cicadaBorder        = Color("BorderDefault", bundle: .module)
    static let cicadaBorderStrong  = Color("BorderStrong", bundle: .module)
    static let cicadaTextPrimary   = Color("TextPrimary", bundle: .module)
    static let cicadaTextSecondary = Color("TextSecondary", bundle: .module)
    static let cicadaTextTertiary  = Color("TextTertiary", bundle: .module)
    static let cicadaTextInverse   = Color("TextInverse", bundle: .module)
    static let cicadaWarn          = Color("Warn", bundle: .module)
    static let cicadaDanger        = Color("Danger", bundle: .module)
    static let cicadaInfo          = Color("Info", bundle: .module)
    static let cicadaPurple        = Color("Purple", bundle: .module)
    // AlarmSunset1/2/3 不建扩展（ColorfulView 自带 .sunset，不需要）
}
```

**⚠️ 关键**：必须用 `bundle: .module`，否则 SwiftPM library 内 `Color("Accent")` 找不到资源 bundle，运行时返回默认色（透明/黑）。这是 v1 R-2 风险的落实点。

**依赖**：`Assets.xcassets`（同步骤）
**验收**：`#Preview { Rectangle().fill(.cicadaAccent) }` 渲染出 Emerald 绿（#10B981 暗色）；每个色值写 Preview 验证

---

#### 5.1.4 `Sources/CicadaUI/Resources/Assets.xcassets/`（新建）

**核心职责**：21 个 Color Set（Light/Dark）

**关键要点**：
- 按 Design.md §2.1 表格建 21 个 Color Set：BGBase/BGSurface/BGSurface2/BGElevated/BGHover/BorderSubtle/BorderDefault/BorderStrong/TextPrimary/TextSecondary/TextTertiary/TextInverse/Accent/AccentHover/Warn/Danger/Info/Purple
- **不含** AlarmSunset1/2/3（保留 ColorfulX，不需要）
- 实际建 18 个 Color Set（去掉 3 个 sunset）
- 每个 Color Set 设 Light + Dark Appearance（Cicada 以深色为主，Dark 是主用值）
- `Assets.xcassets` 根目录要有 `Contents.json`，每个 Color Set 子目录有 `Contents.json` 声明 color-space + appearances

**依赖**：无
**验收**：`swift build` 资源处理无报错；Preview 渲染正确色值

---

#### 5.1.5 `Sources/CicadaUI/Support/WindowAccessor.swift`（新建）

**核心职责**：NSViewRepresentable 取 NSWindow 设 level（仅设层级，不承载视图）

**关键要点**：
```swift
import AppKit  // 仅此文件允许 import AppKit（窗口配置例外）
import SwiftUI

struct WindowAccessor: NSViewRepresentable {
    var onWindow: (NSWindow?) -> Void
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { onWindow(view.window) }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {
        onWindow(nsView.window)
    }
}
```

**⚠️ 说明**：此文件是 §2 约束声明的明确例外（WindowAccessor 设 level）。`CicadaUI` 其他文件不得 import AppKit。若团队要求 `CicadaUI` 完全无 AppKit，可将此文件移到 Xcode 宿主层——但放 CicadaUI 便于复用，建议保留。

**依赖**：无
**验收**：主窗口可用 `WindowAccessor { $0?.level = .floating }` 设层级

---

### ════════ P0 · 步骤 2：IPC async wrapper + 展示模型 ════════

#### 5.2.1 `Sources/CicadaUI/IPC/SentinelControl+Async.swift`（新建）

**核心职责**：为 `SentinelControlClienting` + `UdsSentinelControlClient` 加 async 扩展

**关键要点**：
```swift
import CicadaIPC

extension SentinelControlClienting {
    func statusAsync() async throws -> SentinelControlResponse {
        try await Task.detached(priority: .userInitiated) { try self.status() }.value
    }
    func startAsync() async throws -> SentinelControlResponse {
        try await Task.detached(priority: .userInitiated) { try self.start() }.value
    }
    func stopAsync() async throws -> SentinelControlResponse {
        try await Task.detached(priority: .userInitiated) { try self.stop() }.value
    }
    func unlockAsync() async throws -> SentinelControlResponse {
        try await Task.detached(priority: .userInitiated) { try self.unlock() }.value
    }
    func openAsync() async throws -> SentinelControlResponse {
        try await Task.detached(priority: .userInitiated) { try self.open() }.value
    }
}
```

**要点**：
- `SentinelControlClienting` 协议只有 `request(_:)`，但 `UdsSentinelControlClient` 有 `start()/stop()/status()/unlock()/open()`——扩展要加在协议上需先确认这些方法是否在协议里。**实查**：协议只有 `request(_:)`，`start()/status()` 等是 `UdsSentinelControlClient` 的具体方法。因此扩展加在 `UdsSentinelControlClient` 上（或扩展协议 + 约束 `Self: UdsSentinelControlClient`）。
- **修正**：扩展应写 `extension UdsSentinelControlClient`，或为协议补 `start()/stop()` 等方法声明。推荐直接扩展 `UdsSentinelControlClient`（具体类），因为 ViewModel 持有的是 `SentinelControlClienting` 协议类型——若要协议级 async，需先扩展协议声明同步方法。**最简方案**：ViewModel 持有 `UdsSentinelControlClient` 具体类型（非协议），async 扩展加在具体类上。
- `Task.detached(priority: .userInitiated)` 把同步阻塞 POSIX socket 调用移出主线程；`.value` 自动回主线程（因 ViewModel 是 @MainActor）

**依赖**：`CicadaIPC`（SentinelControlClienting/UdsSentinelControlClient/SentinelControlResponse/SentinelStatusSnapshot）
**验收**：`await client.statusAsync()` 不阻塞主线程；返回的 `resp.status` 是 `SentinelStatusSnapshot?`

---

#### 5.2.2 `Sources/CicadaUI/IPC/SleepHoldControl+Async.swift`（新建）

**核心职责**：为 `SleepHoldControlClient` 加 async 扩展

**关键要点**：
```swift
import CicadaSleepHoldCore

extension SleepHoldControlClient {
    func statusAsync() async throws -> SleepHoldControlResponse {
        try await Task.detached(priority: .userInitiated) { try self.status() }.value
    }
    func pingAsync() async throws -> SleepHoldControlResponse {
        try await Task.detached(priority: .userInitiated) { try self.ping() }.value
    }
    func createSessionAsync() async throws -> SleepHoldControlResponse {
        try await Task.detached(priority: .userInitiated) { try self.createSession() }.value
    }
    func extendSessionAsync(_ id: String) async throws -> SleepHoldControlResponse {
        try await Task.detached(priority: .userInitiated) { try self.extendSession(id) }.value
    }
    func terminateSessionAsync(_ id: String) async throws -> SleepHoldControlResponse {
        try await Task.detached(priority: .userInitiated) { try self.terminateSession(id) }.value
    }
}
```

**要点**：
- `SleepHoldControlClient` 是具体类（非协议），直接扩展
- `SleepHoldControlResponse` 字段：`ok/code/error/message/sessionId/status(SleepHoldPowerStatus?)/activeSessions(Int?)`

**依赖**：`CicadaSleepHoldCore`（SleepHoldControlClient/SleepHoldControlResponse/SleepHoldPowerStatus）
**验收**：`await client.statusAsync()` 返回 `.status == .hold` 等

---

#### 5.2.3 `Sources/CicadaUI/Net/BarkClient.swift`（新建）

**核心职责**：Bark HTTP 推送独立封装（async/await + URLSession）

**关键要点**：
```swift
struct BarkClient {
    let endpoint: URL
    let session: URLSession = .shared

    func push(title: String, body: String, level: String = "critical") async throws {
        var url = endpoint.appendingPathComponent(title).appendingPathComponent(body)
        var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        comps.queryItems = [.init(name:"level",value:level), .init(name:"group",value:"Cicada - Mac"), .init(name:"call",value:"1"), .init(name:"isArchive",value:"1")]
        var req = URLRequest(url: comps.url!)
        req.httpMethod = "GET"
        let (_, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw BarkError.badStatus
        }
    }
    enum BarkError: Error { case badStatus }
}
```

**要点**：
- 参考现有 `Sentry.makeBarkRequest` 的 URL 构造（GET，queryItems 含 level/volume/group/isArchive/call/icon）
- endpoint 来自 `SentryConfiguration.sentryNotificationConfigBark.endpoint`（String → URL）
- 纯 URLSession async，不依赖任何第三方

**依赖**：Foundation
**验收**：mock endpoint 能发请求（单测用 URLProtocol mock）

---

#### 5.2.4 `Sources/CicadaUI/Models/ReadinessItem.swift`（新建）

**核心职责**：UI 展示模型定义（Identifiable）

**关键要点**：
```swift
struct ReadinessItem: Identifiable {
    let id = UUID()
    let key: String           // "triggers"/"notifications"/"camera"/"activation"
    let label: String
    let status: ReadinessStatus
    let valueText: String
}
enum ReadinessStatus { case ok, warn, off }

struct Diagnostic: Identifiable {
    let id = UUID()
    let level: DiagLevel      // .warn / .danger
    let message: String
}
enum DiagLevel { case warn, danger }

struct SleepHoldCellData: Identifiable {
    let id = UUID()
    let label: String
    let value: String
    let isMono: Bool
    let ok: Bool
}

struct FolderAction: Identifiable {
    let id = UUID()
    let systemImage: String
    let label: String
    let isDanger: Bool
    let action: () -> Void
}
```

**要点**：按 Design.md §9.1 原样；`FolderAction.action` 是闭包（维护页按钮用）
**依赖**：无
**验收**：编译通过

---

#### 5.2.5 `Sources/CicadaUI/Models/SentinelState.swift`（新建）

**核心职责**：状态枚举 + title/description

**关键要点**：
```swift
enum SentinelState {
    case running, warning, idle
    var title: String { switch self { case .running: "运行中"; case .warning: "警告"; case .idle: "空闲" } }
    var description: String { ... }
    var systemImage: String { "eye.fill" / "exclamationmark.triangle.fill" / "eye.slash" }
    var badgeColor: Color { .cicadaAccent / .cicadaWarn / .cicadaTextTertiary }
}
```

**要点**：供 `StatusHeroCard`/`StatusBadge`/`NavRow.statusText` 共用
**依赖**：`Color+Cicada.swift`
**验收**：编译通过

---

#### 5.2.6 `Sources/CicadaUI/Models/SnapshotMapper.swift`（新建）

**核心职责**：`SentinelStatusSnapshot` → `[ReadinessItem]` + `SentinelState` + `Diagnostic?` 映射

**关键要点**：
```swift
import CicadaIPC

enum SnapshotMapper {
    static func toState(_ snap: SentinelStatusSnapshot?) -> SentinelState {
        guard let snap else { return .idle }
        switch snap.state {
        case "running": return .running
        case "alarming", "warning": return .warning
        default: return .idle
        }
    }

    static func toReadiness(_ snap: SentinelStatusSnapshot?, triggersOn: Bool, notifOn: Bool) -> [ReadinessItem] {
        guard let snap else { return [] }
        return [
            .init(key:"triggers", label:"触发器", status: triggersOn ? .ok : .off,
                  valueText: triggersOn ? "已启用" : "未启用"),
            .init(key:"notifications", label:"通知", status: notifOn ? .ok : .off,
                  valueText: notifOn ? "已配置" : "未配置"),
            .init(key:"camera", label:"录像", status: snap.recordingEnabled ? .ok : .off,
                  valueText: snap.recordingEnabled ? "录制中" : "关闭"),
            .init(key:"activation", label:"睡眠保持", status: snap.sleepHoldActive ? .ok : .warn,
                  valueText: snap.sleepHoldActive ? "活跃" : "空闲"),
        ]
    }

    static func toDiagnostic(_ snap: SentinelStatusSnapshot?) -> Diagnostic? {
        guard let snap, !snap.activityHint.isEmpty else { return nil }
        let level: DiagLevel = snap.state == "alarming" ? .danger : .warn
        return .init(level: level, message: snap.activityHint)
    }
}
```

**要点**：
- 实际 `SentinelStatusSnapshot` 字段：`state(String)`/`activityHint(String)`/`recordingEnabled(Bool)`/`sleepHoldActive(Bool)`/`sleepHoldSessionId(String)`
- `state` 字符串值：需与 sentinel 进程实际输出对齐（现有 sentinel 返回 "running"/"alarming" 等——工程师实现时用 fixture 验证）
- `triggersOn`/`notifOn` 来自 `SentryConfiguration`（ConfigModel 提供），因为 snapshot 不含触发器配置状态
- readiness 进度环百分比 = ok 项数 / 总项数

**依赖**：`CicadaIPC`（SentinelStatusSnapshot）、`ReadinessItem`/`SentinelState`/`Diagnostic`
**验收**：单测覆盖各 state（running/alarming/idle/nil）+ recordingEnabled true/false + sleepHoldActive true/false

---

### ════════ P1 · 步骤 3：AppModel + 四子 ViewModel + SentryConfigStore ════════

#### 5.3.1 `Sources/CicadaUI/State/AppModel.swift`（新建）

**核心职责**：全局单源状态聚合 + 轮询 Task

**关键要点**：
```swift
@MainActor
final class AppModel: ObservableObject {
    @Published var sentinels: SentinelsModel
    @Published var config: ConfigModel
    @Published var sleepHold: SleepHoldModel
    @Published var alarm: AlarmModel

    private var pollTask: Task<Void, Never>?

    init(
        sentinelClient: UdsSentinelControlClient = .init(),
        sleepHoldClient: SleepHoldControlClient = .init(),
        configStore: ConfigStore = .init(),
        sentryConfigStore: SentryConfigStore = .init()
    ) {
        self.sentinels = SentinelsModel(client: sentinelClient)
        self.config = ConfigModel(store: configStore, sentryStore: sentryConfigStore)
        self.sleepHold = SleepHoldModel(client: sleepHoldClient)
        self.alarm = AlarmModel()
    }

    func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.sentinels.refresh()
                await self?.sleepHold.refresh()
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    func stopPolling() { pollTask?.cancel(); pollTask = nil }

    func quit() { NSApplication.shared.terminate(nil) }  // 或纯 SwiftUI 方式
}
```

**要点**：
- `@StateObject` 在 App 入口创建，`@EnvironmentObject` 注入
- 轮询间隔 3 秒（状态低频变化）
- `startPolling()` 在 `applicationDidFinishLaunching` 或 `.onAppear` 调
- 子模型由 AppModel 持有（聚合），各自 `@MainActor`
- **AlarmModel 桥接**：`AlarmModel` 暴露 `AlarmEngineDelegate` 协议，Xcode 宿主的 `Sentry` 实现该协议，触发时 `await MainActor.run { alarm.activate(reason:) }`

**依赖**：SentinelsModel/ConfigModel/SleepHoldModel/AlarmModel
**验收**：`AppModel().startPolling()` 后 `sentinels.state` 能更新

---

#### 5.3.2 `Sources/CicadaUI/State/SentinelsModel.swift`（新建）

**核心职责**：连接 sentinel IPC，轮询状态，映射到展示模型

**关键要点**：
```swift
@MainActor
final class SentinelsModel: ObservableObject {
    @Published private(set) var state: SentinelState = .idle
    @Published private(set) var readiness: [ReadinessItem] = []
    @Published private(set) var diagnostic: Diagnostic?
    @Published private(set) var activeTriggerCount: Int = 0
    @Published private(set) var lastSnapshot: SentinelStatusSnapshot?

    private let client: UdsSentinelControlClient
    private weak var configProvider: ConfigModel?  // 拿 triggersOn/notifOn

    init(client: UdsSentinelControlClient = .init()) { self.client = client }

    func refresh() async {
        do {
            let resp = try await client.statusAsync()
            if let snap = resp.status {
                lastSnapshot = snap
                state = SnapshotMapper.toState(snap)
                let triggersOn = configProvider?.sentry.hasTriggerEnabled ?? false
                let notifOn = configProvider?.sentry.hasNotificationEnabled ?? false
                readiness = SnapshotMapper.toReadiness(snap, triggersOn: triggersOn, notifOn: notifOn)
                diagnostic = SnapshotMapper.toDiagnostic(snap)
            }
        } catch {
            state = .idle
            diagnostic = .init(level: .warn, message: "无法连接 sentinel: \(error.localizedDescription)")
        }
    }

    func start() async { _ = try? await client.startAsync() }
    func stop() async { _ = try? await client.stopAsync() }
    func unlock() async { _ = try? await client.unlockAsync() }
}
```

**要点**：
- `configProvider` 弱引用 ConfigModel 拿触发器/通知开关状态（readiness 映射需要）
- 实际接线时由 AppModel 在 init 后设 `sentinels.configProvider = config`
- `activeTriggerCount` 可从 `SentryConfiguration` 算（3 个 bool 求和）

**依赖**：SentinelControl+Async、SnapshotMapper、SentinelState、ReadinessItem、Diagnostic、ConfigModel（弱引用）
**验收**：`refresh()` 后 state/readiness/diagnostic 更新；连接失败时 diagnostic 有警告

---

#### 5.3.3 `Sources/CicadaUI/State/ConfigModel.swift`（新建）

**核心职责**：聚合 `CicadaConfig`（连接层）+ `SentryConfiguration`（防护层）双轨

**关键要点**：
```swift
@MainActor
final class ConfigModel: ObservableObject {
    @Published var draft: CicadaConfig              // 连接层编辑态
    @Published var sentry: SentryConfiguration      // 防护层编辑态（注意：SentryConfiguration 定义在 Xcode 宿主，需迁移或共享）
    @Published var saveState: SaveState = .idle
    enum SaveState { case idle, saving, ok, err(String) }

    private let store: ConfigStore           // ~/.cicada/config.json
    private let sentryStore: SentryConfigStore  // ~/.cicada/sentry-config.json

    init(store: ConfigStore, sentryStore: SentryConfigStore) {
        self.store = store
        self.sentryStore = sentryStore
        load()
    }

    func load() {
        draft = (try? store.load()) ?? .defaultConfig()
        sentry = sentryStore.load()
    }

    func saveConnection() async {
        saveState = .saving
        do { try store.save(draft); saveState = .ok }
        catch { saveState = .err(error.localizedDescription) }
    }

    func saveSentry() async {
        do { try sentryStore.save(sentry) }
        catch { saveState = .err(error.localizedDescription) }
    }
}
```

**⚠️ 关键问题：`SentryConfiguration` 的归属**
`SentryConfiguration` 当前定义在 Xcode 宿主 `SentryConfiguration.swift`。`CicadaUI`（SwiftPM）要引用它，有两个选择：
1. **把 `SentryConfiguration` struct 定义迁到 `CicadaUI`**（或 `CicadaCore`），Xcode 宿主改为 import——推荐，因为 ConfigModel 在 CicadaUI
2. 在 Xcode 宿主定义一个协议，ConfigModel 持有协议——过度设计

**决策**：将 `SentryConfiguration` struct（纯 Codable struct，6 个字段）迁移到 `Sources/CicadaUI/Config/SentryConfiguration.swift`。`SentryConfigurationManager`（含 SleepHold 逻辑）留在 Xcode 宿主，改为 import `CicadaUI` 拿 struct 定义。这样 ConfigModel 和 SentryConfigStore 都能用。

**字段确认**（实查 SentryConfiguration.swift）：
- `sentryTriggersLidEnabled: Bool`
- `sentryTriggersInternetEnabled: Bool`
- `sentryTriggersPowerEnabled: Bool`
- `sentryAlarmsSoundsEnabled: Bool`
- `sentryAlarmsNotificationType: NotificationType`（.none/.bark）
- `sentryNotificationConfigBark: NotificationConfiguration_Bark`（含 endpoint: String）
- `sentryRecordingEnabled: Bool`
- `sentryRecordingDevice: String?`

计算属性（从现有 SentryConfigurationManager 提取为 struct 扩展）：`hasTriggerEnabled`/`hasNotificationEnabled`/`hasRecordingEnabled`/`canActivate`

**依赖**：ConfigStore（CicadaCore）、SentryConfigStore、SentryConfiguration（迁入 CicadaUI）
**验收**：`load()` 读两份配置；`saveConnection()`/`saveSentry()` 分别落盘

---

#### 5.3.4 `Sources/CicadaUI/Config/SentryConfiguration.swift`（新建，从 Xcode 迁入）

**核心职责**：`SentryConfiguration` struct + `NotificationType` + `NotificationConfiguration_Bark` 定义

**关键要点**：原样从 `apps/agent/native/sentinel-app/Sentry/SentryConfiguration.swift` 的 struct 部分（226-246 行）迁移，加计算属性扩展：
```swift
struct SentryConfiguration: Codable, Equatable, Hashable {
    var sentryTriggersLidEnabled: Bool = false
    var sentryTriggersInternetEnabled: Bool = false
    var sentryTriggersPowerEnabled: Bool = false
    var sentryAlarmsSoundsEnabled: Bool = false
    var sentryAlarmsNotificationType: NotificationType = .none
    var sentryNotificationConfigBark: NotificationConfiguration_Bark = .init()
    var sentryRecordingEnabled: Bool = false
    var sentryRecordingDevice: String? = nil

    enum NotificationType: String, Codable, Equatable, Hashable { case none, bark }
    struct NotificationConfiguration_Bark: Codable, Equatable, Hashable {
        var endpoint: String = "https://"
    }

    var hasTriggerEnabled: Bool { sentryTriggersLidEnabled || sentryTriggersInternetEnabled || sentryTriggersPowerEnabled }
    var hasNotificationEnabled: Bool { sentryAlarmsNotificationType != .none || sentryAlarmsSoundsEnabled }
    var hasRecordingEnabled: Bool { sentryRecordingEnabled }
    var canActivate: Bool { hasTriggerEnabled && hasNotificationEnabled }
}
```

**要点**：`SentryConfigurationManager`（Xcode 宿主）保留 SleepHold 会话管理逻辑，删掉 struct 定义改为 `import CicadaUI`
**依赖**：Foundation
**验收**：Xcode 宿主 `SentryConfigurationManager` 能 import 此类型

---

#### 5.3.5 `Sources/CicadaUI/Config/SentryConfigStore.swift`（新建）

**核心职责**：`SentryConfiguration` → `~/.cicada/sentry-config.json` 持久化（原子写 + UserDefaults 迁移）

**关键要点**：
```swift
import CicadaCore  // RuntimePaths.cicadaHome

final class SentryConfigStore {
    private let path: String          // ~/.cicada/sentry-config.json
    private let fm = FileManager.default
    private let legacyKey = "sentry.config"  // 旧 UserDefaults key

    init(path: String = RuntimePaths.cicadaHome + "/sentry-config.json") {
        self.path = path
    }

    func load() -> SentryConfiguration {
        // 1. 先尝试文件
        if fm.fileExists(atPath: path),
           let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
           let cfg = try? JSONDecoder().decode(SentryConfiguration.self, from: data) {
            return cfg
        }
        // 2. 迁移 UserDefaults 旧值
        if let legacy = UserDefaults.standard.data(forKey: legacyKey),
           let cfg = try? JSONDecoder().decode(SentryConfiguration.self, from: legacy) {
            try? save(cfg)
            UserDefaults.standard.removeObject(forKey: legacyKey)
            return cfg
        }
        // 3. 默认值
        return .init()
    }

    func save(_ config: SentryConfiguration) throws {
        let dir = (path as NSString).deletingLastPathComponent
        try fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let tempPath = path + ".tmp"
        let data = try JSONEncoder.pretty.encode(config)
        try data.write(to: URL(fileURLWithPath: tempPath), options: .atomic)
        chmod(tempPath, 0o600)
        if fm.fileExists(atPath: path) { try fm.removeItem(atPath: path) }
        try fm.moveItem(atPath: tempPath, toPath: path)
    }
}
```

**要点**：
- 复用 ConfigStore 的原子写模式（temp + atomic + move）
- **首次加载迁移**：检测 `UserDefaults` 旧 key `"sentry.config"`（现有 `@PublishedPersist(key:"sentry.config")` 的存储），迁移到文件后清 UserDefaults——这是 v1 R-15 风险的落实
- `JSONEncoder.pretty` 复用 ConfigStore 的私有扩展——需在 CicadaUI 内重新声明或公开（建议在 SentryConfigStore 内私有声明）
- 路径 `~/.cicada/sentry-config.json`（RuntimePaths.cicadaHome + "/sentry-config.json"）

**依赖**：CicadaCore（RuntimePaths）、SentryConfiguration
**验收**：首次 load 迁移 UserDefaults 旧值并清空；save 后文件存在且可重新 load

---

#### 5.3.6 `Sources/CicadaUI/State/SleepHoldModel.swift`（新建）

**核心职责**：连接 sleephold IPC，查询状态 + 会话操作

**关键要点**：
```swift
@MainActor
final class SleepHoldModel: ObservableObject {
    @Published private(set) var cells: [SleepHoldCellData] = []
    @Published private(set) var isActive: Bool = false
    @Published private(set) var sessionId: String = ""
    @Published private(set) var diagnostic: Diagnostic?

    private let client: SleepHoldControlClient

    init(client: SleepHoldControlClient = .init()) { self.client = client }

    func refresh() async {
        do {
            let resp = try await client.statusAsync()
            isActive = resp.ok
            sessionId = resp.sessionId ?? ""
            cells = [
                .init(label:"状态", value: resp.ok ? "活跃" : "空闲", isMono:false, ok: resp.ok),
                .init(label:"会话ID", value: resp.sessionId ?? "—", isMono:true, ok: resp.ok),
                .init(label:"电源", value: resp.status?.rawValue ?? "未知", isMono:false, ok: resp.ok),
                .init(label:"活跃会话数", value: "\(resp.activeSessions ?? 0)", isMono:true, ok: resp.ok),
            ]
        } catch {
            isActive = false
            diagnostic = .init(level: .warn, message: "无法连接 sleephold: \(error.localizedDescription)")
        }
    }
}
```

**要点**：
- `SleepHoldControlResponse` 字段：`ok/sessionId/status(SleepHoldPowerStatus?)/activeSessions(Int?)`
- `SleepHoldPowerStatus`：`.canSleep("sleep_enabled")` / `.hold("sleep_disabled")` / `.unknown`
- 维护页 SleepHoldCells 用此 model

**依赖**：SleepHoldControl+Async、SleepHoldCellData、Diagnostic
**验收**：`refresh()` 后 cells 有 4 项；连接失败 diagnostic 有警告

---

#### 5.3.7 `Sources/CicadaUI/State/AlarmModel.swift`（新建）

**核心职责**：警戒触发状态 + `AlarmEngineDelegate` 协议（供 Xcode 宿主注入）

**关键要点**：
```swift
@MainActor
final class AlarmModel: ObservableObject {
    @Published private(set) var isActive: Bool = false
    @Published private(set) var reason: String = ""

    func activate(reason: String) {
        isActive = true
        self.reason = reason
    }

    func stop() async {
        isActive = false
        reason = ""
        // 实际停止动作由 Xcode 宿主的 Sentry 引擎执行（通过 delegate 回调）
        await delegate?.alarmDidStop()
    }

    weak var delegate: AlarmEngineDelegate?
}

protocol AlarmEngineDelegate: AnyObject {
    func alarmDidStop() async
    // Xcode 宿主的 Sentry 实现此协议：
    // - alarmDidStop() 调 sentry.stop() / sentry.unlockAlarm()
    // - 触发时 sentry.onAlarmingActivaty 回调调 appModel.alarm.activate(reason:)
}
```

**要点**：
- **警戒触发流程**（同进程桥接，v1 C-7 决策）：
  1. `SentryMonitorRuntime.onAlarm(reason)` → `Sentry.triggerAlarm(reason:)` → `onAlarmingActivaty(reason)` 闭包
  2. Xcode 宿主在创建 Sentry 时注入闭包：`onAlarmingActivaty: { reason in appModel.alarm.activate(reason: reason) }`
  3. `ControlCenterRoot` 或 App 观察 `alarm.isActive`，`true` 时 `openWindow("alarm")`
  4. AlarmOverlay 停止按钮 → `appModel.alarm.stop()` → `delegate?.alarmDidStop()` → `Sentry.stop()`
- `delegate` 弱引用，避免循环
- 协议最小化（仅 `alarmDidStop`），触发用闭包注入而非协议（更灵活）

**依赖**：无（纯状态）
**验收**：`activate(reason:)` 后 `isActive == true`；`stop()` 后 `isActive == false`

---

### ════════ P1 · 步骤 4：14 个通用组件 ════════

> 所有组件放 `Sources/CicadaUI/Components/`，依赖步骤 1 的设计令牌。每个组件必须有 `#Preview`。

#### 5.4.1 `StatusHeroCard.swift`（新建）

**核心职责**：概览 Hero 卡片（渐变背景 + 状态图标 + 标题 + 徽章）

**关键要点**：
- `struct StatusHeroCard: View { let state: SentinelState }`
- 内含 `StatusIcon(state:size:)`（SF Symbol + 状态色圆背景）+ `StatusBadge(state:)`（capsule + 状态色）
- 渐变背景：`LinearGradient(.cicadaBgSurface2 → .cicadaAccent.opacity(0.06))` + `RadialGradient(.cicadaAccent.opacity(0.12) → clear, topTrailing)`
- 圆角 `Radius.xl`，边框 `.cicadaBorderSubtle`
- 按 Design.md §4.1 实现

**依赖**：SentinelState、Color+Cicada、DesignMetrics
**验收**：3 种 state 各有 Preview；视觉与 HTML overview hero 一致

---

#### 5.4.2 `ReadinessCard.swift`（新建）

**核心职责**：就绪度卡片 + ProgressRing + ReadinessRow 列表

**关键要点**：
- `struct ReadinessCard: View { let items: [ReadinessItem]; let progress: Double }`
- `ProgressRing(progress: Double)`：`ZStack { Ring(1).stroke(.cicadaBorderSubtle); Ring(progress).stroke(.cicadaAccent, .round).rotation(-90); Text("\(Int(progress*100))%") }`，`Ring: Shape`
- `ReadinessRow(item:)`：`HStack { Circle().fill(statusColor).shadow; Text(label); Spacer(); Text(valueText) }`
- progress = ok 项数 / 总项数（由调用方算或内部算）

**依赖**：ReadinessItem、Color+Cicada、DesignMetrics
**验收**：Preview 显示进度环 + 4 行

---

#### 5.4.3 `DiagnosticStrip.swift`（新建）

**核心职责**：琥珀色告警条

**关键要点**：
- `struct DiagnosticStrip: View { let diag: Diagnostic }`
- `HStack { Image("exclamationmark.triangle.fill").cicadaWarn; Text(diag.message).cicadaWarn; Spacer() }`
- 背景 `.cicadaWarn.opacity(0.12)`，边框 `.cicadaWarn.opacity(0.2)`
- 按 Design.md §4.3

**依赖**：Diagnostic、Color+Cicada
**验收**：Preview 琥珀色条

---

#### 5.4.4 `Card.swift`（新建）

**核心职责**：通用容器卡片

**关键要点**：
- `struct Card<Header: View, Content: View>: View`（泛型，trailing + content）
- 标题 `.subheadline.weight(.semibold).cicadaTextSecondary` + Spacer + trailing
- 背景 `.cicadaBgSurface2`，圆角 `Radius.lg`，边框 `.cicadaBorderSubtle`
- 按 Design.md §4.4

**依赖**：Color+Cicada、DesignMetrics
**验收**：Preview 标题 + 内容 + trailing 按钮

---

#### 5.4.5 `SettingRow.swift`（新建）

**核心职责**：行式配置项（左标题+描述，右控件）

**关键要点**：
- `struct SettingRow<Control: View>: View`（泛型 control）
- `HStack { VStack { Text(title).subheadline.medium; Text(desc).caption.tertiary }; Spacer; control() }`
- 底部 1px `.cicadaBorderSubtle` 分割线（`.overlay(alignment:.bottom)`）
- 按 Design.md §4.5

**依赖**：Color+Cicada、DesignMetrics
**验收**：Preview 标题 + Toggle

---

#### 5.4.6 `CicadaTextField.swift`（新建）

**核心职责**：带焦点高亮的文本输入

**关键要点**：
- `struct CicadaTextField: View { let title: String; @Binding var text: String; let hint: String?; @FocusState var isFocused }`
- `.textFieldStyle(.plain)` + 自定义背景 `.cicadaBgBase` + 焦点时边框 `.cicadaAccent` + `shadow(.cicadaAccent.opacity(0.12), radius:6)`
- 按 Design.md §4.8

**依赖**：Color+Cicada、DesignMetrics
**验收**：Preview 焦点切换边框变色

---

#### 5.4.7 `InlineMessage.swift`（新建）

**核心职责**：内联消息（ok/err）

**关键要点**：
- `struct InlineMessage: View { enum Kind { case ok, err }; let kind: Kind; let text: String }`
- `HStack { Image(checkmark/xmark); Text }`，背景 `.cicadaAccent/.cicadaDanger.opacity(0.12)`
- 按 Design.md §4.10

**依赖**：Color+Cicada
**验收**：Preview ok 绿 + err 红

---

#### 5.4.8 `FolderGridButton.swift`（新建）

**核心职责**：维护页 3 列网格按钮

**关键要点**：
- `struct FolderGridButton: View { let actions: [FolderAction] }`（外层 LazyVGrid）
- `struct FolderButton: View { let action: FolderAction; @State var hover }`
- `VStack { Image(action.systemImage).title3; Text(action.label).caption }` + hover 背景切 `.cicadaAccent.opacity(0.12)`
- 按 Design.md §4.11

**依赖**：FolderAction、Color+Cicada、DesignMetrics
**验收**：Preview 3 列网格

---

#### 5.4.9 `SleepHoldCell.swift`（新建）

**核心职责**：SleepHold 数据卡片

**关键要点**：
- `struct SleepHoldCell: View { let cell: SleepHoldCellData }`
- `VStack { Text(label).caption2.tertiary.uppercase.tracking(0.5); Text(value).subheadline.medium }`
- `isMono` 时 value 用 `.caption.monospaced()`
- `ok` 时 value 用 `.cicadaAccent`
- 按 Design.md §4.12

**依赖**：SleepHoldCellData、Color+Cicada、DesignMetrics
**验收**：Preview 4 卡片横排

---

#### 5.4.10 `VersionTag.swift`（新建）

**核心职责**：版本号标签

**关键要点**：
- `struct VersionTag: View`（读 Bundle.main 版本）
- `Text("Cicada v\(version) (build \(build)) · macOS \(osVersion)")`
- `.caption.monospaced().cicadaTextTertiary` + 顶部 1px 分割线
- 按 Design.md §4.13

**依赖**：Color+Cicada
**验收**：Preview 显示版本号

---

#### 5.4.11 `CameraPreviewPlaceholder.swift`（新建）

**核心职责**：相机未授权占位

**关键要点**：
- `struct CameraPreviewPlaceholder: View`
- 黑底 `RoundedRectangle` + 居中 `Image("camera.fill")` + 说明文字 + 顶部 `LinearGradient` 高光
- 按 Design.md §4.14
- **注意**：实际相机预览（授权后）由 Xcode 宿主的 `CameraSessionController` + `CameraPreviewView`（NSView）提供，CicadaUI 只做占位。授权后的预览桥接在 P3 处理。

**依赖**：Color+Cicada、DesignMetrics
**验收**：Preview 占位图

---

#### 5.4.12 `PaneHeader.swift`（新建，含 HelpButton）

**核心职责**：Pane 顶部标题 + 副标题 + 右侧帮助按钮

**关键要点**：
- `struct PaneHeader<Trailing: View>: View { let title: String; let subtitle: String; @ViewBuilder var trailing: () -> Trailing }`
- `VStack(alignment:.leading) { Text(title).title2.bold; Text(subtitle).subheadline.secondary }` + Spacer + trailing
- `HelpButton`：`Button { } label: { Image("questionmark.circle") }`，`.buttonStyle(.plain)`
- 按 Design.md §3.2

**依赖**：Color+Cicada
**验收**：Preview 标题 + 副标题 + 帮助按钮

---

#### 5.4.13 `ButtonStyles.swift`（新建，4 个样式 + 修复 typo）

**核心职责**：Primary/Ghost/Danger/Small 四种 ButtonStyle

**关键要点**：
- `PrimaryButtonStyle`：背景 `.cicadaAccent`（pressed `.cicadaAccentHover`），文字 `.cicadaTextInverse`
- `GhostButtonStyle`：背景 `.cicadaBGElevated`（pressed `.cicadaBgHover`），**文字 `.cicadaTextSecondary`**（⚠️ 修复 Design.md §4.7 typo `.cicadaTextSecondaryondary` → `.cicadaTextSecondary`），边框 `.cicadaBorderDefault`
- `DangerButtonStyle`：背景 `.cicadaDanger.opacity(0.12)`，文字 `.cicadaDanger`，边框 `.cicadaDanger.opacity(0.3)`
- `SmallButtonStyle`：小尺寸 accent 按钮，`.caption.weight(.medium)`，圆角 `Radius.sm`
- 按 Design.md §4.7，**typo 必须修复**

**依赖**：Color+Cicada、DesignMetrics
**验收**：4 个 Preview；GhostButtonStyle 无 typo

---

#### 5.4.14 `NavRow.swift`（新建）

**核心职责**：侧栏导航行

**关键要点**：
- `struct NavRow: View { let section: NavSection; let active: Bool }`
- `HStack { Image(systemName: section.systemImage); VStack { Text(section.title); Text(section.statusText).caption.tertiary } }`
- active 时背景 `.cicadaAccent.opacity(0.12)` + 边框 `.cicadaAccent.opacity(0.3)`
- 按 Design.md §3.1
- `NavSection` 枚举定义在 `ControlCenterRoot.swift`（P2），NavRow 引用它——**注意**：P1 阶段 NavRow 可先定义一个临时协议或把 NavSection 提前定义。建议把 `NavSection` 枚举放 `Sources/CicadaUI/Models/NavSection.swift`（P1 步骤 4），NavRow 和 ControlCenterRoot 都引用它。

**依赖**：Color+Cicada、DesignMetrics、NavSection
**验收**：Preview active/inactive 两态

---

## 6. 风险更新

### 6.1 因决策变化消除/减轻的风险

| v1 风险 | 状态 | 说明 |
|---|---|---|
| **R-3** 警戒眼睛 Canvas 在 macOS 13 不可用 | ✅ **消除** | D-5 提升到 macOS 14，Canvas 直接用（且 Canvas 实际 13+ 可用，v1 误标 15+） |
| **R-4** NotchDrop 从 AppKit 迁 SwiftUI 丢失刘海贴合度 | ✅ **消除** | D-4 保留 NotchWindow/NotchWindowController，只换内容 |
| v1 C-4 `@available` 分支维护负担 | ✅ **消除** | D-5 删除全部分支 |
| SunsetGradient 自绘视觉偏差 | ✅ **消除** | D-4 保留 ColorfulView(.sunset)，视觉与现有一致 |
| 警戒窗口迁 SwiftUI WindowGroup 适配风险 | ✅ **消除** | D-4 保留 SkyLightWindow |

### 6.2 新增/仍需关注的风险

| ID | 风险 | 概率 | 影响 | 应对 |
|---|---|---|---|---|
| **R-17** | `SentryConfiguration` 从 Xcode 迁到 CicadaUI 后，Xcode 宿主 `SentryConfigurationManager` 的 `@PublishedPersist` 与新 `SentryConfigStore` 双写冲突 | 中 | 高 | 迁移期 `SentryConfigStore.load()` 首次读取迁移 UserDefaults 旧值并清空；`SentryConfigurationManager` 改为通过 `ConfigModel.sentry` 读写，不再直接 `@PublishedPersist`——**工程师需重构 SentryConfigurationManager 的 cfg 字段为从 ConfigModel 取** |
| **R-18** | `CicadaUI` 引用 `SentryConfiguration` 后，Xcode 宿主与 SwiftPM 的 `SentryConfiguration` 类型冲突（两个同名类型） | 中 | 中 | 迁移时**删除** Xcode 宿主 `SentryConfiguration.swift` 的 struct 定义，只保留 `SentryConfigurationManager`，顶部 `import CicadaUI`。确保全工程只有一个 `SentryConfiguration` 定义 |
| **R-2** | Assets.xcassets 在 SwiftPM 内 Color Set 加载失败 | 中 | 高 | **仍需关注**：必须 `Color("Accent", bundle: .module)`；D-5 不影响此风险 |
| **R-1** | SwiftPM CicadaUI 与 Xcode 混合依赖配置 | 中 | 高 | **仍需关注**：Xcode "Add Local Package" 引用 `apps/agent/swift/`；先 `swift build` 验证再接 Xcode |
| **R-12** | SwiftPM resources 处理报错 | 低 | 中 | `resources: [.copy("Resources/Assets.xcassets")]`；`Bundle.module` 访问 |
| **R-13** | Xcode 引用 CicadaUI 后符号冲突 | 中 | 中 | CicadaUI 内不重复定义 `SentinelIPC`/`CicadaRelayConfigStore`；命名空间隔离 |
| **R-6** | AlarmModel 与 Xcode 引擎桥接协议 | 中 | 高 | 协议最小化（仅 `alarmDidStop`）；触发用闭包注入；`@MainActor` 保证线程安全 |
| **R-14** | 测试覆盖不足 | 中 | 中 | P0/P1 同步写 `CicadaUITests`：SnapshotMapper 各 state、SentryConfigStore 迁移、async wrapper mock |

---

## 7. 文件清单（P0 + P1 新增，完整路径）

```
apps/agent/swift/
├── Package.swift                                          # 修改
└── Sources/CicadaUI/
    ├── DesignMetrics.swift                                # 新建 P0
    ├── DesignTokens/
    │   └── Color+Cicada.swift                             # 新建 P0
    ├── Resources/
    │   └── Assets.xcassets/                               # 新建 P0（18 Color Set）
    ├── Support/
    │   └── WindowAccessor.swift                           # 新建 P0
    ├── IPC/
    │   ├── SentinelControl+Async.swift                    # 新建 P0
    │   └── SleepHoldControl+Async.swift                   # 新建 P0
    ├── Net/
    │   └── BarkClient.swift                               # 新建 P0
    ├── Models/
    │   ├── ReadinessItem.swift                            # 新建 P0
    │   ├── SentinelState.swift                            # 新建 P0
    │   ├── SnapshotMapper.swift                           # 新建 P0
    │   └── NavSection.swift                               # 新建 P1（提前定义供 NavRow）
    ├── Config/
    │   ├── SentryConfiguration.swift                      # 新建 P1（从 Xcode 迁入）
    │   └── SentryConfigStore.swift                        # 新建 P1
    ├── State/
    │   ├── AppModel.swift                                 # 新建 P1
    │   ├── SentinelsModel.swift                           # 新建 P1
    │   ├── ConfigModel.swift                              # 新建 P1
    │   ├── SleepHoldModel.swift                           # 新建 P1
    │   └── AlarmModel.swift                               # 新建 P1
    └── Components/
        ├── StatusHeroCard.swift                           # 新建 P1
        ├── ReadinessCard.swift                            # 新建 P1
        ├── DiagnosticStrip.swift                          # 新建 P1
        ├── Card.swift                                     # 新建 P1
        ├── SettingRow.swift                               # 新建 P1
        ├── CicadaTextField.swift                          # 新建 P1
        ├── InlineMessage.swift                            # 新建 P1
        ├── FolderGridButton.swift                         # 新建 P1
        ├── SleepHoldCell.swift                            # 新建 P1
        ├── VersionTag.swift                               # 新建 P1
        ├── CameraPreviewPlaceholder.swift                 # 新建 P1
        ├── PaneHeader.swift                               # 新建 P1
        ├── ButtonStyles.swift                             # 新建 P1
        └── NavRow.swift                                   # 新建 P1

apps/agent/swift/Tests/CicadaUITests/
└── (SnapshotMapperTests / SentryConfigStoreTests / 等)   # 新建 P0/P1

Xcode 宿主修改（P1 阶段）：
├── SentryConfiguration.swift                              # 删除 struct 定义，保留 Manager，import CicadaUI
├── AppDelegate.swift                                      # 注入 AlarmEngineDelegate（P3）
└── App.swift                                              # 接入 AppModel（P2/P3）
```

---

## 8. 给工程师的共享知识

1. **部署目标 macOS 14**：Package.swift `platforms: [.macOS(.v14)]`，删除所有 `@available` 分支
2. **ViewModel 统一模式**：`@MainActor final class XxxModel: ObservableObject` + `@Published`，**不用** `@Observable` 宏
3. **IPC 桥接**：同步阻塞 UDS client 用 `Task.detached(priority: .userInitiated) { try self.xxx() }.value` 包装，不在主线程调
4. **Color 资源**：必须 `Color("Accent", bundle: .module)`，不能用裸 `Color("Accent")`
5. **CicadaUI 无 AppKit**：除 `WindowAccessor.swift` 外，CicadaUI 内不得 import AppKit/Cocoa
6. **配置双轨**：`CicadaConfig`（连接层，ConfigStore）+ `SentryConfiguration`（防护层，SentryConfigStore），ConfigModel 聚合
7. **SentryConfiguration 迁移**：struct 定义从 Xcode 迁到 `CicadaUI/Config/`，Xcode 删 struct 留 Manager
8. **警戒触发同进程**：不建跨进程推送；`Sentry.onAlarmingActivaty` 闭包 → `appModel.alarm.activate(reason:)`
9. **ColorfulView/SkyLightWindow/NotchWindow 保留**：不自绘 SunsetGradient，不迁窗口层
10. **typo 修复**：`GhostButtonStyle` 的 `.cicadaTextSecondaryondary` → `.cicadaTextSecondary`
11. **轮询间隔**：3 秒（`Task.sleep(for: .seconds(3))`）
12. **原子写**：SentryConfigStore 复用 ConfigStore 的 temp+atomic+move 模式，`chmod 0o600`

---

## 附录：P0 → P1 依赖关系

```
P0 步骤1（设计令牌）────┐
                        ├──→ P1 步骤4（14 组件，依赖令牌）
P0 步骤2（IPC+模型）───┤
                        ├──→ P1 步骤3（ViewModel，依赖 IPC wrapper + 展示模型）
                        │
                        └──→ P1 步骤3 的 SentryConfigStore 依赖 SentryConfiguration（P1 迁入）
```

P0 步骤 1 和步骤 2 可并行；P1 步骤 3 依赖步骤 2；P1 步骤 4 依赖步骤 1。步骤 3 和步骤 4 可并行（仅共享 NavSection，提前定义即可）。