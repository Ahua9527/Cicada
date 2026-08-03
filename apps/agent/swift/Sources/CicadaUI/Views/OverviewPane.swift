import SwiftUI

/// 概览页：PaneHeader + StatusHeroCard + ReadinessCard + DiagnosticStrip + VersionTag。
struct OverviewPane: View {
    @EnvironmentObject var appModel: AppModel
    @State private var showHelp = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignMetrics.Spacing.s5) {
                PaneHeader(
                    title: String(localized: "Cicada 控制中心", bundle: .module),
                    subtitle: String(localized: "状态、控制与配置的统一入口", bundle: .module),
                    trailing: { HelpButton { showHelp = true } }
                )
                StatusHeroCard(state: appModel.sentinels.state)
                ReadinessCard(items: appModel.sentinels.readiness)
                if let diag = appModel.sentinels.diagnostic {
                    DiagnosticStrip(diag: diag)
                }
                VersionTag()
            }
            .padding(DesignMetrics.Spacing.s6)
        }
        .sheet(isPresented: $showHelp) { HelpSheet() }
    }
}

#Preview {
    OverviewPane()
        .environmentObject(AppModel())
        .frame(width: 640, height: 600)
}