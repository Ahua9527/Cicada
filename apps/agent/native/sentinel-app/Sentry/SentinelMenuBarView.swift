import AppKit
import SwiftUI

struct SentinelMenuBarView: View {
    @ObservedObject private var controller = SentinelController.shared
    @ObservedObject private var vm = ViewModel.shared

    var body: some View {
        Button("Open Window") {
            _ = controller.openMainWindow()
        }

        Divider()

        Button(isActive ? "Stop Sentry" : "Start Sentry") {
            if vm.status == .running || vm.status == .activityDetected {
                _ = controller.stop()
            } else {
                _ = controller.start()
            }
        }

        Button("Unlock Alarm") {
            _ = controller.unlockAlarm()
        }
        .disabled(vm.status != .activityDetected)

        Button("Open Recording Folder") {
            controller.openSavedClips()
        }

        Button("Open NotchDrop Folder") {
            controller.openNotchDropFolder()
        }

        Button("Clear NotchDrop Tray") {
            controller.clearNotchDropTray()
        }

        Button("Show Auto Sleep Status") {
            controller.showSleepHoldStatus()
        }

        Divider()

        Text("Status: \(controller.statusTitle)")

        Button("Quit") {
            NSApp.terminate(nil)
        }
    }

    private var isActive: Bool {
        vm.status == .running || vm.status == .activityDetected
    }
}
