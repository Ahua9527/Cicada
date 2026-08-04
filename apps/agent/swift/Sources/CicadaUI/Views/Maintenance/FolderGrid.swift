import SwiftUI

/// 维护页文件夹操作 3 列网格。
///
/// 按钮行为通过 `@Environment(\.folderActions)` 注入：
/// - CicadaUI 默认 6 个占位按钮（闭包全空，保持库不 import AppKit，预览可用）。
/// - Xcode 宿主在 `App.swift` 注入真实 `NSWorkspace` / `NotchDropCoordinator` /
///   `StartupDiagnostics` 行为（见宿主 `ControlCenterRouter+Host` 或 App.swift）。
struct FolderGrid: View {
    @Environment(\.folderActions) private var folderActions

    var body: some View {
        FolderGridButton(actions: folderActions)
    }
}

#Preview {
    FolderGrid()
        .padding()
        .background(.cicadaBgSurface)
        .frame(width: 500)
}