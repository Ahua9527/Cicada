# P4.2 控制中心整体替换 — 交付 Overview

> 主理人：齐活林 ｜ 架构师：高见远 ｜ 工程师：寇豆码 ｜ QA：严过关
> 完成日期：2026-07-16

## TL;DR
把 CicadaUI（SwiftPM）已建好的新控制中心 UI（ControlCenterRoot + MenuBarDropdown）接入 Xcode 宿主 Sentry，替换旧 ContentView/SentinelMenuBarView/SentryControlCenterView，统一路由、注入 AppModel.shared。Sentry target xcodebuild BUILD SUCCEEDED，CicadaUI 118/118 单测全过。

## 交付概览
- 交付状态：✅ 代码完成 + QA 2 轮回归通过
- Sentry xcodebuild：BUILD SUCCEEDED（0 error 0 warning）
- CicadaUI swift test：118/118 全过
- 已知问题：4 个 P0–P3 既定观察点（非本轮引入，建议另立任务）
- 待华哥 GUI：截图与 docs/Design.md 对照 + 运行时验证

## 用户 7 点需求落实
| # | 需求 | 落实 |
|---|------|------|
| 1 | 公开新 UI 根视图入口 | ControlCenterRoot/MenuBarDropdown/NavSection/ControlCenterRouter 加 public |
| 2 | ControlCenterRoot 替换 ContentView | App.swift WindowGroup 内容换 ControlCenterRoot，ViewModel 定时器接线迁 AppDelegate |
| 3 | MenuBarDropdown 替换旧菜单栏 | App.swift MenuBarExtra 换 MenuBarDropdown，删 SentinelMenuBarView |
| 4 | 统一导航路由 | 新建 public ControlCenterRouter ObservableObject，删旧 SentryControlCenterRouter，commands/菜单栏/NotchViewModel 全走 ControlCenterRouter.shared.open |
| 5 | AppModel.shared 依赖注入 | WindowGroup + MenuBarExtra 双注入 AppModel.shared + ControlCenterRouter.shared |
| 6 | 重新构建确认无编译错误 | ✅ Sentry xcodebuild BUILD SUCCEEDED + CicadaUI 118/118 |
| 7 | 截图与设计稿对照 | ⏳ CLI 无法截图，需华哥在 Xcode GUI 运行后对照 docs/Design.md |

## 文件清单
### 新建
- `apps/agent/swift/Sources/CicadaUI/State/ControlCenterRouter.swift`（public 路由器）
- `apps/agent/swift/Sources/CicadaUI/State/HostInjections.swift`（3 个 EnvironmentKey：folderActions/launchAtLoginToggle/runStartupChecks）
- `apps/agent/native/sentinel-app/Sentry/ControlCenterRouter+Host.swift`（shared 单例 + open 桥接）
- `apps/agent/native/sentinel-app/Sentry/ViewModel.swift`（替代 ContentView.swift，留 ViewModel 类）
- `apps/agent/native/sentinel-app/Sentry/MaintenanceHostInjections.swift`（6 FolderAction 真实行为 + LaunchAtLogin.Toggle + runStartupChecks）

### 修改
- `apps/agent/swift/Sources/CicadaUI/Models/NavSection.swift`（public）
- `apps/agent/swift/Sources/CicadaUI/Models/ReadinessItem.swift`（FolderAction public）
- `apps/agent/swift/Sources/CicadaUI/Views/ControlCenterRoot.swift`（public + @EnvironmentObject router）
- `apps/agent/swift/Sources/CicadaUI/Views/MenuBar/MenuBarDropdown.swift`（public + onQuit + router + 窗口 id="main"）
- `apps/agent/swift/Sources/CicadaUI/Views/Maintenance/FolderGrid.swift`（folderActions 改 Environment 读取）
- `apps/agent/swift/Sources/CicadaUI/Views/MaintenancePane.swift`（自启 + 启动检查改 Environment 注入）
- `apps/agent/native/sentinel-app/Sentry/App.swift`（入口换 ControlCenterRoot/MenuBarDropdown + DI）
- `apps/agent/native/sentinel-app/Sentry/AppDelegate.swift`（迁定时器接线）
- `apps/agent/native/sentinel-app/Sentry/NotchDrop/NotchViewModel.swift`（showSettings 路由迁移）

### 删除
- `apps/agent/native/sentinel-app/Sentry/SentryControlCenterView.swift`
- `apps/agent/native/sentinel-app/Sentry/SentinelMenuBarView.swift`
- `apps/agent/native/sentinel-app/Sentry/ContentView.swift`

## 已知限制 / 观察点（P0–P3 既定，非本轮引入）
1. NotchDrop 设置 key 不迁移（@PublishedPersist vs @AppStorage notch.*），既有偏好重置
2. RecordingCard 相机预览是占位，无实时预览/多相机选择器
3. Relay 配置模型差异（CicadaRelayConfig vs CicadaConfig），既有 relay 地址可能重置
4. 诊断展示数据源不同（appModel.sleepHold.diagnostic vs appDelegate.startupDiagnostics）

## 用户下一步
1. 在 Xcode GUI 打开 `apps/agent/native/sentinel-app/Sentry.xcodeproj` 编译运行（CLI 已确认能 build，GUI 用于运行时验证）
2. 运行后截图与 `docs/Design.md` 设计稿对照
3. 验证：菜单栏 3 导航按钮 + 系统 commands 开窗切分区、退出链路清理、维护页 6 按钮 + 自启 Toggle 真实行为
4. 若需处理 4 个已知限制，另立任务