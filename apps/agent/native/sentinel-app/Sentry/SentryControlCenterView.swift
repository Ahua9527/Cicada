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
            return String(localized: "Overview")
        case .alarms:
            return String(localized: "Alarms")
        case .notifications:
            return String(localized: "Notifications")
        case .recordings:
            return String(localized: "Recordings")
        case .notchDrop:
            return String(localized: "NotchDrop")
        case .maintenance:
            return String(localized: "Maintenance")
        }
    }

    var detail: String {
        switch self {
        case .overview:
            return String(localized: "Status and readiness")
        case .alarms:
            return String(localized: "Trigger conditions")
        case .notifications:
            return String(localized: "Sound and Bark alerts")
        case .recordings:
            return String(localized: "Camera capture")
        case .notchDrop:
            return String(localized: "Tray and launch behavior")
        case .maintenance:
            return String(localized: "Folders, sleep hold session, diagnostics")
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
                .help(String(localized: "Help"))
                .popover(isPresented: $showsHelp) {
                    HelpPanelView()
                }

                Button(isActive ? String(localized: "Stop") : String(localized: "Start")) {
                    if isActive {
                        _ = controller.stop()
                    } else {
                        _ = controller.start()
                    }
                }
                .disabled(!config.canActivate && !isActive)

                Button(String(localized: "Unlock")) {
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
            return controller.localizedStatusTitle
        case .alarms:
            return config.hasTriggerEnabled ? String(localized: "Configured") : String(localized: "Required")
        case .notifications:
            return config.hasNotificationEnabled ? String(localized: "Configured") : String(localized: "Required")
        case .recordings:
            return config.hasRecordingEnabled ? String(localized: "Enabled") : String(localized: "Off")
        case .notchDrop:
            return String(localized: "Tray settings")
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

private struct SentryAlarmSettingsPane: View {
    @ObservedObject var config: SentryConfigurationManager

    var body: some View {
        SentryPane(
            title: String(localized: "Alarms"),
            subtitle: String(localized: "Choose which system changes trigger Cicada.")
        ) {
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Text(String(localized: "Alarm triggers fire when configured conditions are met."))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Divider()

                    Toggle(String(localized: "Closing Lid"), isOn: $config.cfg.sentryTriggersLidEnabled)
                    Toggle(String(localized: "Disconnected from Internet"), isOn: $config.cfg.sentryTriggersInternetEnabled)
                    Toggle(String(localized: "Disconnected from Power Adapter"), isOn: $config.cfg.sentryTriggersPowerEnabled)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox(String(localized: "Auto Sleep")) {
                VStack(alignment: .leading, spacing: 12) {
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
}

private struct SentryNotificationSettingsPane: View {
    @ObservedObject var config: SentryConfigurationManager

    var body: some View {
        SentryPane(
            title: String(localized: "Notifications"),
            subtitle: String(localized: "Configure local sound and Bark alerts.")
        ) {
            GroupBox(String(localized: "Sound")) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(String(localized: "Playing sound is the quickest local warning when an alarm fires."))
                        .foregroundStyle(.secondary)
                    Toggle(String(localized: "Play Sound"), isOn: $config.cfg.sentryAlarmsSoundsEnabled)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox(String(localized: "Bark")) {
                VStack(alignment: .leading, spacing: 12) {
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
            title: String(localized: "Recordings"),
            subtitle: String(localized: "Capture camera clips when Cicada is activated.")
        ) {
            GroupBox {
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
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var cameraAccessStatusText: String {
        cameraManager.authorizationStatus == .denied ? String(localized: "Camera Access Denied") : String(localized: "Requesting Camera Access...")
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
            title: String(localized: "NotchDrop"),
            subtitle: String(localized: "Configure tray behavior and storage from the same control center.")
        ) {
            GroupBox(String(localized: "General")) {
                VStack(alignment: .leading, spacing: 12) {
                    Picker(String(localized: "Language"), selection: $settings.selectedLanguage) {
                        ForEach(Language.allCases) { language in
                            Text(language.localized).tag(language)
                        }
                    }
                    .pickerStyle(.menu)
                    .onChange(of: settings.selectedLanguage) { newValue in
                        newValue.apply()
                    }

                    LaunchAtLogin.Toggle {
                        Text(String(localized: "Launch at Login"))
                    }

                    Toggle(String(localized: "Haptic Feedback"), isOn: $settings.hapticFeedback)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox(String(localized: "File Storage")) {
                VStack(alignment: .leading, spacing: 12) {
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
