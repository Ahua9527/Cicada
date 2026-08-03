import SwiftUI

/// 防护设置卡：3 个触发器 Toggle（合盖/断网/断电）。
struct ProtectionCard: View {
    @ObservedObject var model: ConfigModel

    var body: some View {
        Card(title: String(localized: "防护", bundle: .module)) {
            VStack(spacing: 0) {
                SettingRow(title: String(localized: "合盖触发", bundle: .module), desc: String(localized: "检测到 MacBook 合盖时触发警戒", bundle: .module)) {
                    Toggle("", isOn: $model.sentry.sentryTriggersLidEnabled)
                        .labelsHidden()
                        .tint(.cicadaAccent)
                }
                SettingRow(title: String(localized: "断网触发", bundle: .module), desc: String(localized: "检测到网络连接断开时触发警戒", bundle: .module)) {
                    Toggle("", isOn: $model.sentry.sentryTriggersInternetEnabled)
                        .labelsHidden()
                        .tint(.cicadaAccent)
                }
                SettingRow(title: String(localized: "断电触发", bundle: .module), desc: String(localized: "检测到电源适配器断开时触发警戒", bundle: .module)) {
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
