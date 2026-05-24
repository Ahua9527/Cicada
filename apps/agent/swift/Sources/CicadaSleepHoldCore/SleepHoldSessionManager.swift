import Foundation

public final class SleepHoldSessionManager {
    private let sessionDuration: TimeInterval
    private let powerController: any SleepHoldPowerControlling
    private let now: () -> Date
    private let lock = NSLock()
    private var sessions: [String: Date] = [:]
    private var cleanupTimer: DispatchSourceTimer?

    public init(
        sessionDuration: TimeInterval = 30,
        powerController: any SleepHoldPowerControlling = SleepHoldIOPowerController(),
        now: @escaping () -> Date = Date.init
    ) {
        self.sessionDuration = sessionDuration
        self.powerController = powerController
        self.now = now
        _ = powerController.set(.canSleep)
    }

    deinit {
        stopCleanupTimer()
        _ = powerController.set(.canSleep)
    }

    public func createSession() -> String {
        lock.lock()
        defer { lock.unlock() }

        let sessionId = UUID().uuidString
        sessions[sessionId] = now().addingTimeInterval(sessionDuration)
        updateSleepState()
        return sessionId
    }

    public func extendSession(_ sessionId: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        guard sessions[sessionId] != nil else {
            return false
        }
        sessions[sessionId] = now().addingTimeInterval(sessionDuration)
        updateSleepState()
        return true
    }

    public func terminateSession(_ sessionId: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        guard sessions.removeValue(forKey: sessionId) != nil else {
            return false
        }
        updateSleepState()
        return true
    }

    public func cleanupExpiredSessions() {
        lock.lock()
        defer { lock.unlock() }

        let current = now()
        let expired = sessions.filter { $0.value < current }.map(\.key)
        for sessionId in expired {
            sessions.removeValue(forKey: sessionId)
        }
        if !expired.isEmpty {
            updateSleepState()
        }
    }

    public func activeSessionsCount() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return sessions.count
    }

    public func clearSessions() {
        lock.lock()
        defer { lock.unlock() }
        sessions.removeAll()
        updateSleepState()
    }

    public func currentPowerStatus() -> SleepHoldPowerStatus {
        powerController.read()
    }

    public func startCleanupTimer() {
        lock.lock()
        defer { lock.unlock() }

        guard cleanupTimer == nil else {
            return
        }
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "com.cicada.sleephold.cleanup"))
        timer.schedule(deadline: .now() + 1, repeating: 1)
        timer.setEventHandler { [weak self] in
            self?.cleanupExpiredSessions()
        }
        timer.resume()
        cleanupTimer = timer
    }

    public func stopCleanupTimer() {
        lock.lock()
        let timer = cleanupTimer
        cleanupTimer = nil
        lock.unlock()
        timer?.cancel()
    }

    private func updateSleepState() {
        let target: SleepHoldPowerStatus = sessions.isEmpty ? .canSleep : .hold
        if powerController.read() != target {
            _ = powerController.set(target)
        }
    }
}
