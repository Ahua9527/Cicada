import AppKit
import CicadaUI
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
final class SentinelController: ObservableObject, AlarmEngineDelegate {
    static let shared = SentinelController()

    @Published private(set) var sentry: Sentry?
    @Published private(set) var activityHint: String = ""

    let viewModel = ViewModel.shared
    private var mainWindowOpener: (() -> Void)?
    private var isMacLockedProvider: () -> Bool? = DeviceCheck.isMacLocked
    private var sentryFactory: (() -> Sentry)?

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

    var localizedStatusTitle: String {
        switch viewModel.status {
        case .welcome:
            return String(localized: "Ready")
        case .running:
            return String(localized: "Running")
        case .activityDetected:
            return String(localized: "Activity Detected")
        case .completed:
            return String(localized: "Completed")
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
            rearmIfUnlocked()
        }
    }

    func start() -> SentinelCommandResult {
        AppModel.shared.alarm.delegate = self
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
        guard sentry != nil, sentry?.currentStatus != .idle else {
            sentry = nil
            AppModel.shared.alarm.reset()
            viewModel.status = .completed
            return result(ok: true, code: "already_stopped", message: "Sentry is not running")
        }

        viewModel.status = .completed
        finishCurrentSession()
        return result(ok: true, code: nil, message: "Sentry stopped")
    }

    func unlockAlarm() -> SentinelCommandResult {
        AppModel.shared.alarm.reset()
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
        // 仅对主控制中心窗口（WindowGroup id "main"）置前，
        // 避免菜单栏 Extra/警戒窗口等被意外抬升。
        for window in NSApp.windows where window.identifier?.rawValue == "main" {
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

    func configureForTesting(
        isMacLocked: @escaping () -> Bool?,
        makeSentry: @escaping () -> Sentry
    ) {
        isMacLockedProvider = isMacLocked
        sentryFactory = makeSentry
    }

    func resetForTesting() {
        sentry?.stop()
        sentry = nil
        activityHint = ""
        AppModel.shared.alarm.reset()
        AppModel.shared.alarm.delegate = nil
        viewModel.status = .welcome
        isMacLockedProvider = DeviceCheck.isMacLocked
        sentryFactory = nil
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
        let holdState = status.sleepHoldActive ? String(localized: "Holding") : String(localized: "Idle")
        let session = status.sleepHoldActive
            ? status.sleepHoldSessionId
            : String(localized: "No current session")
        let currentHoldLabel = String(localized: "Current Hold")
        let sessionLabel = String(localized: "Session")
        let alert = NSAlert()
        alert.messageText = String(localized: "Sleep Hold Session")
        alert.informativeText = "\(currentHoldLabel): \(holdState)\n\(sessionLabel): \(session)"
        alert.addButton(withTitle: String(localized: "OK"))
        alert.runModal()
    }

    func statusResponse() -> SentinelCommandResult {
        result(ok: true, code: nil, message: statusTitle)
    }

    func statusSnapshot() -> SentinelStatusSnapshot {
        let config = SentryConfigurationManager.shared
        let sleepHoldId = config.sleepHoldSessionIdentifier
        return SentinelStatusSnapshot(
            state: statusTitle,
            activityHint: activityHint,
            recordingEnabled: showsSavedClips,
            sleepHoldActive: config.hasSleepHoldSession,
            sleepHoldSessionId: sleepHoldId
        )
    }

    private func startFromWelcomeIfLocked() {
        guard viewModel.status == .welcome else { return }
        guard sentry == nil || sentry?.currentStatus == .idle else { return }
        guard let isLocked = isMacLockedProvider(), isLocked else { return }
        _ = start()
    }

    private func completeIfUnlocked() {
        guard viewModel.status == .running else { return }
        guard sentry != nil else { return }
        if isMacLockedProvider() ?? true { return }
        viewModel.status = .completed
        finishCurrentSession()
    }

    private func stopAlarmIfUnlocked() {
        guard viewModel.status == .activityDetected else { return }
        guard sentry != nil else { return }
        if isMacLockedProvider() ?? true { return }
        viewModel.status = .completed
        finishCurrentSession()
    }

    private func rearmIfUnlocked() {
        guard viewModel.status == .completed else { return }
        guard isMacLockedProvider() == false else { return }
        viewModel.status = .welcome
    }

    private func makeSentry() -> Sentry {
        if let sentryFactory {
            return sentryFactory()
        }

        // 构造 sentry 并注入警戒桥接（onAlarmingActivaty 触发 UI 层 AlarmModel）。
        let sentry = Sentry(configuration: SentryConfigurationManager.shared.cfg) { [weak self] alarmingReason in
            guard let self else { return }
            print("[*] alarming reason: \(alarmingReason)")
            viewModel.status = .activityDetected
            activityHint = String(
                format: String(localized: "An alarm was triggered at: %@. Reason: %@"),
                Date().formatted(),
                alarmingReason
            )
            AppModel.shared.alarm.activate(reason: alarmingReason)
        }
        return sentry
    }

    private func finishCurrentSession() {
        AppModel.shared.alarm.reset()
        let currentSentry = sentry
        sentry = nil
        currentSentry?.stop()
    }

    func alarmDidStop() async {
        _ = stop()
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
