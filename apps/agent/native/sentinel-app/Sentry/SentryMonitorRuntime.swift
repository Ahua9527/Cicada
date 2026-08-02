import CicadaUI
import Foundation

struct SentryDeviceSnapshot: Equatable {
    let lidClosed: Bool?
    let networkConnected: Bool
    let powerConnected: Bool

    static func current() -> SentryDeviceSnapshot {
        .init(
            lidClosed: DeviceCheck.isMacLidClosed(),
            networkConnected: DeviceCheck.isConnectedToWirelessNetwork(),
            powerConnected: DeviceCheck.isConnectedToPower()
        )
    }
}

actor SentryMonitorRuntime {
    enum State: Equatable {
        case idle
        case running
        case alarming
        case stopping
    }

    private let configuration: SentryConfiguration
    private let deviceSnapshotProvider: () -> SentryDeviceSnapshot
    private let onHeartbeat: () async -> Void
    private let onAlarm: (String) async -> Void
    private let sleep: () async -> Void

    private var state: State = .idle
    private var task: Task<Void, Never>?
    private var lastSnapshot: SentryDeviceSnapshot?

    init(
        configuration: SentryConfiguration,
        deviceSnapshotProvider: @escaping () -> SentryDeviceSnapshot = SentryDeviceSnapshot.current,
        onHeartbeat: @escaping () async -> Void,
        onAlarm: @escaping (String) async -> Void,
        sleep: @escaping () async -> Void = {
            do {
                try await Task.sleep(for: .seconds(1))
            } catch {}
        }
    ) {
        self.configuration = configuration
        self.deviceSnapshotProvider = deviceSnapshotProvider
        self.onHeartbeat = onHeartbeat
        self.onAlarm = onAlarm
        self.sleep = sleep
    }

    func start(loop: Bool = true) {
        guard state == .idle else { return }
        state = .running
        lastSnapshot = nil

        guard loop else { return }
        startLoop()
    }

    func stop() async {
        guard state != .idle else { return }
        state = .stopping

        await cancelLoop()
        resetForIdle()
    }

    func unlockAlarm() {
        guard state == .alarming else { return }
        state = .running
    }

    func currentState() -> State {
        state
    }

    func tick() async {
        guard state == .running else { return }

        await onHeartbeat()
        guard state == .running else { return }

        guard let reason = nextAlarmReason() else { return }
        state = .alarming
        await onAlarm(reason)
    }

    private func runLoop() async {
        while !Task.isCancelled {
            await tick()
            await sleep()
        }
    }

    private func startLoop() {
        task = Task {
            await self.runLoop()
        }
    }

    private func cancelLoop() async {
        let task = self.task
        self.task = nil
        task?.cancel()
        _ = await task?.value
    }

    private func resetForIdle() {
        lastSnapshot = nil
        state = .idle
    }

    private func nextAlarmReason() -> String? {
        let snapshot = deviceSnapshotProvider()
        defer { lastSnapshot = snapshot }

        guard let lastSnapshot else { return nil }

        if configuration.sentryTriggersLidEnabled,
           lastSnapshot.lidClosed == false,
           snapshot.lidClosed == true
        {
            return String(localized: "Mac Lid Closed")
        }

        if configuration.sentryTriggersInternetEnabled,
           lastSnapshot.networkConnected,
           !snapshot.networkConnected
        {
            return String(localized: "Network Disconnected")
        }

        if configuration.sentryTriggersPowerEnabled,
           lastSnapshot.powerConnected,
           !snapshot.powerConnected
        {
            return String(localized: "Power Disconnected")
        }

        return nil
    }
}
