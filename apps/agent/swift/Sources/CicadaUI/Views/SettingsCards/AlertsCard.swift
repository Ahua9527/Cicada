import SwiftUI

/// 告警设置卡：声音 Toggle + Bark 通知 Toggle + Bark Endpoint 输入。
struct AlertsCard: View {
    @ObservedObject var model: ConfigModel

    var body: some View {
        Card(title: "告警") {
            VStack(alignment: .leading, spacing: 0) {
                SettingRow(title: "告警声音", desc: "警戒触发时播放提示音") {
                    Toggle("", isOn: $model.sentry.sentryAlarmsSoundsEnabled)
                        .labelsHidden()
                        .tint(.cicadaAccent)
                }
                SettingRow(title: "Bark 推送", desc: "通过 Bark 服务推送警戒通知") {
                    Toggle("", isOn: barkEnabledBinding)
                        .labelsHidden()
                        .tint(.cicadaAccent)
                }
                CicadaTextField(
                    title: "Bark Endpoint",
                    text: $model.sentry.sentryNotificationConfigBark.endpoint,
                    hint: "输入 Bark 服务端地址，例如 https://api.day.app/xxx"
                )
                .padding(.top, DesignMetrics.Spacing.s3)
            }
        }
    }

    /// 把 NotificationType != .none 映射成 Bool 绑定。
    private var barkEnabledBinding: Binding<Bool> {
        Binding(
            get: { model.sentry.sentryAlarmsNotificationType != .none },
            set: { newValue in
                model.sentry.sentryAlarmsNotificationType = newValue ? .bark : .none
            }
        )
    }
}

#Preview {
    AlertsCard(model: ConfigModel())
        .padding()
        .background(.cicadaBgSurface)
        .frame(width: 500)
}
