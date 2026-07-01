import AppKit
import SwiftUI

struct SentinelMenuBarView: View {
    @ObservedObject private var controller = SentinelController.shared

    var body: some View {
        Button(String(localized: "Open Control Center")) {
            _ = SentryControlCenterRouter.shared.open(.overview)
        }

        Menu(String(localized: "Settings")) {
            Button(String(localized: "Relay")) {
                _ = SentryControlCenterRouter.shared.open(.relay)
            }
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

        Text(String(format: String(localized: "Status: %@"), controller.localizedStatusTitle))

        Button(String(localized: "Quit")) {
            NSApp.terminate(nil)
        }
    }
}
