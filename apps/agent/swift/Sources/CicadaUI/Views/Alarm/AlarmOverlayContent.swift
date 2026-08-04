import SwiftUI

/// 警戒全屏内容层（不含 ColorfulView / ultraThinMaterial 背景）。
///
/// 纯 SwiftUI，可 `swift build` 验证。
/// 布局：`HStack(AlarmLeftPanel + 竖向分隔条 + AlarmEye)`，固定 700×400。
///
/// P4 宿主组合层职责（本视图**不负责**）：
/// ```swift
/// ZStack {
///     ColorfulView(color: .sunset, noise: .constant(64)).ignoresSafeArea()
///     Rectangle().fill(.ultraThinMaterial).opacity(0.5)
///     AlarmOverlayContent(reason: appModel.alarm.reason) {
///         Task { await appModel.alarm.stop(); /* dismissWindow 或 SkyLightOperator 关闭 */ }
///     }
/// }
/// ```
public struct AlarmOverlayContent: View {
    /// 警戒触发原因。
    let reason: String
    /// 停止警戒闭包。
    let onStop: () -> Void

    public init(reason: String, onStop: @escaping () -> Void) {
        self.reason = reason
        self.onStop = onStop
    }

    public var body: some View {
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
    // 模拟宿主组合（背景渐变 + 毛玻璃 + 内容层），仅用于视觉验证。
    ZStack {
        LinearGradient(
            colors: [
                Color(red: 0.98, green: 0.45, blue: 0.09),
                Color(red: 0.94, green: 0.27, blue: 0.27),
                Color(red: 0.42, green: 0.02, blue: 0.06),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        Rectangle().fill(.ultraThinMaterial).opacity(0.5)
        AlarmOverlayContent(reason: "合上盖子") {}
    }
    .clipShape(RoundedRectangle(cornerRadius: 32))
    .background(.black)
}
