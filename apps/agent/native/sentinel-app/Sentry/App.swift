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
                Button("Control Center...") {
                    _ = SentryControlCenterRouter.shared.open(.overview)
                }
                .keyboardShortcut(",", modifiers: [.command])
            }
            CommandMenu("Sentry") {
                Button("Open Control Center") {
                    _ = SentryControlCenterRouter.shared.open(.overview)
                }

                Divider()

                Button("Alarm Settings") {
                    _ = SentryControlCenterRouter.shared.open(.alarms)
                }

                Button("Notification Settings") {
                    _ = SentryControlCenterRouter.shared.open(.notifications)
                }

                Button("Recording Settings") {
                    _ = SentryControlCenterRouter.shared.open(.recordings)
                }

                Button("NotchDrop Settings") {
                    _ = SentryControlCenterRouter.shared.open(.notchDrop)
                }

                Button("Maintenance") {
                    _ = SentryControlCenterRouter.shared.open(.maintenance)
                }

                Divider()

                Button(ViewModel.shared.status == .running || ViewModel.shared.status == .activityDetected ? "Stop Sentry" : "Start Sentry") {
                    if ViewModel.shared.status == .running || ViewModel.shared.status == .activityDetected {
                        _ = SentinelController.shared.stop()
                    } else {
                        _ = SentinelController.shared.start()
                    }
                }

                Button("Unlock Alarm") {
                    _ = SentinelController.shared.unlockAlarm()
                }
                .disabled(ViewModel.shared.status != .activityDetected)
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
