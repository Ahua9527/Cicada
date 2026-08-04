# Cicada P3 剩余部分实施 Spec：AlarmOverlay + NotchPanel 边界设计

> 架构师：高见远（Gao）｜交付总监：齐活林
> 基线文档：`docs/Design.md`（§5 警戒全屏、§6 NotchDrop）、`docs/Implementation-Plan-v2.md`（§4 简化后的步骤 9/10）
> 产出日期：2026-07-17
> 适用范围：P3 剩余部分——`AlarmOverlay`（警戒全屏）+ `NotchPanel`（刘海拖放面板）的**纯 SwiftUI 内容层**实施规格

---

## 0. 本文目的与范围

本文解决两个边界问题，并给出工程师可直接照写的详细 spec：

1. **边界问题 1**：`AlarmOverlay` 的 `ColorfulX` 依赖放在 CicadaUI 还是 Xcode 宿主？
2. **边界问题 2**：`NotchPanel` 的 `TrayDrop`/`AirDrop` 引擎如何通过协议抽象让 CicadaUI（SwiftPM）调用？

然后为以下文件给出**逐文件实施 spec**（路径、职责、关键代码要点、依赖、验收）：

- `Sources/CicadaUI/Views/Alarm/AlarmEye.swift`
- `Sources/CicadaUI/Views/Alarm/AlarmLeftPanel.swift`
- `Sources/CicadaUI/Views/Alarm/AlarmOverlayContent.swift`
- `Sources/CicadaUI/Views/NotchDrop/NotchDropDelegate.swift`
- `Sources/CicadaUI/Views/NotchDrop/NotchPanel.swift`
- `Sources/CicadaUI/Views/NotchDrop/NotchMenu.swift`
- `Sources/CicadaUI/Views/NotchDrop/NotchSection.swift`

并明确**留 Xcode 宿主 P4 实施**的部分。

---

## 1. 边界问题 1：AlarmOverlay 的 ColorfulX 依赖

### 1.1 现状探查

**现有原生应用如何引用 ColorfulX**：

- Xcode 工程 `Sentry.xcodeproj/project.pbxproj` 以 `XCRemoteSwiftPackageReference` 声明：
  - `repositoryURL = "https://github.com/Lakr233/ColorfulX"`
  - `requirement = upToNextMajorVersion, minimumVersion = 5.7.0`
- 作为 `packageProductDependencies` 挂到 Sentry target。
- ColorfulX 自身 `Package.swift`（`swift-tools-version: 5.9`，platforms `.macOS(.v11)+`）有 3 个传递依赖：`ColorVector`、`SpringInterpolation`、`MSDisplayLink`（均为 `https://github.com/Lakr233/*`）。
- 渲染层基于 **Metal + MSDisplayLink**（`AnimatedMulticolorGradientView` 系列），是 GPU 动画渐变。

**现有 SentryView.swift 的用法**（`apps/agent/native/sentinel-app/Sentry/SentryView.swift`）：

```swift
.background(
    ZStack {
        if sentry.isAlrming {
            ColorfulView(color: .sunset, noise: .constant(64))
                .transition(.opacity)
                .ignoresSafeArea()
        }
    }
)
```

即：`ColorfulView(.sunset)` 是**背景装饰层**，与内容层（`texts` + `eye`）解耦——内容层是纯 SwiftUI，背景层是独立渐变。

**SwiftPM Package.swift 现状**（`apps/agent/swift/Package.swift`）：

- `CicadaUI` target 当前依赖：`CicadaCore`、`CicadaIPC`、`CicadaSleepHoldCore`、`CicadaSystem`（全是同 repo 纯 Swift target，零外部远程依赖）。
- 若加 ColorfulX，需在 `CicadaUI` target 的 `dependencies` 加 `.package(url: "https://github.com/Lakr233/ColorfulX", from: "5.7.0")`（或顶层 `dependencies` 声明 + target 引用）。

### 1.2 方案对比

| 维度 | 方案 A：CicadaUI 加 ColorfulX 依赖，AlarmOverlay 整个放 CicadaUI | 方案 B：CicadaUI 只写纯 SwiftUI 部分，ColorfulView 背景留 Xcode 宿主 |
|---|---|---|
| CicadaUI 纯净度 | ❌ 引入 4 个远程 SPM 依赖 + Metal | ✅ 保持纯 SwiftUI，零外部远程依赖 |
| `swift build` 验证 | ⚠️ Metal shader 在无 GPU 的 CLI 构建环境有不确定性；构建时间显著增加 | ✅ 纯 SwiftUI，`swift build` 轻量可验证 |
| 单测可写性 | ⚠️ Metal 依赖增加单测复杂度 | ✅ AlarmEye/AlarmLeftPanel/AlarmOverlayContent 可纯单测 |
| 职责分离 | 背景装饰（窗口层职责）与 UI 组件混在一起 | ✅ 背景渐变属"窗口装饰"（与 SkyLightWindow 同层），内容属 CicadaUI |
| P4 联调成本 | 宿主直接 `AnyView(AlarmOverlay())` | 宿主 `ZStack { ColorfulView(.sunset); AlarmOverlayContent() }`（约 3 行） |
| 与现有结构一致性 | — | ✅ 现有 SentryView 本就是「背景 ZStack + 内容 HStack」解耦结构，方案 B 与之一致 |
| D-4 决策符合度 | ✅ 保留 ColorfulX | ✅ 保留 ColorfulX（只是放宿主） |
| v2 Implementation-Plan §4.1 | 该文档原写 AlarmOverlay 整个放 CicadaUI 含 ColorfulView | 本 spec 据探查结论**修订为方案 B**（见 §1.4 修订声明） |

### 1.3 推荐方案：**方案 B**

**理由**：

1. **保持 CicadaUI 纯净可验证**——CicadaUI 当前是纯 SwiftUI + 同 repo Swift target 依赖，`swift build` 快、单测稳定。引入 ColorfulX（Metal + 3 传递依赖）会让 CLI 构建拉远程包、编译 Metal，且无 GPU 环境下视觉无法验证，违背「纯 SwiftUI、可 swift build 验证」的本轮目标。
2. **职责分离更清晰**——`ColorfulView(.sunset)` 是窗口背景装饰，与 SkyLightWindow（警戒窗口外壳）、NotchWindow（刘海窗口外壳）同属宿主层"窗口外壳"职责；AlarmEye + AlarmLeftPanel + AlarmOverlayContent 是 UI 内容，属 CicadaUI。这完全符合 v2 §2.1「AppKit 只存在于窗口外壳 + 引擎，SwiftUI 负责所有可见 UI 内容」的原则——ColorfulView 是 Metal 渲染装饰，归"外壳"侧更自然。
3. **P4 联调成本极低**——宿主组合层只需：
   ```swift
   ZStack {
       ColorfulView(color: .sunset, noise: .constant(64)).ignoresSafeArea()
       Rectangle().fill(.ultraThinMaterial).opacity(0.5)
       AlarmOverlayContent(reason: appModel.alarm.reason) {
           Task { await appModel.alarm.stop(); /* dismissWindow 或 SkyLightOperator 关闭 */ }
       }
   }
   ```
   与现有 SentryView 的 `.background(ZStack { ColorfulView... })` 结构一致，迁移成本低。
4. **swift build 可验证性最大化**——AlarmEye 的 Canvas 旋转/脉动、AlarmLeftPanel 布局、AlarmOverlayContent 组合层全部纯 SwiftUI，能用 `swift build` 编译 + `CicadaUITests` 单测验证动画驱动值与 reduceMotion 分支。

### 1.4 对 v2 Implementation-Plan §4.1 的修订声明

v2 §4.1 文件清单原写：

- `Sources/CicadaUI/Views/Alarm/AlarmOverlay.swift`（新建，含 `ColorfulView(.sunset)`）

