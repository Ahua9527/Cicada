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
                NavRow(section: section, active: router.selection == section, statusText: statusText(for: section))
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

    /// 侧栏状态从实时模型派生，而非固定文案：
    /// - 概览：Sentinel 运行状态（运行中/警告/空闲）。
    /// - 设置：触发器与通知均配置就绪则「就绪」，否则「待配置」。
    /// - 维护：SleepHold 活跃则「保持中」，否则「睡眠保持空闲」。
    private func statusText(for section: NavSection) -> String {
        switch section {
        case .overview:
            return appModel.sentinels.state.title
        case .settings:
            let ready = appModel.config.sentry.hasTriggerEnabled && appModel.config.sentry.hasNotificationEnabled
            return ready ? String(localized: "就绪", bundle: .module) : String(localized: "待配置", bundle: .module)
        case .maintenance:
            return appModel.sleepHold.isActive
                ? String(localized: "保持中", bundle: .module)
                : String(localized: "睡眠保持空闲", bundle: .module)
        }
    }
}

#Preview {
    ControlCenterRoot()
        .environmentObject(AppModel())
        .environmentObject(ControlCenterRouter())
        .frame(width: 900, height: 600)
}