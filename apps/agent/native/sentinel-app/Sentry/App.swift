//
//  App.swift
//  Sentry
//
//  Created by 秋星桥 on 5/24/25.
//

import SwiftUI

struct App: SwiftUI.App {
    @NSApplicationDelegateAdaptor var appDelegate: AppDelegate

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .environmentObject(appDelegate)
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .appSettings) {
                Button(String(localized: "Control Center...")) {
                    _ = SentryControlCenterRouter.shared.open(.overview)
                }
                .keyboardShortcut(",", modifiers: [.command])
            }
            CommandMenu(String(localized: "Cicada")) {
                Button(String(localized: "Open Control Center")) {
                    _ = SentryControlCenterRouter.shared.open(.overview)
                }

                Divider()

                Button(String(localized: "Overview")) {
                    _ = SentryControlCenterRouter.shared.open(.overview)
                }

                Button(String(localized: "Settings")) {
                    _ = SentryControlCenterRouter.shared.open(.settings)
                }

                Button(String(localized: "Maintenance")) {
                    _ = SentryControlCenterRouter.shared.open(.maintenance)
                }
            }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)

        MenuBarExtra {
            SentinelMenuBarView()
                .environmentObject(appDelegate)
        } label: {
            ZStack {
                Image(systemName: "eye")
                MainWindowOpenBridge()
                    .frame(width: 0, height: 0)
            }
        }
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
