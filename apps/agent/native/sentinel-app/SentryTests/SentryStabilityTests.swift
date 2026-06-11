import AppKit
import Darwin
import XCTest
@testable import Sentry

final class SentryStabilityTests: XCTestCase {
    override func tearDown() {
        _ = PendingStartupDiagnostics.consume()
        super.tearDown()
    }

    func testDebugLaunchWithoutSandboxAllowsAppAndProducesDiagnostic() {
        let decision = StartupLaunchPolicy.evaluate(
            isRunningTests: false,
            isDebugBuild: true,
            isSandboxEnabled: false,
            allowsLocalUnsignedLaunch: false
        )

        XCTAssertEqual(decision, .allowWithDiagnostics([.sandboxDisabledLocalBuild]))
    }

    func testReleaseLaunchWithoutSandboxBlocksStartup() {
        let decision = StartupLaunchPolicy.evaluate(
            isRunningTests: false,
            isDebugBuild: false,
            isSandboxEnabled: false,
            allowsLocalUnsignedLaunch: false
        )

        XCTAssertEqual(
            decision,
            .block("This app should not run outside of sandbox which may cause trouble.")
        )
    }

    func testLocalUnsignedReleaseLaunchWithoutSandboxAllowsWithDiagnostic() {
        let decision = StartupLaunchPolicy.evaluate(
            isRunningTests: false,
            isDebugBuild: false,
            isSandboxEnabled: false,
            allowsLocalUnsignedLaunch: true
        )

        XCTAssertEqual(decision, .allowWithDiagnostics([.sandboxDisabledLocalBuild]))
    }

    func testTestsBypassSandboxPolicy() {
        let decision = StartupLaunchPolicy.evaluate(
            isRunningTests: true,
            isDebugBuild: false,
            isSandboxEnabled: false,
            allowsLocalUnsignedLaunch: false
        )

        XCTAssertEqual(decision, .allow)
    }

    @MainActor
    func testStartupDiagnosticsArePublished() {
        let snapshot = StartupCheckSnapshot(
            clamshellClosed: nil,
            screenLocked: nil,
            wifiConnected: true,
            powerConnected: true,
            batteryLevel: nil,
            hasDefaultSpeaker: false,
            systemVolume: 0.5
        )
        let appDelegate = AppDelegate(startupCheckProvider: MockStartupCheckProvider(storedSnapshot: snapshot))

        appDelegate.runStartupChecks()

        XCTAssertEqual(
            appDelegate.startupDiagnostics.map(\.id),
            ["clamshell-state", "screen-lock-state", "battery-level", "default-speaker"]
        )
    }