**修订为**：

- ~~`Sources/CicadaUI/Views/Alarm/AlarmOverlay.swift`~~ → 拆为：
  - `Sources/CicadaUI/Views/Alarm/AlarmOverlayContent.swift`（**新建**，纯 SwiftUI 内容层：HStack(AlarmLeftPanel + 分隔条 + AlarmEye)，**不含** ColorfulView/ultraThinMaterial 背景）
  - Xcode 宿主 `SentryView.swift`（**P4 修改**）：改为 `ZStack { ColorfulView(.sunset) + ultraThinMaterial + AlarmOverlayContent() }`，保留 ColorfulView import
- `Sources/CicadaUI/Views/Alarm/AlarmEye.swift`（新建，不变）
- `Sources/CicadaUI/Views/Alarm/AlarmLeftPanel.swift`（新建，不变）
- ~~`SunsetGradient.swift`~~ 仍不建（复用 ColorfulView，由宿主持有）

**不修订的**：D-4「保留 ColorfulX」决策不变——ColorfulX 仍保留，只是依赖留在 Xcode 宿主，不引入 CicadaUI SwiftPM。

---

## 2. 边界问题 2：NotchPanel 的 TrayDrop 引擎协议抽象

### 2.1 现状探查

**`NotchDrop/` 引擎暴露的操作**（实查 `TrayDrop.swift` / `AirDrop.swift` / `NotchViewModel.swift` / `NotchViewModel+Events.swift`）：

**TrayDrop（文件暂存引擎，`ObservableObject`，`TrayDrop.shared` 单例）**：

| 成员 | 签名 | 用途 |
|---|---|---|
| `items` | `@PublishedPersist OrderedSet<DropItem>` | 当前暂存项 |
| `isLoading` | `@Published Int` | 加载中计数（>0 时显示 glow） |
| `isEmpty` | `Bool` computed | 是否空 |
| `load(_:)` | `(NSItemProvider[]) -> Void` | 接收拖放，落盘到暂存目录（非主线程） |
| `removeAll()` | `() -> Void` | 清空全部（逐项删文件） |
| `delete(_:)` | `(DropItem.ID) -> Void` | 删除单项 |
| `cleanExpiredFiles()` | `() -> Void` | 清理过期 |
| `selectedFileStorageTime` / `customStorageTime` / `customStorageTimeUnit` | `@PublishedPersist` | 保留时长配置 |
| `keepInterval` | `TimeInterval` | 计算后的保留时长 |

**AirDrop（AirDrop 引擎，普通类）**：

| 成员 | 签名 | 用途 |
|---|---|---|
| `init(files: [URL])` | — | 持有文件 URL |
| `begin()` | `() -> Void` | 调 `NSSharingService.sendViaAirDrop` 发起 |

**NotchViewModel（窗口状态机，`NSObject, ObservableObject`，Combine 驱动）**：

| 成员 | 签名 | 用途 |
|---|---|---|
| `status` | `@Published Status`（.closed/.opened/.popping） | 窗口开合 |
| `contentType` | `@Published ContentType`（.normal/.menu/.notification） | 内容路由 |
| `notchOpen(_:)` / `notchClose()` / `notchPop()` | 方法 | 开合 |
| `cycleInteractiveContent()` | 方法 | normal↔menu 切换 |
| `showSettings()` | 方法 | 路由到设置页 |
| `showNotification(_:)` / `clearNotificationIfNeeded()` | 方法 | 通知 |
| `hapticSender` | `PassthroughSubject<Void,Never>` | 触觉反馈 |

**关键约束**：

- `TrayDrop`/`AirDrop`/`NotchViewModel` 都定义在 Xcode 宿主 `NotchDrop/`，引用 `Cocoa`/`Combine`/`@PublishedPersist`（自定义属性包装器）/`OrderedCollections`（swift-collections）/`NSHapticFeedbackManager`/`NSEvent.mouseLocation`——**CicadaUI（SwiftPM）引用不到这些类型**。
- `NotchViewModel+Events.swift` 的 `setupCancellables()` 用 Combine + AppKit 事件监听，是宿主窗口层的交互逻辑，不可迁 CicadaUI。

**现有 NotchView/NotchContentView 的内容路由**（`NotchView.swift` / `NotchContentView.swift`）：

```swift
// NotchContentView.swift
switch vm.contentType {
case .normal:  HStack { AirDropView(vm:); TrayView(vm:) }   // 两个拖放区
case .menu:    NotchMenuView(vm:)                            // 5 方块按钮
case .notification: NotchDropNotificationView(payload:, vm:) // 通知条
}
```

即：`contentType` 路由决定显示哪个子视图。`.normal` = 两个拖放区（AirDrop + Tray），`.menu` = 5 按钮，`.notification` = 通知。

### 2.2 抽象设计目标

CicadaUI 的 `NotchPanel`/`NotchMenu`/`NotchSection` 需要做到：

1. **不直接引用** `TrayDrop`/`AirDrop`/`NotchViewModel` 等宿主类型。
2. 通过协议 `NotchDropDelegate` 调用引擎落盘/AirDrop/清空等操作。
3. 纯 SwiftUI，`swift build` 可验证 + 可单测（用 Mock delegate）。

### 2.3 路由策略：CicadaUI 不做 contentType 路由

**决策**：`contentType` 路由（`.normal`/`.menu`/`.notification` 切换）**留在 Xcode 宿主**，CicadaUI 只提供三个独立视图：

- `NotchPanel`（对应 `.normal`：两个 `NotchSection` 拖放区，水平排列）
- `NotchMenu`（对应 `.menu`：5 个方块按钮）
- `NotchSection`（单个拖放区，被 `NotchPanel` 组合）

宿主 `NotchContentView` 改为：

```swift
switch vm.contentType {
case .normal:       NotchPanel(delegate: vm)           // CicadaUI
case .menu:         NotchMenu(delegate: vm)            // CicadaUI
case .notification: NotchDropNotificationView(...)     // 保留宿主原视图
}
```

**理由**：

- `contentType`/`status` 是宿主窗口状态机（含 Combine 事件、AppKit 坐标计算），迁 CicadaUI 需镜像一堆枚举 + 状态转发，成本高且本轮不必。
- 通知视图（`NotchDropNotificationView`）依赖宿主 `NotchDropNotificationPayload` 类型，本轮不留 CicadaUI。
- CicadaUI 聚焦"可复用、可 swift build 验证的纯 SwiftUI 视图"，路由是宿主编排职责。

### 2.4 NotchDropDelegate 协议设计（最小必要方法集）

**设计原则**：

- **纯操作协议**：本轮 `NotchPanel`/`NotchMenu` 不读宿主状态（暂存项列表、加载计数等），只调操作。`NotchSection` 文案是固定字面量（Design.md §6.1），不依赖运行时状态。这样协议最小。
- **conform `ObservableObject`**：让宿主 `NotchViewModel`（已 `ObservableObject`）可自然 conform，未来若需读状态可扩展协议不破坏实现。
- **类型边界干净**：协议方法参数只用 Foundation/SwiftUI 类型（`[NSItemProvider]`、`[URL]`、`UUID`），不泄漏 `TrayDrop`/`DropItem`/`AirDrop` 等宿主类型。
  - `NSItemProvider` 属 Foundation 模块（macOS），`import SwiftUI` 即可用，不需要 `import AppKit`。

**协议定义**（`Sources/CicadaUI/Views/NotchDrop/NotchDropDelegate.swift`）：

