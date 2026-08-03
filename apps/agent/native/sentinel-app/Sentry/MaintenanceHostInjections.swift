//
//  MaintenanceHostInjections.swift
//  Sentry
//
//  P4.2 宿主接入：为 CicadaUI 维护页注入真实宿主行为。
//
//  - `folderActions`：FolderGrid 6 个按钮的真实 NSWorkspace / NotchDropCoordinator 行为。
//  - `launchAtLoginToggle`：真实 `LaunchAtLogin.Toggle`（写 SMLoginItemSetEnabled）。
//  - `runStartupChecks`：`AppDelegate.runStartupChecks()` 走启动诊断链路。
//
//  通过 ViewModifier `hostMaintenanceInjections(appDelegate:)` 一次性注入，
//  在 App.swift 的 WindowGroup 上应用。CicadaUI 库默认占位保持库独立可预览/单测。
//

import AppKit
import AVFoundation
import CicadaUI
import LaunchAtLogin
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
            FolderAction(systemImage: "trash", label: String(localized: "Clear NotchDrop Tray"), isDanger: true) {
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

    /// 触发系统相机授权弹窗（`.notDetermined` 时才真正弹窗）。
    static func requestCameraPermission() {
        AVCaptureDevice.requestAccess(for: .video) { _ in }
    }

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
                MaintenanceHostInjections.requestCameraPermission()
            }
            .environment(\.runStartupChecks) {
                // `AppDelegate` 是 `@MainActor` 类，`runStartupChecks()` main-actor 隔离。
                // `runStartupChecks` 环境值类型是 `(() -> Void)?` nonisolated 闭包，
                // 用 `Task { @MainActor in ... }` 异步派发到主线程执行（fire-and-forget）。
                Task { @MainActor in
                    appDelegate.runStartupChecks()
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