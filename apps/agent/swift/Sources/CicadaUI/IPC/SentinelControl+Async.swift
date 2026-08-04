import CicadaIPC

/// 为 `UdsSentinelControlClient` 提供 async/await 扩展。
///
/// `SentinelControlClienting` 协议只有 `request(_:)`，`start()/stop()/status()`
/// 等是 `UdsSentinelControlClient` 的具体方法，因此 async 扩展加在具体类上。
/// `Task.detached(priority: .userInitiated)` 把同步阻塞 POSIX socket 调用移出
/// 主线程；`.value` 自动回到 @MainActor 上下文。
extension UdsSentinelControlClient {
    /// 异步查询 sentinel 状态。
    func statusAsync() async throws -> SentinelControlResponse {
        try await Task.detached(priority: .userInitiated) { try self.status() }.value
    }

    /// 异步启动 sentinel。
    func startAsync() async throws -> SentinelControlResponse {
        try await Task.detached(priority: .userInitiated) { try self.start() }.value
    }

    /// 异步停止 sentinel。
    func stopAsync() async throws -> SentinelControlResponse {
        try await Task.detached(priority: .userInitiated) { try self.stop() }.value
    }

    /// 异步解锁 sentinel 警戒。
    func unlockAsync() async throws -> SentinelControlResponse {
        try await Task.detached(priority: .userInitiated) { try self.unlock() }.value
    }

    /// 异步打开 sentinel（恢复监控）。
    func openAsync() async throws -> SentinelControlResponse {
        try await Task.detached(priority: .userInitiated) { try self.open() }.value
    }
}