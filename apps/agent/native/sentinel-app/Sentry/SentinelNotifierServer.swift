import Darwin
import Foundation

struct SentinelNotifyRequest: Codable {
    let version: Int
    let id: String?
    let source: String?
    let style: String?
    let level: String
    let title: String
    let message: String?
    let durationMs: Int?
    let timestamp: Int64?
}

struct SentinelNotifyResponse: Codable, Equatable {
    let ok: Bool
    let code: String?
    let error: String?
}

@MainActor
final class SentinelNotifierRequestHandler {
    private weak var renderer: (any SentinelNotificationRendering)?

    init(renderer: any SentinelNotificationRendering) {
        self.renderer = renderer
    }

    func handle(line: String) -> SentinelNotifyResponse {
        guard let data = line.data(using: .utf8) else {
            return .invalid("invalid utf8")
        }

        do {
            let request = try JSONDecoder().decode(SentinelNotifyRequest.self, from: data)
            guard let payload = payload(from: request) else {
                return .invalid("invalid request")
            }
            renderer?.render(payload)
            return SentinelNotifyResponse(ok: true, code: nil, error: nil)
        } catch {
            return .invalid("decode failed")
        }
    }

    private func payload(from request: SentinelNotifyRequest) -> NotchDropNotificationPayload? {
        let title = request.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard request.version == 1,
              request.style == "dynamic_island",
              !title.isEmpty
        else { return nil }

        let message = request.message?.trimmingCharacters(in: .whitespacesAndNewlines)
        return NotchDropNotificationPayload(
            level: .from(rawValue: request.level),
            title: title,
            message: message?.isEmpty == true ? nil : message,
            durationMs: max(request.durationMs ?? 2500, 500)
        )
    }
}

final class SentinelNotifierServer {
    static let shared = SentinelNotifierServer()

    private let socketPath: String
    private let queue = DispatchQueue(label: "com.cicada.sentinel.notifier", qos: .userInitiated)
    // fd/running 跨线程访问（start/stop 主线程，acceptLoop 专用 queue）需加锁保护，
    // 否则在 Swift 内存模型下存在数据竞争。
    private let stateLock = NSLock()
    private var _fd: Int32 = -1
    private var _running = false
    // 用于 stop() 等待 acceptLoop 退出（join），避免 stop 后立即析构导致 use-after-free。
    private let acceptExited = DispatchSemaphore(value: 0)
    private var acceptLoopDidStart = false
    private let handlerProvider: @MainActor () -> SentinelNotifierRequestHandler

    private var fd: Int32 {
        get { stateLock.lock(); defer { stateLock.unlock() }; return _fd }
        set { stateLock.lock(); defer { stateLock.unlock() }; _fd = newValue }
    }

    private var running: Bool {
        get { stateLock.lock(); defer { stateLock.unlock() }; return _running }
        set { stateLock.lock(); defer { stateLock.unlock() }; _running = newValue }
    }

    init(
        socketPath: String = CicadaSentinelPaths.notifierSocketPath(),
        handlerProvider: @escaping @MainActor () -> SentinelNotifierRequestHandler = {
            SentinelNotifierRequestHandler(renderer: NotchDropCoordinator.shared)
        }
    ) {
        self.socketPath = socketPath
        self.handlerProvider = handlerProvider
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
            guard bound == 0, listen(socketFd, 16) == 0 else {
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
            print("[*] failed to start sentinel notifier server: \(error)")
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
                if !running { break }
                continue
            }
            handleClient(clientFd)
            close(clientFd)
        }
    }

    private func handleClient(_ clientFd: Int32) {
        var buffer = [UInt8](repeating: 0, count: 4096)
        let readSize = recv(clientFd, &buffer, buffer.count, 0)
        guard readSize > 0 else { return }

        let raw = String(decoding: buffer.prefix(Int(readSize)), as: UTF8.self)
        let line = raw.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: true)
            .first.map(String.init) ?? ""
        let response = dispatch(line: line)

        writeResponse(clientFD: clientFd, response: response)
    }

    private func dispatch(line: String) -> SentinelNotifyResponse {
        let semaphore = DispatchSemaphore(value: 0)
        var response: SentinelNotifyResponse?

        Task { @MainActor in
            response = handlerProvider().handle(line: line)
            semaphore.signal()
        }

        if semaphore.wait(timeout: .now() + 2) == .timedOut {
            return SentinelNotifyResponse(ok: false, code: "RENDER_FAILED", error: "notify timed out")
        }
        return response ?? SentinelNotifyResponse(ok: false, code: "RENDER_FAILED", error: "empty response")
    }

    private func writeResponse(clientFD: Int32, response: SentinelNotifyResponse) {
        guard var data = try? JSONEncoder().encode(response) else { return }
        data.append(0x0A)
        data.withUnsafeBytes {
            _ = Darwin.send(clientFD, $0.baseAddress, data.count, 0)
        }
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

private extension SentinelNotifyResponse {
    static func invalid(_ error: String) -> SentinelNotifyResponse {
        SentinelNotifyResponse(ok: false, code: "INVALID_PAYLOAD", error: error)
    }
}
