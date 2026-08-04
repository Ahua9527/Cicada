import SwiftUI

/// 内联消息（ok/err）。
struct InlineMessage: View {
    enum Kind { case ok, err }
    let kind: Kind
    let text: String

    private var color: Color {
        kind == .ok ? .cicadaAccent : .cicadaDanger
    }

    var body: some View {
        HStack(spacing: DesignMetrics.Spacing.s2) {
            Image(systemName: kind == .ok ? "checkmark.circle.fill" : "xmark.octagon.fill")
            Text(text)
        }
        .font(.caption)
        .padding(.horizontal, DesignMetrics.Spacing.s3)
        .padding(.vertical, DesignMetrics.Spacing.s2)
        .background(color.opacity(0.12))
        .foregroundStyle(color)
        .clipShape(RoundedRectangle(cornerRadius: DesignMetrics.Radius.sm))
    }
}

#Preview {
    VStack(spacing: 8) {
        InlineMessage(kind: .ok, text: "配置已保存")
        InlineMessage(kind: .err, text: "保存失败：无法写入文件")
    }
    .padding()
    .background(.cicadaBgSurface)
    .frame(width: 300)
}