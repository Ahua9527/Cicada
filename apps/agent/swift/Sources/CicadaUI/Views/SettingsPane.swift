import SwiftUI

/// 设置页：PaneHeader + SettingsTabBar + 5 个 Card（按 tab 切换）。
struct SettingsPane: View {
    @SceneStorage("settings.tab") private var tab: SettingsTab = .connection
    @EnvironmentObject var appModel: AppModel
    @EnvironmentObject var router: ControlCenterRouter
    @State private var showHelp = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignMetrics.Spacing.s5) {
                PaneHeader(
                    title: String(localized: "设置", bundle: .module),
                    subtitle: String(localized: "连接、防护、告警、录像与 NotchDrop", bundle: .module),
                    trailing: { HelpButton { showHelp = true } }
                )
                SettingsTabBar(selection: $tab)
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
            .padding(DesignMetrics.Spacing.s6)
        }
        .onAppear { consumePendingTab() }
        .onChange(of: router.pendingSettingsTab) { consumePendingTab() }
        .sheet(isPresented: $showHelp) { HelpSheet() }
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
                    withAnimation(.easeOut(duration: 0.15)) {
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

    var body: some View {
        Button(action: action) {
            Text(tab.title)
                .font(.subheadline.weight(isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? AnyShapeStyle(.cicadaTextPrimary) : AnyShapeStyle(.cicadaTextTertiary))
                .padding(.horizontal, DesignMetrics.Spacing.s4)
                .padding(.vertical, DesignMetrics.Spacing.s2)
                .background(isSelected ? Color.cicadaBGElevated : Color.cicadaBgSurface)
                .clipShape(RoundedRectangle(cornerRadius: DesignMetrics.Radius.md))
                .overlay(
                    RoundedRectangle(cornerRadius: DesignMetrics.Radius.md)
                        .stroke(isSelected ? AnyShapeStyle(.cicadaBorder) : AnyShapeStyle(.cicadaBorderSubtle),
                                lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    @Previewable @State var tab: SettingsTab = .connection
    return SettingsPane()
        .environmentObject(AppModel())
        .frame(width: 640, height: 600)
}