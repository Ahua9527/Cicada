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
            FolderAction(systemImage: "film", label: "打开录像文件夹", isDanger: false) {
                Task { @MainActor in
                    SentinelController.shared.openSavedClips()
                }
            },
            FolderAction(systemImage: "tray", label: "打开 NotchDrop 文件夹", isDanger: false) {
                Task { @MainActor in
                    SentinelController.shared.openNotchDropFolder()
                }
            },
            FolderAction(systemImage: "trash", label: "清空 NotchDrop 托盘", isDanger: true) {
                Task { @MainActor in
                    SentinelController.shared.clearNotchDropTray()
                }
            },
            FolderAction(systemImage: "folder", label: "打开 ~/.cicada", isDanger: false) {
                openDirectory(cicadaHomeURL())
            },
            FolderAction(systemImage: "gearshape", label: "打开配置", isDanger: false) {
                revealInFinder(URL(fileURLWithPath: CicadaSentinelPaths.configPath()))
            },
            FolderAction(systemImage: "externaldrive", label: "打开数据目录", isDanger: false) {
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