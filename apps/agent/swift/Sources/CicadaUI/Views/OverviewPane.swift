import SwiftUI

/// 概览页：PaneHeader + StatusHeroCard + ReadinessCard + DiagnosticStrip + VersionTag。
struct OverviewPane: View {
    @EnvironmentObject var appModel: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showHelp = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignMetrics.Spacing.s5) {
                PaneHeader(
                    title: String(localized: "Cicada 控制中心", bundle: .module),
                    subtitle: String(localized: "状态、控制与配置的统一入口", bundle: .module),
                    trailing: {
                        HelpButton { showHelp = true }
                            .popover(isPresented: $showHelp, arrowEdge: .top) { HelpSheet() }
                    }
                )
                StatusHeroCard(state: appModel.sentinels.state)
                ReadinessCard(items: appModel.sentinels.readiness)
                if let diag = appModel.sentinels.diagnostic {
                    DiagnosticStrip(diag: diag)
                        .id(diag.motionKey)
                        .transition(diagnosticTransition)
                }
                VersionTag()
            }
            .animation(.easeOut(duration: 0.2), value: appModel.sentinels.diagnostic?.motionKey)
            .padding(DesignMetrics.Spacing.s6)
        }
    }

    private var diagnosticTransition: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top))
    }
}

#Preview {
    OverviewPane()
        .environmentObject(AppModel())
        .frame(width: 640, height: 600)
}
