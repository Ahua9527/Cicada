import SwiftUI

/// 连接设置卡：Relay 地址输入 + 保存按钮 + InlineMessage。
struct ConnectionCard: View {
    @ObservedObject var model: ConfigModel

    var body: some View {
        Card(title: String(localized: "连接", bundle: .module)) {
            VStack(alignment: .leading, spacing: DesignMetrics.Spacing.s4) {
                CicadaTextField(
                    title: String(localized: "Relay 地址", bundle: .module),
                    text: $model.draft.relayURL,
                    hint: String(localized: "Cicada 中继服务地址，例如 wss://relay.example.com", bundle: .module)
                )
                HStack {
                    Button(String(localized: "保存", bundle: .module)) {
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
        case .ok:     return (.ok, String(localized: "配置已保存", bundle: .module))
        case .saving: return nil
        case .err(let e): return (.err, String(localized: "保存失败：", bundle: .module) + e)
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