    @MainActor
    func testPendingStartupDiagnosticsArePublishedOnLaunch() {
        let snapshot = StartupCheckSnapshot(
            clamshellClosed: false,
            screenLocked: false,
            wifiConnected: true,
            powerConnected: true,
            batteryLevel: 100,
            hasDefaultSpeaker: true,
            systemVolume: 0.5
        )
        let appDelegate = AppDelegate(startupCheckProvider: MockStartupCheckProvider(storedSnapshot: snapshot))

        PendingStartupDiagnostics.publish([.sandboxDisabledLocalBuild])
        appDelegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))

        XCTAssertEqual(appDelegate.startupDiagnostics.map(\.id), ["sandbox-disabled-local-build"])
    }

    @MainActor
    func testSleepHoldThrottlesRequestsAndIgnoresLateConnect() async {
        let client = MockSleepHoldServiceClient()
        var now = Date()
        let manager = SentryConfigurationManager(
            sleepHoldClient: client,
            now: { now },
            persistEngine: MemoryPersistProvider()
        )

        manager.communicateWithSleepHoldServiceIfNeeded()
        manager.communicateWithSleepHoldServiceIfNeeded()
        XCTAssertEqual(client.createCallCount, 1)

        manager.disconnectFromSleepHold()
        client.completeCreate(.success("session-1"))
        await Task.yield()

        XCTAssertEqual(manager.sleepHoldServiceIdentifier, "")
        XCTAssertEqual(client.terminatedSessionIDs, ["session-1"])

        manager.communicateWithSleepHoldServiceIfNeeded()
        XCTAssertEqual(client.createCallCount, 2)

        client.completeCreate(.success("session-2"))
        await Task.yield()
        XCTAssertEqual(manager.sleepHoldServiceIdentifier, "session-2")

        manager.communicateWithSleepHoldServiceIfNeeded()
        manager.communicateWithSleepHoldServiceIfNeeded()
        XCTAssertEqual(client.extendCallCount, 0)

        now = now.addingTimeInterval(10)
        manager.communicateWithSleepHoldServiceIfNeeded()
        manager.communicateWithSleepHoldServiceIfNeeded()
        XCTAssertEqual(client.extendCallCount, 1)
    }

    @MainActor
    func testInvalidBarkEndpointDoesNotConsumeNotification() {
        var requestCount = 0
        let sentry = Sentry(
            configuration: .init(
                sentryTriggersLidEnabled: false,
                sentryTriggersInternetEnabled: false,
                sentryTriggersPowerEnabled: false,
                sentryAlarmsSoundsEnabled: false,
                sentryAlarmsNotificationType: .bark,
                sentryNotificationConfigBark: .init(endpoint: "http://["),
                sentryRecordingEnabled: false,
                sentryRecordingDevice: nil
            ),
            onAlarmingActivaty: { _ in },
            shouldStartRuntimeLoop: false,
            barkRequestSender: { _ in
                requestCount += 1
            }
        )

        sentry.sendBarkNotification(message: "test")
        XCTAssertFalse(sentry.hasPostedNotification)
        XCTAssertEqual(requestCount, 0)

        sentry.sendBarkNotification(message: "test-again")
        XCTAssertFalse(sentry.hasPostedNotification)
        XCTAssertEqual(requestCount, 0)
    }

    @MainActor
    func testStopAllowsImmediateRunBeforeOldWindowAnimationCompletes() async throws {
        let windowFactory = MockWindowFactory()
        var pendingCloseCompletions: [() -> Void] = []
        let sentry = Sentry(
            configuration: .init(),
            onAlarmingActivaty: { _ in },
            shouldStartRuntimeLoop: false,
            makeWindowController: { _ in
                windowFactory.makeWindowController()
            },
            animateWindowClose: { _, completion in
                pendingCloseCompletions.append(completion)
            },
            readSystemVolume: { 0.5 },
            setSystemVolume: { _ in }
        )

        sentry.run()
        let firstWindow = try XCTUnwrap(windowFactory.createdWindowControllers.first)
        XCTAssertEqual(sentry.currentStatus, .running)

        sentry.stop()
        await Task.yield()
        XCTAssertEqual(sentry.currentStatus, .idle)
        XCTAssertEqual(firstWindow.closeCount, 0)
        XCTAssertEqual(pendingCloseCompletions.count, 1)

        sentry.run()
        let secondWindow = try XCTUnwrap(windowFactory.createdWindowControllers.last)
        XCTAssertEqual(sentry.currentStatus, .running)
        XCTAssertTrue(firstWindow !== secondWindow)

        pendingCloseCompletions.removeFirst()()

        XCTAssertEqual(firstWindow.closeCount, 1)
        XCTAssertEqual(secondWindow.closeCount, 0)
        XCTAssertEqual(sentry.currentStatus, .running)
    }

    func testRuntimeTransitionsRemainRecoverable() async {
        let snapshots = SnapshotFeeder(
            snapshots: [
                .init(lidClosed: false, networkConnected: true, powerConnected: true),
                .init(lidClosed: true, networkConnected: true, powerConnected: true),
            ]
        )
        let alarms = AlarmRecorder()
        let runtime = SentryMonitorRuntime(
            configuration: .init(
                sentryTriggersLidEnabled: true,
                sentryTriggersInternetEnabled: false,
                sentryTriggersPowerEnabled: false
            ),
            deviceSnapshotProvider: { snapshots.next() },
            onHeartbeat: {},
            onAlarm: { reason in
                await alarms.append(reason)
            },
            sleep: {}
        )

        await runtime.start(loop: false)
        var state = await runtime.currentState()
        XCTAssertEqual(state, .running)

        await runtime.tick()
        var alarmCount = await alarms.count()
        state = await runtime.currentState()
        XCTAssertEqual(alarmCount, 0)
        XCTAssertEqual(state, .running)

        await runtime.tick()
        alarmCount = await alarms.count()
        state = await runtime.currentState()
        XCTAssertEqual(alarmCount, 1)
        XCTAssertEqual(state, .alarming)

        await runtime.unlockAlarm()
        state = await runtime.currentState()
        XCTAssertEqual(state, .running)

        await runtime.stop()
        state = await runtime.currentState()
        XCTAssertEqual(state, .idle)

        await runtime.start(loop: false)
        state = await runtime.currentState()
        XCTAssertEqual(state, .running)
    }

    func testRecordingOutputURLsAreUniqueWithinSameSecond() {
        let directory = URL(fileURLWithPath: "/tmp/VideoClip", isDirectory: true)
        let now = Date(timeIntervalSinceReferenceDate: 12345.678)
        let first = RecordingOutputURLBuilder.makeURL(
            in: directory,
            now: now,
            uuid: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        )
        let second = RecordingOutputURLBuilder.makeURL(
            in: directory,
            now: now,
            uuid: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        )

        XCTAssertNotEqual(first, second)
        XCTAssertEqual(first.deletingLastPathComponent(), directory)
        XCTAssertEqual(second.deletingLastPathComponent(), directory)
        XCTAssertEqual(first.pathExtension, "mov")
        XCTAssertTrue(first.lastPathComponent.hasPrefix("Sentry_"))
    }

    func testSentinelIPCPayloadsRoundTrip() throws {
        let request = SentinelIPCRequest(action: .start)
        let decodedRequest = try JSONDecoder().decode(
            SentinelIPCRequest.self,
            from: try JSONEncoder().encode(request)
        )
        XCTAssertEqual(decodedRequest.action, .start)

        let response = SentinelCommandResult(
            ok: true,
            code: nil,
            message: "Sentry started",
            status: SentinelStatusSnapshot(
                state: "Running",
                activityHint: "",
                recordingEnabled: true,
                sleepHoldActive: true,
                sleepHoldSessionId: "cicada-daemon-power-assertion"
            )
        )
        let decodedResponse = try JSONDecoder().decode(
            SentinelCommandResult.self,
            from: try JSONEncoder().encode(response)
        )
        XCTAssertEqual(decodedResponse, response)
    }

    @MainActor
    func testOpenMainWindowInvokesRegisteredWindowOpener() {
        let controller = SentinelController.shared
        controller.clearMainWindowOpenerForTesting()
        var openCount = 0

        controller.registerMainWindowOpener {
            openCount += 1
        }
        let result = controller.openMainWindow()

        XCTAssertTrue(result.ok)
        XCTAssertEqual(openCount, 1)
        controller.clearMainWindowOpenerForTesting()
    }

    @MainActor
    func testSentinelNotifierHandlerValidatesPayloadAndRenders() throws {
        let renderer = RecordingNotificationRenderer()
        let handler = SentinelNotifierRequestHandler(renderer: renderer)
        let request = SentinelNotifyRequest(
            version: 1,
            id: "notify-1",
            source: "test",
            style: "dynamic_island",
            level: "warning",
            title: "Wake up",
            message: "Motion detected",
            durationMs: 100,
            timestamp: 1
        )

        let ok = handler.handle(line: String(data: try JSONEncoder().encode(request), encoding: .utf8)!)
        let invalid = handler.handle(line: "{\"version\":1,\"title\":\"   \"}")

        XCTAssertEqual(ok, SentinelNotifyResponse(ok: true, code: nil, error: nil))
        XCTAssertEqual(invalid.code, "INVALID_PAYLOAD")
        XCTAssertEqual(renderer.rendered, [
            NotchDropNotificationPayload(
                level: .warning,
                title: "Wake up",
                message: "Motion detected",
                durationMs: 500
            ),
        ])
    }

    @MainActor
    func testNotchDropCoordinatorQueuesNotificationsWhileInteractive() throws {
        let presenter = RecordingNotchDropPresenter()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cicada-notchdrop-\(UUID().uuidString)", isDirectory: true)
        let coordinator = NotchDropCoordinator(storageDirectory: directory, presenter: presenter)
        let payload = NotchDropNotificationPayload(
            level: .success,
            title: "Done",
            message: nil,
            durationMs: 750
        )

        coordinator.setInteractionActiveForTesting(true)
        coordinator.render(payload)
        XCTAssertTrue(presenter.presentedNotifications.isEmpty)
        XCTAssertEqual(coordinator.pendingNotificationCount, 1)

        coordinator.setInteractionActiveForTesting(false)
        XCTAssertEqual(presenter.presentedNotifications, [payload])
        XCTAssertEqual(coordinator.pendingNotificationCount, 0)
    }

    @MainActor
    func testNotchDropCoordinatorDrainsNotificationsWhenViewModelLeavesInteraction() throws {
        let presenter = RecordingNotchDropPresenter()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cicada-notchdrop-\(UUID().uuidString)", isDirectory: true)
        let coordinator = NotchDropCoordinator(storageDirectory: directory, presenter: presenter)
        let vm = NotchViewModel()
        let payload = NotchDropNotificationPayload(
            level: .success,
            title: "Done",
            message: nil,
            durationMs: 750
        )

        coordinator.bindInteractionDrainForTesting(to: vm)
        vm.notchOpen(.click)
        coordinator.render(payload)

        XCTAssertTrue(presenter.presentedNotifications.isEmpty)
        XCTAssertEqual(coordinator.pendingNotificationCount, 1)

        vm.notchClose()
        XCTAssertEqual(presenter.presentedNotifications, [payload])
        XCTAssertEqual(coordinator.pendingNotificationCount, 0)
    }

    @MainActor
    func testNotchDropCoordinatorQueuesNotificationsWhileDragging() throws {
        let presenter = RecordingNotchDropPresenter()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cicada-notchdrop-\(UUID().uuidString)", isDirectory: true)
        let coordinator = NotchDropCoordinator(storageDirectory: directory, presenter: presenter)
        let vm = NotchViewModel()
        let payload = NotchDropNotificationPayload(
            level: .info,
            title: "Dragged",
            message: nil,
            durationMs: 750
        )

        coordinator.bindInteractionDrainForTesting(to: vm)
        vm.notchPop()
        coordinator.render(payload)

        XCTAssertTrue(presenter.presentedNotifications.isEmpty)
        XCTAssertEqual(coordinator.pendingNotificationCount, 1)

        vm.notchClose()
        XCTAssertEqual(presenter.presentedNotifications, [payload])
        XCTAssertEqual(coordinator.pendingNotificationCount, 0)
    }

    @MainActor
    func testNotchDropCoordinatorSerializesNotifications() throws {
        let presenter = ManualCompletionNotchDropPresenter()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cicada-notchdrop-\(UUID().uuidString)", isDirectory: true)
        let coordinator = NotchDropCoordinator(storageDirectory: directory, presenter: presenter)
        let first = NotchDropNotificationPayload(
            level: .info,
            title: "First",
            message: nil,
            durationMs: 750
        )
        let second = NotchDropNotificationPayload(
            level: .warning,
            title: "Second",
            message: nil,
            durationMs: 750
        )

        coordinator.render(first)
        XCTAssertEqual(presenter.presentedNotifications, [first])
        XCTAssertEqual(coordinator.pendingNotificationCount, 0)

        coordinator.render(second)
        XCTAssertEqual(presenter.presentedNotifications, [first])
        XCTAssertEqual(coordinator.pendingNotificationCount, 1)

        presenter.completeNext()
        XCTAssertEqual(presenter.presentedNotifications, [first, second])
        XCTAssertEqual(coordinator.pendingNotificationCount, 0)

        presenter.completeNext()
    }

    func testNotchDropUsesCicadaInternalStorageByDefault() {
        XCTAssertEqual(
            NotchDropPaths.defaultStorageDirectory.path,
            NSHomeDirectory() + "/.cicada/notchdrop"
        )
    }

    func testSentinelRuntimePathsUseInjectedEnvironment() {
        let environment = [
            "CICADA_DAEMON_SOCKET": "/tmp/cicada-daemon.sock",
            "CICADA_NOTIFIER_SOCKET": "/tmp/cicada-notifier.sock",
            "CICADA_SENTINEL_SOCKET": "/tmp/cicada-sentinel.sock",
            "CICADA_NOTCHDROP_DIR": "/tmp/cicada-notchdrop",
        ]

        XCTAssertEqual(
            CicadaSentinelPaths.daemonSocketPath(environment: environment, homeDirectory: "/Users/alice"),
            "/tmp/cicada-daemon.sock"
        )
        XCTAssertEqual(
            CicadaSentinelPaths.notifierSocketPath(environment: environment, homeDirectory: "/Users/alice"),
            "/tmp/cicada-notifier.sock"
        )
        XCTAssertEqual(
            CicadaSentinelPaths.sentinelSocketPath(environment: environment, homeDirectory: "/Users/alice"),
            "/tmp/cicada-sentinel.sock"
        )
        XCTAssertEqual(
            NotchDropPaths.storageDirectory(
                environment: environment,
                homeDirectory: "/Users/alice"
            ).path,
            "/tmp/cicada-notchdrop"
        )
    }

    func testSentinelRuntimePathsFallbackToUserCicadaHome() {
        XCTAssertEqual(
            CicadaSentinelPaths.daemonSocketPath(environment: [:], homeDirectory: "/Users/alice"),
            "/Users/alice/.cicada/run/daemon.sock"
        )
        XCTAssertEqual(
            CicadaSentinelPaths.notchDropDirectory(environment: [:], homeDirectory: "/Users/alice").path,
            "/Users/alice/.cicada/notchdrop"
        )
    }

    func testDaemonSleepHoldClientReportsUnavailableSocket() async {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("missing-cicada-daemon-\(UUID().uuidString).sock")
            .path
        let client = CicadaDaemonSleepHoldServiceClient(socketPath: path, timeoutMs: 100)

        let result = await withCheckedContinuation { continuation in
            client.createSession { result in
                continuation.resume(returning: result)
            }
        }

        if case .success = result {
            XCTFail("Expected missing daemon socket to fail")
        }
    }

    func testDaemonSleepHoldClientExtendReassertsPowerAssertion() async throws {
        let server = try DaemonSleepHoldTestServer(expectedRequests: 2)
        try server.start()
        defer { server.stop() }

        let client = CicadaDaemonSleepHoldServiceClient(socketPath: server.socketPath, timeoutMs: 500)
        let created = await withCheckedContinuation { continuation in
            client.createSession { result in
                continuation.resume(returning: result)
            }
        }
        let extended = await withCheckedContinuation { continuation in
            client.extendSession("cicada-daemon-power-assertion") { ok in
                continuation.resume(returning: ok)
            }
        }

        if case .failure(let error) = created {
            XCTFail("Expected create to succeed, got \(error)")
        }
        XCTAssertTrue(extended)
        XCTAssertEqual(server.recordedActions(), ["power_assertion_start", "power_assertion_start"])
    }
}

