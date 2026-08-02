import SwiftUI

/// 侧栏导航行。
struct NavRow: View {
    let section: NavSection
    let active: Bool

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
                Text(section.statusText)
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
        NavRow(section: .overview, active: true)
        NavRow(section: .settings, active: false)
        NavRow(section: .maintenance, active: false)
    }
    .padding()
    .background(.cicadaBgSurface)
    .frame(width: 220)
}