```swift
import Foundation

/// NotchDrop 引擎委托协议，供 Xcode 宿主实现。
///
/// CicadaUI 的 `NotchPanel`/`NotchMenu`/`NotchSection` 通过此协议调用宿主引擎
/// （TrayDrop 落盘 / AirDrop / 面板控制 / 外链），不直接引用 `TrayDrop`/`AirDrop`/
/// `NotchViewModel` 等宿主类型。
///
/// 宿主实现：`extension NotchViewModel: NotchDropDelegate { ... }`
/// （`NotchViewModel` 已是 `ObservableObject`，仅需补齐方法实现）
protocol NotchDropDelegate: AnyObject, ObservableObject {

    // MARK: - TrayDrop 暂存引擎

    /// 接收拖放数据并落盘到暂存目录。
    /// 宿主实现：`TrayDrop.shared.load(providers)`（内部 providers→urls→DropItem 落盘，非主线程）。
    func loadTray(providers: [NSItemProvider])

    /// 清空全部暂存文件。
    /// 宿主实现：`TrayDrop.shared.removeAll()`。
    func clearTray()

    // MARK: - AirDrop 引擎

    /// 用给定 URL 发起 AirDrop。
    /// 宿主实现：`AirDrop(files: urls).begin()`。
    func airDrop(urls: [URL])

    /// 点击 AirDrop 区时弹出文件选择面板（NSOpenPanel），选中后发起 AirDrop。
    /// 宿主实现：弹 `NSOpenPanel` → `AirDrop(files: picker.urls).begin()`。
    func openTrayPicker()

    // MARK: - 面板控制

    /// 关闭刘海面板。
    /// 宿主实现：`notchClose()`。
    func close()

    /// 打开设置页。
    /// 宿主实现：`showSettings()`（路由到控制中心设置 Tab）。
    func showSettings()

    // MARK: - 外链

    /// 打开项目 GitHub 页。
    /// 宿主实现：`NSWorkspace.shared.open(productPage)`。
    func openGitHub()

    /// 打开赞助页。
    /// 宿主实现：`NSWorkspace.shared.open(sponsorPage)`。
    func openSponsor()
}
```

**宿主实现示例**（P4 在 Xcode 宿主，仅供工程师参考，不属本轮 CicadaUI）：

```swift
// apps/agent/native/sentinel-app/Sentry/NotchDrop/NotchViewModel+Delegate.swift （P4 新建）
extension NotchViewModel: NotchDropDelegate {
    func loadTray(providers: [NSItemProvider]) {
        DispatchQueue.global().async { TrayDrop.shared.load(providers) }
    }
    func clearTray() { TrayDrop.shared.removeAll(); notchClose() }
    func airDrop(urls: [URL]) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { self.notchClose() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            AirDrop(files: urls).begin()
        }
    }
    func openTrayPicker() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { self.notchClose() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let picker = NSOpenPanel()
            picker.allowsMultipleSelection = true
            picker.canChooseDirectories = true
            picker.canChooseFiles = true
            picker.begin { response in
                if response == .OK { AirDrop(files: picker.urls).begin() }
            }
        }
    }
    func close() { notchClose() }
    func showSettings() { showSettings() }   // 已有
    func openGitHub() { NSWorkspace.shared.open(productPage); notchClose() }
    func openSponsor() { NSWorkspace.shared.open(sponsorPage); notchClose() }
}
```

### 2.5 NotchPanel 如何持有 delegate（泛型方案）

`@ObservedObject` 要求具体 `ObservableObject` 类型，不接受 `any NotchDropDelegate`。采用泛型约束：

```swift
struct NotchPanel<Delegate: ObservableObject & NotchDropDelegate>: View {
    @ObservedObject var delegate: Delegate
    // ...
}
```

宿主使用：`NotchPanel(delegate: vm)`（`vm: NotchViewModel`，已 conform 协议）。
CicadaUI 单测：`NotchPanel(delegate: MockNotchDropDelegate())`。

---

## 3. 逐文件实施 Spec

> 所有文件放 `apps/agent/swift/Sources/CicadaUI/Views/Alarm/` 或 `Views/NotchDrop/`。
> 每个文件必须有 `#Preview`。
> 依赖设计令牌（`DesignMetrics`/`Color+Cicada`）——已存在，直接复用。

---

### 3.1 `Sources/CicadaUI/Views/Alarm/AlarmEye.swift`（新建）

**核心职责**：警戒眼睛动画——`Canvas` 画 36 条外层径向线 + 24 条内层线 + 瞳孔脉动 + 反光点闪烁 + **reduceMotion 兜底**。

**对应 Design.md §5.2**。

**关键代码要点**：

```swift
import SwiftUI

struct AlarmEye: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // 动画驱动值
    @State private var rotation: Double = 0      // 外层 20s 旋转
    @State private var pulse: Bool = false        // 瞳孔 2s 脉动
    @State private var shimmer: Bool = false      // 反光点 2s 闪烁

    // 构图常量（对照 Design.md §5.2 + 现有 EyeView.swift）
    private let outerSize: CGFloat = 200
    private let irisSize: CGFloat = 180
    private let innerLineScale: CGFloat = 0.75   // 内层线半径 = 外层 75%
    private let pupilSize: CGFloat = 50
    private let reflectionSize: CGFloat = 8

    var body: some View {
        ZStack {
            // ① 眼白边框：8px 橙色环
            Circle()
                .stroke(Color.orange.opacity(0.3), lineWidth: 8)
                .frame(width: outerSize, height: outerSize)

            // ② 虹膜渐变：radial red→orange→red
            Circle()
                .fill(RadialGradient(
                    gradient: Gradient(colors: [
                        Color.red.opacity(0.8),
                        Color.orange,
                        Color.red.opacity(0.9),
                    ]),
                    center: .center,
                    startRadius: 30,
                    endRadius: 90
                ))
                .frame(width: irisSize, height: irisSize)

            // ③ 外层 36 条径向黑线（Canvas）+ 20s 旋转
            outerLines
                .rotationEffect(.degrees(rotation))
                .animation(rotationAnimation, value: rotation)

            // ④ 内层 24 条红色线（Canvas，半径 75%）
            innerLines

            // ⑤ 瞳孔：black→red 径向 + 2s 缩放脉动
            Circle()
                .fill(RadialGradient(
                    gradient: Gradient(colors: [Color.black, Color.red.opacity(0.2)]),
                    center: .center,
                    startRadius: 5,
                    endRadius: 25
                ))
                .frame(width: pupilSize, height: pupilSize)
                .scaleEffect(reduceMotion ? 1 : (pulse ? 0.8 : 1))
                .animation(pulseAnimation, value: pulse)

            // ⑥ 反光点：2s 透明度闪烁
            Circle()
                .fill(Color.red.opacity(0.6))
                .frame(width: reflectionSize, height: reflectionSize)
                .opacity(reduceMotion ? 0.6 : (shimmer ? 0.8 : 0.3))
                .animation(shimmerAnimation, value: shimmer)
        }
        .clipShape(Circle())
        .frame(width: outerSize, height: outerSize)
        .onAppear {
            guard !reduceMotion else { return }   // reduceMotion 时停在静态构图
            rotation = 360
            pulse = true
            shimmer = true
        }
    }

    // MARK: - Canvas 层

    /// 外层 36 条径向黑线（对照 Design.md §5.2「外层纹理线 36 条 conic 黑线，20s 旋转」）。
    /// 用 Canvas 按角度等分画线段，整体 rotationEffect 驱动旋转。
    private var outerLines: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let lineLength: CGFloat = 80          // 对照 EyeView: height 80
            let innerRadius: CGFloat = 0          // 从中心放射
            for i in 0..<36 {
                let angle = Angle.degrees(Double(i) * 10).radians   // 36 等分 = 10°/条
                let dx = cos(angle), dy = sin(angle)
                let start = CGPoint(x: center.x + dx * innerRadius,
                                    y: center.y + dy * innerRadius)
                let end = CGPoint(x: center.x + dx * (innerRadius + lineLength),
                                  y: center.y + dy * (innerRadius + lineLength))
                var path = Path()
                path.move(to: start)
                path.addLine(to: end)
                context.stroke(path, with: .color(Color.black.opacity(0.3)),
                               lineWidth: 1)
            }
        }
        .frame(width: irisSize, height: irisSize)
    }

    /// 内层 24 条红色线（半径 75%）。对照 Design.md §5.2「内层纹理线 24 条红色线，半径缩小 25%」。
    private var innerLines: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let lineLength: CGFloat = 50 * innerLineScale   // 50 * 0.75
            for i in 0..<24 {
                let angle = Angle.degrees(Double(i) * 15).radians   // 24 等分 = 15°/条
                let dx = cos(angle), dy = sin(angle)
                let start = center
                let end = CGPoint(x: center.x + dx * lineLength,
                                  y: center.y + dy * lineLength)
                var path = Path()
                path.move(to: start)
                path.addLine(to: end)
                context.stroke(path, with: .color(Color.red.opacity(0.4)),
                               lineWidth: 0.5)
            }
        }
        .frame(width: irisSize, height: irisSize)
    }

    // MARK: - 动画（reduceMotion 三态兜底）

    private var rotationAnimation: Animation? {
        reduceMotion ? nil : .linear(duration: 20).repeatForever(autoreverses: false)
    }
    private var pulseAnimation: Animation? {
        reduceMotion ? nil : .easeInOut(duration: 2).repeatForever(autoreverses: true)
    }
    private var shimmerAnimation: Animation? {
        reduceMotion ? nil : .easeInOut(duration: 2).repeatForever(autoreverses: true)
    }
}

#Preview {
    AlarmEye()
        .frame(width: 250, height: 250)
        .background(.black)
}
```

