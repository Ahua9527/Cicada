import SwiftUI

/// 警戒非告警态内容层：已激活监控的占位视图（不含告警原因与停止按钮）。
///
/// 与 `AlarmOverlayContent` 共用 `AlarmEye` + 竖向分隔条构图，左侧文案改为
/// 「Cicada 已激活」+ 监控描述，**无停止按钮**——避免监控启动（锁定后 `prepareForRun`）
/// 但尚未告警时暴露「停止警戒」导致用户误按中断整次监控。宿主按 `sentry.isAlrming`
/// 在本视图与 `AlarmOverlayContent` 之间切换。
public struct MonitoringOverlayContent: View {
    public init() {}

    public var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: DesignMetrics.Spacing.s2) {
                Image(systemName: "eye.fill")
                    .font(.largeTitle)
                    .bold()
                    .opacity(0.2)

                Spacer()

                Text("Cicada 已激活", bundle: .module)
                    .font(.system(size: 28, weight: .heavy))

                Text("此 Mac 已联网并正在监控你的行为。", bundle: .module)
                    .font(.body)
                    .foregroundStyle(.primary.opacity(0.7))
            }
            .padding(DesignMetrics.Spacing.s8)
            .frame(maxWidth: .infinity, alignment: .leading)

            Rectangle()
                .fill(Color.black.opacity(0.5))
                .frame(width: 10)

            AlarmEye()
                .frame(width: 200)
                .padding(DesignMetrics.Spacing.s8)
        }
        .frame(width: 700, height: 400, alignment: .center)
    }
}

#Preview {
    MonitoringOverlayContent()
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 32))
}