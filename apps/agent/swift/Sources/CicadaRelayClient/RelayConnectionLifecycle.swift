import Foundation

enum RelayDisconnectionAction: Equatable {
    case stop
    case reconnect
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

    /// 第 attempt 次重连前的等待时间：逐次拉长，最长 60 秒。
    /// 重连不设次数上限——断网或 Relay 故障恢复后，守护进程要能自己连回来。
    static func reconnectDelayMs(attempt: Int, reconnectIntervalMs: Int) -> Int {
        let baseDelay = max(1_000, reconnectIntervalMs)
        return min(baseDelay * attempt, 60_000)
    }

    /// 心跳超时判定：只在有已发出但未应答的 ping 时才可能超时。
    /// 空闲连接（无未完成 ping）不算超时——ping 间隔（heartbeatInterval）通常
    /// 大于 connectionTimeout，旧实现用 lastPongAt 新鲜度判定会让连接在
    /// 首个心跳发出前就被误杀（真机复现：连接后 10s 必断）。
    static func isPongTimedOut(
        awaitingPongSince: Date?,
        now: Date,
        timeoutMs: Int
    ) -> Bool {
        guard let awaitingPongSince else { return false }
        return now.timeIntervalSince(awaitingPongSince) * 1_000 > Double(timeoutMs)
    }
}
