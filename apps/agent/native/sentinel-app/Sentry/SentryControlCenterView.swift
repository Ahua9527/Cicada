import AppKit
import AVFoundation
import LaunchAtLogin
import SwiftUI

enum SentryControlSection: String, CaseIterable, Identifiable, Hashable {
    case overview
    case settings
    case maintenance

    var id: Self { self }

    var title: String {
        switch self {
        case .overview:
            return String(localized: "Overview")
        case .settings:
            return String(localized: "Settings")
        case .maintenance:
            return String(localized: "Maintenance")
        }
    }

    var detail: String {
        switch self {
        case .overview:
            return String(localized: "Status and readiness")
        case .settings:
            return String(localized: "Connection, protection, alerts, recording, and NotchDrop.")
        case .maintenance:
            return String(localized: "Folders, sleep hold session, diagnostics")
        }
    }

    var systemImage: String {
        switch self {
        case .overview:
            return "eye"
        case .settings:
            return "slider.horizontal.3"
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
                .help(String(localized: "Help"))
                .popover(isPresented: $showsHelp) {
                    HelpPanelView()
                }
            }
        }
        .onAppear {
            presentHelpIfNeeded()
        }
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
        case .settings:
            SentrySettingsPane(config: config)
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
            return controller.localizedStatusTitle
        case .settings:
            return config.canActivate ? String(localized: "Ready") : String(localized: "Required")
        case .maintenance:
            return config.hasSleepHoldSession ? String(localized: "Sleep hold active") : String(localized: "Sleep hold idle")
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
            title: String(localized: "Cicada Control Center"),
            subtitle: String(localized: "One place for status, controls, and configuration.")
        ) {
            GroupBox {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .center, spacing: 16) {
                        statusIcon
                            .frame(width: 52, height: 52)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(controller.localizedStatusTitle)
                                .font(.title3)
                                .bold()
                            Text(statusDescription)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()
                    }

                    if !controller.activityHint.isEmpty {
                        Divider()
                        Text(controller.activityHint)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            GroupBox(String(localized: "Readiness")) {
                VStack(spacing: 10) {
                    SentryStatusRow(
                        title: String(localized: "Alarm Triggers"),
                        systemImage: "light.beacon.max",
                        value: config.hasTriggerEnabled ? String(localized: "Configured") : String(localized: "Required"),
                        tint: config.hasTriggerEnabled ? .green : .orange
                    )
                    SentryStatusRow(
                        title: String(localized: "Notifications"),
                        systemImage: "app.badge",
                        value: config.hasNotificationEnabled ? String(localized: "Configured") : String(localized: "Required"),
                        tint: config.hasNotificationEnabled ? .green : .orange
                    )
                    SentryStatusRow(
                        title: String(localized: "Camera Recording"),
                        systemImage: "camera",
                        value: config.hasRecordingEnabled ? String(localized: "Enabled") : String(localized: "Off"),
                        tint: config.hasRecordingEnabled ? .green : .secondary
                    )
                    SentryStatusRow(
                        title: String(localized: "Activation"),
                        systemImage: "lock",
                        value: config.canActivate ? String(localized: "Ready after lock") : String(localized: "Needs alarm and notification"),
                        tint: config.canActivate ? .green : .orange
                    )
                }
            }

            if !startupDiagnostics.isEmpty {
                GroupBox(String(localized: "Startup Diagnostics")) {
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
            return config.canActivate ? String(localized: "Lock your Mac to activate Cicada.") : String(localized: "Finish required setup before activation.")
        case .running:
            return String(localized: "Cicada is watching configured triggers.")
        case .activityDetected:
            return String(localized: "An alarm is active until it is unlocked or stopped.")
        case .completed:
            return String(localized: "The current Cicada session has ended.")
        }
    }

    private var versionText: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? String(localized: "Unknown")
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? String(localized: "Unknown")
        return String(format: String(localized: "Version %@ (%@)"), version, build)
    }
}

private struct SentrySettingsPane: View {
    @ObservedObject var config: SentryConfigurationManager

    var body: some View {
        SentryPane(
            title: String(localized: "Settings"),
            subtitle: String(localized: "Connection, protection, alerts, recording, and NotchDrop.")
        ) {
            SentryRelaySettingsSection()
            SentryAlarmSettingsSection(config: config)
            SentryNotificationSettingsSection(config: config)
            SentryRecordingSettingsSection(config: config)
            NotchDropSettingsSection()
        }
    }
}

private struct SentryRelaySettingsSection: View {
    private let store: CicadaRelayConfigStore
    @State private var relayURL = ""
    @State private var statusMessage: String?
    @State private var statusTint = Color.secondary

