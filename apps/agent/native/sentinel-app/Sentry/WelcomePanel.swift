//
//  WelcomePanel.swift
//  Sentry
//
//  Created by 秋星桥 on 5/24/25.
//

import ColorfulX
import SwiftUI

struct WelcomePanel: View {
    @State private var openHint: Bool = false
    @AppStorage("isFirstVisit") var isFirstVisit: Bool = true
    @StateObject private var vm = SentryConfigurationManager.shared
    @EnvironmentObject var appDelegate: AppDelegate

    enum TitleType {
        case welcome
        case setupNow
        case lockToContinue
    }

    @State private var titleType: TitleType = .welcome

    private var title: String {
        switch titleType {
        case .welcome:
            String(localized: "Welcome to Sentry")
        case .setupNow:
            String(localized: "Setup with Options Below")
        case .lockToContinue:
            String(localized: "Lock Your Mac to Activate Sentry")
        }
    }

    private var versionText: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
        return String(localized: "Version \(version) (\(build))")
    }

    private let timer = Timer
        .publish(every: 1, on: .main, in: .common)
        .autoconnect()
        .dropFirst()

    var body: some View {
        VStack(spacing: 32) {
            Divider().hidden()
            Image(.icon512)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 64, height: 64)
                .padding(-8)
            Text(title)
                .font(.title)
                .bold()
                .contentTransition(.numericText())
                .animation(.interactiveSpring, value: title)
                .onReceive(timer) { _ in
                    updateTitleType()
                }
            startupDiagnosticsSection
            HStack(spacing: 16) {
                options
            }
            .padding(.horizontal, 16)
            Text(versionText)
                .font(.footnote)
                .opacity(0.5)
            Divider().hidden()
        }
        .frame(width: 600)
        .overlay {
            Image(systemName: "questionmark.circle")
                .font(.body)
                .opacity(0.5)
                .contentShape(Circle())
                .onTapGesture { openHint = true }
                .popover(isPresented: $openHint) { HelpPanelView() }
                .padding(8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        }
        .onAppear {
            presentHelpIfNeeded()
        }
    }

    @State private var openSetupAlarm: Bool = false
    @State private var openSetupNotifications: Bool = false
    @State private var openSetupRecordings: Bool = false

    @ViewBuilder
    private var startupDiagnosticsSection: some View {
        if !appDelegate.startupDiagnostics.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Label("Startup Diagnostics", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                ForEach(appDelegate.startupDiagnostics) { diagnostic in
                    Text(diagnostic.message)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color.orange.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 16)
        }
    }

    private func updateTitleType() {
        titleType = vm.canActivate ? .lockToContinue : .setupNow
    }

    private func presentHelpIfNeeded() {
        guard isFirstVisit else { return }
        openHint = true
        isFirstVisit = false
    }

    @ViewBuilder
    private var options: some View {
        SentryOption(
            icon: "light.beacon.max",
            text: "Setup Alarms",
            isActivated: vm.hasTriggerEnabled
        )
        .onTapGesture { openSetupAlarm = true }
        .sheet(isPresented: $openSetupAlarm) {
            SetupAlarmsView()
        }
        SentryOption(
            icon: "app.badge",
            text: "Setup Notifications",
            isActivated: vm.hasNotificationEnabled
        )
        .onTapGesture { openSetupNotifications = true }
        .sheet(isPresented: $openSetupNotifications) {
            SetupNotificationsView()
        }
        SentryOption(
            icon: "camera",
            text: "Setup Recordings",
            isActivated: vm.hasRecordingEnabled
        )
        .onTapGesture { openSetupRecordings = true }
        .sheet(isPresented: $openSetupRecordings) {
            SetupRecordingsView()
        }
    }
}

struct SentryOption: View {
    let icon: String
    let text: LocalizedStringKey
    let isActivated: Bool

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .bold()
            Text(text)
        }
        .frame(maxWidth: .infinity)
        .padding(12)
        .padding(.horizontal, 8)
        .background(Color.gray.opacity(0.1))
        .contentShape(Rectangle())
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .opacity(isActivated ? 1 : 0)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .offset(x: 4, y: -4)
        }
    }
}

private struct WelcomePanelPreviewContainer: View {
    @StateObject private var appDelegate = AppDelegate()

    var body: some View {
        WelcomePanel()
            .environmentObject(appDelegate)
    }
}

#Preview {
    WelcomePanelPreviewContainer()
}
