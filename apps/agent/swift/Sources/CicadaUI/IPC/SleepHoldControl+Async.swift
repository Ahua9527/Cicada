import CicadaSleepHoldCore
import CicadaSystem

/// 为 `SleepHoldControlClient` 提供 async/await 扩展。
///
/// `SleepHoldControlClient` 是具体类（非协议），直接扩展。
/// 所有同步阻塞 POSIX socket 调用通过 `Task.detached` 移出主线程。
extension SleepHoldControlClient {
    /// 异步查询 sleephold 状态。
    func statusAsync() async throws -> SleepHoldControlResponse {
        try await Task.detached(priority: .userInitiated) { try self.status() }.value
    }

    /// 异步 ping sleephold。
    func pingAsync() async throws -> SleepHoldControlResponse {
        try await Task.detached(priority: .userInitiated) { try self.ping() }.value
    }

    /// 异步创建 sleephold 会话。
    func createSessionAsync() async throws -> SleepHoldControlResponse {
        try await Task.detached(priority: .userInitiated) { try self.createSession() }.value
    }

    /// 异步续期 sleephold 会话。
    func extendSessionAsync(_ sessionId: String) async throws -> SleepHoldControlResponse {
        try await Task.detached(priority: .userInitiated) { try self.extendSession(sessionId) }.value
    }

    /// 异步终止 sleephold 会话。
    func terminateSessionAsync(_ sessionId: String) async throws -> SleepHoldControlResponse {
        try await Task.detached(priority: .userInitiated) { try self.terminateSession(sessionId) }.value
    }
}