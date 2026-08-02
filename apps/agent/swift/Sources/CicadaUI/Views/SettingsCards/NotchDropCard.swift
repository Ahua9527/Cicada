import SwiftUI

/// NotchDrop 设置卡：触觉反馈 + 文件保留时长 + 界面语言（本地 @AppStorage）。
struct NotchDropCard: View {
    @AppStorage("notch.hapticFeedback") private var hapticFeedback: Bool = true
    @AppStorage("notch.fileRetentionDays") private var fileRetentionDays: Int = 7
    @AppStorage("notch.interfaceLanguage") private var interfaceLanguage: String = "auto"

    var body: some View {
        Card(title: "NotchDrop") {
            VStack(spacing: 0) {
                SettingRow(title: "触觉反馈", desc: "拖放文件到刘海时播放触觉反馈") {
                    Toggle("", isOn: $hapticFeedback)
                        .labelsHidden()
                        .tint(.cicadaAccent)
                }
                SettingRow(title: "文件保留时长", desc: "刘海暂存的文件保留天数") {
                    Picker("", selection: $fileRetentionDays) {
                        Text("1 天").tag(1)
                        Text("7 天").tag(7)
                        Text("30 天").tag(30)
                        Text("永不清理").tag(0)
                    }
                    .labelsHidden()
                    .frame(width: 120)
                }
                SettingRow(title: "界面语言", desc: "应用显示语言") {
                    Picker("", selection: $interfaceLanguage) {
                        Text("跟随系统").tag("auto")
                        Text("简体中文").tag("zh-Hans")
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