**与 Design.md §5.2 对照表**：

| Design.md §5.2 层 | 本实现 | 一致性 |
|---|---|---|
| 眼白边框 8px 橙色环 | `Circle().stroke(.orange.opacity(0.3), lineWidth: 8)` | ✅ 与现有 EyeView 一致 |
| 虹膜 radial red→orange→red | `Circle().fill(RadialGradient(...))` 180×180 | ✅ |
| 外层 36 条 conic 黑线 20s 旋转 | `Canvas` 36 等分（10°/条）+ `rotationEffect` + `.linear(20).repeatForever` | ✅ Canvas 替代 ForEach+Rectangle（性能更优） |
| 内层 24 条红色线 半径 75% | `Canvas` 24 等分（15°/条）+ `lineLength * 0.75` | ✅ |
| 瞳孔 black→red 径向 + 2s 缩放脉动 | `Circle().fill(RadialGradient)` + `scaleEffect(pulse ? 0.8 : 1)` + `.easeInOut(2).repeatForever` | ✅ |
| 反光点 2s 透明度闪烁 | `Circle().opacity(shimmer ? 0.8 : 0.3)` + 同上 | ✅ |
| reduceMotion 兜底 | `@Environment(\.accessibilityReduceMotion)`；三动画传 `nil`；`.onAppear` guard；旋转/脉动停静态构图 | ✅ 对应 Design.md §10.1 |

**依赖**：`SwiftUI`（Canvas 需 macOS 13+，本目标 macOS 14 ✅）。
**验收**：
- `swift build` 通过
- Preview 渲染眼睛，旋转/脉动可见
- 系统开启「减弱动态效果」后眼睛静止、瞳孔不脉动（Preview 无法验证，靠代码审查 + 单测可加 `rotationAnimation` 在 reduceMotion=true 返回 nil 的断言）

---

### 3.2 `Sources/CicadaUI/Views/Alarm/AlarmLeftPanel.swift`（新建）

**核心职责**：警戒左侧文字区——装饰图标（顶对齐）+ Spacer + 标题 + 描述 + 停止按钮。

**对应 Design.md §5.1 `AlarmLeftPanel`**。

**关键代码要点**：

```swift
import SwiftUI

struct AlarmLeftPanel: View {
    let reason: String                       // appModel.alarm.reason
    let onStop: () -> Void                   // 停止闭包：Task { await appModel.alarm.stop(); dismiss }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignMetrics.Spacing.s2) {
            // ① 装饰图标（顶对齐，半透明）
            Image(systemName: "eye.fill")
                .font(.largeTitle)
                .bold()
                .opacity(0.2)

            Spacer()

            // ② 标题
            Text("Cicada 警戒已触发")
                .font(.system(size: 28, weight: .heavy))
                .foregroundStyle(.white)

            // ③ 触发原因（若有）
            if !reason.isEmpty {
                Text(reason)
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.85))
            }

            // ④ 描述
            Text("此 Mac 已联网并正在监控你的行为。")
                .font(.body)
                .foregroundStyle(.white.opacity(0.7))

            // ⑤ 停止按钮
            Button(action: onStop) {
                Label("停止警戒", systemImage: "stop.fill")
            }
            .buttonStyle(AlarmStopButtonStyle())
            .padding(.top, DesignMetrics.Spacing.s3)
        }
        .padding(DesignMetrics.Spacing.s8)   // 32pt，对照现有 SentryView texts padding(32)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 警戒停止按钮样式：反色大按钮（白底深字 / 红边强调）。
/// Design.md §5.1 说「停止按钮用 PrimaryButtonStyle（反色）或自定义大按钮」——这里自定义，因警戒背景是暖色渐变，
/// PrimaryButtonStyle 的 accent 绿与 sunset 不搭，改用半透明白底 + danger 红边的强对比样式。
private struct AlarmStopButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, DesignMetrics.Spacing.s5)
            .padding(.vertical, DesignMetrics.Spacing.s3)
            .background(.white.opacity(configuration.isPressed ? 0.75 : 0.9))
            .foregroundStyle(.black)
            .clipShape(RoundedRectangle(cornerRadius: DesignMetrics.Radius.md))
            .overlay(
                RoundedRectangle(cornerRadius: DesignMetrics.Radius.md)
                    .stroke(Color.red.opacity(0.6), lineWidth: 1.5)
            )
    }
}

#Preview {
    AlarmLeftPanel(reason: "合上盖子") {}
        .frame(width: 360, height: 400)
        .background(Color.black.opacity(0.6))
        .preferredColorScheme(.dark)
}
```

**要点**：
- 文案用中文（Design.md §5.1 原英文 "Cicada Activated" 是占位，本 spec 按产品语境中文化；实际文案以产品最终定稿为准，工程师可保留英文 Key 走 Localizable）。
- `onStop` 是闭包注入，由 `AlarmOverlayContent` 传入 `{ Task { await appModel.alarm.stop(); dismissWindow() } }`，不直接依赖 `AlarmModel`（保持组件可独立预览/单测）。
- 停止按钮样式为 `AlarmStopButtonStyle`（私有），因警戒背景是 sunset 暖色渐变，`PrimaryButtonStyle` 的 accent 绿不搭；用半透明白底 + danger 红边强调停止动作。若产品要求统一用 `PrimaryButtonStyle`，可改回。

**依赖**：`DesignMetrics`、`SwiftUI`。
**验收**：`swift build` 通过；Preview 显示装饰图标 + 标题 + 原因 + 描述 + 停止按钮。

---

### 3.3 `Sources/CicadaUI/Views/Alarm/AlarmOverlayContent.swift`（新建）

**核心职责**：警戒内容层（纯 SwiftUI，**不含** ColorfulView 背景）——`HStack(AlarmLeftPanel + 竖向分隔条 + AlarmEye)`，固定 700×400。

**对应 Design.md §5.1 布局**，但剥离背景层（背景由 P4 宿主 ZStack 组合）。

**关键代码要点**：

