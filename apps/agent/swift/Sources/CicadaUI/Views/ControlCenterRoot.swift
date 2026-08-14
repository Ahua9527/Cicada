import SwiftUI

/// 主窗口双栏骨架：NavigationSplitView 侧栏 + detail switch。
///
/// `public` 暴露：宿主 `App.swift` 的 `WindowGroup(id:"main")` 直接引用。
/// 选中态由共享路由器 `ControlCenterRouter`（`@EnvironmentObject`）持有，宿主 commands
/// 与菜单栏按钮可通过 `ControlCenterRouter.shared.open(_:)` 外部驱动。
///
/// 侧栏刻意不用 `List(selection:)`：真机实测（macOS 15.6）该构造的点击选中整体失灵——
/// 视图层级、命中测试、手势识别器全部正常，事件也确实到达，但系统从不派发选中；
/// 最小复现对照实验（同一结构的 5 种写法）确认所有 List 变体均失效、仅 Button 写法
/// 可点。改用 Button 列表 + NavRow 自绘选中态，视觉一致且交互可靠。
public struct ControlCenterRoot: View {
    @EnvironmentObject var appModel: AppModel
    @EnvironmentObject var router: ControlCenterRouter

    public init() {}

    public var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: DesignMetrics.Spacing.s1) {
                ForEach(NavSection.allCases) { section in
                    Button {
                        router.selection = section
                    } label: {
                        NavRow(
                            section: section,
                            active: router.selection == section,
                            statusText: statusText(for: section)
                        )
                    }
                    .buttonStyle(NavRowButtonStyle())
                }
                Spacer()
            }
            .padding(.horizontal, DesignMetrics.Spacing.s4)
            .padding(.top, DesignMetrics.Spacing.s2)
            .navigationSplitViewColumnWidth(DesignMetrics.sidebarWidth)
        } detail: {
            switch router.selection {
            case .overview:    OverviewPane()
            case .settings:    SettingsPane()
            case .maintenance: MaintenancePane()
            case .none:        OverviewPane()
            }
        }
        .frame(minWidth: 880, minHeight: 600)
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

/// 侧栏行按钮样式：悬停/按压叠加一层中性底色（参数与 MenuBarButtonStyle 一致），
/// 选中态由 NavRow 自绘（accent 底 + 描边），位于样式底色之上，互不干扰。
private struct NavRowButtonStyle: ButtonStyle {
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: DesignMetrics.Radius.md)
                    .fill(backgroundColor(pressed: configuration.isPressed))
            )
            .animation(.easeOut(duration: 0.1), value: isHovered)
            .onHover { isHovered = $0 }
    }

    private func backgroundColor(pressed: Bool) -> Color {
        if pressed { return .cicadaTextPrimary.opacity(0.12) }
        return isHovered ? .cicadaTextPrimary.opacity(0.08) : .clear
    }
}

#Preview {
    ControlCenterRoot()
        .environmentObject(AppModel())
        .environmentObject(ControlCenterRouter())
        .frame(width: 900, height: 600)
}