private struct MockStartupCheckProvider: StartupCheckProviding {
    let storedSnapshot: StartupCheckSnapshot

    func snapshot() -> StartupCheckSnapshot {
        storedSnapshot
    }
}

private final class MockSleepHoldServiceClient: SleepHoldServiceClient {
    private var createCompletions: [(Result<String, Error>) -> Void] = []
    private var extendCompletions: [(Bool) -> Void] = []

    private(set) var createCallCount = 0
    private(set) var extendCallCount = 0
    private(set) var terminateCallCount = 0
    private(set) var terminatedSessionIDs: [String] = []

    func createSession(completion: @escaping (Result<String, Error>) -> Void) {
        createCallCount += 1
        createCompletions.append(completion)
    }

    func extendSession(_: String, completion: @escaping (Bool) -> Void) {
        extendCallCount += 1
        extendCompletions.append(completion)
    }

    func terminateSession(_ sessionId: String, completion: @escaping (Bool) -> Void) {
        terminateCallCount += 1
        terminatedSessionIDs.append(sessionId)
        completion(true)
    }

    func completeCreate(_ result: Result<String, Error>) {
        guard !createCompletions.isEmpty else { return }
        createCompletions.removeFirst()(result)
    }

    func completeExtend(_ ok: Bool) {
        guard !extendCompletions.isEmpty else { return }
        extendCompletions.removeFirst()(ok)
    }
}

