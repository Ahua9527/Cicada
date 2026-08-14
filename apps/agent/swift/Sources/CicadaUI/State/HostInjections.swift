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
        FolderAction(systemImage: "folder", label: String(localized: "打开 ~/.cicada", bundle: .module), isDanger: false, action: {}),
        FolderAction(systemImage: "doc.text", label: String(localized: "打开日志", bundle: .module), isDanger: false, action: {}),
        FolderAction(systemImage: "gearshape", label: String(localized: "打开配置", bundle: .module), isDanger: false, action: {}),
        FolderAction(systemImage: "arrow.triangle.2.circlepath", label: String(localized: "重启服务", bundle: .module), isDanger: false, action: {}),
        FolderAction(systemImage: "trash", label: String(localized: "清空缓存", bundle: .module), isDanger: false, action: {}),
        FolderAction(systemImage: "exclamationmark.triangle", label: String(localized: "重置配置", bundle: .module), isDanger: true, action: {}),
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
public enum CameraAuthorizationStatus: Equatable {
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
    static let defaultValue: (() async -> CameraAuthorizationStatus)? = nil
}

extension EnvironmentValues {
    /// 查询当前相机授权状态。宿主注入 `AVCaptureDevice.authorizationStatus(for: .video)` 映射。
    public var cameraAuthorizationStatus: () -> CameraAuthorizationStatus {
        get { self[CameraAuthorizationStatusKey.self] }
        set { self[CameraAuthorizationStatusKey.self] = newValue }
    }

    /// 请求相机授权并返回系统最终状态。`nil` 时 RecordingCard 不显示请求按钮；
    /// 宿主注入 `AVCaptureDevice.requestAccess(for: .video)` 的异步结果。
    public var requestCameraPermission: (() async -> CameraAuthorizationStatus)? {
        get { self[RequestCameraPermissionKey.self] }
        set { self[RequestCameraPermissionKey.self] = newValue }
    }
}

// MARK: - Camera Options

/// 可选相机设备（包内值类型，避免 CicadaUI 依赖 AVFoundation）。
public struct CameraOption: Identifiable, Hashable {
    public let id: String
    public let name: String
    public init(id: String, name: String) { self.id = id; self.name = name }
}

private struct CameraOptionsKey: EnvironmentKey {
    /// 默认空列表：库独立预览/单测时不显示设备选择器。
    static let defaultValue: () -> [CameraOption] = { [] }
}

extension EnvironmentValues {
    /// 可用相机列表。宿主注入 `AVCaptureDevice.DiscoverySession` 映射；
    /// 多摄像头 Mac 在授权态下用此列表渲染设备选择器（绑定 `sentryRecordingDevice`）。
    public var cameraOptions: () -> [CameraOption] {
        get { self[CameraOptionsKey.self] }
        set { self[CameraOptionsKey.self] = newValue }
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

// MARK: - Open Control Center

private struct OpenControlCenterKey: EnvironmentKey {
    /// 默认 `nil`:MenuBarDropdown 回退为仅切 `router.selection`(库独立可预览)。
    /// 宿主注入 `ControlCenterRouter.shared.open(_:)` 走完整开窗口链路
    /// (activate + 置前 + 去重)。
    static let defaultValue: ((NavSection) -> Void)? = nil
}

extension EnvironmentValues {
    /// 菜单栏「打开控制中心/设置…/维护…」按钮的宿主注入。
    /// 统一走 `SentinelController.openMainWindow()` 单一 opener——openWindow(id:)
    /// 若存在多个环境来源(label bridge / MenuBarExtra content),各自首调会各建一窗,
    /// 用户看到两个控制中心重叠。
    public var openControlCenter: ((NavSection) -> Void)? {
        get { self[OpenControlCenterKey.self] }
        set { self[OpenControlCenterKey.self] = newValue }
    }
}

// MARK: - NotchDrop Tray Content

private struct TrayContentKey: EnvironmentKey {
    /// 默认 `nil`：NotchPanel 显示库内空态拖放区（NotchSection .tray），库独立可预览。
    static let defaultValue: (() -> AnyView)? = nil
}

extension EnvironmentValues {
    /// 刘海暂存区内容注入。宿主注入观察 `TrayDrop.shared` 的视图（既有 `TrayView`），
    /// 覆盖空态与已暂存文件列表（打开/拖拽/删除）；`nil` 时 NotchPanel 用库内空态拖放区。
    public var trayContent: (() -> AnyView)? {
        get { self[TrayContentKey.self] }
        set { self[TrayContentKey.self] = newValue }
    }
}
