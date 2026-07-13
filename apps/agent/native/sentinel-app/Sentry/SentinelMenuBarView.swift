import AppKit
import SwiftUI

struct SentinelMenuBarView: View {
    @ObservedObject private var controller = SentinelController.shared

    var body: some View {
        Button(String(localized: "Open Control Center")) {
            _ = SentryControlCenterRouter.shared.open(.overview)
        }

        Menu(String(localized: "Settings")) {
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

        Divider()

        Text(String(format: String(localized: "Status: %@"), controller.localizedStatusTitle))

        Button(String(localized: "Quit")) {
            NSApp.terminate(nil)
        }
    }
}
