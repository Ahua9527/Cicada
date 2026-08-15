//
//  MaintenanceHostInjections.swift
//  Sentry
//
//  P4.2 宿主接入：为 CicadaUI 维护页注入真实宿主行为。
//
//  - `folderActions`：FolderGrid 6 个按钮的真实 NSWorkspace / NotchDropCoordinator 行为。
//  - `launchAtLoginToggle`：真实 `LaunchAtLogin.Toggle`（写 SMLoginItemSetEnabled）。
//  - `runStartupChecks`：`AppDelegate.runStartupChecks()` 走启动诊断链路。
//  - `installSleepHoldService`：SleepHold 后台服务的 SMAppService 注册链路。
//
//  通过 ViewModifier `hostMaintenanceInjections(appDelegate:)` 一次性注入，
//  在 App.swift 的 WindowGroup 上应用。CicadaUI 库默认占位保持库独立可预览/单测。
//

import AppKit
import AVFoundation
import CicadaSystem
import CicadaUI
import LaunchAtLogin
import ServiceManagement
import SwiftUI

enum MaintenanceHostInjections {
    /// 构建维护页 FolderGrid 的 6 个按钮行为。
    ///
    /// 逐一覆盖旧 `SentryMaintenancePane` 的文件夹功能：
    /// - 打开录像文件夹 → `SentinelController.shared.openSavedClips()`（旧「Open Recording Folder」）
    /// - 打开 NotchDrop 文件夹 → `SentinelController.shared.openNotchDropFolder()`（旧「Open NotchDrop Folder」）
    /// - 清空 NotchDrop 托盘 → `SentinelController.shared.clearNotchDropTray()`（旧「Clear NotchDrop Tray」）
    /// - 打开 ~/.cicada → NSWorkspace 打开 cicada 主目录
    /// - 打开配置 → NSWorkspace 在 Finder 中显示 config.json
    /// - 打开数据目录 → NSWorkspace 打开应用数据目录
    ///
    /// 「运行启动检查」不在 FolderGrid，在诊断 Card（见 `runStartupChecks` 注入）。
    ///
    /// 注：`SentinelController` 是 `@MainActor` 类，其 `openSavedClips/openNotchDropFolder/
    /// clearNotchDropTray` 均 main-actor 隔离。`FolderAction.action: () -> Void` 闭包是
    /// nonisolated，从 nonisolated 闭包同步调 @MainActor 方法会触发 Swift 并发硬错误。
    /// 故这 3 个闭包用 `Task { @MainActor in ... }` 异步派发到主线程执行（fire-and-forget）。
    /// 另 3 个直接调 `NSWorkspace`（非 @MainActor 隔离）的闭包无需此处理。
    static func makeFolderActions() -> [FolderAction] {
        [
            FolderAction(systemImage: "film", label: String(localized: "Open Recording Folder"), isDanger: false) {
                Task { @MainActor in
                    SentinelController.shared.openSavedClips()
                }
            },
            FolderAction(systemImage: "tray", label: String(localized: "Open NotchDrop Folder"), isDanger: false) {
                Task { @MainActor in
                    SentinelController.shared.openNotchDropFolder()
                }
            },
            FolderAction(
                systemImage: "trash",
                label: String(localized: "Clear NotchDrop Tray"),
                isDanger: true,
                requiresHoldConfirmation: true
            ) {
                Task { @MainActor in
                    SentinelController.shared.clearNotchDropTray()
                }
            },
            FolderAction(systemImage: "folder", label: String(localized: "Open ~/.cicada"), isDanger: false) {
                openDirectory(cicadaHomeURL())
            },
            FolderAction(systemImage: "gearshape", label: String(localized: "Open Config"), isDanger: false) {
                revealInFinder(URL(fileURLWithPath: CicadaSentinelPaths.configPath()))
            },
            FolderAction(systemImage: "externaldrive", label: String(localized: "Open Data Directory"), isDanger: false) {
                openDirectory(appDataDirectoryURL())
            },
        ]
    }

