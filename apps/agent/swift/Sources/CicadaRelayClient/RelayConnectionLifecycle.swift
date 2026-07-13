import Foundation

enum RelayDisconnectionAction: Equatable {
    case stop
    case reconnect
}

enum RelayReconnectDecision: Equatable {
    case reconnect(attempt: Int, delayMs: Int)
    case stop(attempt: Int)
}

enum RelayConnectionLifecycle {
    static func disconnectionAction(
        isStopping: Bool,
        autoConnect: Bool,
        enableAutoReconnect: Bool
    ) -> RelayDisconnectionAction {
        if isStopping || !autoConnect || !enableAutoReconnect {
            return .stop
        }
        return .reconnect
    }

    static func reconnectDecision(
        currentAttempts: Int,
        maxAttempts: Int,
        reconnectIntervalMs: Int
    ) -> RelayReconnectDecision {
        let attempt = currentAttempts + 1
        if maxAttempts > 0 && attempt > maxAttempts {
            return .stop(attempt: attempt)
        }

        let baseDelay = max(1_000, reconnectIntervalMs)
        return .reconnect(attempt: attempt, delayMs: min(baseDelay * attempt, 60_000))
    }

    static func isPongTimedOut(
        lastPongAt: Date,
        now: Date,
        timeoutMs: Int
    ) -> Bool {
        now.timeIntervalSince(lastPongAt) * 1_000 > Double(timeoutMs)
    }
}