    init(store: CicadaRelayConfigStore = CicadaRelayConfigStore()) {
        self.store = store
    }

    var body: some View {
        GroupBox(String(localized: "Connection")) {
            VStack(alignment: .leading, spacing: 12) {
                LabeledContent(String(localized: "Cicada Relay Address")) {
                    TextField(String(localized: "Cicada Relay Address"), text: $relayURL)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                        .onSubmit(save)
                }

                HStack {
                    Spacer()
                    Button(String(localized: "Reload"), action: reload)
                    Button(String(localized: "Save"), action: save)
                        .keyboardShortcut(.defaultAction)
                }

                if let statusMessage {
                    Text(statusMessage)
                        .font(.footnote)
                        .foregroundStyle(statusTint)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear {
            load(showSuccess: false)
        }
    }

    private func reload() {
        load(showSuccess: true)
    }

    private func load(showSuccess: Bool) {
        do {
            let config = try store.loadOrCreate()
            relayURL = config.relayURL
            if showSuccess {
                statusMessage = String(localized: "Relay settings reloaded.")
                statusTint = .green
            }
        } catch {
            setError(prefix: String(localized: "Unable to load Relay settings."), error: error)
        }
    }

    private func save() {
        let trimmedRelayURL = relayURL.trimmingCharacters(in: .whitespacesAndNewlines)
        relayURL = trimmedRelayURL

        do {
            let config = try store.saveRelayURL(trimmedRelayURL)
            relayURL = config.relayURL
            statusMessage = String(localized: "Relay settings saved.")
            statusTint = .green
        } catch {
            setError(prefix: String(localized: "Unable to save Relay settings."), error: error)
        }
    }

    private func setError(prefix: String, error: Error) {
        let description = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        statusMessage = "\(prefix) \(description)"
        statusTint = .red
    }
}

private struct SentryAlarmSettingsSection: View {
    @ObservedObject var config: SentryConfigurationManager

    var body: some View {
        GroupBox(String(localized: "Protection")) {
            VStack(alignment: .leading, spacing: 12) {
                Text(String(localized: "Alarm triggers fire when configured conditions are met."))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Toggle(String(localized: "Closing Lid"), isOn: $config.cfg.sentryTriggersLidEnabled)
                Toggle(String(localized: "Disconnected from Internet"), isOn: $config.cfg.sentryTriggersInternetEnabled)
                Toggle(String(localized: "Disconnected from Power Adapter"), isOn: $config.cfg.sentryTriggersPowerEnabled)

                Divider()

                Text(String(localized: "Auto Sleep"))
                    .font(.headline)

                Text(String(localized: "While Cicada is monitoring, it asks SleepHold to prevent sleep so alarm triggers stay reliable. If that hold is unavailable or blocked by system policy, disable automatic sleep in macOS."))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button(String(localized: "Learn More")) {
                    NSWorkspace.shared.open(
                        URL(string: "https://github.com/Lakr233/Sentry?tab=readme-ov-file#system-requirements")!
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct SentryNotificationSettingsSection: View {
    @ObservedObject var config: SentryConfigurationManager

    var body: some View {
        GroupBox(String(localized: "Alerts")) {
            VStack(alignment: .leading, spacing: 12) {
                Text(String(localized: "Sound"))
                    .font(.headline)
                Text(String(localized: "Playing sound is the quickest local warning when an alarm fires."))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Toggle(String(localized: "Play Sound"), isOn: $config.cfg.sentryAlarmsSoundsEnabled)

                Divider()

                Text(String(localized: "Bark"))
                    .font(.headline)
                Text(String(localized: "Connect Bark if you want alarm notifications on your phone."))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Toggle(isOn: barkEnabledBinding) {
                    Text(String(localized: "Use Bark"))
                }

                LabeledContent(String(localized: "Endpoint")) {
                    TextField(String(localized: "Server Endpoint"), text: $config.cfg.sentryNotificationConfigBark.endpoint)
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

private struct SentryRecordingSettingsSection: View {
    @ObservedObject var config: SentryConfigurationManager
    @StateObject private var cameraManager = CameraManager()

    var body: some View {
        GroupBox(String(localized: "Recordings")) {
            VStack(alignment: .leading, spacing: 12) {
                Toggle(String(localized: "Enable Camera Recording"), isOn: $config.cfg.sentryRecordingEnabled)

                cameraContent

                HStack {
                    Button(String(localized: "Open Saved Clips")) {
                        SentinelController.shared.openSavedClips()
                    }
                    Spacer()
                    Text(String(localized: "Respect the privacy of others."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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
                Picker(String(localized: "Camera"), selection: selectedCameraBinding) {
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

                    if cameraManager.authorizationStatus == .notDetermined {
                        Button(String(localized: "Allow Camera Access")) {
                            cameraManager.requestPermission()
                        }
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var cameraAccessStatusText: String {
        cameraManager.authorizationStatus == .notDetermined
            ? String(localized: "Camera Access Required")
            : String(localized: "Camera Access Denied")
    }
}

@MainActor
private final class NotchDropSettingsStore: ObservableObject {
    @PublishedPersist(key: "selectedLanguage", defaultValue: .system)
    var selectedLanguage: Language

    @PublishedPersist(key: "hapticFeedback", defaultValue: true)
    var hapticFeedback: Bool
}

private struct NotchDropSettingsSection: View {
    @StateObject private var settings = NotchDropSettingsStore()
    @StateObject private var tray = TrayDrop.shared
    private let numberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.minimum = NSNumber(value: 1)
        return formatter
    }()

    var body: some View {
        GroupBox(String(localized: "NotchDrop")) {
            VStack(alignment: .leading, spacing: 12) {
                Text(String(localized: "General"))
                    .font(.headline)

                Picker(String(localized: "Language"), selection: $settings.selectedLanguage) {
                    ForEach(Language.allCases) { language in
                        Text(language.localized).tag(language)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: settings.selectedLanguage) { newValue in
                    newValue.apply()
                }

                Toggle(String(localized: "Haptic Feedback"), isOn: $settings.hapticFeedback)

                Divider()

                Text(String(localized: "File Storage"))
                    .font(.headline)

                Picker(String(localized: "Keep Files"), selection: $tray.selectedFileStorageTime) {
                    ForEach(TrayDrop.FileStorageTime.allCases) { time in
                        Text(time.localized).tag(time)
                    }
                }
                .pickerStyle(.menu)

                if tray.selectedFileStorageTime == .custom {
                    HStack {
                        TextField(String(localized: "Value"), value: $tray.customStorageTime, formatter: numberFormatter)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 72)

                        Picker(String(localized: "Unit"), selection: $tray.customStorageTimeUnit) {
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

private struct SentryMaintenancePane: View {
    @ObservedObject var config: SentryConfigurationManager
    @ObservedObject var controller: SentinelController
    @ObservedObject var appDelegate: AppDelegate

    var body: some View {
        SentryPane(
            title: String(localized: "Maintenance"),
            subtitle: String(localized: "Runtime paths, sleep hold session, and diagnostics.")
        ) {
            GroupBox(String(localized: "Runtime")) {
                VStack(alignment: .leading, spacing: 8) {
                    LaunchAtLogin.Toggle {
                        Text(String(localized: "Start Cicada at Login"))
                    }

                    Text(String(localized: "Launch the Cicada app and services when you sign in."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox(String(localized: "Folders")) {
                VStack(alignment: .leading, spacing: 10) {
                    Button(String(localized: "Open Recording Folder")) {
                        controller.openSavedClips()
                    }
                    Button(String(localized: "Open NotchDrop Folder")) {
                        controller.openNotchDropFolder()
                    }
                    Button(String(localized: "Clear NotchDrop Tray")) {
                        controller.clearNotchDropTray()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox(String(localized: "SleepHold")) {
                VStack(spacing: 10) {
                    SentryStatusRow(
                        title: String(localized: "Current Hold"),
                        systemImage: "power",
                        value: config.hasSleepHoldSession ? String(localized: "Holding") : String(localized: "Idle"),
                        tint: config.hasSleepHoldSession ? .green : .secondary
                    )
                    SentryStatusRow(
                        title: String(localized: "Session"),
                        systemImage: "number",
                        value: config.hasSleepHoldSession ? config.sleepHoldSessionIdentifier : String(localized: "No current session"),
                        tint: .secondary
                    )
                    SentryStatusRow(
                        title: String(localized: "Last Update"),
                        systemImage: "clock",
                        value: config.sleepHoldServiceLastUpdate.formatted(date: .abbreviated, time: .standard),
                        tint: .secondary
                    )
                }
            }

            GroupBox(String(localized: "Diagnostics")) {
                VStack(alignment: .leading, spacing: 10) {
                    Button(String(localized: "Run Startup Checks")) {
                        appDelegate.runStartupChecks()
                    }

                    if appDelegate.startupDiagnostics.isEmpty {
                        Text(String(localized: "No startup diagnostics are currently reported."))
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