    /// 真实 LaunchAtLogin.Toggle，写 SMLoginItemSetEnabled。
    static func makeLaunchAtLoginToggle() -> LaunchAtLoginToggleProvider {
        LaunchAtLoginToggleProvider {
            AnyView(
                LaunchAtLogin.Toggle {
                    Text(String(localized: "Start Cicada at Login"))
                }
                .labelsHidden()
            )
        }
    }

    /// 当前相机授权状态（AVFoundation → CicadaUI 包内镜像枚举）。
    static func cameraAuthorizationStatus() -> CameraAuthorizationStatus {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .notDetermined: return .notDetermined
        case .restricted: return .restricted
        case .denied: return .denied
        case .authorized: return .authorized
        @unknown default: return .denied
        }
    }

    /// 等待系统相机授权弹窗结束并返回最终权限状态。
    static func requestCameraPermission() async -> CameraAuthorizationStatus {
        _ = await AVCaptureDevice.requestAccess(for: .video)
        return cameraAuthorizationStatus()
    }

    /// 可用相机列表（映射 AVCaptureDevice.DiscoverySession → 包内 CameraOption）。
    /// 与 `CameraManager.discoverCameras` 同源，供 RecordingCard 设备选择器。
    static func availableCameraOptions() -> [CameraOption] {
        let session = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .externalUnknown],
            mediaType: .video,
            position: .unspecified
        )
        return session.devices.map { CameraOption(id: $0.uniqueID, name: $0.localizedName) }
    }

    /// 安装/修复 SleepHold 后台服务：SMAppService 注册内嵌 daemon plist（macOS 13+）。
    ///
    /// 为什么不再用 osascript `with administrator privileges`：沙箱进程的提权调用被
    /// Authorization Services 拦截，必返回 -60005（管理员用户名或密码不正确），与密码
    /// 是否正确无关——沙箱签名构建下该链路永远失败（见 issue #9）。SMAppService 是
    /// 沙箱应用安装 launchd daemon 的受支持路径：注册内嵌在
    /// Contents/Library/LaunchDaemons 的静态 plist（BundleProgram 指向包内 helper），
    /// 用户经系统设置批准，无密码弹窗。
    ///
    /// 幂等/修复语义：探活已通过（含旧 CLI sudo 安装）→ 直接成功，不做多余注册；
    /// 已注册但无响应（部分安装/服务挂掉）→ unregister + register 强制重建；
    /// 未注册 → register。修复入口沿用 CicadaUI `recoveryAction`，不增加卸载或迁移流程。
    static func installSleepHoldService() async -> Result<Void, SleepHoldInstallError> {
        await Task.detached(priority: .userInitiated) { () -> Result<Void, SleepHoldInstallError> in
            let service = SMAppService.daemon(plistName: sleepHoldDaemonPlistName)
            let manager = SleepHoldServiceManager()

            // 服务已健康（含旧 CLI 安装）：幂等成功。
            if (try? manager.ping())?.ok == true {
                return .success(())
            }

            do {
                // 已注册但无响应：先注销再注册，强制 launchd 重建。
                if service.status == .enabled {
                    try service.unregister()
                }
                try service.register()
            } catch {
                return .failure(.registrationFailed(error.localizedDescription))
            }

            if let statusError = installError(for: service.status) {
                if case .requiresApproval = statusError {
                    // 待批准：顺手打开系统设置对应面板，减少用户找入口的成本。
                    Task { @MainActor in SMAppService.openSystemSettingsLoginItems() }
                }
                return .failure(statusError)
            }

            // 探活：launchd 拉起需要一点时间。
            for attempt in 0 ..< 5 {
                if attempt > 0 { Thread.sleep(forTimeInterval: 0.4) }
                if let response = try? manager.ping(), response.ok {
                    return .success(())
                }
            }
            return .failure(.serviceNotResponding)
        }.value
    }

    /// SMAppService 状态 → 安装错误分类（纯函数，供单测）。
    static func installError(for status: SMAppService.Status) -> SleepHoldInstallError? {
        switch status {
        case .enabled:
            return nil
        case .requiresApproval:
            return .requiresApproval
        case .notRegistered:
            return .registrationFailed("register() 后服务仍未注册")
        case .notFound:
            return .registrationFailed("应用包内缺少内嵌 daemon plist（Contents/Library/LaunchDaemons）")
        @unknown default:
            return .registrationFailed("未知注册状态: \(status.rawValue)")
        }
    }

    /// SMAppService 注册用的内嵌 daemon plist 文件名
    ///（来源：Resources/LaunchDaemons/，build.sh 嵌入 Contents/Library/LaunchDaemons/）。
    private static let sleepHoldDaemonPlistName = "com.cicada.sleephold.plist"

    // MARK: - Path Helpers

    /// ~/.cicada 主目录。由 `CicadaSentinelPaths.notchDropDirectory()` 的父目录推导
    /// （`cicadaHome` 本身是 private，notchDropDirectory = cicadaHome/notchdrop）。
    private static func cicadaHomeURL() -> URL {
        CicadaSentinelPaths.notchDropDirectory()
            .deletingLastPathComponent()
    }

    /// 应用数据目录（VideoClip 父目录，与 `openSavedClips` 同根）。
    /// `videoClipDir` 在 main.swift 定义为 `Documents/VideoClip`，
    /// 录像实际写入此目录，故「打开数据目录」打开其父目录（即 Documents）。
    private static func appDataDirectoryURL() -> URL {
        videoClipDir.deletingLastPathComponent()
    }

    /// 在 Finder 中打开目录（不存在则先创建）。
    private static func openDirectory(_ url: URL) {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        NSWorkspace.shared.open(url)
    }

    /// 在 Finder 中显示并选中文件。
    private static func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}

