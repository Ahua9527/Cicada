import AppKit
import AVFoundation
import LaunchAtLogin
import SwiftUI

enum SentryControlSection: String, CaseIterable, Identifiable, Hashable {
    case overview
    case alarms
    case notifications
    case recordings
    case notchDrop
    case maintenance

    var id: Self { self }

    var title: String {
        switch self {
        case .overview:
            return "Overview"
        case .alarms:
            return "Alarms"
        case .notifications:
            return "Notifications"
        case .recordings:
            return "Recordings"
        case .notchDrop:
            return "NotchDrop"
        case .maintenance:
            return "Maintenance"
        }
    }

    var detail: String {
        switch self {
        case .overview:
            return "Status and primary controls"
        case .alarms:
            return "Trigger conditions"
        case .notifications:
            return "Sound and Bark alerts"
        case .recordings:
            return "Camera capture"
        case .notchDrop:
            return "Tray and launch behavior"
        case .maintenance:
            return "Folders, SleepHold, diagnostics"
        }
    }

    var systemImage: String {
        switch self {
        case .overview:
            return "eye"
        case .alarms:
            return "light.beacon.max"
        case .notifications:
            return "app.badge"
        case .recordings:
            return "camera"
        case .notchDrop:
            return "tray"
        case .maintenance:
            return "wrench.and.screwdriver"
        }
    }
}

@MainActor
final class SentryControlCenterRouter: ObservableObject {
    static let shared = SentryControlCenterRouter()

    @Published var selection: SentryControlSection? = .overview

    private init() {}

    @discardableResult
    func open(_ section: SentryControlSection = .overview) -> SentinelCommandResult {
        selection = section
        return SentinelController.shared.openMainWindow()
    }
}

struct SentryControlCenterView: View {
    @StateObject private var config = SentryConfigurationManager.shared
    @StateObject private var controller = SentinelController.shared
    @StateObject private var viewModel = ViewModel.shared
    @ObservedObject private var router = SentryControlCenterRouter.shared
    @State private var showsHelp = false
    @AppStorage("isFirstVisit") private var isFirstVisit = true
    @EnvironmentObject private var appDelegate: AppDelegate

