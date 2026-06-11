import Darwin
import Foundation
import CicadaCore

public enum SentinelControlAction: String, Codable, CaseIterable {
    case start = "sentry_start"
    case stop = "sentry_stop"
    case status = "sentry_status"
    case unlock = "sentry_unlock"
    case open = "sentry_open"
}

public struct SentinelControlRequest: Codable, Equatable {
    public let action: SentinelControlAction

    public init(action: SentinelControlAction) {
        self.action = action
    }
}

private func copySocketPath(_ path: String, into addr: inout sockaddr_un) throws {
    let maxPathLength = MemoryLayout.size(ofValue: addr.sun_path)
    if path.utf8.count >= maxPathLength {
        throw DaemonControlError.socketPathTooLong
    }

    withUnsafeMutableBytes(of: &addr.sun_path) { buffer in
        buffer.initializeMemory(as: CChar.self, repeating: 0)
        _ = path.withCString { src in
            strncpy(buffer.baseAddress?.assumingMemoryBound(to: CChar.self), src, maxPathLength - 1)
        }
    }
}

public struct SentinelStatusSnapshot: Codable, Equatable {
    public let state: String
    public let activityHint: String
    public let recordingEnabled: Bool
    public let sleepHoldActive: Bool
    public let sleepHoldSessionId: String

    public init(
        state: String,
        activityHint: String,
        recordingEnabled: Bool,
        sleepHoldActive: Bool,
        sleepHoldSessionId: String
    ) {
        self.state = state
        self.activityHint = activityHint
        self.recordingEnabled = recordingEnabled
        self.sleepHoldActive = sleepHoldActive
        self.sleepHoldSessionId = sleepHoldSessionId
    }
}

public struct SentinelControlResponse: Codable, Equatable {
    public let ok: Bool
    public let code: String?
    public let message: String
    public let status: SentinelStatusSnapshot?

    public init(
        ok: Bool,
        code: String? = nil,
        message: String,
        status: SentinelStatusSnapshot? = nil
    ) {
        self.ok = ok
        self.code = code
        self.message = message
        self.status = status
    }
}

public protocol SentinelControlClienting {
    func request(_ request: SentinelControlRequest) throws -> SentinelControlResponse
}

public final class UdsSentinelControlClient: SentinelControlClienting {
    private let socketPath: String
    private let timeoutMs: Int

    public init(socketPath: String = RuntimePaths.sentinelSocketPath, timeoutMs: Int = 1000) {
        self.socketPath = socketPath
        self.timeoutMs = timeoutMs
    }

    public func start() throws -> SentinelControlResponse {
        try request(SentinelControlRequest(action: .start))
    }

    public func stop() throws -> SentinelControlResponse {
        try request(SentinelControlRequest(action: .stop))
    }

    public func status() throws -> SentinelControlResponse {
        try request(SentinelControlRequest(action: .status))
    }

    public func unlock() throws -> SentinelControlResponse {
        try request(SentinelControlRequest(action: .unlock))
    }

    public func open() throws -> SentinelControlResponse {
        try request(SentinelControlRequest(action: .open))
    }

    public func request(_ request: SentinelControlRequest) throws -> SentinelControlResponse {
        var payload = try JSONEncoder().encode(request)
        payload.append(0x0A)

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        if fd < 0 {
            throw DaemonControlError.unavailable("sentinel control socket create failed")
        }
        defer { close(fd) }

        var timeout = timeval(tv_sec: Int(timeoutMs / 1000), tv_usec: Int32(timeoutMs % 1000 * 1000))
        _ = setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        _ = setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        try copySocketPath(socketPath, into: &addr)

        let connected = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else {
            throw DaemonControlError.unavailable(String(cString: strerror(errno)))
        }

        let sent = payload.withUnsafeBytes {
            Darwin.send(fd, $0.baseAddress, payload.count, 0)
        }
        guard sent > 0 else {
            throw DaemonControlError.unavailable("sentinel control send failed")
        }

        var buffer = [UInt8](repeating: 0, count: 8192)
        let readSize = recv(fd, &buffer, buffer.count, 0)
        guard readSize > 0 else {
            throw DaemonControlError.unavailable("sentinel control timeout")
        }

        let raw = String(decoding: buffer.prefix(Int(readSize)), as: UTF8.self)
        let line = raw.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: true).first.map(String.init) ?? ""
        guard let data = line.data(using: .utf8) else {
            throw DaemonControlError.invalidPayload
        }
        return try JSONDecoder().decode(SentinelControlResponse.self, from: data)
    }
}
