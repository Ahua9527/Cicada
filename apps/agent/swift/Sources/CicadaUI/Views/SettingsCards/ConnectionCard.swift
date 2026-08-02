import SwiftUI

/// 连接设置卡：Relay 地址输入 + 保存按钮 + InlineMessage。
struct ConnectionCard: View {
    @ObservedObject var model: ConfigModel

    var body: some View {
        Card(title: "连接") {
            VStack(alignment: .leading, spacing: DesignMetrics.Spacing.s4) {
                CicadaTextField(
                    title: "Relay 地址",
                    text: $model.draft.relayURL,
                    hint: "Cicada 中继服务地址，例如 wss://relay.example.com"
                )
                HStack {
                    Button("保存") {
                        Task { await model.saveConnection() }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    if let msg = inlineMessage {
                        InlineMessage(kind: msg.kind, text: msg.text)
                    }
                }
            }
        }
    }

    private var inlineMessage: (kind: InlineMessage.Kind, text: String)? {
        switch model.saveState {
        case .ok:     return (.ok, "配置已保存")
        case .saving: return nil
        case .err(let e): return (.err, "保存失败：\(e)")
        case .idle:   return nil
        }
    }
}

#Preview {
    ConnectionCard(model: ConfigModel())
        .padding()
        .background(.cicadaBgSurface)
        .frame(width: 500)
}