import SwiftUI

/// Pane 顶部标题 + 副标题 + 右侧帮助按钮。
struct PaneHeader<Trailing: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let trailing: () -> Trailing

    init(title: String, subtitle: String, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: DesignMetrics.Spacing.s1) {
                Text(title)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.cicadaTextPrimary)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.cicadaTextSecondary)
            }
            Spacer()
            trailing()
        }
    }
}

/// 帮助按钮。
struct HelpButton: View {
    var action: () -> Void

    init(action: @escaping () -> Void = {}) {
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: "questionmark.circle")
                .font(.title3)
                .foregroundStyle(.cicadaTextSecondary)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    PaneHeader(title: "Cicada 控制中心", subtitle: "状态、控制与配置的统一入口") {
        HelpButton()
    }
    .padding()
    .background(.cicadaBgSurface)
    .frame(width: 500)
}