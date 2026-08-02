import SwiftUI

/// 宿主可注入能力：保持 CicadaUI 不 import AppKit 系宿主依赖（NSWorkspace /
/// LaunchAtLogin），由宿主在 Scene 渲染处通过 `.environment(...)` 注入真实行为。
///
/// 三类注入：
/// 1. `folderActions`：维护页 `FolderGrid` 的 6 个按钮行为（默认空闭包，库独立可预览）。
/// 2. `launchAtLoginToggle`：维护页开机自启项（默认一个绑定 `@AppStorage` 的占位 Toggle，
///    库独立可预览；宿主注入真实 `LaunchAtLogin.Toggle` 才会注册开机自启）。
/// 3. `runStartupChecks`：维护页「运行启动检查」按钮行为（默认调 `appModel.refreshAll()`，
///    宿主可注入 `AppDelegate.runStartupChecks()` 走启动诊断链路）。

// MARK: - FolderActions

private struct FolderActionsKey: EnvironmentKey {
    /// 默认 6 个占位按钮，闭包全空，保持 CicadaUI 不依赖 AppKit。
    /// 标签与图标与设计稿一致；宿主注入时替换为真实 `NSWorkspace` 行为。
    static let defaultValue: [FolderAction] = [
        FolderAction(systemImage: "folder", label: "打开 ~/.cicada", isDanger: false, action: {}),
        FolderAction(systemImage: "doc.text", label: "打开日志", isDanger: false, action: {}),
        FolderAction(systemImage: "gearshape", label: "打开配置", isDanger: false, action: {}),
        FolderAction(systemImage: "arrow.triangle.2.circlepath", label: "重启服务", isDanger: false, action: {}),
        FolderAction(systemImage: "trash", label: "清空缓存", isDanger: false, action: {}),
        FolderAction(systemImage: "exclamationmark.triangle", label: "重置配置", isDanger: true, action: {}),
    ]
}

extension EnvironmentValues {
    /// 维护页 `FolderGrid` 的按钮行为列表。宿主注入真实 NSWorkspace/NotchDrop 行为。
    public var folderActions: [FolderAction] {
        get { self[FolderActionsKey.self] }
        set { self[FolderActionsKey.self] = newValue }
    }
}

// MARK: - LaunchAtLogin Toggle

/// 开机自启项的注入接口：返回一个 Toggle 视图。
/// 宿主注入真实 `LaunchAtLogin.Toggle`（写 SMLoginItemSetEnabled）；
/// 库默认返回绑定 `@AppStorage("launchAtLogin")` 的占位 Toggle（仅预览用，不真正注册自启）。
public struct LaunchAtLoginToggleProvider: Sendable {
    public let makeView: @MainActor @Sendable () -> AnyView

    public init(makeView: @MainActor @escaping @Sendable () -> AnyView) {
        self.makeView = makeView
    }

    /// 库默认占位：仅写入 `@AppStorage("launchAtLogin")` 的普通 Toggle。
    /// 不依赖 LaunchAtLogin 第三方库，供 CicadaUI 独立预览/单测用。
    public static let `default` = LaunchAtLoginToggleProvider {
        AnyView(PlaceholderLaunchAtLoginToggle())
    }
}

/// 库默认占位 Toggle：写 `@AppStorage("launchAtLogin")`，不注册真正自启。
private struct PlaceholderLaunchAtLoginToggle: View {
    @AppStorage("launchAtLogin") private var launchAtLogin: Bool = false

    var body: some View {
        Toggle("", isOn: $launchAtLogin)
            .labelsHidden()
            .tint(.cicadaAccent)
    }
}

private struct LaunchAtLoginToggleKey: EnvironmentKey {
    static let defaultValue: LaunchAtLoginToggleProvider = .default
}

extension EnvironmentValues {
    /// 维护页开机自启 Toggle 注入点。宿主注入真实 LaunchAtLogin.Toggle。
    public var launchAtLoginToggle: LaunchAtLoginToggleProvider {
        get { self[LaunchAtLoginToggleKey.self] }
        set { self[LaunchAtLoginToggleKey.self] = newValue }
    }
}

// MARK: - Run Startup Checks

private struct RunStartupChecksKey: EnvironmentKey {
    /// 默认 `nil`：MaintenancePane 回退到 `appModel.refreshAll()` 刷新 IPC 快照
    /// （库独立可用，无宿主 AppDelegate 依赖）。
    /// 宿主注入非空闭包时走 `AppDelegate.runStartupChecks()` 启动诊断链路。
    static let defaultValue: (() -> Void)? = nil
}

extension EnvironmentValues {
    /// 维护页「运行启动检查」按钮行为。`nil` 时回退到 `appModel.refreshAll()`；
    /// 宿主注入非空闭包（如 `AppDelegate.runStartupChecks()`）走启动诊断链路。
    public var runStartupChecks: (() -> Void)? {
        get { self[RunStartupChecksKey.self] }
        set { self[RunStartupChecksKey.self] = newValue }
    }
}