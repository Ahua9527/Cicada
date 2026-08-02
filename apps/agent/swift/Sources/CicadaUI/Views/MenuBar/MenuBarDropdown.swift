import SwiftUI

/// 菜单栏下拉内容：状态卡 + 4 个操作按钮 + Divider。
///
/// `public` 暴露：宿主 `App.swift` 的 `MenuBarExtra` content 直接引用。
/// 三个导航按钮先设 `router.selection` 再 `openWindow(id:"main")`（宿主窗口 id），
/// 确保主窗口置顶时显示对应分区。退出按钮调可注入 `onQuit` 闭包：
/// - CicadaUI 默认 `{ exit(0) }`（库独立预览/单测用，跳过 `applicationWillTerminate`）。
/// - 宿主注入 `{ NSApp.terminate(nil) }`，走正常终止链路（`stopPolling`/servers.stop/...）。
public struct MenuBarDropdown: View {
    @EnvironmentObject var appModel: AppModel
    @EnvironmentObject var router: ControlCenterRouter
    @Environment(\.openWindow) private var openWindow

    /// 退出闭包。默认 `exit(0)` 保持库独立；宿主注入 `NSApp.terminate(nil)`。
    public var onQuit: () -> Void

    public init(onQuit: @escaping () -> Void = { exit(0) }) {
        self.onQuit = onQuit
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: DesignMetrics.Spacing.s2) {
            MenuBarStatusCard(
                state: appModel.sentinels.state,
                detail: "监控活跃 · \(appModel.sentinels.activeTriggerCount) 个触发器"
            )
            MenuBarButton(icon: "rectangle.split.2x1", title: "打开控制中心") {
                router.selection = .overview
                openWindow(id: "main")
            }
            MenuBarButton(icon: "slider.horizontal.3", title: "设置…") {
                router.selection = .settings
                openWindow(id: "main")
            }
            MenuBarButton(icon: "wrench.and.screwdriver", title: "维护…") {
                router.selection = .maintenance
                openWindow(id: "main")
            }
            Divider()
            MenuBarButton(icon: "arrow.right.square", title: "退出 Cicada", tint: .cicadaDanger) {
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
        configuration.label
            .background(configuration.isPressed ? tint.opacity(0.12) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: DesignMetrics.Radius.sm))
    }
}

#Preview {
    MenuBarDropdown()
        .environmentObject(AppModel())
        .environmentObject(ControlCenterRouter())
        .padding()
        .background(.cicadaBgSurface)
}