import AppKit
import SwiftUI

struct SentinelMenuBarView: View {
    @ObservedObject private var controller = SentinelController.shared
    @ObservedObject private var vm = ViewModel.shared

    var body: some View {
        Button("Open Control Center") {
            _ = SentryControlCenterRouter.shared.open(.overview)
        }

        Menu("Settings") {
            Button("Alarms") {
                _ = SentryControlCenterRouter.shared.open(.alarms)
            }
            Button("Notifications") {
                _ = SentryControlCenterRouter.shared.open(.notifications)
            }
            Button("Recordings") {
                _ = SentryControlCenterRouter.shared.open(.recordings)
            }
            Button("NotchDrop") {
                _ = SentryControlCenterRouter.shared.open(.notchDrop)
            }
            Button("Maintenance") {
                _ = SentryControlCenterRouter.shared.open(.maintenance)
            }
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
