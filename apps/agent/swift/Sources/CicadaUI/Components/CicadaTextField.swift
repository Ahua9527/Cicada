import SwiftUI

/// 带焦点高亮的文本输入。
struct CicadaTextField: View {
    let title: String
    @Binding var text: String
    let hint: String?
    @FocusState private var isFocused: Bool

    init(title: String, text: Binding<String>, hint: String? = nil) {
        self.title = title
        self._text = text
        self.hint = hint
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignMetrics.Spacing.s2) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.cicadaTextSecondary)
            TextField("", text: $text)
                .textFieldStyle(.plain)
                .focused($isFocused)
                .padding(.horizontal, DesignMetrics.Spacing.s4)
                .padding(.vertical, DesignMetrics.Spacing.s3)
                .background(Color.cicadaBgBase)
                .clipShape(RoundedRectangle(cornerRadius: DesignMetrics.Radius.md))
                .overlay(
                    RoundedRectangle(cornerRadius: DesignMetrics.Radius.md)
                        .stroke(isFocused ? AnyShapeStyle(.cicadaAccent) : AnyShapeStyle(.cicadaBorder), lineWidth: 1)
                )
                .shadow(color: isFocused ? .cicadaAccent.opacity(0.12) : .clear, radius: 6)
            if let hint {
                Text(hint)
                    .font(.caption2)
                    .foregroundStyle(.cicadaTextTertiary)
            }
        }
    }
}

#Preview {
    @Previewable @State var text = "https://api.day.app/xxx"
    return CicadaTextField(title: "Bark Endpoint", text: $text, hint: "输入 Bark 服务端地址")
        .padding()
        .background(.cicadaBgSurface)
        .frame(width: 400)
}