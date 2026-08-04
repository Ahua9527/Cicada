import SwiftUI

/// 警戒眼睛动画视图。
///
/// 纯 SwiftUI 实现，用 `Canvas` 绘制 36 条外层径向黑线（20s 旋转）+ 24 条内层红色线
/// （半径 75%）+ 瞳孔径向渐变（2s 缩放脉动）+ 反光点（2s 透明度闪烁）。
/// `reduceMotion` 时三动画均传 `nil`，`.onAppear` guard，保留静态构图不消失。
///
/// 对照 Design.md §5.2 与现有 `EyeView.swift` 构图常量，不改动画数值。
struct AlarmEye: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - 动画驱动值

    /// 外层 36 条径向线的整体旋转角度（20s 一圈）。
    @State private var rotation: Double = 0
    /// 瞳孔 2s 缩放脉动开关。
    @State private var pulse: Bool = false
    /// 反光点 2s 透明度闪烁开关。
    @State private var shimmer: Bool = false

    // MARK: - 构图常量（对照 Design.md §5.2 + 现有 EyeView.swift，不改动效数值）

    /// 外层眼白边框直径。
    private let outerSize: CGFloat = 200
    /// 虹膜渐变直径。
    private let irisSize: CGFloat = 180
    /// 内层线半径相对外层的比例（75%）。
    private let innerLineScale: CGFloat = 0.75
    /// 瞳孔直径。
    private let pupilSize: CGFloat = 50
    /// 反光点直径。
    private let reflectionSize: CGFloat = 8

    var body: some View {
        ZStack {
            // ① 眼白边框：8px 橙色环
            Circle()
                .stroke(Color.orange.opacity(0.3), lineWidth: 8)
                .frame(width: outerSize, height: outerSize)

            // ② 虹膜渐变：radial red→orange→red
            Circle()
                .fill(
                    RadialGradient(
                        gradient: Gradient(colors: [
                            Color.red.opacity(0.8),
                            Color.orange,
                            Color.red.opacity(0.9),
                        ]),
                        center: .center,
                        startRadius: 30,
                        endRadius: 90
                    )
                )
                .frame(width: irisSize, height: irisSize)

            // ③ 外层 36 条径向黑线（Canvas）+ 20s 旋转
            outerLines
                .rotationEffect(.degrees(rotation))
                .animation(rotationAnimation, value: rotation)

            // ④ 内层 24 条红色线（Canvas，半径 75%）
            innerLines

            // ⑤ 瞳孔：black→red 径向 + 2s 缩放脉动
            Circle()
                .fill(
                    RadialGradient(
                        gradient: Gradient(colors: [Color.black, Color.red.opacity(0.2)]),
                        center: .center,
                        startRadius: 5,
                        endRadius: 25
                    )
                )
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
            // reduceMotion 时停在静态构图（rotation=0 / pulse=false / shimmer=false / opacity=0.6）
            guard !reduceMotion else { return }
            rotation = 360
            pulse = true
            shimmer = true
        }
    }

    // MARK: - Canvas 层

    /// 外层 36 条径向黑线。
    ///
    /// 对照 Design.md §5.2「外层纹理线 36 条 conic 黑线，20s 旋转」。
    /// 用 `Canvas` 按角度等分画线段（10°/条），整体 `rotationEffect` 驱动旋转，
    /// 比 ForEach+Rectangle 少 36 个视图节点，性能更优。
    private var outerLines: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let lineLength: CGFloat = 80          // 对照 EyeView: height 80
            let innerRadius: CGFloat = 0          // 从中心放射
            for i in 0..<36 {
                let angle = Angle.degrees(Double(i) * 10).radians   // 36 等分 = 10°/条
                let dx = cos(angle), dy = sin(angle)
                let start = CGPoint(
                    x: center.x + dx * innerRadius,
                    y: center.y + dy * innerRadius
                )
                let end = CGPoint(
                    x: center.x + dx * (innerRadius + lineLength),
                    y: center.y + dy * (innerRadius + lineLength)
                )
                var path = Path()
                path.move(to: start)
                path.addLine(to: end)
                context.stroke(
                    path,
                    with: .color(Color.black.opacity(0.3)),
                    lineWidth: 1
                )
            }
        }
        .frame(width: irisSize, height: irisSize)
    }

    /// 内层 24 条红色线（半径 75%）。
    ///
    /// 对照 Design.md §5.2「内层纹理线 24 条红色线，半径缩小 25%」。
    private var innerLines: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let lineLength: CGFloat = 50 * innerLineScale   // 50 * 0.75
            for i in 0..<24 {
                let angle = Angle.degrees(Double(i) * 15).radians   // 24 等分 = 15°/条
                let dx = cos(angle), dy = sin(angle)
                let start = center
                let end = CGPoint(
                    x: center.x + dx * lineLength,
                    y: center.y + dy * lineLength
                )
                var path = Path()
                path.move(to: start)
                path.addLine(to: end)
                context.stroke(
                    path,
                    with: .color(Color.red.opacity(0.4)),
                    lineWidth: 0.5
                )
            }
        }
        .frame(width: irisSize, height: irisSize)
    }

    // MARK: - 动画（reduceMotion 三态兜底）

    /// 外层 20s 旋转动画。reduceMotion 时返回 `nil`，旋转停在 0°。
    private var rotationAnimation: Animation? {
        reduceMotion ? nil : .linear(duration: 20).repeatForever(autoreverses: false)
    }

    /// 瞳孔 2s 缩放脉动动画。reduceMotion 时返回 `nil`，瞳孔固定 scaleEffect=1。
    private var pulseAnimation: Animation? {
        reduceMotion ? nil : .easeInOut(duration: 2).repeatForever(autoreverses: true)
    }

    /// 反光点 2s 透明度闪烁动画。reduceMotion 时返回 `nil`，反光点固定 opacity=0.6。
    private var shimmerAnimation: Animation? {
        reduceMotion ? nil : .easeInOut(duration: 2).repeatForever(autoreverses: true)
    }
}

#Preview {
    AlarmEye()
        .frame(width: 250, height: 250)
        .background(.black)
}

/// 注：`accessibilityReduceMotion` 是只读 `EnvironmentValue`（仅有 getter），
/// 无法在 `#Preview` 中通过 `.environment(\\.accessibilityReduceMotion, true)` 注入。
/// reduceMotion 代码路径（三动画 computed 返回 nil + `.onAppear` guard）由源码与单测覆盖，
/// 实际减弱动态效果分支需在系统「辅助功能 → 减弱动态效果」开启后人工验证。