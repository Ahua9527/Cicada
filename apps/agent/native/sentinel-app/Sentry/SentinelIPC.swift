import Darwin
import Foundation

enum SentinelIPCAction: String, Codable {
    case start = "sentry_start"
    case stop = "sentry_stop"
    case status = "sentry_status"
    case unlock = "sentry_unlock"
    case open = "sentry_open"
}

struct SentinelIPCRequest: Codable {
    let action: SentinelIPCAction
}

final class SentinelIPCServer {
    static let shared = SentinelIPCServer()

    private let socketPath: String
    private let queue = DispatchQueue(label: "com.cicada.sentinel.ipc")
    // fd/running 跨线程访问（start/stop 主线程，acceptLoop 专用 queue）需加锁保护，
    // 否则在 Swift 内存模型下存在数据竞争。
    private let stateLock = NSLock()
    private var _fd: Int32 = -1
    private var _running = false
    // 用于 stop() 等待 acceptLoop 退出（join），避免 stop 后立即析构导致 use-after-free。
    private let acceptExited = DispatchSemaphore(value: 0)
    private var acceptLoopDidStart = false

    private var fd: Int32 {
        get { stateLock.lock(); defer { stateLock.unlock() }; return _fd }
        set { stateLock.lock(); defer { stateLock.unlock() }; _fd = newValue }
    }

    private var running: Bool {
        get { stateLock.lock(); defer { stateLock.unlock() }; return _running }
        set { stateLock.lock(); defer { stateLock.unlock() }; _running = newValue }
    }

    init(socketPath: String = CicadaSentinelPaths.sentinelSocketPath()) {
        self.socketPath = socketPath
    }

    func start() {
        stateLock.lock()
        if _running { stateLock.unlock(); return }
        stateLock.unlock()

        do {
            try FileManager.default.createDirectory(
                atPath: (socketPath as NSString).deletingLastPathComponent,
                withIntermediateDirectories: true
            )
            _ = unlink(socketPath)

            let socketFd = socket(AF_UNIX, SOCK_STREAM, 0)
            guard socketFd >= 0 else { return }

            var addr = sockaddr_un()
            addr.sun_family = sa_family_t(AF_UNIX)
            try copySocketPath(socketPath, into: &addr)

            let bound = withUnsafePointer(to: &addr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    bind(socketFd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
                }
            }
            guard bound == 0, listen(socketFd, 8) == 0 else {
                close(socketFd)
                return
            }

            _ = chmod(socketPath, 0o600)
            stateLock.lock()
            _fd = socketFd
            _running = true
            acceptLoopDidStart = true
            stateLock.unlock()
            queue.async { [weak self] in
                self?.acceptLoop()
                self?.acceptExited.signal()
            }
        } catch {
            print("[*] failed to start sentinel ipc server: \(error)")
        }
    }

    func stop() {
        stateLock.lock()
        let wasRunning = _running
        let fdToShutdown = _fd
        _running = false
        _fd = -1
        let didStartLoop = acceptLoopDidStart
        acceptLoopDidStart = false
        stateLock.unlock()

        if fdToShutdown >= 0 {
            // shutdown 唤醒阻塞在 accept() 上的 acceptLoop（best effort，
            // 监听 socket 在 macOS 上 shutdown 可能返回 ENOTCONN，可忽略），
            // close 释放 fd。
            _ = shutdown(fdToShutdown, SHUT_RDWR)
            close(fdToShutdown)
        }
        _ = unlink(socketPath)

        // join：等待 acceptLoop 退出（最长 1s，防止异常情况下死锁）。
        if didStartLoop && wasRunning {
            _ = acceptExited.wait(timeout: .now() + 1)
        }
    }

    private func acceptLoop() {
        while running {
            let clientFd = accept(fd, nil, nil)
            if clientFd < 0 {
                // 停止时 accept 返回错误，再次检查 running 以快速退出。
                if !running { break }
                continue
            }
            handleClient(clientFd)
            close(clientFd)
        }
    }

    private func handleClient(_ clientFd: Int32) {
        var buffer = [UInt8](repeating: 0, count: 8192)
        let readSize = recv(clientFd, &buffer, buffer.count, 0)
        let response: SentinelCommandResult

        guard readSize > 0 else { return }

        let raw = String(decoding: buffer.prefix(Int(readSize)), as: UTF8.self)
        let line = raw.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: true)
            .first.map(String.init) ?? ""
        if let data = line.data(using: .utf8),
           let request = try? JSONDecoder().decode(SentinelIPCRequest.self, from: data) {
            response = dispatch(request)
        } else {
            response = errorResult(code: "invalid_request", message: "invalid request")
        }

        guard var data = try? JSONEncoder().encode(response) else { return }
        data.append(0x0A)
        data.withUnsafeBytes {
            _ = Darwin.send(clientFd, $0.baseAddress, data.count, 0)
        }
    }

    private func dispatch(_ request: SentinelIPCRequest) -> SentinelCommandResult {
        let semaphore = DispatchSemaphore(value: 0)
        var response: SentinelCommandResult?

        Task { @MainActor in
            let controller = SentinelController.shared
            switch request.action {
            case .start:
                response = controller.start()
            case .stop:
                response = controller.stop()
            case .status:
                response = controller.statusResponse()
            case .unlock:
                response = controller.unlockAlarm()
            case .open:
                response = controller.openMainWindow()
            }
            semaphore.signal()
        }

        if semaphore.wait(timeout: .now() + 2) == .timedOut {
            return errorResult(code: "timeout", message: "sentinel command timed out")
        }
        return response ?? errorResult(code: "empty_response", message: "sentinel returned no response")
    }

    private func errorResult(code: String, message: String) -> SentinelCommandResult {
        SentinelCommandResult(
            ok: false,
            code: code,
            message: message,
            status: nil
        )
    }

    private func copySocketPath(_ path: String, into addr: inout sockaddr_un) throws {
        let maxPathLength = MemoryLayout.size(ofValue: addr.sun_path)
        if path.utf8.count >= maxPathLength {
            throw SleepHoldServiceClientError.socketPathTooLong
        }

        withUnsafeMutableBytes(of: &addr.sun_path) { buffer in
            buffer.initializeMemory(as: CChar.self, repeating: 0)
            _ = path.withCString { src in
                strncpy(buffer.baseAddress?.assumingMemoryBound(to: CChar.self), src, maxPathLength - 1)
            }
        }
    }
}
