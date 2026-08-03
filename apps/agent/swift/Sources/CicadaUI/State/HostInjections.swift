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

// MARK: - Camera Permission

/// 相机授权状态的包内镜像（避免 CicadaUI 依赖 AVFoundation）。
public enum CameraAuthorizationStatus {
    case notDetermined
    case restricted
    case denied
    case authorized
}

private struct CameraAuthorizationStatusKey: EnvironmentKey {
    /// 默认 `.authorized`：库独立预览/单测时不显示权限引导。
    static let defaultValue: () -> CameraAuthorizationStatus = { .authorized }
}

private struct RequestCameraPermissionKey: EnvironmentKey {
    static let defaultValue: (() -> Void)? = nil
}

extension EnvironmentValues {
    /// 查询当前相机授权状态。宿主注入 `AVCaptureDevice.authorizationStatus(for: .video)` 映射。
    public var cameraAuthorizationStatus: () -> CameraAuthorizationStatus {
        get { self[CameraAuthorizationStatusKey.self] }
        set { self[CameraAuthorizationStatusKey.self] = newValue }
    }

    /// 请求相机授权。`nil` 时 RecordingCard 不显示请求按钮；宿主注入
    /// `AVCaptureDevice.requestAccess(for: .video)` 或 `CameraManager.requestPermission()`。
    public var requestCameraPermission: (() -> Void)? {
        get { self[RequestCameraPermissionKey.self] }
        set { self[RequestCameraPermissionKey.self] = newValue }
    }
}

// MARK: - NotchDrop Settings

/// NotchDrop 设置的宿主桥接模型：把引擎真实设置（NotchViewModel 的 hapticFeedback /
/// selectedLanguage、TrayDrop 的 selectedFileStorageTime）投影为可观察值。
///
/// 宿主创建共享实例：初值从持久层/引擎读取；用户编辑经 `didSet → onChange` 写回引擎。
/// 默认 `nil`：NotchDropCard 回退到本地 @AppStorage 占位（库独立可预览）。
@MainActor
public final class NotchDropSettingsStore: ObservableObject {
    @Published public var hapticFeedback: Bool {
        didSet { onChange(.haptic(hapticFeedback)) }
    }

    /// 保留天数：1 / 7 / 30 / 0（0 = 永不清理）。
    @Published public var fileRetentionDays: Int {
        didSet { onChange(.retention(fileRetentionDays)) }
    }

    /// 界面语言："auto" / "zh-Hans" / "en"。
    @Published public var interfaceLanguage: String {
        didSet { onChange(.language(interfaceLanguage)) }
    }

    public enum Change {
        case haptic(Bool)
        case retention(Int)
        case language(String)
    }

    private let onChange: (Change) -> Void

    public init(
        hapticFeedback: Bool,
        fileRetentionDays: Int,
        interfaceLanguage: String,
        onChange: @escaping (Change) -> Void
    ) {
        self.hapticFeedback = hapticFeedback
        self.fileRetentionDays = fileRetentionDays
        self.interfaceLanguage = interfaceLanguage
        self.onChange = onChange
    }
}

private struct NotchDropSettingsStoreKey: EnvironmentKey {
    static let defaultValue: NotchDropSettingsStore? = nil
}

extension EnvironmentValues {
    /// NotchDrop 设置桥。宿主注入 `NotchDropSettingsStore.shared`（见宿主 +Host 扩展）。
    public var notchDropSettingsStore: NotchDropSettingsStore? {
        get { self[NotchDropSettingsStoreKey.self] }
        set { self[NotchDropSettingsStoreKey.self] = newValue }
    }
}