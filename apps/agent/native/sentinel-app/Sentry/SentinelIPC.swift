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
    private var fd: Int32 = -1
    private var running = false

    init(socketPath: String = CicadaSentinelPaths.sentinelSocketPath()) {
        self.socketPath = socketPath
    }

    func start() {
        guard !running else { return }

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
            fd = socketFd
            running = true
            queue.async { [weak self] in
                self?.acceptLoop()
            }
        } catch {
            print("[*] failed to start sentinel ipc server: \(error)")
        }
    }

    func stop() {
        running = false
        if fd >= 0 {
            close(fd)
            fd = -1
        }
        _ = unlink(socketPath)
    }

    private func acceptLoop() {
        while running {
            let clientFd = accept(fd, nil, nil)
            if clientFd < 0 {
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