/// 一次性注入维护页三项宿主行为的 ViewModifier。
/// 在 App.swift 的 `WindowGroup(id:"main")` 上应用：
/// `.modifier(hostMaintenanceInjections(appDelegate: appDelegate))`。
struct HostMaintenanceInjectionsModifier: ViewModifier {
    @ObservedObject var appDelegate: AppDelegate

    func body(content: Content) -> some View {
        content
            .environment(\.folderActions, MaintenanceHostInjections.makeFolderActions())
            .environment(\.launchAtLoginToggle, MaintenanceHostInjections.makeLaunchAtLoginToggle())
            .environment(\.cameraAuthorizationStatus, MaintenanceHostInjections.cameraAuthorizationStatus)
            .environment(\.notchDropSettingsStore, .shared)
            .environment(\.requestCameraPermission) {
                await MaintenanceHostInjections.requestCameraPermission()
            }
            .environment(\.installSleepHoldService) {
                await MaintenanceHostInjections.installSleepHoldService()
            }
            .environment(\.cameraOptions) {
                MaintenanceHostInjections.availableCameraOptions()
            }
            .environment(\.runStartupChecks) {
                // `AppDelegate` 是 `@MainActor` 类，`runStartupChecks()` main-actor 隔离。
                // `runStartupChecks` 环境值类型是 `(() -> Void)?` nonisolated 闭包，
                // 用 `Task { @MainActor in ... }` 异步派发到主线程执行（fire-and-forget）。
                Task { @MainActor in
                    appDelegate.runStartupChecks()
                    // 把启动检查失败项映射为诊断写回 AppModel，供维护页诊断卡展示
                    // （否则失败项只留在 AppDelegate.startupDiagnostics，UI 无任何读取者）。
                    let messages = appDelegate.startupDiagnostics.map(\.message).joined(separator: "\n")
                    AppModel.shared.setStartupDiagnostic(message: messages.isEmpty ? nil : messages)
                }
            }
    }
}