```swift
import SwiftUI

/// 警戒全屏内容层（不含 ColorfulView 背景）。
///
/// 纯 SwiftUI，可 `swift build` 验证。
/// P4 宿主组合：`ZStack { ColorfulView(.sunset); ultraThinMaterial; AlarmOverlayContent(...) }`。
struct AlarmOverlayContent: View {
    let reason: String
    let onStop: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            AlarmLeftPanel(reason: reason, onStop: onStop)

            // 竖向黑色分隔条（对照现有 SentryView: Rectangle 10×888 → 本 spec 用 10 宽自适应高）
            Rectangle()
                .fill(Color.black.opacity(0.5))
                .frame(width: 10)

            // 右侧眼睛
            AlarmEye()
                .frame(width: 200)
                .padding(DesignMetrics.Spacing.s8)
        }
        .frame(width: 700, height: 400, alignment: .center)
        .foregroundStyle(.white)
        // 警戒固定深色（Design.md §2.1）
        .preferredColorScheme(.dark)
    }
}

#Preview {
    // 模拟宿主组合（背景渐变 + 毛玻璃 + 内容层）
    ZStack {
        LinearGradient(colors: [Color(red: 0.98, green: 0.45, blue: 0.09),
                                 Color(red: 0.94, green: 0.27, blue: 0.27),
                                 Color(red: 0.42, green: 0.02, blue: 0.06)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
        Rectangle().fill(.ultraThinMaterial).opacity(0.5)
        AlarmOverlayContent(reason: "合上盖子") {}
    }
    .clipShape(RoundedRectangle(cornerRadius: 32))
    .background(.black)
}
```

**要点**：
- **不含** `ColorfulView` / `ultraThinMaterial` / `.clipShape(RoundedRectangle(32))` / `.background(.black)`——这些都是 P4 宿主组合层职责。本视图只负责内容布局。
- `.preferredColorScheme(.dark)` 保留在内容层（影响文字对比），宿主背景层也可再设一次（幂等）。
- 固定 700×400 与现有 SentryView 一致。
- Preview 用 `LinearGradient` 模拟 sunset 背景，仅用于视觉验证；实际 ColorfulView 由宿主提供。

**依赖**：`AlarmLeftPanel`、`AlarmEye`、`DesignMetrics`。
**验收**：`swift build` 通过；Preview 显示左文字 + 分隔条 + 右眼睛三段布局。

---

### 3.4 `Sources/CicadaUI/Views/NotchDrop/NotchDropDelegate.swift`（新建）

**核心职责**：定义 `NotchDropDelegate` 协议（见 §2.4 完整代码）。

**关键代码要点**：见 §2.4 协议定义，原样落地。

**依赖**：`Foundation`（`NSItemProvider`/`URL`/`UUID`）。
**验收**：`swift build` 通过；单测可写 `MockNotchDropDelegate: ObservableObject, NotchDropDelegate` 验证调用。

---

### 3.5 `Sources/CicadaUI/Views/NotchDrop/NotchSection.swift`（新建）

**核心职责**：单个拖放区——图标 + 文字 + 虚线边框 + `.onDrop` 视觉反馈（边框高亮）+ 转发拖放数据给 delegate。

**对应 Design.md §6.1 `NotchSection`**（dashed 拖放区）。

**关键代码要点**：

```swift
import SwiftUI
import UniformTypeIdentifiers

/// 单个刘海拖放区。
///
/// 本轮只实现**空态**（拖放提示 + 虚线边框 + .onDrop 视觉反馈 + 转发落盘）。
/// 非空态（DropItemView 横滑列表）涉及 QuickLook/NSImage 预览，留 Xcode 宿主 P4 扩展。
struct NotchSection<Delegate: ObservableObject & NotchDropDelegate>: View {
    @ObservedObject var delegate: Delegate

    let icon: String
    let text: String
    let kind: Kind                          // .airDrop / .tray
    let cornerRadius: CGFloat               // 沿用宿主 vm.cornerRadius（由 NotchPanel 传入）

    @State private var isTargeted = false

    enum Kind {
        case airDrop                         // 拖放 → delegate.airDrop(urls)；点击 → delegate.openTrayPicker()
        case tray                            // 拖放 → delegate.loadTray(providers)
    }

    var body: some View {
        panel
            .onDrop(of: [.data], isTargeted: $isTargeted) { providers in
                handleDrop(providers)
                return true
            }
            .onTapGesture(perform: handleTap)
    }

    private var panel: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .strokeBorder(style: StrokeStyle(lineWidth: 4, dash: [10]))
            .foregroundStyle(isTargeted ? Color.cicadaAccent.opacity(0.8) : Color.white.opacity(0.1))
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(isTargeted ? Color.cicadaAccent.opacity(0.15) : Color.white.opacity(0.08))
            )
            .overlay {
                VStack(spacing: DesignMetrics.Spacing.s2) {
                    Image(systemName: icon)
                        .font(.title3)
                    Text(text)
                        .font(.system(.headline, design: .rounded))
                        .multilineTextAlignment(.center)
                }
                .padding(DesignMetrics.Spacing.s4)
            }
            .aspectRatio(1, contentMode: .fit)   // 对照 AirDropView: aspectRatio(1, .fit)
            .animation(.spring(response: 0.3), value: isTargeted)
    }

    private func handleDrop(_ providers: [NSItemProvider]) {
        switch kind {
        case .airDrop:
            // AirDrop 需先转 URL（providers→urls），宿主在 airDrop 内做或在此做。
            // 为保持 CicadaUI 不依赖宿主的 interfaceConvert 扩展，暴露 providers 给宿主转换：
            // 这里改为调 delegate.airDrop(urls:) —— 但 CicadaUI 无 interfaceConvert。
            // ⚠️ 决策：AirDrop 区的 onDrop 仍把 providers 传给宿主，由宿主转 URL 再 airDrop。
            // 因此 NotchDropDelegate 需补一个 airDrop(providers:) 重载（见下方说明）。
            delegate.airDrop(providers: providers)
        case .tray:
            delegate.loadTray(providers: providers)
        }
    }

    private func handleTap() {
        switch kind {
        case .airDrop: delegate.openTrayPicker()
        case .tray:    break   // 暂存区点击无动作（非空态列表交互留宿主）
        }
    }
}
```

**⚠️ AirDrop 拖放的数据转换问题与协议补充**：

AirDrop 需要 `[URL]`，但 `.onDrop` 给的是 `[NSItemProvider]`。宿主有 `interfaceConvert()` 扩展（`Ext+FileProvider.swift`）把 providers 转 urls，但 CicadaUI 没有此扩展。

**两个解法**：

- **解法 1（推荐）**：协议补 `func airDrop(providers: [NSItemProvider])` 重载，宿主实现里 `providers.interfaceConvert()` → `AirDrop(files: urls).begin()`。这样 CicadaUI 不需要 interfaceConvert。
- **解法 2**：CicadaUI 内复制一份 `interfaceConvert`（基于 `NSItemProvider.loadItem` 的 async wrapper）——但这会复制宿主代码，维护两份。

**采用解法 1**——在 `NotchDropDelegate` 补充：

```swift
// 在 §2.4 协议中补充（替换原 airDrop(urls:)）
func airDrop(providers: [NSItemProvider])   // 拖放直传：宿主 providers→urls→AirDrop
func airDrop(urls: [URL])                    // 文件选择器选中：宿主直接 AirDrop
func openTrayPicker()                        // 弹 NSOpenPanel，选中后调 airDrop(urls:)
```

> 工程师注意：`airDrop(providers:)` 与 `airDrop(urls:)` 是两个入口——拖放走 providers 版，文件选择器走 urls 版。宿主实现 providers 版时复用宿主 `interfaceConvert()`。

**修订后的 NotchDropDelegate 完整签名**（见 §2.4，把 `airDrop(urls:)` 改为上述双入口）——已在 §2.4 代码中体现为 `airDrop(urls:)` + 本节补充 `airDrop(providers:)`。**最终协议以本节为准**，工程师请合并：

