import SwiftUI

/// 设置页：PaneHeader + SettingsTabBar + 5 个 Card（按 tab 切换）。
struct SettingsPane: View {
    @SceneStorage("settings.tab") private var tab: SettingsTab = .connection
    @EnvironmentObject var appModel: AppModel
    @EnvironmentObject var router: ControlCenterRouter
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showHelp = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignMetrics.Spacing.s5) {
                PaneHeader(
                    title: String(localized: "设置", bundle: .module),
                    subtitle: String(localized: "连接、防护、告警、录像与 NotchDrop", bundle: .module),
                    trailing: {
                        HelpButton { showHelp = true }
                            .popover(isPresented: $showHelp, arrowEdge: .top) { HelpSheet() }
                    }
                )
                SettingsTabBar(selection: $tab)
                if let sentrySaveError {
                    HStack(spacing: DesignMetrics.Spacing.s3) {
                        InlineMessage(
                            kind: .err,
                            text: String(localized: "保存失败：", bundle: .module) + sentrySaveError
                        )
                        Button(String(localized: "重试", bundle: .module)) {
                            Task { await appModel.config.retrySentrySave() }
                        }
                        .buttonStyle(GhostButtonStyle())
                    }
                    .transition(sentrySaveErrorTransition)
                }
                Group {
                    switch tab {
                    case .connection: ConnectionCard(model: appModel.config)
                    case .protection: ProtectionCard(model: appModel.config)
                    case .alerts:     AlertsCard(model: appModel.config)
                    case .recording:  RecordingCard(model: appModel.config)
                    case .notch:      NotchDropCard()
                    }
                }
                .transition(.opacity)
            }
            .animation(.easeOut(duration: 0.2), value: sentrySaveError)
            .padding(DesignMetrics.Spacing.s6)
        }
        .onAppear { consumePendingTab() }
        .onChange(of: router.pendingSettingsTab) { _ in consumePendingTab() }
    }

    private var sentrySaveError: String? {
        guard case let .err(error) = appModel.config.sentrySaveState else { return nil }
        return error
    }

    private var sentrySaveErrorTransition: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top))
    }

    /// 消费一次性子页路由命令（如 NotchDrop 齿轮 → `.notch`）。
    private func consumePendingTab() {
        guard let pending = router.pendingSettingsTab else { return }
        tab = pending
        router.pendingSettingsTab = nil
    }
}

/// 设置页子导航 Tab 枚举。public：供 `ControlCenterRouter.pendingSettingsTab` 与宿主路由使用。
public enum SettingsTab: String, CaseIterable, Hashable {
    case connection
    case protection
    case alerts
    case recording
    case notch

    var title: String {
        switch self {
        case .connection: return String(localized: "连接", bundle: .module)
        case .protection: return String(localized: "防护", bundle: .module)
        case .alerts:     return String(localized: "告警", bundle: .module)
        case .recording:  return String(localized: "录像", bundle: .module)
        case .notch:      return "NotchDrop"
        }
    }
}

/// 横向 Tab 条：HStack of SettingsTabChip。
struct SettingsTabBar: View {
    @Binding var selection: SettingsTab

    var body: some View {
        HStack(spacing: DesignMetrics.Spacing.s2) {
            ForEach(SettingsTab.allCases, id: \.self) { tab in
                SettingsTabChip(tab: tab, isSelected: selection == tab) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selection = tab
                    }
                }
            }
        }
    }
}

/// 单个 Tab chip。
struct SettingsTabChip: View {
    let tab: SettingsTab
    let isSelected: Bool
    let action: () -> Void

    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Text(tab.title)
                .font(.subheadline.weight(isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? AnyShapeStyle(.cicadaTextPrimary) : AnyShapeStyle(.cicadaTextTertiary))
                .padding(.horizontal, DesignMetrics.Spacing.s4)
                .padding(.vertical, DesignMetrics.Spacing.s2)
                .background(isSelected ? Color.cicadaBGElevated : (hover ? Color.cicadaBGElevated.opacity(0.5) : Color.cicadaBgSurface))
                .clipShape(RoundedRectangle(cornerRadius: DesignMetrics.Radius.md))
                .overlay(
                    RoundedRectangle(cornerRadius: DesignMetrics.Radius.md)
                        .stroke(isSelected ? AnyShapeStyle(.cicadaBorder) : AnyShapeStyle(.cicadaBorderSubtle),
                                lineWidth: 1)
                )
                .animation(.easeOut(duration: 0.1), value: hover)
        }
        .buttonStyle(SettingsTabChipButtonStyle())
        .onHover { hover = $0 }
        .accessibilityAddTraits(accessibilityTraits)
    }

    private var accessibilityTraits: AccessibilityTraits {
        var traits: AccessibilityTraits = []
        if isSelected { _ = traits.insert(.isSelected) }
        return traits
    }
}

/// Tab chip 按压反馈:isPressed 降不透明度(同 NotchSectionButtonStyle 模式)。
private struct SettingsTabChipButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

#Preview {
    SettingsPane()
        .environmentObject(AppModel())
        .environmentObject(ControlCenterRouter())
        .frame(width: 640, height: 600)
}
