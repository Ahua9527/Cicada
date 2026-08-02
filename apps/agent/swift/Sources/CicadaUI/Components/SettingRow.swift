import SwiftUI

/// 行式配置项（左标题+描述，右控件）。
struct SettingRow<Control: View>: View {
    let title: String
    let desc: String
    @ViewBuilder let control: () -> Control

    init(title: String, desc: String, @ViewBuilder control: @escaping () -> Control) {
        self.title = title
        self.desc = desc
        self.control = control
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.cicadaTextPrimary)
                Text(desc)
                    .font(.caption)
                    .foregroundStyle(.cicadaTextTertiary)
            }
            Spacer(minLength: DesignMetrics.Spacing.s6)
            control()
        }
        .padding(.vertical, DesignMetrics.Spacing.s3)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(.cicadaBorderSubtle)
                .frame(height: 1)
        }
    }
}

#Preview {
    VStack {
        SettingRow(title: "合盖触发", desc: "检测到 MacBook 合盖时触发警戒") {
            Toggle("", isOn: .constant(true)).labelsHidden().tint(.cicadaAccent)
        }
        SettingRow(title: "Bark 通知", desc: "通过 Bark 推送警戒通知") {
            Toggle("", isOn: .constant(false)).labelsHidden().tint(.cicadaAccent)
        }
    }
    .padding()
    .background(.cicadaBgSurface)
    .frame(width: 400)
}