```swift
protocol NotchDropDelegate: AnyObject, ObservableObject {
    // TrayDrop
    func loadTray(providers: [NSItemProvider])
    func clearTray()

    // AirDrop（两入口）
    func airDrop(providers: [NSItemProvider])   // 拖放直传
    func airDrop(urls: [URL])                    // 文件选择器选中
    func openTrayPicker()                        // 弹 NSOpenPanel

    // 面板控制
    func close()
    func showSettings()

    // 外链
    func openGitHub()
    func openSponsor()
}
```

**依赖**：`NotchDropDelegate`、`DesignMetrics`、`UniformTypeIdentifiers`、`SwiftUI`。
**验收**：`swift build` 通过；Preview 两个 NotchSection（AirDrop + Tray）虚线边框；拖入时边框切 accent 绿（Preview 无法交互验证，靠代码审查）。

---

### 3.6 `Sources/CicadaUI/Views/NotchDrop/NotchPanel.swift`（新建）

**核心职责**：打开态主体（`.normal` 内容）——`NotchHeader`（标题 + ellipsis）+ `HStack(两个 NotchSection 拖放区)`。

**对应 Design.md §6.1 `NotchPanel`**。

**关键代码要点**：

```swift
import SwiftUI

/// 刘海面板打开态（contentType == .normal 的内容）。
///
/// 纯 SwiftUI，可 `swift build` 验证。
/// 宿主 `NotchContentView` 在 `.normal` 分支用 `NotchPanel(delegate: vm)`。
/// 背景毛玻璃 + 圆角 + 阴影由宿主 `NotchView` 外壳提供（本视图不自带背景）。
struct NotchPanel<Delegate: ObservableObject & NotchDropDelegate>: View {
    @ObservedObject var delegate: Delegate

    /// 沿用宿主 vm.cornerRadius（NotchViewModel.cornerRadius，默认 16）。
    /// 由宿主传入，使本视图圆角与宿主窗口形状一致。
    var cornerRadius: CGFloat = 16
    var spacing: CGFloat = DesignMetrics.Spacing.s4

    var body: some View {
        VStack(spacing: spacing) {
            notchHeader
            HStack(spacing: spacing) {
                NotchSection(delegate: delegate, icon: "airplayaudio",
                             text: "拖放以 AirDrop", kind: .airDrop,
                             cornerRadius: cornerRadius)
                NotchSection(delegate: delegate, icon: "tray.and.arrow.down.fill",
                             text: "拖放文件到此处暂存一周", kind: .tray,
                             cornerRadius: cornerRadius)
            }
        }
        .padding(spacing)
        .frame(maxWidth: 600, maxHeight: 160)   // 对照 NotchViewModel.notchOpenedSize 600×160
        .preferredColorScheme(.dark)
    }

    /// 标题行（对照 NotchHeaderView：标题 + ellipsis）。
    /// ellipsis 点击 → 宿主 cycleInteractiveContent() 切到 menu。
    /// 但本协议未暴露 cycleContent——因 menu 切换由宿主点击 NotchHeader 触发，
    /// 这里 ellipsis 用 Button 调 delegate（需协议补 cycleMenu()）。
    // ⚠️ 决策：NotchHeader 的 ellipsis 点击切菜单是宿主 NotchViewModel.cycleInteractiveContent()。
    // 为最小化协议，本视图 ellipsis 不绑定动作（纯装饰），menu 切换由宿主 NotchView 的点击事件处理。
    // 若需在 CicadaUI 内点击切菜单，协议补 `func cycleMenu()`。本轮按「协议最小」不补，ellipsis 纯装饰。
    private var notchHeader: some View {
        HStack {
            Text("NotchDrop")
                .font(.system(.headline, design: .rounded))
            Spacer()
            Image(systemName: "ellipsis")
        }
    }
}

#Preview {
    NotchPanel(delegate: MockNotchDropDelegate())
        .background(Color.black.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 32))
        .overlay(RoundedRectangle(cornerRadius: 32).stroke(.white.opacity(0.06), lineWidth: 1))
}
```

**要点**：
- 背景毛玻璃 + clipShape + 阴影由宿主 `NotchView` 外壳提供（现有 NotchView 已有 `.preferredColorScheme(.dark)` + 窗口形状 mask）。本视图只做内容布局。
- `cornerRadius`/`spacing` 由宿主传入（对齐 `NotchViewModel.cornerRadius`/`spacing`），保证与窗口形状一致。
- 文案"拖放以 AirDrop"/"拖放文件到此处暂存一周"按 Design.md §6.1；"一周"是占位，实际保留时长文案由宿主 `TrayView.storageTime` 计算——本轮固定"一周"，宿主若需动态文案可后续扩展协议读 `storageTimeText`。
- `NotchHeader` 的 ellipsis **纯装饰**（不绑动作）——menu 切换由宿主 `NotchViewModel+Events` 的点击事件处理（现有逻辑：点 headline 区触发 `cycleInteractiveContent()`）。本轮协议不补 `cycleMenu()`，保持最小。若工程师要在 CicadaUI 内点切菜单，可协议补 `func cycleMenu()`，但不推荐（增加协议面）。

**依赖**：`NotchSection`、`NotchDropDelegate`、`DesignMetrics`。
**验收**：`swift build` 通过；Preview 显示标题 + 两个虚线拖放区。

---

### 3.7 `Sources/CicadaUI/Views/NotchDrop/NotchMenu.swift`（新建）

**核心职责**：横向 5 方块按钮（关闭 / AirDrop / GitHub / 赞助 / 设置 / 清空）。

**对应 Design.md §6.2 `NotchMenu`**。

> ⚠️ Design.md §6.2 写的是「5 方块」，但列了 6 个按钮（关闭/AirDrop/GitHub/赞助/设置/清空）。现有 `NotchMenuView.swift` 是 5 个（close/github/donate/settings/clear，无独立 AirDrop）。本 spec 按 Design.md §6.2 文字「横向 5 个方块按钮」+ 实际需求，定为 **5 个**：关闭 / AirDrop / GitHub / 赞助 / 设置 / 清空——取 Design.md 文字「5」为准，合并 AirDrop 进设置或删 AirDrop。**最终定 6 个**（与现有 NotchMenuView 一致 + Design.md 列表一致，文字「5」是笔误）。工程师按 6 个实现。

**关键代码要点**：

```swift
import SwiftUI

/// 刘海面板菜单态（contentType == .menu 的内容）——横向 6 方块按钮。
///
/// 纯 SwiftUI，可 `swift build` 验证。
/// 宿主 `NotchContentView` 在 `.menu` 分支用 `NotchMenu(delegate: vm)`。
struct NotchMenu<Delegate: ObservableObject & NotchDropDelegate>: View {
    @ObservedObject var delegate: Delegate

    var spacing: CGFloat = DesignMetrics.Spacing.s3
    var cornerRadius: CGFloat = 16

    var body: some View {
        HStack(spacing: spacing) {
            menuButton(icon: "xmark", label: "关闭", tint: .cicadaDanger) {
                delegate.close()
            }
            menuButton(icon: "airplayaudio", label: "AirDrop", tint: .cicadaAccent) {
                delegate.openTrayPicker()    // 点 AirDrop 弹文件选择器
            }
            menuButton(icon: "ellipsis.bubble", label: "GitHub", tint: .cicadaAccent) {
                delegate.openGitHub()
            }
            menuButton(icon: "heart.fill", label: "赞助", tint: .cicadaAccent) {
                delegate.openSponsor()
            }
            menuButton(icon: "gearshape", label: "设置", tint: .cicadaAccent) {
                delegate.showSettings()
            }
            menuButton(icon: "trash", label: "清空", tint: .cicadaDanger) {
                delegate.clearTray()
            }
        }
        .padding(spacing)
        .preferredColorScheme(.dark)
    }

    /// 单个方块按钮（对照 Design.md §6.2 NotchMenuButton：72×72 圆角方块，hover 缩放 1.05 + 背景提亮）。
    private func menuButton(icon: String, label: String, tint: Color,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: DesignMetrics.Spacing.s2) {
                Image(systemName: icon)
                    .font(.title3)
                Text(label)
                    .font(.caption)
            }
            .frame(width: 72, height: 72)
            .background(tint.opacity(0.12))
            .foregroundStyle(tint)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(tint.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    NotchMenu(delegate: MockNotchDropDelegate())
        .background(Color.black.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 32))
}
```

