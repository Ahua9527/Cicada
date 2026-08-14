# Cicada SwiftUI 设计规范

> 基于 `design-previews/2026-07-15-cicada-redesign/index.html`，面向纯 SwiftUI 实现。
> 适配 macOS 14+；SwiftPM、原生 App、CLI、daemon 与测试 target 的最低部署目标统一为 macOS 14。
> 全文不含 UIKit 桥接，所有界面、动画、数据流均以 SwiftUI 原生方式描述。

## 目录

| 章节 | 内容 | 关键产出 |
|---|---|---|
| [1. 架构总览](#1-架构总览) | Scene 结构、状态分层 | `CicadaApp`、`AppModel` 聚合子模型 |
| [2. 设计令牌](#2-设计令牌design-tokens) | 颜色 / 字体 / 间距 / 圆角 | `Assets.xcassets` Color Set、`DesignMetrics` |
| [3. 导航与视图层级](#3-导航与视图层级) | 主窗口双栏、Pane 骨架 | `ControlCenterRoot`、`NavSection` |
| [4. 组件规范](#4-组件规范) | 14 个通用组件 | `StatusHeroCard`、`Card`、`SettingRow`… |
| [5. 警戒全屏](#5-警戒全屏视图--alarmoverlay) | sunset 渐变 + 旋转眼睛 | `AlarmOverlay`、`AlarmEye` |
| [6. NotchDrop](#6-notchdrop) | 刘海拖放面板 | `NotchPanel`、`NotchMenu` |
| [7. 菜单栏下拉](#7-菜单栏下拉--menubardropdown) | 常驻菜单栏窗口 | `MenuBarDropdown` |
| [8. 帮助面板](#8-帮助面板--helpsheet) | 触发器与注意事项说明 | `HelpSheet` |
| [9. 数据模型与网络层](#9-数据模型与网络层) | 展示模型、ViewModel、IPC/HTTP | `SentinelsModel`、`ConfigModel`、`BarkClient` |
| [10. 动画与过渡](#10-动画与过渡) | 声明式动画清单 + 无障碍兜底 | reduceMotion 分支 |
| [11. 设置页子导航](#11-设置页子导航) | 5 个设置 Tab | `SettingsPane`、`SettingsTabBar` |
| [12. 维护页](#12-维护页) | 运行时 / 文件夹 / SleepHold / 诊断 | `MaintenancePane` |
| [13. 不包含的内容](#13-不包含的内容约束声明) | 约束边界 | 禁用项清单 |
| [14. 落地清单](#14-落地清单) | 按依赖顺序的实现任务 | 13 步验收 |

> 阅读路径建议：先 1 → 2 → 3 建立全局，再 4 通读组件，然后按 5–8 看 feature 视图，9 补数据流，10 看动效，11–12 回到主窗口两个 Pane 的细节。

---

## 1. 架构总览

Cicada GUI 是一个独立 SwiftUI App（`Cicada.app`），通过现有的 Unix Domain Socket IPC 层与后台 daemon / sentinel / sleephold 通信，配置读写走 `CicadaCore.ConfigStore`。App 本身不持有任何监控逻辑，只做**状态展示 + 控制下发 + 配置编辑**。

### 1.1 Scene 结构

App 入口用 SwiftUI 的 `App` 协议，声明三类 Scene：

```swift
@main
struct CicadaApp: App {
    @StateObject private var appModel = AppModel()   // 全局单源状态

    var body: some Scene {
        // 主控制中心窗口
        WindowGroup("Cicada 控制中心") {
            ControlCenterRoot()
                .environmentObject(appModel)
                .frame(minWidth: 880, minHeight: 600)
        }
        .windowResizability(.contentSize)
        .commands { CicadaCommands() }

        // 菜单栏常驻
        MenuBarExtra("Cicada", systemImage: "eye.fill") {
            MenuBarDropdown()
                .environmentObject(appModel)
        }
        .menuBarExtraStyle(.window)

        // 警戒全屏（独立窗口，按需呈现）
        WindowGroup("Cicada 警戒", id: "alarm") {
            AlarmOverlay()
                .environmentObject(appModel)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 700, height: 400)
    }
}
```

- **主窗口**：`WindowGroup` + `ControlCenterRoot`，承载概览 / 设置 / 维护三个面板。
- **菜单栏**：`MenuBarExtra(.window)`，下拉为一个 SwiftUI 视图，不用 `NSStatusItem`。
- **警戒全屏**：独立 `WindowGroup(id:)`，由 `openWindow(id: "alarm")` 触发；daemon 通过 IPC 通知 App 后 App 调 `openWindow`。关闭时由视图内按钮调 `dismissWindow`（或 `NSApplication` 共享场景退出，但优先用 SwiftUI 的 `dismissWindow`）。

> 刘海拖拽（NotchDrop）和警戒眼睛这类需要自定义窗口层级/形状的，仍尽量用 SwiftUI 的 `Window` + `WindowAccessor`（仅取 `NSWindow` 设 `level`/`collectionBehavior`，不写视图内容）。窗口**内容**全部是 SwiftUI 视图，`NSWindow` 只用于设层级，不承载 UI。这不算 UIKit/AppKit 桥接的"视图内容"，属于必要的窗口配置；若团队要求严格零 AppKit，可退化为 `fullScreenCover` + 自绘形状，但会损失刘海贴合度。

### 1.2 状态分层

```
AppModel (@StateObject, 全局)
 ├─ SentinelsModel (@StateObject)      // 连接 daemon/sentinel IPC，轮询状态
 ├─ ConfigModel (@StateObject)         // 包装 ConfigStore，读写 CicadaConfig
 ├─ SleepHoldModel (@StateObject)      // 连接 sleephold IPC
 ├─ AlarmModel (@StateObject)          // 警戒触发状态 + 当前触发原因
 └─ view-level @State                  // 选中页、Tab、输入框草稿等局部状态
```

- `AppModel` 是 `@StateObject`，在 App 入口创建一次，注入为 `@EnvironmentObject`。
- 子模型由 `AppModel` 持有（聚合而非继承），各自 `@MainActor` 刷新。
- 视图按需 `@ObservedObject` 拿到子模型；只有跨多视图共享的才提到 `@EnvironmentObject`。

---

## 2. 设计令牌（Design Tokens）

### 2.1 颜色 — Asset Catalog Color Set

所有颜色在 `Assets.xcassets` 里建 Color Set，支持 Light/Dark Appearance（Cicada 以深色为主，但 Color Set 仍给 Light 一个合理映射）。命名对应 HTML 变量：

| Color Set 名 | Light 值 | Dark 值（主用） | HTML 变量 |
|---|---|---|---|
| `BGBase` | `#FAFAFA` | `#09090B` | `--bg-base` |
| `BGSurface` | `#F4F4F5` | `#18181B` | `--bg-surface` |
| `BGSurface2` | `#E4E4E7` | `#1F1F23` | `--bg-surface-2` |
| `BGElevated` | `#D4D4D8` | `#27272A` | `--bg-elevated` |
| `BGHover` | `#E4E4E7` | `#2A2A2E` | `--bg-hover` |
| `BorderSubtle` | `#E4E4E7` | `#27272A` | `--border-subtle` |
| `BorderDefault` | `#D4D4D8` | `#3F3F46` | `--border-default` |
| `BorderStrong` | `#A1A1AA` | `#52525B` | `--border-strong` |
| `TextPrimary` | `#09090B` | `#FAFAFA` | `--text-primary` |
| `TextSecondary` | `#3F3F46` | `#A1A1AA` | `--text-secondary` |
| `TextTertiary` | `#71717A` | `#71717A` | `--text-tertiary` |
| `TextInverse` | `#FAFAFA` | `#09090B` | `--text-inverse` |
| `Accent` | `#059669` | `#10B981` | `--accent` (Emerald) |
| `AccentHover` | `#047857` | `#059669` | `--accent-hover` |
| `Warn` | `#D97706` | `#F59E0B` | `--warn` |
| `Danger` | `#DC2626` | `#EF4444` | `--danger` |
| `Info` | `#2563EB` | `#3B82F6` | `--info` |
| `Purple` | `#9333EA` | `#A855F7` | `--purple`（备注标签） |
| `AlarmSunset1` | `#F97316` | `#F97316` | sunset 渐变橙 |
| `AlarmSunset2` | `#EF4444` | `#EF4444` | sunset 渐变红 |
| `AlarmSunset3` | `#6A040F` | `#6A040F` | sunset 渐变暗红 |

> HTML 的 `--accent-soft / --warn-soft / --danger-soft / --info-soft` 及 `--accent-border` 不单独建 Color Set，统一用 `Color.cicadaXxx.opacity(0.12)`（软背景）/ `.opacity(0.3)`（强调边框）在调用处派生，避免 Color Set 数量爆炸。语义色用法固定：绿=成功/激活、橙=警告、红=危险/错误、蓝=信息、紫=备注标签。

调用方式：`Color("Accent")` 或封装为扩展：

```swift
extension Color {
    static let cicadaAccent       = Color("Accent")
    static let cicadaAccentHover  = Color("AccentHover")
    static let cicadaBgBase       = Color("BGBase")
    static let cicadaBgSurface    = Color("BGSurface")
    static let cicadaBgSurface2   = Color("BGSurface2")
    static let cicadaBGElevated   = Color("BGElevated")
    static let cicadaBgHover      = Color("BGHover")
    static let cicadaBorderSubtle = Color("BorderSubtle")
    static let cicadaBorder       = Color("BorderDefault")
    static let cicadaBorderStrong = Color("BorderStrong")
    static let cicadaTextPrimary  = Color("TextPrimary")
    static let cicadaTextSecondary = Color("TextSecondary")
    static let cicadaTextTertiary = Color("TextTertiary")
    static let cicadaTextInverse  = Color("TextInverse")
    static let cicadaWarn         = Color("Warn")
    static let cicadaDanger       = Color("Danger")
    static let cicadaInfo         = Color("Info")
    static let cicadaPurple       = Color("Purple")
}
```

> 命名约定：`cicadaXxx` 直接对应 Color Set 名，避免与 SwiftUI 系统语义色（`.primary`/`.secondary`）冲突。组件代码里一律用这些别名，不裸写 `Color("Accent")`。

Accent 设为 App 的 `.tint(.cicadaAccent)`，让系统控件（Toggle、焦点环）自动套用。

> 外观策略：Cicada 以深色为主调，但不强制。主窗口与菜单栏用 `.preferredColorScheme(nil)` 跟随系统外观——Color Set 已给 Light 合理映射，浅色下也能用。警戒全屏 `AlarmOverlay` 固定 `.dark`，因为 sunset 渐变在浅色下会失去沉浸感；刘海面板同理固定深色毛玻璃。

### 2.2 字体

不用硬编码字号，全部用 SwiftUI 语义字体 + `.monospaced()`：

| HTML token | SwiftUI | 用途 |
|---|---|---|
| Display / 28 / 700 / -0.03em | `.system(size: 28, weight: .bold, design: .default).tracking(-0.6)` | `sec-title` |
| Title / 18 / 700 | `.title2.weight(.bold)` | Hero 标题 |
| Body / 14 | `.body` | 正文、描述 |
| Label / 13 / 500 | `.subheadline.weight(.medium)` | 行标题、卡片标题 |
| Caption / 12 / secondary | `.caption` + `.foregroundStyle(.cicadaTextSecondary)` | 辅助说明 |
| Mono / 12 | `.caption.monospaced()` | 版本号、会话 ID、时间戳 |
| sec-label / 11 / 600 / uppercase / 0.08em | `.caption2.weight(.semibold).tracking(1.0).textCase(.uppercase)` | 分区编号 |

> macOS 上 `tracking()` 需要 14+；13 目标用 `.kern` 修饰符替代（`.kern(0.08)` 等值用 pt 近似）。

### 2.3 间距与圆角常量

集中在一个 `DesignMetrics` enum，避免散落魔数：

```swift
enum DesignMetrics {
    // 8pt 网格
    enum Spacing {
        static let s1: CGFloat  = 4
        static let s2: CGFloat  = 8
        static let s3: CGFloat  = 12
        static let s4: CGFloat  = 16
        static let s5: CGFloat  = 20
        static let s6: CGFloat  = 24
        static let s8: CGFloat  = 32
        static let s10: CGFloat = 40
        static let s12: CGFloat = 48
    }
    enum Radius {
        static let sm: CGFloat  = 6
        static let md: CGFloat  = 10
        static let lg: CGFloat  = 14
        static let xl: CGFloat  = 20
        static let x2l: CGFloat = 28
    }
    enum Shadow {
        static let sm   = (radius: 2,  x: 0, y: 1, opacity: 0.3)
        static let md   = (radius: 12, x: 0, y: 4, opacity: 0.25)
        static let lg   = (radius: 32, x: 0, y: 12, opacity: 0.35)
        static let diff = (radius: 20, x: 0, y: 2, opacity: 0.15)   // 弥散阴影，卡片浮起
        static let accent = (radius: 20, x: 0, y: 0, opacity: 0.15, color: .cicadaAccent)
    }
    static let sidebarWidth: CGFloat = 240
    static let progressRingSize: CGFloat = 56
}
```

`Shadow.accent` 需要彩色阴影时用 `.shadow(color:radius:x:y:)`。

---

## 3. 导航与视图层级

### 3.1 主控制中心 — `ControlCenterRoot`

用 `NavigationSplitView` 实现 HTML 的「左侧栏 + 右侧详情」双栏：

```swift
struct ControlCenterRoot: View {
    @EnvironmentObject var appModel: AppModel
    @State private var selection: NavSection? = .overview

    enum NavSection: String, Hashable, CaseIterable, Identifiable {
        case overview, settings, maintenance
        var id: String { rawValue }
        var title: String { … }
        var systemImage: String { … }      // "eye" / "slider.horizontal.3" / "wrench.and.screwdriver"
        var statusText: String { … }       // "运行中" / "就绪" / "睡眠保持空闲"
    }

    var body: some View {
        NavigationSplitView {
            List(NavSection.allCases, selection: $selection) { section in
                NavRow(section: section, active: selection == section)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(DesignMetrics.sidebarWidth)
        } detail: {
            switch selection {
            case .overview:    OverviewPane()
            case .settings:    SettingsPane()
            case .maintenance: MaintenancePane()
            case .none:        OverviewPane()
            }
        }
    }
}
```

- `NavRow`：自定义行，左侧 `Image(systemName:)` + 标题 + 状态副标题；选中态用 `.accent` 软背景 + 边框（用 `.listRowBackground` + 条件填充实现，不用 HTML 的边框 hack）。
- macOS 14 `NavigationSplitView` 原生支持侧栏样式、宽度记忆，不需要手写 split。

### 3.2 各 Pane 的内部结构

每个 Pane 顶部固定一个 `PaneHeader`（标题 + 副标题 + 右侧帮助按钮），下面是 `ScrollView` + `VStack`（卡片纵向堆叠，`spacing: DesignMetrics.Spacing.s4`）。本节只展开 `OverviewPane` 的骨架与子视图；`SettingsPane` 的 Tab 结构见 §11，`MaintenancePane` 的卡片布局见 §12——三个 Pane 共用 §4 的通用组件。

```swift
struct OverviewPane: View {
    @EnvironmentObject var appModel: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignMetrics.Spacing.s5) {
                PaneHeader(title: "Cicada 控制中心",
                           subtitle: "状态、控制与配置的统一入口",
                           trailing: HelpButton())
                StatusHeroCard(state: appModel.sentinels.state)
                ReadinessCard(items: appModel.sentinels.readiness)
                if let diag = appModel.sentinels.diagnostic {
                    DiagnosticStrip(diag: diag)
                }
                VersionTag()
            }
            .padding(DesignMetrics.Spacing.s6)
        }
    }
}
```

---

## 4. 组件规范

### 4.1 StatusHeroCard（概览 Hero）

渐变背景 + 左侧大图标 + 右侧状态徽章 + 右上角光晕。

```swift
struct StatusHeroCard: View {
    let state: SentinelState          // .running / .warning / .idle

    var body: some View {
        HStack(spacing: DesignMetrics.Spacing.s5) {
            StatusIcon(state: state, size: 56)
            VStack(alignment: .leading, spacing: DesignMetrics.Spacing.s1) {
                HStack(spacing: DesignMetrics.Spacing.s3) {
                    Text(state.title).font(.title2.weight(.bold))
                    StatusBadge(state: state)
                }
                Text(state.description)
                    .font(.subheadline)
                    .foregroundStyle(.cicadaTextSecondary)
            }
            Spacer()
        }
        .padding(DesignMetrics.Spacing.s6)
        .background {
            // 渐变 + 右上角径向光晕
            ZStack {
                LinearGradient(colors: [.cicadaBgSurface2, .cicadaAccent.opacity(0.06)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                RadialGradient(colors: [.cicadaAccent.opacity(0.12), .clear],
                               center: .topTrailing, radius: 1.2)
                    .allowsHitTesting(false)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: DesignMetrics.Radius.xl))
        .overlay(RoundedRectangle(cornerRadius: DesignMetrics.Radius.xl)
                    .stroke(.cicadaBorderSubtle, lineWidth: 1))
    }
}
```

`StatusBadge`：`capsule` 形状，按 state 选 accent/warn/idle 配色。

### 4.2 ReadinessCard + ProgressRing

清单行用 `VStack` + 自定义 `ReadinessRow`，不用 `Form`（视觉太系统化）。进度环用 `Canvas` 或 `Shape`：

```swift
struct ProgressRing: View {
    let progress: Double              // 0...1
    let size: CGFloat = DesignMetrics.progressRingSize
    private let lineWidth: CGFloat = 4

    var body: some View {
        ZStack {
            Ring(progress: 1).stroke(.cicadaBorderSubtle, lineWidth: lineWidth)
            Ring(progress: progress)
                .stroke(.cicadaAccent, style: .init(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(Int(progress * 100))%")
                .font(.caption.weight(.bold))
                .foregroundStyle(.cicadaAccent)
        }
        .frame(width: size, height: size)
        .animation(.easeOut(duration: 0.5), value: progress)
    }

    struct Ring: Shape {
        let progress: Double
        func path(in r: CGRect) -> Path {
            var p = Path()
            p.addArc(center: CGPoint(x: r.midX, y: r.midY),
                     radius: min(r.width, r.height) / 2 - 2,
                     startAngle: .zero,
                     endAngle: .degrees(360 * progress),
                     clockwise: false)
            return p
        }
    }
}
```

`ReadinessRow`：`HStack` = 状态圆点（`Circle` + glow via `.shadow`）+ 标题 + 右侧状态值。

### 4.3 DiagnosticStrip

琥珀色告警条，仅在 `diagnostic != nil` 时出现：

```swift
struct DiagnosticStrip: View {
    let diag: Diagnostic
    var body: some View {
        HStack(alignment: .top, spacing: DesignMetrics.Spacing.s3) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.cicadaWarn)
            Text(diag.message).font(.caption).foregroundStyle(.cicadaWarn)
            Spacer()
        }
        .padding(.horizontal, DesignMetrics.Spacing.s4)
        .padding(.vertical, DesignMetrics.Spacing.s3)
        .background(Color.cicadaWarn.opacity(0.12))
        .overlay(RoundedRectangle(cornerRadius: DesignMetrics.Radius.md)
                    .stroke(.cicadaWarn.opacity(0.2), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: DesignMetrics.Radius.md))
    }
}
```

### 4.4 Card / CardHeader

通用容器，供设置、维护区复用：

```swift
struct Card<Header: View, Content: View>: View {
    let title: String
    @ViewBuilder let trailing: Header
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: DesignMetrics.Spacing.s4) {
            HStack {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.cicadaTextSecondary)
                Spacer()
                trailing
            }
            content()
        }
        .padding(DesignMetrics.Spacing.s5)
        .background(Color.cicadaBgSurface2)
        .clipShape(RoundedRectangle(cornerRadius: DesignMetrics.Radius.lg))
        .overlay(RoundedRectangle(cornerRadius: DesignMetrics.Radius.lg)
                    .stroke(.cicadaBorderSubtle, lineWidth: 1))
    }
}
```

### 4.5 SettingRow

行式配置项，左标题+描述、右 Toggle/输入/Picker：

```swift
struct SettingRow<Control: View>: View {
    let title: String
    let desc: String
    @ViewBuilder let control: () -> Control

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.medium))
                Text(desc).font(.caption).foregroundStyle(.cicadaTextTertiary)
            }
            Spacer(minLength: DesignMetrics.Spacing.s6)
            control()
        }
        .padding(.vertical, DesignMetrics.Spacing.s3)
        .overlay(alignment: .bottom) {
            Rectangle().fill(.cicadaBorderSubtle).frame(height: 1)
        }
    }
}
```

> 实际用 `Form`/`List` + `.listRowSeparator` 也能得到分割线，但设计要的是自定义节奏和背景，这里用纯 `VStack` 行更可控。

### 4.6 Toggle

直接用系统 `Toggle(isOn:)`，配 `.tint(.cicadaAccent)` 即可匹配 HTML 的 accent 绿。开关尺寸系统固定，不要强行改。

### 4.7 Button 样式

三个自定义 `ButtonStyle`：

```swift
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, DesignMetrics.Spacing.s4)
            .padding(.vertical, DesignMetrics.Spacing.s2)
            .background(configuration.isPressed ? Color.cicadaAccentHover : Color.cicadaAccent)
            .foregroundStyle(.cicadaTextInverse)
            .clipShape(RoundedRectangle(cornerRadius: DesignMetrics.Radius.md))
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

struct GhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, DesignMetrics.Spacing.s4)
            .padding(.vertical, DesignMetrics.Spacing.s2)
            .background(configuration.isPressed ? Color.cicadaBgHover : Color.cicadaBGElevated)
            .foregroundStyle(.cicadaTextSecondaryondary)
            .clipShape(RoundedRectangle(cornerRadius: DesignMetrics.Radius.md))
            .overlay(RoundedRectangle(cornerRadius: DesignMetrics.Radius.md)
                        .stroke(.cicadaBorderDefault, lineWidth: 1))
    }
}

struct DangerButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, DesignMetrics.Spacing.s4)
            .padding(.vertical, DesignMetrics.Spacing.s2)
            .background(Color.cicadaDanger.opacity(configuration.isPressed ? 0.2 : 0.12))
            .foregroundStyle(.cicadaDanger)
            .clipShape(RoundedRectangle(cornerRadius: DesignMetrics.Radius.md))
            .overlay(RoundedRectangle(cornerRadius: DesignMetrics.Radius.md)
                        .stroke(.cicadaDanger.opacity(0.3), lineWidth: 1))
    }
}

struct SmallButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption.weight(.medium))
            .padding(.horizontal, DesignMetrics.Spacing.s3)
            .padding(.vertical, DesignMetrics.Spacing.s1)
            .background(configuration.isPressed ? Color.cicadaAccentHover : Color.cicadaAccent)
            .foregroundStyle(.cicadaTextInverse)
            .clipShape(RoundedRectangle(cornerRadius: DesignMetrics.Radius.sm))
    }
}
```

禁用态统一用 `.disabled(true)`，系统自动降透明度，无需在 `ButtonStyle` 内手写。

### 4.8 表单输入

```swift
struct CicadaTextField: View {
    let title: String
    @Binding var text: String
    let hint: String?
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: DesignMetrics.Spacing.s2) {
            Text(title).font(.caption.weight(.medium)).foregroundStyle(.cicadaTextSecondary)
            TextField("", text: $text)
                .textFieldStyle(.plain)
                .focused($isFocused)
                .padding(.horizontal, DesignMetrics.Spacing.s4)
                .padding(.vertical, DesignMetrics.Spacing.s3)
                .background(Color.cicadaBgBase)
                .clipShape(RoundedRectangle(cornerRadius: DesignMetrics.Radius.md))
                .overlay(RoundedRectangle(cornerRadius: DesignMetrics.Radius.md)
                            .stroke(isFocused ? .cicadaAccent : .cicadaBorderDefault, lineWidth: 1))
                .shadow(isFocused ? .cicadaAccent.opacity(0.12) : .clear, radius: 6)
            if let hint { Text(hint).font(.caption2).foregroundStyle(.cicadaTextTertiary) }
        }
    }
}
```

焦点高亮：`@FocusState` 驱动边框切 `.cicadaAccent` + `shadow(.cicadaAccent.opacity(0.12), radius: 6)`，失焦恢复 `.cicadaBorderDefault` + 无阴影。`@FocusState` 需要 macOS 12+，与部署目标兼容。

### 4.9 Picker（下拉）

HTML 的自定义 `.picker` 用 SwiftUI `Picker` + `.pickerStyle(.menu)` 即可，外观足够接近。需要完全自定义时用 `Menu` + 触发器按钮。

### 4.10 InlineMessage

```swift
struct InlineMessage: View {
    enum Kind { case ok, err }
    let kind: Kind
    let text: String
    var body: some View {
        HStack(spacing: DesignMetrics.Spacing.s2) {
            Image(systemName: kind == .ok ? "checkmark.circle.fill" : "xmark.octagon.fill")
            Text(text)
        }
        .font(.caption)
        .padding(.horizontal, DesignMetrics.Spacing.s3).padding(.vertical, DesignMetrics.Spacing.s2)
        .background((kind == .ok ? Color.cicadaAccent : Color.cicadaDanger).opacity(0.12))
        .foregroundStyle(kind == .ok ? .cicadaAccent : .cicadaDanger)
        .clipShape(RoundedRectangle(cornerRadius: DesignMetrics.Radius.sm))
    }
}
```

### 4.11 FolderGridButton（维护区 3 列网格）

```swift
LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
          spacing: DesignMetrics.Spacing.s3) {
    ForEach(folderActions) { FolderButton(action: $0) }
}

struct FolderButton: View {
    let action: FolderAction
    @State private var hover = false
    var body: some View {
        VStack(spacing: DesignMetrics.Spacing.s2) {
            Image(systemName: action.systemImage).font(.title3)
            Text(action.label).font(.caption)
        }
        .frame(maxWidth: .infinity)
        .padding(DesignMetrics.Spacing.s4)
        .background(hover ? Color.cicadaAccent.opacity(0.12) : Color.cicadaBgBase)
        .overlay(RoundedRectangle(cornerRadius: DesignMetrics.Radius.md)
                    .stroke(hover ? .cicadaAccent.opacity(0.3) : .cicadaBorderSubtle, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: DesignMetrics.Radius.md))
        .onHover { hover = $0 }
    }
}
```

### 4.12 SleepHoldCell（数据卡片矩阵）

```swift
HStack(spacing: DesignMetrics.Spacing.s3) {
    ForEach(sleepHoldCells) { cell in
        VStack(alignment: .leading, spacing: DesignMetrics.Spacing.s1) {
            Text(cell.label).font(.caption2).foregroundStyle(.cicadaTextTertiary)
                .textCase(.uppercase).tracking(0.5)
            Text(cell.value)
                .font(cell.isMono ? .caption.monospaced() : .subheadline.weight(.medium))
                .foregroundStyle(cell.ok ? .cicadaAccent : .primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DesignMetrics.Spacing.s3)
        .background(Color.cicadaBgBase)
        .clipShape(RoundedRectangle(cornerRadius: DesignMetrics.Radius.md))
        .overlay(RoundedRectangle(cornerRadius: DesignMetrics.Radius.md)
                    .stroke(.cicadaBorderSubtle, lineWidth: 1))
    }
}
```

### 4.13 VersionTag

`Text("Cicada v2.1.0 (build 347) · macOS 14.5")`
`.font(.caption.monospaced()).foregroundStyle(.cicadaTextTertiary)` + 顶部 1px 分割线。

### 4.14 CameraPreview

未授权占位：黑底 `RoundedRectangle` + 居中 `Image(systemName: "camera.fill")` + 说明文字，顶部加一层 `LinearGradient` 高光。

---

## 5. 警戒全屏视图 — `AlarmOverlay`

对应 HTML 的 sunset 渐变 + 毛玻璃 + 旋转眼睛。

### 5.1 布局

```swift
struct AlarmOverlay: View {
    @EnvironmentObject var appModel: AppModel
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        ZStack {
            // ① sunset 渐变（多层径向叠加，模拟 ColorfulView(.sunset)）
            SunsetGradient()
            // ② thinMaterial 毛玻璃
            Rectangle().fill(.ultraThinMaterial).opacity(0.5)

            HStack(spacing: 0) {
                // 左侧文字区
                AlarmLeftPanel(reason: appModel.alarm.reason) {
                    Task { await appModel.alarm.stop(); dismissWindow() }
                }
                // 竖向黑色分隔条
                Rectangle().fill(Color.black.opacity(0.5)).frame(width: 10)
                // 右侧眼睛
                AlarmEye()
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 32))
        .background(.black)
    }
}
```

`SunsetGradient`：

```swift
struct SunsetGradient: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color("AlarmSunset1"), Color("AlarmSunset2"),
                                     Color("AlarmSunset3"), Color(red: 0.21, green: 0.04, blue: 0.01)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(colors: [Color(red: 1, green: 0.7, blue: 0.3, opacity: 0.35), .clear],
                           center: UnitPoint(x: 0.25, y: 0.3), radius: 0.6)
            RadialGradient(colors: [Color(red: 0.86, green: 0.16, blue: 0.24, opacity: 0.3), .clear],
                           center: UnitPoint(x: 0.75, y: 0.7), radius: 0.55)
        }
    }
}
```

`AlarmLeftPanel`：装饰图标（`Image(systemName: "eye.fill").opacity(0.2)`）顶对齐 + `Spacer`，标题 `.system(size: 28, weight: .heavy)` 白色 + 描述 15pt 半透明白 + 停止按钮。

### 5.2 AlarmEye（核心动画）

眼睛由 4 层组成，全部用 SwiftUI `Shape`/`Canvas` + 动画：

| 层 | HTML | SwiftUI 实现 |
|---|---|---|
| 眼白边框 | 8px 橙色环 | `Circle().stroke(Color("AlarmSunset1").opacity(0.3), lineWidth: 8)` |
| 虹膜渐变 | radial red→orange→red | `Circle().fill(RadialGradient(...))` |
| 外层纹理线 | 36 条 conic 黑线，20s 旋转 | `Canvas` 画 36 条径向线，整体 `.rotationEffect` + `.animation(.linear(duration: 20).repeatForever(autoreverses: false))` |
| 内层纹理线 | 24 条红色线 | 同上，半径缩小 25% |
| 瞳孔 | black→red 径向 + 2s 缩放脉动 | `Circle().fill(RadialGradient)` + `scaleEffect` `.easeInOut(2s).repeatForever(autoreverses:true)` |
| 反光点 | 8px 圆 + 2s 透明度闪烁 | `Circle()` + `opacity` `.easeInOut(2s).repeatForever(autoreverses:true)` |

旋转/脉动用 `@State` 驱动 + `.onAppear { rotation = 360 }`，`.animation(.linear(duration: 20).repeatForever(autoreverses: false), value: rotation)`。纯 SwiftUI 动画，无 `CADisplayLink`/`Timer`。

> conic-gradient 在 SwiftUI 没有原生等价，用 `Canvas` 按 36 等分画径向线段最准确；也可用 36 个细 `Capsule` 旋转排列，但 Canvas 性能更好。

---

## 6. NotchDrop

### 6.1 打开态 `NotchPanel`

```swift
struct NotchPanel: View {
    var body: some View {
        VStack(spacing: DesignMetrics.Spacing.s3) {
            NotchHeader(title: "NotchDrop", trailing: Menu { ... } label: { Image(systemName: "ellipsis") })
            HStack(spacing: DesignMetrics.Spacing.s3) {
                NotchSection(icon: "arrow.up.bin", text: "拖放以 AirDrop",
                             dashed: true)        // .onDrop(of: [.fileURL], ...)
                NotchSection(icon: "tray", text: "拖放文件到此处暂存一周",
                             dashed: true)        // .onDrop(of: [.fileURL], ...)
            }
        }
        .padding(DesignMetrics.Spacing.s4)
        .frame(width: 600)
        .background {
            ZStack {
                Color.black.opacity(0.55)          // 底色压暗，保证文字对比
                .ultraThinMaterial                  // 系统毛玻璃，不要再叠 opacity
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: DesignMetrics.Radius.xl))
        .overlay(RoundedRectangle(cornerRadius: DesignMetrics.Radius.xl)
                    .stroke(.white.opacity(0.06), lineWidth: 1))
        .shadow(.black.opacity(0.5), radius: 30, y: 20)
    }
}
```

> material 不接受 opacity 调制——`.background(Color.black.opacity(0.7).ultraThinMaterial)` 是反模式，会破坏材质渲染。正确做法是 `ZStack` 里先铺一层半透明底色再叠 material，让系统接管模糊。

虚线边框：自定义 `DashedBorder: Shape` 或 `Canvas` 画 dashed stroke。

文件接收：`NotchSection` 用 `.onDrop(of: [.fileURL], isTargeted: $isTargeted)`，`isTargeted` 时边框切 `.cicadaAccent`。实际落盘逻辑交给下层 ViewModel，UI 只管拖放视觉反馈。

### 6.2 菜单 `NotchMenu`

横向 5 个方块按钮（关闭 / GitHub / 赞助 / 设置 / 清空）：

```swift
HStack(spacing: DesignMetrics.Spacing.s3) {
    NotchMenuButton(icon: "xmark", label: "关闭", tint: .cicadaDanger) {
        // 关闭面板
    }
    NotchMenuButton(icon: "network", label: "AirDrop") { … }
    NotchMenuButton(icon: "ellipsis.bubble", label: "GitHub") { openURL(...) }
    NotchMenuButton(icon: "heart", label: "赞助") { openURL(...) }
    NotchMenuButton(icon: "gearshape", label: "设置") { … }
    NotchMenuButton(icon: "trash", label: "清空", tint: .cicadaDanger) { … }
}
```

`NotchMenuButton`：72×72 圆角方块，`.onHover` 缩放 1.05 + 背景提亮（`.scaleEffect` + `.animation(.spring(response: 0.2))`）。关闭/清空用 `.cicadaDanger` 色调，其余中性。

---

## 7. 菜单栏下拉 — `MenuBarDropdown`

由 `MenuBarExtra(.window)` 自动承载窗口，内容：

```swift
struct MenuBarDropdown: View {
    @EnvironmentObject var appModel: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: DesignMetrics.Spacing.s2) {
            MenuBarStatusCard(state: appModel.sentinels.state,
                              detail: "监控活跃 · \(appModel.sentinels.activeTriggerCount) 个触发器")
            MenuBarButton(icon: "rectangle.split.2x1", title: "打开控制中心") {
                openWindow(id: "control-center")
            }
            MenuBarButton(icon: "slider.horizontal.3", title: "设置…") { … }
            MenuBarButton(icon: "wrench.and.screwdriver", title: "维护…") { … }
            Divider()
            MenuBarButton(icon: "arrow.right.square", title: "退出 Cicada", tint: .cicadaDanger) {
                appModel.quit()
            }
        }
        .padding(DesignMetrics.Spacing.s2)
        .frame(width: 280)
        .onAppear { Task { await appModel.sentinels.refresh() } }
    }
}
```

`MenuBarButton`：`.menuBarExtraStyle(.window)` 下 hover 由系统处理；如要自定义 hover 高亮，用 `Button` + `ButtonStyle`，`isPressed` 时切 accent 背景 + inverse 文字。

---

## 8. 帮助面板 — `HelpSheet`

作为主窗口的 `.sheet` 或独立 `Window` 呈现，结构：

```swift
struct HelpSheet: View {
    var body: some View {
        VStack(alignment: .leading, spacing: DesignMetrics.Spacing.s4) {
            // 简介：富文本，关键词加粗
            Text(helpIntro).font(.subheadline).foregroundStyle(.cicadaTextSecondary)
            Divider()
            HelpSection(title: "可用触发器", icon: "bolt.fill", accent: true) {
                HelpNumberedList(items: ["合上 Mac 盖子", "断开网络连接", "断开电源适配器"])
            }
            Divider()
            HelpSection(title: "注意事项", icon: "exclamationmark.triangle.fill", accent: true) {
                HelpBulletList(items: [...])
            }
        }
        .padding(DesignMetrics.Spacing.s6)
        .frame(width: 420)
        .background(Color.cicadaBgSurface)
        .clipShape(RoundedRectangle(cornerRadius: DesignMetrics.Radius.lg))
        .overlay(RoundedRectangle(cornerRadius: DesignMetrics.Radius.lg)
                    .stroke(.cicadaBorderDefault, lineWidth: 1))
    }
}
```

`HelpNumberedList`：`ForEach` + `HStack { Text("\(n)").foregroundStyle(.cicadaAccent).monospacedDigit(); Text(item) }`，编号用 accent 色。

---

## 9. 数据模型与网络层

本节是 §1.2 状态分层的落地细节：展示模型、ViewModel 实现、IPC/HTTP 桥接。视图层只通过 `@ObservedObject`/`@EnvironmentObject` 读这些 ViewModel，不直接碰 IPC。

### 9.1 模型协议

所有需进 `List`/`ForEach` 的模型加 `Identifiable`；传输模型复用现有 `Codable`。

```swift
// 复用 CicadaCore.CicadaConfig（已 Codable）——GUI 层不重复定义
// 新增面向 UI 的展示模型，统一 Identifiable

struct ReadinessItem: Identifiable {
    let id = UUID()
    let key: String        // "triggers" / "notifications" / "camera" / "activation"
    let label: String
    let status: ReadinessStatus   // .ok / .warn / .off
    let valueText: String
}

enum ReadinessStatus { case ok, warn, off }

struct Diagnostic: Identifiable {
    let id = UUID()
    let level: DiagLevel      // .warn / .danger
    let message: String
}

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

现有 IPC 响应模型已经是 `Codable`（`SentinelStatusSnapshot`、`DaemonControlResponse`），UI 层做一层映射函数 `func toReadiness(_ snap: SentinelStatusSnapshot) -> [ReadinessItem]`，保持传输模型与视图模型解耦。

### 9.2 状态对象（`@StateObject` / `@ObservedObject`）

```swift
@MainActor
final class SentinelsModel: ObservableObject {
    @Published private(set) var state: SentinelState = .idle
    @Published private(set) var readiness: [ReadinessItem] = []
    @Published private(set) var diagnostic: Diagnostic?
    @Published private(set) var activeTriggerCount: Int = 0

    private let client: SentinelControlClienting   // 复用现有 UdsSentinelControlClient

    init(client: SentinelControlClienting = UdsSentinelControlClient()) {
        self.client = client
    }

    func refresh() async {
        do {
            let resp = try await Task.detached { try self.client.status() }.value
            apply(resp.status)
        } catch {
            state = .idle
            diagnostic = Diagnostic(level: .warn, message: "无法连接 sentinel: \(error)")
        }
    }

    func start() async { … }      // try await Task.detached { try client.start() }.value
    func stop() async { … }

    private func apply(_ snap: SentinelStatusSnapshot?) { … }
}
```

- `@MainActor` 保证 `@Published` 更新在主线程。
- 现有 IPC client 是同步阻塞（POSIX socket），所以包一层 `Task.detached { try client... }` 拿到结果后回主线程赋值。不要在主线程直接调。
- 轮询：`AppModel` 启动一个 `Timer.publish` 或 `Task` + `try await Task.sleep`，每 N 秒 `await sentinels.refresh()`。

```swift
@MainActor
final class ConfigModel: ObservableObject {
    @Published var draft: CicadaConfig          // 编辑态，双向绑定到输入框
    @Published var saveState: SaveState = .idle // .idle / .saving / .ok / .err(String)

    private let store: ConfigStore

    func load() { draft = (try? store.load()) ?? .defaultConfig() }
    func save() async {
        saveState = .saving
        do {
            try store.save(draft)
            saveState = .ok
        } catch { saveState = .err(error.localizedDescription) }
    }
}
```

设置页的输入框绑 `@Binding` 到 `configModel.draft.relayURL` 等；点「保存」触发 `save()`，结果用 `InlineMessage` 显示。

### 9.3 网络层 — `async/await` + `URLSession`

两类网络：

**(A) IPC（Unix Domain Socket）**：复用现有 `UdsSentinelControlClient` / `UdsDaemonControlClient`。它们是同步 API，UI 层用 `Task.detached` 包装为异步：

```swift
extension SentinelControlClienting {
    func statusAsync() async throws -> SentinelControlResponse {
        try await Task.detached(priority: .userInitiated) { try self.status() }.value
    }
    func startAsync() async throws -> SentinelControlResponse {
        try await Task.detached(priority: .userInitiated) { try self.start() }.value
    }
    // stop / unlock / open 同理
}
```

**(B) Bark 推送（HTTP）**：纯 `URLSession` + `async/await`：

```swift
struct BarkClient {
    let endpoint: URL
    let session: URLSession = .shared

    func push(title: String, body: String) async throws {
        var req = URLRequest(url: endpoint.appendingPathComponent("\(title)/\(body)"))
        req.httpMethod = "POST"
        let (_, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw BarkError.badStatus
        }
    }
}
```

**(C) Relay 连接（WebSocket）**：若 GUI 需要直连 relay（当前由 daemon 承担），用 `URLSessionWebSocketTask` + `async/await` 收发；但按现有架构 GUI 不直连，只通过 daemon IPC 看 relay 状态，这里不展开。

> 所有网络/IPC 调用都在 ViewModel 的 `async` 方法里完成，视图层只 `Task { await model.x() }`，不在 View 里直接做网络。

### 9.4 属性包装器使用一览

| 包装器 | 用在哪 |
|---|---|
| `@State` | 局部 UI 状态：选中行、hover、输入草稿、动画驱动值（眼睛旋转角度） |
| `@Binding` | 子视图接收父级 `@State`/`@Published` 的引用（`CicadaTextField(text: $model.draft.relayURL)`、`SettingRow` 的 Toggle） |
| `@StateObject` | 视图**拥有并创建**的 ViewModel（`AppModel` 在 App 入口、各 Pane 若有独立 VM） |
| `@ObservedObject` | 视图**接收但不拥有**的 ViewModel（子视图拿到 `appModel.sentinels`） |
| `@EnvironmentObject` | 跨层级共享的全局模型（`AppModel`、`ConfigModel` 注入整个视图树） |
| `@FocusState` | 输入框焦点管理 |
| `@SceneStorage` | 主窗口侧栏选中项、设置 Tab 选中项（窗口重开后恢复） |

---

## 10. 动画与过渡

| 场景 | 实现 |
|---|---|
| 警戒眼睛虹膜 20s 旋转 | `@State var rot: Double = 0`；`.onAppear { rot = 360 }`；`.rotationEffect(.degrees(rot)).animation(.linear(duration: 20).repeatForever(autoreverses:false), value: rot)` |
| 瞳孔 2s 脉动 | `@State var pulse = false`；`.onAppear{pulse=true}`；`scaleEffect(pulse ? 0.8 : 1).animation(.easeInOut(duration:2).repeatForever(autoreverses:true), value: pulse)` |
| 反光点闪烁 | `opacity` + 同上 |
| 进度环填充 | `.animation(.easeOut(duration:0.5), value: progress)` |
| Toggle 开关 | 系统自带 spring |
| 文件夹按钮 hover 缩放 | `.scaleEffect(hover ? 1.02 : 1).animation(.spring(response:0.2), value: hover)` |
| NotchMenu 按钮 hover | `.scaleEffect(hover ? 1.05 : 1)` + 背景色动画 |
| 警戒窗口进场 | `.transition(.scale.combined(with: .opacity))` + 父级 `.animation(.spring(response:0.4))` |
| 内联消息出现 | `.transition(.opacity.combined(with: .move(edge:.top)))` |
| 设置 Tab 切换 | `withAnimation(.easeInOut(duration:0.2)) { selectedTab = ... }`；内容区可用 `.transition(.opacity)` |
| 侧栏选中切换 | `NavigationSplitView` 自带；自定义行用 `.animation(.easeInOut(duration:0.15))` 跟随 `selection` |

全部用 SwiftUI 声明式动画，不引入 `CADisplayLink`/`Timer` 驱动帧。

### 10.1 无障碍兜底（reduceMotion）

警戒眼睛的 20s 无限旋转 + 2s 脉动、反光点闪烁属于强动效，必须在用户开启「减弱动态效果」时收敛。SwiftUI 等价物是 `@Environment(\.accessibilityReduceMotion)`：

```swift
struct AlarmEye: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var rot: Double = 0
    @State private var pulse = false

    var body: some View {
        IrisLayer()
            .rotationEffect(.degrees(rot))
            .animation(reduceMotion ? nil
                       : .linear(duration: 20).repeatForever(autoreverses: false),
                       value: rot)
        // 瞳孔脉动同理：reduceMotion 时退化为静态显示，保留配色与构图
        PupilLayer()
            .scaleEffect(reduceMotion ? 1 : (pulse ? 0.8 : 1))
            .animation(reduceMotion ? nil
                       : .easeInOut(duration: 2).repeatForever(autoreverses: true),
                       value: pulse)
        .onAppear {
            guard !reduceMotion else { return }
            rot = 360; pulse = true
        }
    }
}
```

规则：
- `reduceMotion == true` 时，所有 `repeatForever` 动画传 `nil`，元素停在终态/静态构图，不消失。
- hover 缩放（FolderButton / NotchMenu）保留——属于即时反馈，不属于持续动效，不影响前庭敏感用户。
- 进度环、Toggle、进场 transition 等短动画可保留。注意：系统**不会**自动简化自定义 `.animation`/`spring`(AlarmEye 手动传 `nil` 即为此);大幅位移/缩放动画须自行门控——刘海外壳开合已在 `NotchView` 手动接 reduceMotion(外壳瞬时改形 + 内容纯淡入)。
- VoiceOver：警戒窗口、状态徽章、进度环都要给 `accessibilityLabel`（如「警戒已触发：合盖」/「就绪度 80%」），眼睛的纯装饰旋转层加 `.accessibilityHidden(true)`。

---

## 11. 设置页子导航

HTML 用 `.sub-nav` 横向 Tab（连接/防护/告警/录像/NotchDrop）。SwiftUI 用 `Picker(.segmented)` 或自定义 `SegmentedTab`：

```swift
struct SettingsPane: View {
    @SceneStorage("settings.tab") private var tab: SettingsTab = .connection
    @EnvironmentObject var appModel: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignMetrics.Spacing.s5) {
                PaneHeader(title: "设置", subtitle: "连接、防护、告警、录像与 NotchDrop")
                SettingsTabBar(selection: $tab)
                Group {
                    switch tab {
                    case .connection:  ConnectionCard(model: appModel.config)
                    case .protection:  ProtectionCard(model: appModel.config)
                    case .alerts:      AlertsCard(model: appModel.config)
                    case .recording:   RecordingCard(model: appModel.config)
                    case .notch:       NotchDropCard(model: appModel.config)
                    }
                }
                .transition(.opacity)
            }
            .padding(DesignMetrics.Spacing.s6)
        }
    }
}

enum SettingsTab: String, CaseIterable, Hashable {
    case connection, protection, alerts, recording, notch
    var title: String { … }   // "连接" / "防护" / "告警" / "录像" / "NotchDrop"
}
```

`SettingsTabBar`：`HStack` of `SettingsTabChip`，选中态 `.cicadaBGElevated` 背景 + `.cicadaTextPrimary` 文字 + `.cicadaBorderDefault` 边框；未选中 `.cicadaBgSurface` + tertiary 文字。

各设置 Card 内容映射 HTML：
- **ConnectionCard**：Relay 地址 `CicadaTextField` + 保存/重载按钮 + `InlineMessage`。
- **ProtectionCard**：3 个 `SettingRow` + `Toggle`（合盖 / 断网 / 断电）。
- **AlertsCard**：2 个 `SettingRow`+`Toggle`（声音 / Bark）+ Bark Endpoint 输入。
- **RecordingCard**：1 个 `Toggle` + `CameraPreview` 占位。
- **NotchDropCard**：触觉反馈 `Toggle` + 文件保留时长 `Picker` + 界面语言 `Picker`。

---

## 12. 维护页

```swift
struct MaintenancePane: View {
    @EnvironmentObject var appModel: AppModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignMetrics.Spacing.s4) {
                PaneHeader(title: "维护", subtitle: "运行时路径、睡眠保持会话与诊断")
                // 运行时
                Card(title: "运行时") {
                    SettingRow(title: "登录时启动 Cicada", desc: "登录时自动启动应用和服务") {
                        Toggle("", isOn: $appModel.config.draft.autoConnectAtLogin).tint(.cicadaAccent)
                    }
                }
                // 文件夹网格
                Card(title: "文件夹") { FolderGrid() }
                // SleepHold 状态
                Card(title: "SleepHold 状态") { SleepHoldCells(model: appModel.sleepHold) }
                // 诊断
                Card(title: "诊断", trailing: Button("运行启动检查") { Task { await appModel.runDiagnostics() } }
                                          .buttonStyle(PrimaryButtonStyle())) {
                    if let d = appModel.sleepHold.diagnostic { DiagnosticStrip(diag: d) }
                }
            }
            .padding(DesignMetrics.Spacing.s6)
        }
    }
}
```

---

## 13. 不包含的内容（约束声明）

- **无 UIKit / AppKit 视图内容**：所有可见 UI 均为 SwiftUI 视图。
- **窗口层级配置**：见 §1.1 的 NotchDrop / 警戒说明——`WindowAccessor` 仅取 `NSWindow` 设 `level`/`collectionBehavior`，不承载视图。这是必要的窗口配置而非 UI 桥接。若团队禁用一切 AppKit 符号，警戒改 `fullScreenCover`、刘海改普通浮窗，损失贴合度但功能不损。
- **无 `UIViewRepresentable` / `NSViewRepresentable`**。
- **无 Storyboard / XIB**。
- **不引入 Combine 驱动 UI**：现有 IPC 是同步阻塞式，统一在 ViewModel 里用 `Task.detached` 桥接到 `@Published`，不新建 Combine pipeline。

---

## 14. 落地清单

按依赖顺序拆分实现任务：

1. `Assets.xcassets` 建全部 Color Set + `DesignMetrics` + `Color` 扩展。
2. 复用/确认 `CicadaCore`、`CicadaIPC` 模块在 GUI target 可链接。
3. `AppModel` + `SentinelsModel` + `ConfigModel` + `SleepHoldModel` + async IPC wrapper。
4. 通用组件：`Card`、`SettingRow`、`CicadaTextField`、`InlineMessage`、`ProgressRing`、`DiagnosticStrip`、`StatusBadge`、3 个 `ButtonStyle`。
5. `ControlCenterRoot` + `NavRow` + 三个 Pane 骨架。
6. `OverviewPane` 全部子视图。
7. `SettingsPane` + TabBar + 5 个设置 Card。
8. `MaintenancePane` + FolderGrid + SleepHoldCells。
9. `AlarmOverlay` + `SunsetGradient` + `AlarmEye`（Canvas 旋转线 + 脉动）。
10. `NotchPanel` + `NotchMenu` + 拖放 `.onDrop`。
11. `MenuBarDropdown`。
12. `HelpSheet`。
13. 联调：IPC 状态轮询 → UI 刷新、警戒触发 → `openWindow("alarm")`、配置保存 → `InlineMessage`。

每步验收：编译通过 + 对应界面与 HTML 预览视觉一致 + 关键交互（Toggle/保存/拖放/警戒触发）能跑通。
