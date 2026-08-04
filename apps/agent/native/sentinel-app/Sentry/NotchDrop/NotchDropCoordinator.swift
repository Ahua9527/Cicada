import AppKit
import Combine
import Foundation

@MainActor
final class NotchDropCoordinator: ObservableObject, SentinelNotificationRendering {
    static let shared = NotchDropCoordinator()

    let storageDirectory: URL

    private let presenter: NotchDropPresenting
    private var screenObserver: NSObjectProtocol?
    private var visibilityTimer: Timer?
    private var interactionDrainCancellables: Set<AnyCancellable> = []
    private var interactionState: (status: NotchViewModel.Status, contentType: NotchViewModel.ContentType)?
    private var isFirstOpen = true
    private var isNotificationInFlight = false
    private var forcedInteractionActive: Bool?
    private var pendingNotifications: [NotchDropNotificationPayload] = []
    private let maxPendingNotifications = 100

    fileprivate var windowController: NotchWindowController?

    /// 当前活动的 NotchViewModel：供控制中心设置卡读写引擎真实设置
    /// （hapticFeedback / selectedLanguage）。无刘海窗口时为 nil。
    var activeViewModel: NotchViewModel? { windowController?.vm }

    init(storageDirectory: URL = NotchDropPaths.defaultStorageDirectory, presenter: NotchDropPresenting? = nil) {
        self.storageDirectory = storageDirectory
        let defaultPresenter = NotchDropWindowPresenter()
        self.presenter = presenter ?? defaultPresenter
        defaultPresenter.coordinator = self
    }

    var pendingNotificationCount: Int {
        pendingNotifications.count
    }

    func start(openInitialWindow: Bool = true) {
        try? FileManager.default.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)

        _ = EventMonitors.shared
        TrayDrop.shared.cleanExpiredFiles()

        if screenObserver == nil {
            screenObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.rebuildWindow(openAfterCreate: false) }
            }
        }

        if visibilityTimer == nil {
            visibilityTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.makeKeyAndVisibleIfNeeded() }
            }
        }

        rebuildWindow(openAfterCreate: isFirstOpen && openInitialWindow)
        isFirstOpen = false
    }

    func stop() {
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
            self.screenObserver = nil
        }
        visibilityTimer?.invalidate()
        visibilityTimer = nil
        clearInteractionDrainBinding()
        windowController?.destroy()
        windowController = nil
        isNotificationInFlight = false
        try? FileManager.default.removeItem(at: temporaryDirectory)
    }

    func render(_ payload: NotchDropNotificationPayload) {
        if isInteractionActive || isNotificationInFlight {
            enqueue(payload)
            return
        }
        present(payload)
    }

    func openStorageDirectory() {
        try? FileManager.default.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: storageDirectory.path)
    }

    func clearTray() {
        TrayDrop.shared.removeAll()
    }

    func setInteractionActiveForTesting(_ active: Bool) {
        forcedInteractionActive = active
        if !active {
            playNextIfPossible()
        }
    }

    private var isInteractionActive: Bool {
        if let forcedInteractionActive {
            return forcedInteractionActive
        }
        guard let interactionState else { return false }
        return Self.isInteractionActive(
            status: interactionState.status,
            contentType: interactionState.contentType
        )
    }

    private func enqueue(_ payload: NotchDropNotificationPayload) {
        pendingNotifications.append(payload)
        if pendingNotifications.count > maxPendingNotifications {
            pendingNotifications.removeFirst(pendingNotifications.count - maxPendingNotifications)
            fputs("cicada sentinel notification queue overflow, dropped oldest notifications\n", stderr)
        }
    }

    private func present(_ payload: NotchDropNotificationPayload) {
        rebuildWindowIfNeeded()
        isNotificationInFlight = true
        presenter.presentNotification(payload) { [weak self] in
            self?.isNotificationInFlight = false
            self?.playNextIfPossible()
        }
    }

    private func playNextIfPossible() {
        guard !isInteractionActive, !isNotificationInFlight, !pendingNotifications.isEmpty else { return }
        let next = pendingNotifications.removeFirst()
        present(next)
    }

    private func rebuildWindowIfNeeded() {
        if windowController == nil {
            rebuildWindow(openAfterCreate: false)
        }
    }

    private func rebuildWindow(openAfterCreate: Bool) {
        clearInteractionDrainBinding()
        windowController?.destroy()
        windowController = nil
        guard let screen = findScreen() else { return }
        let controller = NotchWindowController(screen: screen)
        controller.openAfterCreate = openAfterCreate
        windowController = controller
        bindInteractionDrain(to: controller.vm)
    }

    private func findScreen() -> NSScreen? {
        if let screen = NSScreen.buildin, screen.notchSize != .zero {
            return screen
        }
        return .main
    }

    private func makeKeyAndVisibleIfNeeded() {
        guard let controller = windowController,
              let window = controller.window,
              let vm = controller.vm,
              vm.status == .opened
        else { return }
        window.makeKeyAndOrderFront(nil)
    }

    func bindInteractionDrainForTesting(to vm: NotchViewModel) {
        bindInteractionDrain(to: vm)
    }

    private func bindInteractionDrain(to vm: NotchViewModel?) {
        clearInteractionDrainBinding()
        guard let vm else {
            return
        }

        interactionState = (vm.status, vm.contentType)
        vm.$status
            .combineLatest(vm.$contentType)
            .sink { [weak self] status, contentType in
                guard let self else { return }
                interactionState = (status, contentType)
                if !Self.isInteractionActive(status: status, contentType: contentType) {
                    playNextIfPossible()
                }
            }
            .store(in: &interactionDrainCancellables)
    }

    private func clearInteractionDrainBinding() {
        interactionDrainCancellables.removeAll()
        interactionState = nil
    }

    private static func isInteractionActive(
        status: NotchViewModel.Status,
        contentType: NotchViewModel.ContentType
    ) -> Bool {
        status == .popping || (status == .opened && contentType != .notification)
    }
}

@MainActor
private final class NotchDropWindowPresenter: NotchDropPresenting {
    weak var coordinator: NotchDropCoordinator?

    func presentNotification(_ payload: NotchDropNotificationPayload, completion: @escaping () -> Void) {
        guard let vm = coordinator?.windowController?.vm else {
            completion()
            return
        }

        vm.showNotification(payload)
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(payload.durationMs)) { [weak vm] in
            vm?.clearNotificationIfNeeded()
            completion()
        }
    }
}
