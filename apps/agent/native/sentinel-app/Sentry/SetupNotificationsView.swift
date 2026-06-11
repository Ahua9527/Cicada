//
//  SetupNotificationsView.swift
//  Sentry
//
//  Created by 秋星桥 on 5/24/25.
//

import SwiftUI

struct SetupNotificationsView: View {
    @StateObject var vm = SentryConfigurationManager.shared

    var body: some View {
        FormView(title: "Setup Notifications") {
            VStack(alignment: .leading, spacing: 8) {
                Text("The easiest way to warn the troublemaker is to play sound. It is recommended to enable.")
                    .fixedSize(horizontal: false, vertical: true)
                Divider()
                Toggle(isOn: $vm.cfg.sentryAlarmsSoundsEnabled) {
                    Text("Play Sound")
                }
                Divider()
                Text("If you have Bark installed on your phone, connect to Bark here. For more information, please visit [https://bark.day.app/](https://bark.day.app/).")
                    .fixedSize(horizontal: false, vertical: true)
                Divider()
                Toggle(isOn: .init(get: {
                    vm.cfg.sentryAlarmsNotificationType == .bark
                }, set: { newValue in
                    if newValue {
                        vm.cfg.sentryAlarmsNotificationType = .bark
                    } else {
                        vm.cfg.sentryAlarmsNotificationType = .none
                    }
                })) {
                    Text("Use Bark")
                }
                Divider()
                Grid(
                    alignment: .trailing,
                    horizontalSpacing: 8,
                    verticalSpacing: 4
                ) {
                    GridRow {
                        Text("Endpoint")
                        TextField("Server Endpoint", text: $vm.cfg.sentryNotificationConfigBark.endpoint)
                            .autocorrectionDisabled()
                            .onChange(of: vm.cfg.sentryNotificationConfigBark.endpoint) { newValue in
                                guard var url = URL(string: newValue) else { return }
                                while url.pathComponents.count > 2 {
                                    url = url.deletingLastPathComponent()
                                }
                                var text = url.absoluteString
                                if text.hasSuffix("/") { text.removeLast() }
                                guard text != newValue else { return }
                                vm.cfg.sentryNotificationConfigBark.endpoint = text
                            }
                    }
                }
                .disabled(vm.cfg.sentryAlarmsNotificationType != .bark)
            }
        }
    }
}

#Preview {
    SetupNotificationsView()
}
