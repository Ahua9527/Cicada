import SwiftUI

/// 菜单栏下拉内容:状态卡 + 4 个操作按钮 + Divider。
///
/// `public` 暴露:宿主 `App.swift` 的 `MenuBarExtra` content 直接引用。
/// 三个导航按钮走 `\.openControlCenter` 注入(宿主 → `ControlCenterRouter.shared.open`,
/// 单一 opener 链路,避免多 openWindow 来源造成重复窗口);注入为 nil 时回退为仅切
/// `router.selection`(库独立预览)。退出按钮调可注入 `onQuit` 闭包:
/// - CicadaUI 默认 `{ exit(0) }`(库独立预览/单测用,跳过 `applicationWillTerminate`)。
/// - 宿主注入 `{ NSApp.terminate(nil) }`,走正常终止链路(`stopPolling`/servers.stop/...)。
public struct MenuBarDropdown: View {
    @EnvironmentObject var appModel: AppModel
    @EnvironmentObject var router: ControlCenterRouter
    @Environment(\.openControlCenter) private var openControlCenter

    /// 退出闭包。默认 `exit(0)` 保持库独立；宿主注入 `NSApp.terminate(nil)`。
    public var onQuit: () -> Void

    public init(onQuit: @escaping () -> Void = { exit(0) }) {
        self.onQuit = onQuit
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: DesignMetrics.Spacing.s2) {
            MenuBarStatusCard(
                state: appModel.sentinels.state,
                detail: statusDetail
            )
            MenuBarButton(icon: "rectangle.split.2x1", title: String(localized: "打开控制中心", bundle: .module)) {
                if let openControlCenter {
                    openControlCenter(.overview)
                } else {
                    router.selection = .overview
                }
            }
            MenuBarButton(icon: "slider.horizontal.3", title: String(localized: "设置…", bundle: .module)) {
                if let openControlCenter {
                    openControlCenter(.settings)
                } else {
                    router.selection = .settings
                }
            }
            MenuBarButton(icon: "wrench.and.screwdriver", title: String(localized: "维护…", bundle: .module)) {
                if let openControlCenter {
                    openControlCenter(.maintenance)
                } else {
                    router.selection = .maintenance
                }
            }
            Divider()
            MenuBarButton(icon: "arrow.right.square", title: String(localized: "退出 Cicada", bundle: .module), tint: .cicadaDanger) {
                onQuit()
            }
        }
        .padding(DesignMetrics.Spacing.s2)
        .frame(width: 280)
        // 用 `.task(id:)` 让 SwiftUI 管理 task 生命周期：
        // onAppear 自动启动，onDisappear/disappear 自动取消，无需手动持有 Task。
        .task(id: "menubar-refresh") {
            await appModel.sentinels.refresh()
        }
    }

    /// 详情文案随 Sentinel 真实状态派生：空闲/告警时若仍显示「监控活跃」，
    /// 会让用户误以为 Mac 正在被守护。
    private var statusDetail: String {
        switch appModel.sentinels.state {
        case .running:
            return String(localized: "监控活跃", bundle: .module) + " · \(appModel.sentinels.activeTriggerCount) " + String(localized: "个触发器", bundle: .module)
        case .warning:
            return appModel.sentinels.diagnostic?.message ?? String(localized: "检测到异常活动", bundle: .module)
        case .idle:
            return String(localized: "未在监控", bundle: .module)
        }
    }
}

/// 菜单栏状态卡：左侧状态图标 + 右侧标题与详情。
struct MenuBarStatusCard: View {
    let state: SentinelState
    let detail: String

    var body: some View {
        HStack(spacing: DesignMetrics.Spacing.s3) {
            StatusIcon(state: state, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(state.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.cicadaTextPrimary)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.cicadaTextTertiary)
            }
            Spacer()
        }
        .padding(DesignMetrics.Spacing.s3)
        .background(Color.cicadaBgSurface2)
        .clipShape(RoundedRectangle(cornerRadius: DesignMetrics.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: DesignMetrics.Radius.md)
                .stroke(.cicadaBorderSubtle, lineWidth: 1)
        )
    }
}

/// 菜单栏操作按钮：自定义 ButtonStyle，isPressed 切 accent 背景。
struct MenuBarButton: View {
    let icon: String
    let title: String
    var tint: Color = .cicadaTextPrimary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: DesignMetrics.Spacing.s3) {
                Image(systemName: icon)
                    .font(.body)
                    .foregroundStyle(tint)
                    .frame(width: 20)
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.cicadaTextPrimary)
                Spacer()
            }
            .padding(.horizontal, DesignMetrics.Spacing.s3)
            .padding(.vertical, DesignMetrics.Spacing.s2)
            .contentShape(RoundedRectangle(cornerRadius: DesignMetrics.Radius.sm))
        }
        .buttonStyle(MenuBarButtonStyle(tint: tint))
    }
}

/// MenuBarButton 的 ButtonStyle：hover/pressed 时切 tint 软背景。
struct MenuBarButtonStyle: ButtonStyle {
    var tint: Color = .cicadaTextPrimary

    func makeBody(configuration: Configuration) -> some View {
        MenuBarButtonStyleBody(configuration: configuration, tint: tint)
    }
}

private struct MenuBarButtonStyleBody: View {
    let configuration: ButtonStyle.Configuration
    let tint: Color
    @State private var isHovered = false

    var body: some View {
        configuration.label
            .background(backgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: DesignMetrics.Radius.sm))
            .animation(.easeOut(duration: 0.1), value: isHovered)
            .onHover { isHovered = $0 }
    }

    private var backgroundColor: Color {
        if configuration.isPressed { return tint.opacity(0.12) }
        return isHovered ? tint.opacity(0.08) : .clear
    }
}

#Preview {
    MenuBarDropdown()
        .environmentObject(AppModel())
        .environmentObject(ControlCenterRouter())
        .padding()
        .background(.cicadaBgSurface)
}
