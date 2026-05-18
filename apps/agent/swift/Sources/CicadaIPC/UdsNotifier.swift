import Darwin
import Foundation
import CicadaCore

public final class UdsNotifier {
    private let socketPath: String
    private let timeoutMs: Int
    private let autoStart: Bool
    private let manager: NotifierManager

    public init(
        socketPath: String = RuntimePaths.notifierSocketPath,
        timeoutMs: Int = 1000,
        autoStart: Bool = true,
        manager: NotifierManager = NotifierManager()
    ) {
        self.socketPath = socketPath
        self.timeoutMs = timeoutMs
        self.autoStart = autoStart
        self.manager = manager
    }

    public func notify(_ request: NotifyRequest) -> NotifyResponse {
        if request.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return NotifyResponse(ok: false, code: "INVALID_PAYLOAD", error: "title is required")
        }

        let firstAttempt = sendRequest(request)
        if firstAttempt.ok || !autoStart || firstAttempt.code != "AGENT_UNAVAILABLE" {
            return firstAttempt
        }

        Logger.warn("UdsNotifier", "Notifier agent unavailable, attempting auto-start")
        if manager.ensureStarted() {
            return sendRequest(request)
        }

        return firstAttempt
    }

    public func notifyQuick(
        source: String,
        level: NotificationLevel,
        title: String,
        message: String? = nil,
        durationMs: Int? = 2500
    ) -> NotifyResponse {
        let request = NotifyRequest.quick(
            source: source,
            level: level,
            title: title,
            message: message,
            durationMs: durationMs
        )
        return notify(request)
    }

    private func sendRequest(_ request: NotifyRequest) -> NotifyResponse {
        let encoder = JSONEncoder()
        guard let requestData = try? encoder.encode(request) else {
            return NotifyResponse(ok: false, code: "INVALID_PAYLOAD", error: "encode failed")
        }

        var payload = requestData
        payload.append(0x0A)

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        if fd < 0 {
            return NotifyResponse(ok: false, code: "AGENT_UNAVAILABLE", error: "socket create failed")
        }
        defer { close(fd) }

        var timeout = timeval(tv_sec: Int(timeoutMs / 1000), tv_usec: Int32(timeoutMs % 1000 * 1000))
        _ = setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        _ = setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)

        let maxPathLength = MemoryLayout.size(ofValue: addr.sun_path)
        if socketPath.utf8.count >= maxPathLength {
            return NotifyResponse(ok: false, code: "AGENT_UNAVAILABLE", error: "socket path too long")
        }

        withUnsafeMutableBytes(of: &addr.sun_path) { buffer in
            buffer.initializeMemory(as: CChar.self, repeating: 0)
            _ = socketPath.withCString { src in
                strncpy(buffer.baseAddress?.assumingMemoryBound(to: CChar.self), src, maxPathLength - 1)
            }
        }

        let connected = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }

        if connected != 0 {
            let errorCode = errno
            if errorCode == ENOENT || errorCode == ECONNREFUSED || errorCode == ETIMEDOUT {
                return NotifyResponse(ok: false, code: "AGENT_UNAVAILABLE", error: String(cString: strerror(errorCode)))
            }
            return NotifyResponse(ok: false, code: "RENDER_FAILED", error: String(cString: strerror(errorCode)))
        }

        let sent = payload.withUnsafeBytes {
            send(fd, $0.baseAddress, payload.count, 0)
        }
        if sent <= 0 {
            return NotifyResponse(ok: false, code: "AGENT_UNAVAILABLE", error: "send failed")
        }

        var buffer = [UInt8](repeating: 0, count: 4096)
        let readSize = recv(fd, &buffer, buffer.count, 0)
        if readSize <= 0 {
            return NotifyResponse(ok: false, code: "AGENT_UNAVAILABLE", error: "notify timeout")
        }

        let raw = String(decoding: buffer.prefix(Int(readSize)), as: UTF8.self)
        let line = raw.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: true).first.map(String.init) ?? ""
        guard let responseData = line.data(using: .utf8) else {
            return NotifyResponse(ok: false, code: "RENDER_FAILED", error: "invalid notifier response")
        }

        do {
            return try JSONDecoder().decode(NotifyResponse.self, from: responseData)
        } catch {
            return NotifyResponse(ok: false, code: "RENDER_FAILED", error: "invalid notifier response")
        }
    }
}
