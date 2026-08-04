import SwiftUI

/// 警戒左侧文字区：装饰图标（顶对齐）+ Spacer + 标题 + 触发原因 + 描述 + 停止按钮。
///
/// 对照 Design.md §5.1 `AlarmLeftPanel`。
/// `onStop` 是闭包注入，由 `AlarmOverlayContent` 传入
/// `{ Task { await appModel.alarm.stop(); dismissWindow() } }`，
/// 不直接依赖 `AlarmModel`，保持组件可独立预览/单测。
struct AlarmLeftPanel: View {
    /// 警戒触发原因（`appModel.alarm.reason`），空串时不显示原因行。
    let reason: String
    /// 停止警戒闭包，由上层注入。
    let onStop: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DesignMetrics.Spacing.s2) {
            // ① 装饰图标（顶对齐，半透明）
            Image(systemName: "eye.fill")
                .font(.largeTitle)
                .bold()
                .opacity(0.2)

            Spacer()

            // ② 标题
            Text("Cicada 警戒已触发", bundle: .module)
                .font(.system(size: 28, weight: .heavy))
                .foregroundStyle(.white)

            // ③ 触发原因（若有）
            if !reason.isEmpty {
                Text(reason)
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.85))
            }

            // ④ 描述
            Text("此 Mac 已联网并正在监控你的行为。", bundle: .module)
                .font(.body)
                .foregroundStyle(.white.opacity(0.7))

            // ⑤ 停止按钮
            Button(action: onStop) {
                Label(String(localized: "停止警戒", bundle: .module), systemImage: "stop.fill")
            }
            .buttonStyle(AlarmStopButtonStyle())
            .padding(.top, DesignMetrics.Spacing.s3)
        }
        .padding(DesignMetrics.Spacing.s8)   // 32pt，对照现有 SentryView texts padding(32)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 警戒停止按钮样式：半透明白底 + danger 红边强调停止动作。
///
/// 警戒背景是 sunset 暖色渐变，`PrimaryButtonStyle` 的 accent 绿与 sunset 不搭，
/// 故自定义此样式（Design.md §8.2 修复版决策：停止按钮用 `AlarmStopButtonStyle`，
/// 不用 `PrimaryButtonStyle`）。
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

#Preview("Empty reason") {
    AlarmLeftPanel(reason: "") {}
        .frame(width: 360, height: 400)
        .background(Color.black.opacity(0.6))
        .preferredColorScheme(.dark)
}