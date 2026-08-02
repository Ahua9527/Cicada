import SwiftUI

/// 主窗口双栏骨架：NavigationSplitView 侧栏 + detail switch。
///
/// `public` 暴露：宿主 `App.swift` 的 `WindowGroup(id:"main")` 直接引用。
/// 选中态由共享路由器 `ControlCenterRouter`（`@EnvironmentObject`）持有，宿主 commands
/// 与菜单栏按钮可通过 `ControlCenterRouter.shared.open(_:)` 外部驱动。
public struct ControlCenterRoot: View {
    @EnvironmentObject var appModel: AppModel
    @EnvironmentObject var router: ControlCenterRouter

    public init() {}

    public var body: some View {
        NavigationSplitView {
            List(NavSection.allCases, selection: $router.selection) { section in
                NavRow(section: section, active: router.selection == section)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(DesignMetrics.sidebarWidth)
        } detail: {
            switch router.selection {
            case .overview:    OverviewPane()
            case .settings:    SettingsPane()
            case .maintenance: MaintenancePane()
            case .none:        OverviewPane()
            }
        }
    }
}

#Preview {
    ControlCenterRoot()
        .environmentObject(AppModel())
        .environmentObject(ControlCenterRouter())
        .frame(width: 900, height: 600)
}