/// 便捷构造器：`.hostMaintenanceInjections(appDelegate:)`。
extension View {
    func hostMaintenanceInjections(appDelegate: AppDelegate) -> some View {
        modifier(HostMaintenanceInjectionsModifier(appDelegate: appDelegate))
    }
}

// MARK: - NotchDropSettingsStore 宿主桥

/// 引擎持久层读取辅助：`@PublishedPersist` 以 JSON 编码写入 UserDefaults
/// （见 PublishedPersist.swift），此处按同 key 同编码读回初值。
private enum EnginePersistReader {
    static func read<Value: Decodable>(_ type: Value.Type, key: String) -> Value? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    static func write<Value: Encodable>(_ value: Value, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

/// FileStorageTime（含 custom 字段）→ 设置卡天数（1/7/30/0）。
/// 卡片选项是引擎枚举的子集：oneHour/twoDays/threeDays 无对应项，近似归到 1 天展示
/// （展示值不影响引擎，用户重选后才写回精确值）；custom 仅 30 天可逆映射。
private func retentionDaysFromEngine() -> Int {
    let tray = TrayDrop.shared
    switch tray.selectedFileStorageTime {
    case .oneHour, .oneDay, .twoDays, .threeDays:
        return 1
    case .oneWeek:
        return 7
    case .never:
        return 0
    case .custom:
        return (tray.customStorageTimeUnit == .days && tray.customStorageTime == 30) ? 30 : 7
    }
}

/// 卡片天数 → 引擎 FileStorageTime。30 天走 custom（枚举无 30 天档位）。
private func applyRetentionDays(_ days: Int) {
    let tray = TrayDrop.shared
    switch days {
    case 1:
        tray.selectedFileStorageTime = .oneDay
    case 7:
        tray.selectedFileStorageTime = .oneWeek
    case 30:
        tray.customStorageTime = 30
        tray.customStorageTimeUnit = .days
        tray.selectedFileStorageTime = .custom
    default: // 0 = 永不清理
        tray.selectedFileStorageTime = .never
    }
}

private func languageTagFromEngine() -> String {
    switch EnginePersistReader.read(Language.self, key: "selectedLanguage") ?? .system {
    case .system: return "auto"
    case .simplifiedChinese: return "zh-Hans"
    case .english: return "en"
    }
}

private func languageFromTag(_ tag: String) -> Language? {
    switch tag {
    case "auto": return .system
    case "zh-Hans": return .simplifiedChinese
    case "en": return .english
    default: return nil
    }
}

@MainActor
extension NotchDropSettingsStore {
    /// 宿主共享桥：初值读引擎持久层（UserDefaults，JSON 编码与 @PublishedPersist 一致），
    /// 用户编辑写回引擎真实模型。
    ///
    /// - haptic / language：优先写入活动 `NotchViewModel`（其 @PublishedPersist 自动持久化，
    ///   且 selectedLanguage 的 sink 会触发 Language.apply() 重启式切换）；无活动 vm 时
    ///   直写 UserDefaults 保底（language 同时直接调用 `apply()` 保持切换生效）。
    /// - retention：`TrayDrop.shared` 是真单例，直接写。
    static let shared = NotchDropSettingsStore(
        hapticFeedback: EnginePersistReader.read(Bool.self, key: "hapticFeedback") ?? true,
        fileRetentionDays: retentionDaysFromEngine(),
        interfaceLanguage: languageTagFromEngine()
    ) { change in
        Task { @MainActor in
            switch change {
            case .haptic(let value):
                EnginePersistReader.write(value, key: "hapticFeedback")
                NotchDropCoordinator.shared.activeViewModel?.hapticFeedback = value
            case .retention(let days):
                applyRetentionDays(days)
            case .language(let tag):
                guard let language = languageFromTag(tag) else { return }
                if let vm = NotchDropCoordinator.shared.activeViewModel {
                    vm.selectedLanguage = language // sink 自动 apply() + 重启提示
                } else {
                    EnginePersistReader.write(language, key: "selectedLanguage")
                    language.apply()
                }
            }
        }
    }
}
