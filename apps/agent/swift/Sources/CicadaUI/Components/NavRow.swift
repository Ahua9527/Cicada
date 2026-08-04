import SwiftUI

/// 侧栏导航行。
struct NavRow: View {
    let section: NavSection
    let active: Bool
    /// 侧栏状态文案：由调用方从实时模型派生（见 ControlCenterRoot.statusText(for:)）。
    let statusText: String

    var body: some View {
        HStack(spacing: DesignMetrics.Spacing.s3) {
            Image(systemName: section.systemImage)
                .font(.body)
                .foregroundStyle(active ? AnyShapeStyle(.cicadaAccent) : AnyShapeStyle(.cicadaTextSecondary))
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(section.title)
                    .font(.subheadline.weight(active ? .semibold : .regular))
                    .foregroundStyle(.cicadaTextPrimary)
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.cicadaTextTertiary)
            }
            Spacer()
        }
        .padding(.vertical, DesignMetrics.Spacing.s2)
        .padding(.horizontal, DesignMetrics.Spacing.s3)
        .background(active ? Color.cicadaAccent.opacity(0.12) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: DesignMetrics.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: DesignMetrics.Radius.md)
                .stroke(active ? AnyShapeStyle(.cicadaAccent.opacity(0.3)) : AnyShapeStyle(.clear), lineWidth: 1)
        )
    }
}

#Preview {
    VStack(spacing: 4) {
        NavRow(section: .overview, active: true, statusText: "运行中")
        NavRow(section: .settings, active: false, statusText: "就绪")
        NavRow(section: .maintenance, active: false, statusText: "睡眠保持空闲")
    }
    .padding()
    .background(.cicadaBgSurface)
    .frame(width: 220)
}