    var body: some View {
        NavigationSplitView {
            List(selection: $router.selection) {
                ForEach(SentryControlSection.allCases) { section in
                    SentryControlSidebarRow(section: section, status: sidebarStatus(for: section))
                        .tag(section)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 210, ideal: 230, max: 280)
        } detail: {
            detailView(for: router.selection ?? .overview)
        }
        .frame(minWidth: 780, minHeight: 540)
        .toolbar {
            ToolbarItemGroup {
                Button {
                    showsHelp = true
                } label: {
                    Image(systemName: "questionmark.circle")
                }
                .help("Help")
                .popover(isPresented: $showsHelp) {
                    HelpPanelView()
                }

                Button(isActive ? "Stop" : "Start") {
                    if isActive {
                        _ = controller.stop()
                    } else {
                        _ = controller.start()
                    }
                }
                .disabled(!config.canActivate && !isActive)

                Button("Unlock") {
                    _ = controller.unlockAlarm()
                }
                .disabled(viewModel.status != .activityDetected)
            }
        }
        .onAppear {
            presentHelpIfNeeded()
        }
    }

    private var isActive: Bool {
        viewModel.status == .running || viewModel.status == .activityDetected
    }

    @ViewBuilder
    private func detailView(for section: SentryControlSection) -> some View {
        switch section {
        case .overview:
            SentryOverviewPane(
                config: config,
                controller: controller,
                viewModel: viewModel,
                startupDiagnostics: appDelegate.startupDiagnostics
            )
        case .alarms:
            SentryAlarmSettingsPane(config: config)
        case .notifications:
            SentryNotificationSettingsPane(config: config)
        case .recordings:
            SentryRecordingSettingsPane(config: config)
        case .notchDrop:
            NotchDropSettingsPane()
        case .maintenance:
            SentryMaintenancePane(
                config: config,
                controller: controller,
                appDelegate: appDelegate
            )
        }
    }

    private func sidebarStatus(for section: SentryControlSection) -> String {
        switch section {
        case .overview:
            return controller.statusTitle
        case .alarms:
            return config.hasTriggerEnabled ? "Configured" : "Required"
        case .notifications:
            return config.hasNotificationEnabled ? "Configured" : "Required"
        case .recordings:
            return config.hasRecordingEnabled ? "Enabled" : "Off"
        case .notchDrop:
            return "Tray settings"
        case .maintenance:
            return config.sleepHoldServiceIdentifier.isEmpty ? "SleepHold inactive" : "SleepHold active"
        }
    }

    private func presentHelpIfNeeded() {
        guard isFirstVisit else { return }
        showsHelp = true
        isFirstVisit = false
    }
}

private struct SentryControlSidebarRow: View {
    let section: SentryControlSection
    let status: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: section.systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(section.title)
                    .lineLimit(1)
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

private struct SentryPane<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.title2)
                        .bold()
                    Text(subtitle)
                        .foregroundStyle(.secondary)
                }
                content()
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct SentryOverviewPane: View {
    @ObservedObject var config: SentryConfigurationManager
    @ObservedObject var controller: SentinelController
    @ObservedObject var viewModel: ViewModel
    let startupDiagnostics: [StartupDiagnostic]

    var body: some View {
        SentryPane(
            title: "Sentry Control Center",
            subtitle: "One place for status, controls, and configuration."
        ) {
            GroupBox {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .center, spacing: 16) {
                        statusIcon
                            .frame(width: 52, height: 52)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(controller.statusTitle)
                                .font(.title3)
                                .bold()
                            Text(statusDescription)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        HStack(spacing: 8) {
                            Button(isActive ? "Stop Sentry" : "Start Sentry") {
                                if isActive {
                                    _ = controller.stop()
                                } else {
                                    _ = controller.start()
                                }
                            }
                            .disabled(!config.canActivate && !isActive)

                            Button("Unlock Alarm") {
                                _ = controller.unlockAlarm()
                            }
                            .disabled(viewModel.status != .activityDetected)
                        }
                    }

                    if !controller.activityHint.isEmpty {
                        Divider()
                        Text(controller.activityHint)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            GroupBox("Readiness") {
                VStack(spacing: 10) {
                    SentryStatusRow(
                        title: "Alarm Triggers",
                        systemImage: "light.beacon.max",
                        value: config.hasTriggerEnabled ? "Configured" : "Required",
                        tint: config.hasTriggerEnabled ? .green : .orange
                    )
                    SentryStatusRow(
                        title: "Notifications",
                        systemImage: "app.badge",
                        value: config.hasNotificationEnabled ? "Configured" : "Required",
                        tint: config.hasNotificationEnabled ? .green : .orange
                    )
                    SentryStatusRow(
                        title: "Camera Recording",
                        systemImage: "camera",
                        value: config.hasRecordingEnabled ? "Enabled" : "Off",
                        tint: config.hasRecordingEnabled ? .green : .secondary
                    )
                    SentryStatusRow(
                        title: "Activation",
                        systemImage: "lock",
                        value: config.canActivate ? "Ready after lock" : "Needs alarm and notification",
                        tint: config.canActivate ? .green : .orange
                    )
                }
            }

            if !startupDiagnostics.isEmpty {
                GroupBox("Startup Diagnostics") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(startupDiagnostics) { diagnostic in
                            Label(diagnostic.message, systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }

            Text(versionText)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var isActive: Bool {
        viewModel.status == .running || viewModel.status == .activityDetected
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch viewModel.status {
        case .welcome:
            Image(.icon512)
                .resizable()
                .aspectRatio(contentMode: .fit)
        case .running:
            EyeView()
        case .activityDetected:
            Image(systemName: "light.beacon.max.fill")
                .font(.largeTitle)
                .foregroundStyle(.red)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .font(.largeTitle)
                .foregroundStyle(.green)
        }
    }

    private var statusDescription: String {
        switch viewModel.status {
        case .welcome:
            return config.canActivate ? "Lock your Mac to activate Sentry." : "Finish required setup before activation."
        case .running:
            return "Sentry is watching configured triggers."
        case .activityDetected:
            return "An alarm is active until it is unlocked or stopped."
        case .completed:
            return "The current Sentry session has ended."
        }
    }

    private var versionText: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
        return "Version \(version) (\(build))"
    }
}

private struct SentryAlarmSettingsPane: View {
    @ObservedObject var config: SentryConfigurationManager

    var body: some View {
        SentryPane(
            title: "Alarms",
            subtitle: "Choose which system changes trigger Sentry."
        ) {
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Alarm triggers fire when configured conditions are met.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Divider()

                    Toggle("Closing Lid", isOn: $config.cfg.sentryTriggersLidEnabled)
                    Toggle("Disconnected from Internet", isOn: $config.cfg.sentryTriggersInternetEnabled)
                    Toggle("Disconnected from Power Adapter", isOn: $config.cfg.sentryTriggersPowerEnabled)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox("Auto Sleep") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("If SleepHold is not installed, disable automatic sleep for the most reliable trigger behavior.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Learn More") {
                        NSWorkspace.shared.open(
                            URL(string: "https://github.com/Lakr233/Sentry?tab=readme-ov-file#system-requirements")!
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

private struct SentryNotificationSettingsPane: View {
    @ObservedObject var config: SentryConfigurationManager

    var body: some View {
        SentryPane(
            title: "Notifications",
            subtitle: "Configure local sound and Bark alerts."
        ) {
            GroupBox("Sound") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Playing sound is the quickest local warning when an alarm fires.")
                        .foregroundStyle(.secondary)
                    Toggle("Play Sound", isOn: $config.cfg.sentryAlarmsSoundsEnabled)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox("Bark") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Connect Bark if you want alarm notifications on your phone.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Toggle(isOn: barkEnabledBinding) {
                        Text("Use Bark")
                    }

                    LabeledContent("Endpoint") {
                        TextField("Server Endpoint", text: $config.cfg.sentryNotificationConfigBark.endpoint)
                            .textFieldStyle(.roundedBorder)
                            .autocorrectionDisabled()
                            .onChange(of: config.cfg.sentryNotificationConfigBark.endpoint) { newValue in
                                normalizeBarkEndpoint(newValue)
                            }
                    }
                    .disabled(config.cfg.sentryAlarmsNotificationType != .bark)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var barkEnabledBinding: Binding<Bool> {
        .init(
            get: { config.cfg.sentryAlarmsNotificationType == .bark },
            set: { newValue in
                config.cfg.sentryAlarmsNotificationType = newValue ? .bark : .none
            }
        )
    }

    private func normalizeBarkEndpoint(_ newValue: String) {
        guard var url = URL(string: newValue) else { return }
        while url.pathComponents.count > 2 {
            url = url.deletingLastPathComponent()
        }
        var text = url.absoluteString
        if text.hasSuffix("/") { text.removeLast() }
        guard text != newValue else { return }
        config.cfg.sentryNotificationConfigBark.endpoint = text
    }
}

private struct SentryRecordingSettingsPane: View {
    @ObservedObject var config: SentryConfigurationManager
    @StateObject private var cameraManager = CameraManager()

    var body: some View {
        SentryPane(
            title: "Recordings",
            subtitle: "Capture camera clips when Sentry is activated."
        ) {
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Enable Camera Recording", isOn: $config.cfg.sentryRecordingEnabled)

                    cameraContent

                    HStack {
                        Button("Open Saved Clips") {
                            SentinelController.shared.openSavedClips()
                        }
                        Spacer()
                        Text("Respect the privacy of others.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .onAppear {
            cameraManager.requestPermission()
        }
    }

    @ViewBuilder
    private var cameraContent: some View {
        if cameraManager.isAuthorized {
            authorizedCameraContent
        } else {
            unauthorizedCameraContent
        }
    }

    private var selectedCameraBinding: Binding<AVCaptureDevice?> {
        Binding(
            get: { cameraManager.selectedCamera },
            set: { newCamera in
                guard let newCamera else { return }
                cameraManager.switchCamera(to: newCamera)
            }
        )
    }

    private var authorizedCameraContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            CameraPreviewView(captureSession: cameraManager.captureSession)
                .background(.black)
                .frame(height: 170)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            if cameraManager.availableCameras.count > 1 {
                Picker("Camera", selection: selectedCameraBinding) {
                    ForEach(cameraManager.availableCameras, id: \.uniqueID) { camera in
                        Text(camera.localizedName).tag(camera as AVCaptureDevice?)
                    }
                }
                .pickerStyle(.menu)
            }
        }
    }

    private var unauthorizedCameraContent: some View {
        Rectangle()
            .foregroundStyle(.black)
            .frame(height: 170)
            .overlay {
                VStack(spacing: 8) {
                    Image(systemName: "camera.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.white)
                    Text(cameraAccessStatusText)
                        .font(.caption)
                        .foregroundStyle(.white)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var cameraAccessStatusText: String {
        cameraManager.authorizationStatus == .denied ? "Camera Access Denied" : "Requesting Camera Access..."
    }
}

@MainActor
private final class NotchDropSettingsStore: ObservableObject {
    @PublishedPersist(key: "selectedLanguage", defaultValue: .system)
    var selectedLanguage: Language

    @PublishedPersist(key: "hapticFeedback", defaultValue: true)
    var hapticFeedback: Bool
}

private struct NotchDropSettingsPane: View {
    @StateObject private var settings = NotchDropSettingsStore()
    @StateObject private var tray = TrayDrop.shared
    private let numberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.minimum = NSNumber(value: 1)
        return formatter
    }()

    var body: some View {
        SentryPane(
            title: "NotchDrop",
            subtitle: "Configure tray behavior and storage from the same control center."
        ) {
            GroupBox("General") {
                VStack(alignment: .leading, spacing: 12) {
                    Picker("Language", selection: $settings.selectedLanguage) {
                        ForEach(Language.allCases) { language in
                            Text(language.localized).tag(language)
                        }
                    }
                    .pickerStyle(.menu)
                    .onChange(of: settings.selectedLanguage) { newValue in
                        newValue.apply()
                    }

                    LaunchAtLogin.Toggle {
                        Text("Launch at Login")
                    }

                    Toggle("Haptic Feedback", isOn: $settings.hapticFeedback)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox("File Storage") {
                VStack(alignment: .leading, spacing: 12) {
                    Picker("Keep Files", selection: $tray.selectedFileStorageTime) {
                        ForEach(TrayDrop.FileStorageTime.allCases) { time in
                            Text(time.localized).tag(time)
                        }
                    }
                    .pickerStyle(.menu)

                    if tray.selectedFileStorageTime == .custom {
                        HStack {
                            TextField("Value", value: $tray.customStorageTime, formatter: numberFormatter)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 72)

                            Picker("Unit", selection: $tray.customStorageTimeUnit) {
                                ForEach(TrayDrop.CustomstorageTimeUnit.allCases) { unit in
                                    Text(unit.localized).tag(unit)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(width: 180)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

private struct SentryMaintenancePane: View {
    @ObservedObject var config: SentryConfigurationManager
    @ObservedObject var controller: SentinelController
    @ObservedObject var appDelegate: AppDelegate

    var body: some View {
        SentryPane(
            title: "Maintenance",
            subtitle: "Runtime paths, SleepHold status, and diagnostics."
        ) {
            GroupBox("Folders") {
                VStack(alignment: .leading, spacing: 10) {
                    Button("Open Recording Folder") {
                        controller.openSavedClips()
                    }
                    Button("Open NotchDrop Folder") {
                        controller.openNotchDropFolder()
                    }
                    Button("Clear NotchDrop Tray") {
                        controller.clearNotchDropTray()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox("SleepHold") {
                VStack(spacing: 10) {
                    SentryStatusRow(
                        title: "State",
                        systemImage: "power",
                        value: config.sleepHoldServiceIdentifier.isEmpty ? "Inactive" : "Active",
                        tint: config.sleepHoldServiceIdentifier.isEmpty ? .secondary : .green
                    )
                    SentryStatusRow(
                        title: "Session",
                        systemImage: "number",
                        value: config.sleepHoldServiceIdentifier.isEmpty ? "None" : config.sleepHoldServiceIdentifier,
                        tint: .secondary
                    )
                    SentryStatusRow(
                        title: "Last Update",
                        systemImage: "clock",
                        value: config.sleepHoldServiceLastUpdate.formatted(date: .abbreviated, time: .standard),
                        tint: .secondary
                    )
                }
            }

            GroupBox("Diagnostics") {
                VStack(alignment: .leading, spacing: 10) {
                    Button("Run Startup Checks") {
                        appDelegate.runStartupChecks()
                    }

                    if appDelegate.startupDiagnostics.isEmpty {
                        Text("No startup diagnostics are currently reported.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(appDelegate.startupDiagnostics) { diagnostic in
                            Label(diagnostic.message, systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

private struct SentryStatusRow: View {
    let title: String
    let systemImage: String
    let value: String
    let tint: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
                .frame(width: 18)
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

private struct SentryControlCenterPreviewContainer: View {
    @StateObject private var appDelegate = AppDelegate()

    var body: some View {
        SentryControlCenterView()
            .environmentObject(appDelegate)
    }
}

#Preview {
    SentryControlCenterPreviewContainer()
}