private final class MemoryPersistProvider: PersistProvider {
    private var storage: [String: Data] = [:]

    func data(forKey key: String) -> Data? {
        storage[key]
    }

    func set(_ data: Data?, forKey key: String) {
        storage[key] = data
    }
}

private actor AlarmRecorder {
    private var reasons: [String] = []

    func append(_ reason: String) {
        reasons.append(reason)
    }

    func count() -> Int {
        reasons.count
    }
}

private final class SnapshotFeeder {
    private var snapshots: [SentryDeviceSnapshot]
    private var index = 0

    init(snapshots: [SentryDeviceSnapshot]) {
        self.snapshots = snapshots
    }

    func next() -> SentryDeviceSnapshot {
        guard !snapshots.isEmpty else {
            return .init(lidClosed: nil, networkConnected: true, powerConnected: true)
        }

        let currentIndex = min(index, snapshots.count - 1)
        if index < snapshots.count - 1 {
            index += 1
        }
        return snapshots[currentIndex]
    }
}

@MainActor
private final class RecordingNotificationRenderer: SentinelNotificationRendering {
    private(set) var rendered: [NotchDropNotificationPayload] = []

    func render(_ payload: NotchDropNotificationPayload) {
        rendered.append(payload)
    }
}

@MainActor
private final class RecordingNotchDropPresenter: NotchDropPresenting {
    private(set) var presentedNotifications: [NotchDropNotificationPayload] = []

