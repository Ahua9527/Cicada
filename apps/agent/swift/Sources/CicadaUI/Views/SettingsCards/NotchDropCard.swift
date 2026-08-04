import SwiftUI

/// NotchDrop 设置卡：触觉反馈 + 文件保留时长 + 界面语言。
///
/// 宿主注入 `notchDropSettingsStore` 时绑定引擎真实设置（NotchViewModel / TrayDrop）；
/// 未注入（预览/单测）回退到本地 @AppStorage 占位。
struct NotchDropCard: View {
    @Environment(\.notchDropSettingsStore) private var store

    @AppStorage("notch.hapticFeedback") private var fallbackHapticFeedback: Bool = true
    @AppStorage("notch.fileRetentionDays") private var fallbackFileRetentionDays: Int = 7
    @AppStorage("notch.interfaceLanguage") private var fallbackInterfaceLanguage: String = "auto"

    var body: some View {
        if let store {
            StoreDrivenContent(store: store)
        } else {
            NotchDropCardRows(
                hapticFeedback: $fallbackHapticFeedback,
                fileRetentionDays: $fallbackFileRetentionDays,
                interfaceLanguage: $fallbackInterfaceLanguage
            )
        }
    }
}

private struct StoreDrivenContent: View {
    @ObservedObject var store: NotchDropSettingsStore

    var body: some View {
        NotchDropCardRows(
            hapticFeedback: $store.hapticFeedback,
            fileRetentionDays: $store.fileRetentionDays,
            interfaceLanguage: $store.interfaceLanguage
        )
    }
}

private struct NotchDropCardRows: View {
    @Binding var hapticFeedback: Bool
    @Binding var fileRetentionDays: Int
    @Binding var interfaceLanguage: String

    var body: some View {
        Card(title: "NotchDrop") {
            VStack(spacing: 0) {
                SettingRow(title: String(localized: "触觉反馈", bundle: .module), desc: String(localized: "拖放文件到刘海时播放触觉反馈", bundle: .module)) {
                    Toggle("", isOn: $hapticFeedback)
                        .labelsHidden()
                        .tint(.cicadaAccent)
                }
                SettingRow(title: String(localized: "文件保留时长", bundle: .module), desc: String(localized: "刘海暂存的文件保留天数", bundle: .module)) {
                    Picker("", selection: $fileRetentionDays) {
                        Text(String(localized: "1 天", bundle: .module)).tag(1)
                        Text(String(localized: "7 天", bundle: .module)).tag(7)
                        Text(String(localized: "30 天", bundle: .module)).tag(30)
                        Text(String(localized: "永不清理", bundle: .module)).tag(0)
                    }
                    .labelsHidden()
                    .frame(width: 120)
                }
                SettingRow(title: String(localized: "界面语言", bundle: .module), desc: String(localized: "应用显示语言", bundle: .module)) {
                    Picker("", selection: $interfaceLanguage) {
                        Text(String(localized: "跟随系统", bundle: .module)).tag("auto")
                        Text(String(localized: "简体中文", bundle: .module)).tag("zh-Hans")
                        Text("English").tag("en")
                    }
                    .labelsHidden()
                    .frame(width: 140)
                }
            }
        }
    }
}

#Preview {
    NotchDropCard()
        .padding()
        .background(.cicadaBgSurface)
        .frame(width: 500)
}
