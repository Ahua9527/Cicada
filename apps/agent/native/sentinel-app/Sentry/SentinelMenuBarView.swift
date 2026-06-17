import AppKit
import SwiftUI

struct SentinelMenuBarView: View {
    @ObservedObject private var controller = SentinelController.shared
    @ObservedObject private var vm = ViewModel.shared

    var body: some View {
        Button(String(localized: "Open Control Center")) {
            _ = SentryControlCenterRouter.shared.open(.overview)
        }

        Menu(String(localized: "Settings")) {
            Button(String(localized: "Alarms")) {
                _ = SentryControlCenterRouter.shared.open(.alarms)
            }
            Button(String(localized: "Notifications")) {
                _ = SentryControlCenterRouter.shared.open(.notifications)
            }
            Button(String(localized: "Recordings")) {
                _ = SentryControlCenterRouter.shared.open(.recordings)
            }
            Button(String(localized: "NotchDrop")) {
                _ = SentryControlCenterRouter.shared.open(.notchDrop)
            }
            Button(String(localized: "Maintenance")) {
                _ = SentryControlCenterRouter.shared.open(.maintenance)
            }
        }

        Divider()

        Button(isActive ? String(localized: "Stop Cicada") : String(localized: "Start Cicada")) {
            if vm.status == .running || vm.status == .activityDetected {
                _ = controller.stop()
            } else {
                _ = controller.start()
            }
        }

        Button(String(localized: "Unlock Alarm")) {
            _ = controller.unlockAlarm()
        }
        .disabled(vm.status != .activityDetected)

        Divider()

        Text(String(format: String(localized: "Status: %@"), controller.localizedStatusTitle))

        Button(String(localized: "Quit")) {
            NSApp.terminate(nil)
        }
    }

    private var isActive: Bool {
        vm.status == .running || vm.status == .activityDetected
    }
}