    func presentNotification(_ payload: NotchDropNotificationPayload, completion: @escaping () -> Void) {
        presentedNotifications.append(payload)
        completion()
    }
}

@MainActor
private final class ManualCompletionNotchDropPresenter: NotchDropPresenting {
    private(set) var presentedNotifications: [NotchDropNotificationPayload] = []
    private var completions: [() -> Void] = []

    func presentNotification(_ payload: NotchDropNotificationPayload, completion: @escaping () -> Void) {
        presentedNotifications.append(payload)
        completions.append(completion)
    }

    func completeNext() {
        guard !completions.isEmpty else { return }
        completions.removeFirst()()
    }
}

private final class DaemonSleepHoldTestServer {
    let socketPath: String

    private let expectedRequests: Int
    private let queue = DispatchQueue(label: "com.cicada.sentinel.tests.daemon-sleephold")
    private let lock = NSLock()
    private var fd: Int32 = -1
    private var actions: [String] = []

    init(expectedRequests: Int) throws {
        self.expectedRequests = expectedRequests
        socketPath = "/tmp/cicada-\(UUID().uuidString).sock"
    }

    func start() throws {
        _ = unlink(socketPath)
        let socketFd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard socketFd >= 0 else {
            throw SleepHoldServiceClientError.unavailable("test socket create failed")
        }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        try copySocketPath(socketPath, into: &addr)

        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(socketFd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0, listen(socketFd, 4) == 0 else {
            close(socketFd)
            throw SleepHoldServiceClientError.unavailable("test socket bind failed")
        }

        fd = socketFd
        queue.async { [weak self] in
            self?.acceptLoop()
        }
    }

    func stop() {
        if fd >= 0 {
            close(fd)
            fd = -1
        }
        _ = unlink(socketPath)
    }

    func recordedActions() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return actions
    }

