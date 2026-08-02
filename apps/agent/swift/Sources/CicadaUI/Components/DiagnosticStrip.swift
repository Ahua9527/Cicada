import SwiftUI

/// 琥珀色告警条，仅在 `diagnostic != nil` 时出现。
struct DiagnosticStrip: View {
    let diag: Diagnostic

    var body: some View {
        HStack(alignment: .top, spacing: DesignMetrics.Spacing.s3) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.cicadaWarn)
            Text(diag.message)
                .font(.caption)
                .foregroundStyle(.cicadaWarn)
            Spacer()
        }
        .padding(.horizontal, DesignMetrics.Spacing.s4)
        .padding(.vertical, DesignMetrics.Spacing.s3)
        .background(Color.cicadaWarn.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: DesignMetrics.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: DesignMetrics.Radius.md)
                .stroke(.cicadaWarn.opacity(0.2), lineWidth: 1)
        )
    }
}

#Preview {
    VStack(spacing: 12) {
        DiagnosticStrip(diag: Diagnostic(level: .warn, message: "检测到异常活动：合盖触发器已激活"))
        DiagnosticStrip(diag: Diagnostic(level: .danger, message: "警戒已触发：电源断开"))
    }
    .padding()
    .background(.cicadaBgSurface)
    .frame(width: 400)
}