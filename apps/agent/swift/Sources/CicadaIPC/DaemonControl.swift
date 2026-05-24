import Darwin
import Foundation
import CicadaCore

public enum DaemonControlAction: String, Codable {
    case shortcutGrantCreate = "shortcut_grant_create"
    case shortcutGrantList = "shortcut_grant_list"
    case shortcutGrantRevoke = "shortcut_grant_revoke"
    case powerAssertionStart = "power_assertion_start"
    case powerAssertionStop = "power_assertion_stop"
}

public struct DaemonControlRequest: Codable {
    public let action: DaemonControlAction
    public let name: String?
    public let commands: [String]?
    public let ttlMs: Int64?
    public let grantId: String?

    public init(
        action: DaemonControlAction,
        name: String? = nil,
        commands: [String]? = nil,
        ttlMs: Int64? = nil,
        grantId: String? = nil
    ) {
        self.action = action
        self.name = name
        self.commands = commands
        self.ttlMs = ttlMs
        self.grantId = grantId
    }
}

public struct DaemonControlResponse: Codable {
    public let ok: Bool
    public let code: String?
    public let error: String?
    public let shortcutToken: String?
    public let shortcutGrant: ShortcutGrant?
    public let shortcutGrants: [ShortcutGrant]?
    public let commandResult: CommandExecutionResult?

    public init(
        ok: Bool,
        code: String? = nil,
        error: String? = nil,
        shortcutToken: String? = nil,
        shortcutGrant: ShortcutGrant? = nil,
        shortcutGrants: [ShortcutGrant]? = nil,
        commandResult: CommandExecutionResult? = nil
    ) {
        self.ok = ok
        self.code = code
        self.error = error
        self.shortcutToken = shortcutToken
        self.shortcutGrant = shortcutGrant
        self.shortcutGrants = shortcutGrants
        self.commandResult = commandResult
    }
}

public enum DaemonControlError: Error, CustomStringConvertible {
    case unavailable(String)
    case invalidPayload
    case socketPathTooLong

    public var description: String {
        switch self {
        case let .unavailable(message):
            return message
        case .invalidPayload:
            return "invalid daemon control payload"
        case .socketPathTooLong:
            return "daemon control socket path is too long"
        }
    }
}

public final class UdsDaemonControlClient {
    private let socketPath: String
    private let timeoutMs: Int

    public init(socketPath: String = RuntimePaths.daemonSocketPath, timeoutMs: Int = 1000) {
        self.socketPath = socketPath
        self.timeoutMs = timeoutMs
    }

    public func shortcutGrantCreate(
        name: String,
        commands: [String],
        ttlMs: Int64
    ) throws -> DaemonControlResponse {
        try request(
            DaemonControlRequest(
                action: .shortcutGrantCreate,
                name: name,
                commands: commands,
                ttlMs: ttlMs
            )
        )
    }

    public func shortcutGrantList() throws -> DaemonControlResponse {
        try request(DaemonControlRequest(action: .shortcutGrantList))
    }

    public func shortcutGrantRevoke(grantId: String) throws -> DaemonControlResponse {
        try request(DaemonControlRequest(action: .shortcutGrantRevoke, grantId: grantId))
    }

    public func powerAssertionStart() throws -> DaemonControlResponse {
        try request(DaemonControlRequest(action: .powerAssertionStart))
    }

    public func powerAssertionStop() throws -> DaemonControlResponse {
        try request(DaemonControlRequest(action: .powerAssertionStop))
    }

    public func request(_ request: DaemonControlRequest) throws -> DaemonControlResponse {
        var payload = try JSONEncoder().encode(request)
        payload.append(0x0A)

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        if fd < 0 {
            throw DaemonControlError.unavailable("daemon control socket create failed")
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
            send(fd, $0.baseAddress, payload.count, 0)
        }
        guard sent > 0 else {
            throw DaemonControlError.unavailable("daemon control send failed")
        }

        var buffer = [UInt8](repeating: 0, count: 8192)
        let readSize = recv(fd, &buffer, buffer.count, 0)
        guard readSize > 0 else {
            throw DaemonControlError.unavailable("daemon control timeout")
        }

        let raw = String(decoding: buffer.prefix(Int(readSize)), as: UTF8.self)
        let line = raw.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: true).first.map(String.init) ?? ""
        guard let data = line.data(using: .utf8) else {
            throw DaemonControlError.invalidPayload
        }
        return try JSONDecoder().decode(DaemonControlResponse.self, from: data)
    }
}

public final class UdsDaemonControlServer {
    private let socketPath: String
    private let queue = DispatchQueue(label: "com.cicada.agent.daemon-control")
    private var fd: Int32 = -1
    private var running = false

    public init(socketPath: String = RuntimePaths.daemonSocketPath) {
        self.socketPath = socketPath
    }

    public func start(handler: @escaping (DaemonControlRequest) -> DaemonControlResponse) throws {
        try FileManager.default.createDirectory(atPath: RuntimePaths.runDir, withIntermediateDirectories: true)
        _ = unlink(socketPath)

        let socketFd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard socketFd >= 0 else {
            throw DaemonControlError.unavailable("daemon control socket create failed")
        }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        try copySocketPath(socketPath, into: &addr)

        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(socketFd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0 else {
            close(socketFd)
            throw DaemonControlError.unavailable(String(cString: strerror(errno)))
        }
        guard listen(socketFd, 8) == 0 else {
            close(socketFd)
            throw DaemonControlError.unavailable(String(cString: strerror(errno)))
        }

        _ = chmod(socketPath, 0o600)
        fd = socketFd
        running = true
        queue.async { [weak self] in
            self?.acceptLoop(handler: handler)
        }
    }

    public func stop() {
        running = false
        if fd >= 0 {
            close(fd)
            fd = -1
        }
        _ = unlink(socketPath)
    }

    private func acceptLoop(handler: @escaping (DaemonControlRequest) -> DaemonControlResponse) {
        while running {
            let clientFd = accept(fd, nil, nil)
            if clientFd < 0 {
                continue
            }
            handleClient(clientFd, handler: handler)
            close(clientFd)
        }
    }

    private func handleClient(
        _ clientFd: Int32,
        handler: @escaping (DaemonControlRequest) -> DaemonControlResponse
    ) {
        var buffer = [UInt8](repeating: 0, count: 8192)
        let readSize = recv(clientFd, &buffer, buffer.count, 0)
        let response: DaemonControlResponse
        if readSize <= 0 {
            response = DaemonControlResponse(ok: false, code: "invalid_request", error: "empty request")
        } else {
            let raw = String(decoding: buffer.prefix(Int(readSize)), as: UTF8.self)
            let line = raw.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: true).first.map(String.init) ?? ""
            if let data = line.data(using: .utf8),
               let request = try? JSONDecoder().decode(DaemonControlRequest.self, from: data) {
                response = handler(request)
            } else {
                response = DaemonControlResponse(ok: false, code: "invalid_request", error: "invalid request")
            }
        }

        guard var data = try? JSONEncoder().encode(response) else {
            return
        }
        data.append(0x0A)
        data.withUnsafeBytes {
            _ = send(clientFd, $0.baseAddress, data.count, 0)
        }
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