    private func acceptLoop() {
        for _ in 0 ..< expectedRequests {
            let clientFd = accept(fd, nil, nil)
            guard clientFd >= 0 else { return }
            handle(clientFd)
            close(clientFd)
        }
    }

    private func handle(_ clientFd: Int32) {
        var buffer = [UInt8](repeating: 0, count: 4096)
        let readSize = recv(clientFd, &buffer, buffer.count, 0)
        guard readSize > 0 else { return }

        let raw = String(decoding: buffer.prefix(Int(readSize)), as: UTF8.self)
        let line = raw.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: true)
            .first.map(String.init) ?? ""
        if let data = line.data(using: .utf8),
           let request = try? JSONDecoder().decode(DaemonSleepHoldTestRequest.self, from: data) {
            lock.lock()
            actions.append(request.action)
            lock.unlock()
        }

        let response = #"{"ok":true}"# + "\n"
        response.withCString { pointer in
            _ = Darwin.send(clientFd, pointer, strlen(pointer), 0)
        }
    }

    private func copySocketPath(_ path: String, into addr: inout sockaddr_un) throws {
        let maxPathLength = MemoryLayout.size(ofValue: addr.sun_path)
        guard path.utf8.count < maxPathLength else {
            throw SleepHoldServiceClientError.socketPathTooLong
        }

        withUnsafeMutableBytes(of: &addr.sun_path) { buffer in
            buffer.initializeMemory(as: CChar.self, repeating: 0)
            _ = path.withCString { src in
                strncpy(buffer.baseAddress?.assumingMemoryBound(to: CChar.self), src, maxPathLength - 1)
            }
        }
    }

    private struct DaemonSleepHoldTestRequest: Decodable {
        let action: String
    }
}

@MainActor
private final class MockWindowFactory {
    private(set) var createdWindowControllers: [MockWindowController] = []

    func makeWindowController() -> NSWindowController {
        let controller = MockWindowController()
        createdWindowControllers.append(controller)
        return controller
    }
}

@MainActor
private final class MockWindowController: NSWindowController {
    private(set) var closeCount = 0

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 200),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.contentView = NSView(frame: window.contentRect(forFrameRect: window.frame))
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func close() {
        closeCount += 1
        super.close()
    }
}
