import AppKit
import Foundation

struct SentinelCommandResult: Codable, Equatable {
    let ok: Bool
    let code: String?
    let message: String
    let status: SentinelStatusSnapshot?
}

struct SentinelStatusSnapshot: Codable, Equatable {
    let state: String
    let activityHint: String
    let recordingEnabled: Bool
    let sleepHoldActive: Bool
    let sleepHoldSessionId: String
}

@MainActor
final class SentinelController: ObservableObject {
    static let shared = SentinelController()

    @Published private(set) var sentry: Sentry?
    @Published private(set) var activityHint: String = ""

    let viewModel = ViewModel.shared
    private var mainWindowOpener: (() -> Void)?

    private init() {}

    var showsSavedClips: Bool {
        sentry?.configuration.sentryRecordingEnabled
            ?? SentryConfigurationManager.shared.cfg.sentryRecordingEnabled
    }

    var statusTitle: String {
        switch viewModel.status {
        case .welcome:
            return "Ready"
        case .running:
            return "Running"
        case .activityDetected:
            return "Activity Detected"
        case .completed:
            return "Completed"
        }
    }

    func handleTimerTick() {
        print("[*] interface timer tik: \(viewModel.status)")
        defer { print("[*] interface timer tik out: \(viewModel.status)") }

        switch viewModel.status {
        case .welcome:
            startFromWelcomeIfLocked()
        case .running:
            completeIfUnlocked()
        case .activityDetected:
            stopAlarmIfUnlocked()
        case .completed:
            break
        }
    }

    func start() -> SentinelCommandResult {
        if let sentry, sentry.currentStatus != .idle {
            return result(ok: true, code: "already_running", message: "Sentry is already running")
        }

        let sentry = makeSentry()
        self.sentry = sentry
        sentry.run()
        viewModel.status = .running
        return result(ok: true, code: nil, message: "Sentry started")
    }

    func stop() -> SentinelCommandResult {
        guard let sentry, sentry.currentStatus != .idle else {
            viewModel.status = .completed
            return result(ok: true, code: "already_stopped", message: "Sentry is not running")
        }

        viewModel.status = .completed
        sentry.stop()
        return result(ok: true, code: nil, message: "Sentry stopped")
    }

    func unlockAlarm() -> SentinelCommandResult {
        guard let sentry else {
            return result(ok: false, code: "not_running", message: "Sentry is not running")
        }

        sentry.unlockAlarm()
        if viewModel.status == .activityDetected {
            viewModel.status = .running
        }
        return result(ok: true, code: nil, message: "Sentry alarm unlocked")
    }

    func openMainWindow() -> SentinelCommandResult {
        let hadOpenableWindow = NSApp.windows.contains { $0.canBecomeKey || $0.isVisible }
        mainWindowOpener?()

        guard mainWindowOpener != nil || hadOpenableWindow || !NSApp.windows.isEmpty else {
            return result(ok: false, code: "window_unavailable", message: "Sentry window unavailable")
        }

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.forEach { window in
            window.makeKeyAndOrderFront(nil)
        }
        return result(ok: true, code: nil, message: "Sentry window opened")
    }

    func registerMainWindowOpener(_ opener: @escaping () -> Void) {
        mainWindowOpener = opener
    }

    func clearMainWindowOpenerForTesting() {
        mainWindowOpener = nil
    }

    func openSavedClips() {
        try? FileManager.default.createDirectory(
            atPath: videoClipDir.path,
            withIntermediateDirectories: true
        )
        NSWorkspace.shared.selectFile(
            nil,
            inFileViewerRootedAtPath: videoClipDir.path
        )
    }

    func openNotchDropFolder() {
        NotchDropCoordinator.shared.openStorageDirectory()
    }

    func clearNotchDropTray() {
        NotchDropCoordinator.shared.clearTray()
    }

    func showSleepHoldStatus() {
        let status = statusSnapshot()
        let alert = NSAlert()
        alert.messageText = "Disable Auto Sleep"
        alert.informativeText = status.sleepHoldActive
            ? "Active: \(status.sleepHoldSessionId)"
            : "Inactive"
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    func statusResponse() -> SentinelCommandResult {
        result(ok: true, code: nil, message: statusTitle)
    }

    func statusSnapshot() -> SentinelStatusSnapshot {
        let sleepHoldId = SentryConfigurationManager.shared.sleepHoldServiceIdentifier
        return SentinelStatusSnapshot(
            state: statusTitle,
            activityHint: activityHint,
            recordingEnabled: showsSavedClips,
            sleepHoldActive: !sleepHoldId.isEmpty,
            sleepHoldSessionId: sleepHoldId
        )
    }

    private func startFromWelcomeIfLocked() {
        guard viewModel.status == .welcome else { return }
        guard sentry == nil || sentry?.currentStatus == .idle else { return }
        guard let isLocked = DeviceCheck.isMacLocked(), isLocked else { return }
        _ = start()
    }

    private func completeIfUnlocked() {
        guard viewModel.status == .running else { return }
        guard let sentry else { return }
        if DeviceCheck.isMacLocked() ?? true { return }
        viewModel.status = .completed
        sentry.stop()
    }

    private func stopAlarmIfUnlocked() {
        guard viewModel.status == .activityDetected else { return }
        guard let sentry else { return }
        if DeviceCheck.isMacLocked() ?? true { return }
        sentry.stop()
    }

    private func makeSentry() -> Sentry {
        Sentry(configuration: SentryConfigurationManager.shared.cfg) { [weak self] alarmingReason in
            guard let self else { return }
            print("[*] alarming reason: \(alarmingReason)")
            viewModel.status = .activityDetected
            activityHint = String(
                localized: "An alarm was triggered at: \(Date().formatted()). Reason: \(alarmingReason)"
            )
        }
    }

    private func result(ok: Bool, code: String?, message: String) -> SentinelCommandResult {
        SentinelCommandResult(
            ok: ok,
            code: code,
            message: message,
            status: statusSnapshot()
        )
    }
}
