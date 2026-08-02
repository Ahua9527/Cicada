import SwiftUI

/// SleepHold 数据卡片。
struct SleepHoldCell: View {
    let cell: SleepHoldCellData

    var body: some View {
        VStack(alignment: .leading, spacing: DesignMetrics.Spacing.s1) {
            Text(cell.label)
                .font(.caption2)
                .foregroundStyle(.cicadaTextTertiary)
                .textCase(.uppercase)
                .tracking(0.5)
            Text(cell.value)
                .font(cell.isMono ? .caption.monospaced() : .subheadline.weight(.medium))
                .foregroundStyle(cell.ok ? AnyShapeStyle(.cicadaAccent) : AnyShapeStyle(.cicadaTextPrimary))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DesignMetrics.Spacing.s3)
        .background(Color.cicadaBgBase)
        .clipShape(RoundedRectangle(cornerRadius: DesignMetrics.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: DesignMetrics.Radius.md)
                .stroke(.cicadaBorderSubtle, lineWidth: 1)
        )
    }
}

#Preview {
    HStack(spacing: DesignMetrics.Spacing.s3) {
        SleepHoldCell(cell: SleepHoldCellData(label: "状态", value: "活跃", isMono: false, ok: true))
        SleepHoldCell(cell: SleepHoldCellData(label: "电源", value: "sleep_disabled", isMono: false, ok: true))
        SleepHoldCell(cell: SleepHoldCellData(label: "活跃数", value: "1", isMono: true, ok: true))
    }
    .padding()
    .background(.cicadaBgSurface)
    .frame(width: 500)
}
