//
//  App.swift
//  Sentry
//
//  Created by 秋星桥 on 5/24/25.
//

import CicadaUI
import SwiftUI

struct CicadaApp: SwiftUI.App {
    @NSApplicationDelegateAdaptor var appDelegate: AppDelegate

    var body: some Scene {
        WindowGroup(id: "main") {
            ControlCenterRoot()
                .environmentObject(appDelegate)
                .environmentObject(AppModel.shared)
                .environmentObject(ControlCenterRouter.shared)
                .hostMaintenanceInjections(appDelegate: appDelegate)
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .appSettings) {
                Button(String(localized: "Control Center...")) {
                    _ = ControlCenterRouter.shared.open(.overview)
                }
                .keyboardShortcut(",", modifiers: [.command])
            }
            CommandMenu(String(localized: "Cicada")) {
                Button(String(localized: "Open Control Center")) {
                    _ = ControlCenterRouter.shared.open(.overview)
                }

                Divider()

                Button(String(localized: "Overview")) {
                    _ = ControlCenterRouter.shared.open(.overview)
                }

                Button(String(localized: "Settings")) {
                    _ = ControlCenterRouter.shared.open(.settings)
                }

                Button(String(localized: "Maintenance")) {
                    _ = ControlCenterRouter.shared.open(.maintenance)
                }
            }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)

        MenuBarExtra {
            MenuBarDropdown(onQuit: { NSApp.terminate(nil) })
                .environmentObject(AppModel.shared)
                .environmentObject(ControlCenterRouter.shared)
                .environment(\.openControlCenter) { section in
                    // ControlCenterRouter 共享单例是 @MainActor;nonisolated 闭包同步调
                    // @MainActor 方法会触发并发硬错误,Task 派发(同 showSettings 模式)。
                    Task { @MainActor in
                        _ = ControlCenterRouter.shared.open(section)
                    }
                }
        } label: {
            ZStack {
                Image(systemName: "eye")
                MainWindowOpenBridge()
                    .frame(width: 0, height: 0)
            }
        }
        .menuBarExtraStyle(.window)
    }
}

private struct MainWindowOpenBridge: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear {
                let openWindow = openWindow
                SentinelController.shared.registerMainWindowOpener {
                    openWindow(id: "main")
                }
            }
    }
}