**要点**：
- 现有 `NotchMenuView` 用 `ColorfulView` mask 做按钮渐变装饰——本 spec 按 Design.md §6.2 重新设计为**中性方块**（tint 软背景 + tint 边框），**不用 ColorfulView**（符合方案 B 精神：ColorfulView 装饰留宿主）。若产品要求保留 ColorfulView 装饰，可在 P4 宿主包一层 mask，但 CicadaUI 本轮不做。
- `Button(action:)` + `.buttonStyle(.plain)` + 内部 `@State hover` 缩放——本 spec 用纯 `.buttonStyle(.plain)` + 固定 hover 由系统 Button 处理；若要 hover 缩放 1.05，加 `@State hover` + `.onHover` + `.scaleEffect`。为简洁先不加 hover 缩放（Design.md §6.2 提到但非必须），工程师可按需补：
  ```swift
  @State private var hover = false
  // 在 menuButton 内 view 修饰：
  .scaleEffect(hover ? 1.05 : 1)
  .animation(.spring(response: 0.2), value: hover)
  .onHover { hover = $0 }
  ```
- AirDrop 按钮点 → `delegate.openTrayPicker()`（弹文件选择器）；拖放 AirDrop 在 `NotchSection(.airDrop)` 已处理。

**依赖**：`NotchDropDelegate`、`DesignMetrics`、`Color+Cicada`。
**验收**：`swift build` 通过；Preview 显示 6 个方块按钮横排。

---

## 4. Mock + 单测（放 `Tests/CicadaUITests/`，本轮可选但推荐）

### 4.1 MockNotchDropDelegate

```swift
import Foundation
import SwiftUI

@MainActor
final class MockNotchDropDelegate: ObservableObject, NotchDropDelegate {
    var loadTrayCallCount = 0
    var clearTrayCallCount = 0
    var airDropProvidersCallCount = 0
    var airDropUrlsCallCount = 0
    var openTrayPickerCallCount = 0
    var closeCallCount = 0
    var showSettingsCallCount = 0
    var openGitHubCallCount = 0
    var openSponsorCallCount = 0

    func loadTray(providers: [NSItemProvider]) { loadTrayCallCount += 1 }
    func clearTray() { clearTrayCallCount += 1 }
    func airDrop(providers: [NSItemProvider]) { airDropProvidersCallCount += 1 }
    func airDrop(urls: [URL]) { airDropUrlsCallCount += 1 }
    func openTrayPicker() { openTrayPickerCallCount += 1 }
    func close() { closeCallCount += 1 }
    func showSettings() { showSettingsCallCount += 1 }
    func openGitHub() { openGitHubCallCount += 1 }
    func openSponsor() { openSponsorCallCount += 1 }
}
```

### 4.2 推荐单测

- `AlarmEyeTests`：构造 AlarmEye，验证 reduceMotion 路径下 `rotationAnimation` 为 nil（需把动画 computed 改可测，或抽 `func rotationAnimation(reduceMotion:)` 静态方法单测）。
- `NotchPanelTests`：用 `MockNotchDropDelegate`，验证 NotchSection.onDrop 转发（需模拟 NSItemProvider，较难，可只验证 `MockNotchDropDelegate` 方法被调用——用 SwiftUI ViewInspector 或省略，靠代码审查）。
- 协议 conform 编译测试：`final class _: ObservableObject, NotchDropDelegate { ... }` 编译通过即可证明协议可被实现。

> 本轮单测以「协议可 conform + 编译通过」为最低要求，深度交互测试留 P4 宿主联调。

---

## 5. 哪些放 CicadaUI（本轮）vs 哪些留 Xcode 宿主（P4）

### 5.1 本轮放 CicadaUI（纯 SwiftUI，`swift build` 验证）

| 文件 | 职责 |
|---|---|
| `Sources/CicadaUI/Views/Alarm/AlarmEye.swift` | Canvas 眼睛动画 + reduceMotion |
| `Sources/CicadaUI/Views/Alarm/AlarmLeftPanel.swift` | 警戒左文字区 + 停止按钮 |
| `Sources/CicadaUI/Views/Alarm/AlarmOverlayContent.swift` | 警戒内容层（不含 ColorfulView） |
| `Sources/CicadaUI/Views/NotchDrop/NotchDropDelegate.swift` | 引擎委托协议 |
| `Sources/CicadaUI/Views/NotchDrop/NotchSection.swift` | 单个拖放区（空态 + .onDrop） |
| `Sources/CicadaUI/Views/NotchDrop/NotchPanel.swift` | 打开态主体（两个 NotchSection） |
| `Sources/CicadaUI/Views/NotchDrop/NotchMenu.swift` | 6 方块菜单按钮 |

### 5.2 留 Xcode 宿主（P4 实施）

| 文件/职责 | P4 动作 |
|---|---|
| `SentryView.swift` | 改为 `ZStack { ColorfulView(.sunset, noise: .constant(64)).ignoresSafeArea(); Rectangle().fill(.ultraThinMaterial).opacity(0.5); AlarmOverlayContent(reason: appModel.alarm.reason) { Task { await appModel.alarm.stop(); /* SkyLightOperator 关闭 */ } } }`；保留 `import ColorfulX` |
| `EyeView.swift` | **删除**，被 `CicadaUI/AlarmEye.swift` 取代 |
| 警戒窗口注入（`Sentry.makeDefaultWindowController`） | 改为 `SkyLightOperator.shared.delegateView(AnyView(AlarmOverlayContent(...)), toScreen: .main!)`，或保留 SentryView 作组合层注入 |
| `NotchDrop/NotchViewModel+Delegate.swift` | **新建**：`extension NotchViewModel: NotchDropDelegate`，实现 8 个方法（见 §2.4 宿主实现示例） |
| `NotchDrop/NotchContentView.swift` | 改为 `switch vm.contentType { case .normal: NotchPanel(delegate: vm); case .menu: NotchMenu(delegate: vm); case .notification: NotchDropNotificationView(...) }` |
| `NotchDrop/NotchViewController.swift` | 仍是 `NSHostingController<NotchView>`，rootView 不变（NotchView 内部用新 NotchContentView） |
| `NotchDrop/NotchView.swift` | 刘海形状 mask + dragDetector 保留（窗口外壳）；内容区用新 NotchContentView |
| `NotchDrop/NotchWindowController.swift` / `NotchWindow.swift` | **不变** |
| `NotchDrop/TrayDrop*.swift` / `AirDrop*.swift` | **不变**（引擎层） |
| `NotchDrop/NotchMenuView.swift` | **删除/替换**，被 `CicadaUI/NotchMenu.swift` 取代 |
| `NotchDrop/NotchHeaderView.swift` | **删除/替换**，标题行并入 `CicadaUI/NotchPanel.notchHeader` |
| `NotchDrop/AirDrop+View.swift` / `TrayDrop+View.swift` | 非空态列表（DropItemView 横滑）保留宿主，作为 NotchSection(.tray) 有文件时的内容扩展；本轮 CicadaUI NotchSection 只做空态 |
| `NotchDrop/NotchDropNotification.swift`（通知视图） | **保留宿主**，本轮不迁 CicadaUI（依赖宿主 payload 类型） |
| `AppDelegate.swift` / `App.swift` | 注入 `AlarmModel.activate` 闭包（`Sentry.onAlarmingActivaty` → `appModel.alarm.activate(reason:)`）；`AlarmModel.delegate` 设为 Sentry 实现 `AlarmEngineDelegate` |

