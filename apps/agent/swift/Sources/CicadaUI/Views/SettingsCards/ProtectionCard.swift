import SwiftUI

/// 防护设置卡：3 个触发器 Toggle（合盖/断网/断电）。
struct ProtectionCard: View {
    @ObservedObject var model: ConfigModel

    var body: some View {
        Card(title: "防护") {
            VStack(spacing: 0) {
                SettingRow(title: "合盖触发", desc: "检测到 MacBook 合盖时触发警戒") {
                    Toggle("", isOn: $model.sentry.sentryTriggersLidEnabled)
                        .labelsHidden()
                        .tint(.cicadaAccent)
                }
                SettingRow(title: "断网触发", desc: "检测到网络连接断开时触发警戒") {
                    Toggle("", isOn: $model.sentry.sentryTriggersInternetEnabled)
                        .labelsHidden()
                        .tint(.cicadaAccent)
                }
                SettingRow(title: "断电触发", desc: "检测到电源适配器断开时触发警戒") {
                    Toggle("", isOn: $model.sentry.sentryTriggersPowerEnabled)
                        .labelsHidden()
                        .tint(.cicadaAccent)
                }
            }
        }
    }
}

#Preview {
    ProtectionCard(model: ConfigModel())
        .padding()
        .background(.cicadaBgSurface)
        .frame(width: 500)
}
