import SwiftUI

/// 帮助面板：简介 + 可用触发器（编号列表）+ 注意事项（项目符号列表）。
struct HelpSheet: View {
    var body: some View {
        VStack(alignment: .leading, spacing: DesignMetrics.Spacing.s4) {
            Text(String(localized: "Cicada 是一款 macOS 安全防护工具，通过监控合盖、断网、断电等触发器，在异常发生时启动警戒并推送通知。", bundle: .module))
                .font(.subheadline)
                .foregroundStyle(.cicadaTextSecondary)

            Divider()

            HelpSection(title: String(localized: "可用触发器", bundle: .module), icon: "bolt.fill") {
                HelpNumberedList(items: [
                    String(localized: "合上 Mac 盖子", bundle: .module),
                    String(localized: "断开网络连接", bundle: .module),
                    String(localized: "断开电源适配器", bundle: .module),
                ])
            }

            Divider()

            HelpSection(title: String(localized: "注意事项", bundle: .module), icon: "exclamationmark.triangle.fill") {
                HelpBulletList(items: [
                    String(localized: "至少启用一个触发器和一个通知方式才能激活警戒。", bundle: .module),
                    String(localized: "合盖触发需要屏幕处于休眠状态才会响应。", bundle: .module),
                    String(localized: "录像功能需要授予摄像头访问权限。", bundle: .module),
                    String(localized: "Bark 推送需要正确配置 Endpoint 地址。", bundle: .module),
                ])
            }
        }
        .padding(DesignMetrics.Spacing.s6)
        .frame(width: 420)
        .background(Color.cicadaBgSurface)
        .clipShape(RoundedRectangle(cornerRadius: DesignMetrics.Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: DesignMetrics.Radius.lg)
                .stroke(.cicadaBorder, lineWidth: 1)
        )
    }
}

/// 帮助小节：图标 + 标题 + 内容。
struct HelpSection<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: DesignMetrics.Spacing.s3) {
            HStack(spacing: DesignMetrics.Spacing.s2) {
                Image(systemName: icon)
                    .font(.subheadline)
                    .foregroundStyle(.cicadaAccent)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.cicadaTextPrimary)
            }
            content()
        }
    }
}

/// 编号列表：编号用 accent 色 + monospacedDigit。
struct HelpNumberedList: View {
    let items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: DesignMetrics.Spacing.s2) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .top, spacing: DesignMetrics.Spacing.s3) {
                    Text("\(index + 1)")
                        .font(.subheadline.weight(.medium).monospacedDigit())
                        .foregroundStyle(.cicadaAccent)
                        .frame(width: 18, alignment: .leading)
                    Text(item)
                        .font(.subheadline)
                        .foregroundStyle(.cicadaTextSecondary)
                }
            }
        }
    }
}

/// 项目符号列表：accent 色圆点。
struct HelpBulletList: View {
    let items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: DesignMetrics.Spacing.s2) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .top, spacing: DesignMetrics.Spacing.s3) {
                    Circle()
                        .fill(.cicadaAccent)
                        .frame(width: 5, height: 5)
                        .padding(.top, 6)
                    Text(item)
                        .font(.subheadline)
                        .foregroundStyle(.cicadaTextSecondary)
                }
            }
        }
    }
}

#Preview {
    HelpSheet()
        .padding()
        .background(.cicadaBgBase)
}