---

## 6. NotchDropDelegate 协议完整方法签名（最终版）

```swift
import Foundation

protocol NotchDropDelegate: AnyObject, ObservableObject {
    // MARK: - TrayDrop 暂存引擎
    /// 接收拖放数据并落盘到暂存目录。
    /// 宿主实现：`DispatchQueue.global().async { TrayDrop.shared.load(providers) }`。
    func loadTray(providers: [NSItemProvider])

    /// 清空全部暂存文件。
    /// 宿主实现：`TrayDrop.shared.removeAll(); notchClose()`。
    func clearTray()

    // MARK: - AirDrop 引擎
    /// 拖放直传：由拖放区 onDrop 触发，宿主做 providers→urls→AirDrop。
    /// 宿主实现：`guard let urls = providers.interfaceConvert() else { return }; AirDrop(files: urls).begin()`。
    func airDrop(providers: [NSItemProvider])

    /// 文件选择器选中：由 AirDrop 按钮点击弹 NSOpenPanel 后触发。
    /// 宿主实现：`AirDrop(files: urls).begin()`。
    func airDrop(urls: [URL])

    /// 弹出 NSOpenPanel 选文件，选中后调 `airDrop(urls:)`。
    /// 宿主实现：弹 NSOpenPanel → `airDrop(urls: picker.urls)`。
    func openTrayPicker()

    // MARK: - 面板控制
    /// 关闭刘海面板。宿主实现：`notchClose()`。
    func close()

    /// 打开设置页。宿主实现：`showSettings()`。
    func showSettings()

    // MARK: - 外链
    /// 打开 GitHub 项目页。宿主实现：`NSWorkspace.shared.open(productPage); notchClose()`。
    func openGitHub()

    /// 打开赞助页。宿主实现：`NSWorkspace.shared.open(sponsorPage); notchClose()`。
    func openSponsor()
}
```

共 **8 个方法**，全部为操作（无状态读），参数类型限于 `[NSItemProvider]`/`[URL]`（Foundation）。

---

## 7. AlarmEye Canvas 实现要点（对照 Design.md §5.2）

| 要点 | 实现 |
|---|---|
| 36 条外层径向线 | `Canvas` for i in 0..<36，角度 `Double(i) * 10`°（10°/条），`ctx.stroke(path, with: .color(.black.opacity(0.3)), lineWidth: 1)`，线长 80 |
| 24 条内层线 | `Canvas` for i in 0..<24，角度 `Double(i) * 15`°（15°/条），`.red.opacity(0.4)`，lineWidth 0.5，线长 `50 * 0.75` |
| 20s 旋转 | `outerLines.rotationEffect(.degrees(rotation))` + `.animation(.linear(duration: 20).repeatForever(autoreverses: false), value: rotation)`；`.onAppear { rotation = 360 }` |
| 2s 瞳孔脉动 | `Circle().scaleEffect(pulse ? 0.8 : 1)` + `.animation(.easeInOut(duration: 2).repeatForever(autoreverses: true), value: pulse)`；`.onAppear { pulse = true }` |
| 2s 反光点闪烁 | `Circle().opacity(shimmer ? 0.8 : 0.3)` + 同脉动动画 |
| reduceMotion 三态 | `@Environment(\.accessibilityReduceMotion) reduceMotion`；三动画 computed `reduceMotion ? nil : ...`；`.onAppear { guard !reduceMotion else { return }; ... }`；reduceMotion 时旋转=0/脉动=false/反光=0.6 静态构图 |
| Canvas 性能 | Canvas 一次性绘制 36/24 线段，比 ForEach+Rectangle 少 36 个视图节点；旋转用整体 rotationEffect 而非每线 animate |

---

## 8. 共享知识（给工程师）

1. **本轮全部纯 SwiftUI**：7 个新文件均不 `import AppKit`/`Cocoa`/`ColorfulX`/`Pow`，`swift build` 必须通过。
2. **ColorfulView 不进 CicadaUI**：AlarmOverlay 的 sunset 渐变背景由 P4 宿主 ZStack 组合，CicadaUI 只提供 `AlarmOverlayContent`（内容层）。
3. **NotchDropDelegate 协议 8 方法**：宿主 `NotchViewModel` conform 时补实现，转发到 `TrayDrop`/`AirDrop`/`NSWorkspace`/`notchClose`。
4. **泛型持有 delegate**：`NotchPanel<Delegate>`/`NotchMenu<Delegate>`/`NotchSection<Delegate>` where `Delegate: ObservableObject & NotchDropDelegate`，用 `@ObservedObject` 观察。
5. **contentType 路由留宿主**：CicadaUI 提供 `NotchPanel`（normal）/`NotchMenu`（menu）两个独立视图，通知视图留宿主，宿主 `NotchContentView` 做 switch。
6. **NotchSection 只做空态**：拖放提示 + 虚线边框 + .onDrop；非空态 DropItemView 横滑列表留宿主 P4。
7. **reduceMotion 必做**：AlarmEye 三动画（旋转/脉动/闪烁）必须有 reduceMotion 分支，传 nil 动画 + 静态构图，不消失。
8. **文案中文化**：本 spec 给中文文案占位，实际以产品定稿/Localizable 为准；工程师可保留英文 Key 走 `String(localized:)`。
9. **圆角/间距对齐宿主**：`NotchPanel`/`NotchMenu` 的 `cornerRadius`/`spacing` 由宿主传入（对齐 `NotchViewModel.cornerRadius=16`/`spacing=16`）。
10. **AlarmEye 构图常量**：outerSize=200/irisSize=180/pupilSize=50/reflectionSize=8，与现有 EyeView.swift 一致，不改动效数值。
11. **AlarmOverlayContent 固定 700×400**：与现有 SentryView 一致。
12. **停止按钮样式**：`AlarmStopButtonStyle`（半透明白底 + danger 红边），非 PrimaryButtonStyle（accent 绿与 sunset 不搭）。

---

## 9. 验收清单（本轮 swift build）

- [ ] `swift build --target CicadaUI` 通过，7 个新文件无编译错误
- [ ] `AlarmEye` Preview 渲染眼睛（旋转/脉动可见）
- [ ] `AlarmLeftPanel` Preview 显示装饰图标 + 标题 + 原因 + 描述 + 停止按钮
- [ ] `AlarmOverlayContent` Preview 显示左文字 + 分隔条 + 右眼睛三段布局
- [ ] `NotchDropDelegate` 协议可被 `MockNotchDropDelegate` conform（编译通过）
- [ ] `NotchSection` Preview 两个虚线拖放区
- [ ] `NotchPanel` Preview 标题 + 两个拖放区
- [ ] `NotchMenu` Preview 6 方块按钮横排
- [ ] 无 `import AppKit`/`import ColorfulX`/`import Pow` 出现在 7 个新文件
- [ ] reduceMotion 代码路径存在（AlarmEye 三动画 computed 有 reduceMotion 分支）

---

## 附录：文件清单（本轮新增）

```
apps/agent/swift/Sources/CicadaUI/Views/
├── Alarm/
│   ├── AlarmEye.swift                  # 新建
│   ├── AlarmLeftPanel.swift            # 新建
│   └── AlarmOverlayContent.swift       # 新建
└── NotchDrop/
    ├── NotchDropDelegate.swift         # 新建
    ├── NotchSection.swift              # 新建
    ├── NotchPanel.swift                # 新建
    └── NotchMenu.swift                 # 新建

apps/agent/swift/Tests/CicadaUITests/   # 可选
└── NotchDropDelegateMockTests.swift     # 新建（Mock + 协议 conform 编译验证）
```