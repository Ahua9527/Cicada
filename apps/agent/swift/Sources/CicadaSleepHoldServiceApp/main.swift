import Darwin
import Foundation
import CicadaSleepHoldCore

struct SleepHoldServiceOptions {
    let socketPath: String
    let ownerUID: uid_t
    let ownerGID: gid_t
}

final class SleepHoldControlServer {
    private let socketPath: String
    private let ownerUID: uid_t
    private let ownerGID: gid_t
    private let manager: SleepHoldSessionManager
    private var fd: Int32 = -1
    private var running = false

    init(socketPath: String, ownerUID: uid_t, ownerGID: gid_t, manager: SleepHoldSessionManager) {
        self.socketPath = socketPath
        self.ownerUID = ownerUID
        self.ownerGID = ownerGID
        self.manager = manager
    }

    func start() throws {
        let parent = URL(fileURLWithPath: socketPath).deletingLastPathComponent().path
        try FileManager.default.createDirectory(atPath: parent, withIntermediateDirectories: true)
        _ = unlink(socketPath)

        let socketFd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard socketFd >= 0 else {
            throw ServerError.message("socket create failed")
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
            throw ServerError.message(String(cString: strerror(errno)))
        }

        guard listen(socketFd, 8) == 0 else {
            close(socketFd)
            throw ServerError.message(String(cString: strerror(errno)))
        }

        _ = chown(socketPath, ownerUID, ownerGID)
        _ = chmod(socketPath, 0o600)
        fd = socketFd
        running = true
        manager.startCleanupTimer()
        DispatchQueue(label: "com.cicada.sleephold.server").async { [weak self] in
            self?.acceptLoop()
        }
    }

    func stop() {
        running = false
        manager.stopCleanupTimer()
        manager.clearSessions()
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
        let response: SleepHoldControlResponse

        if readSize <= 0 {
            response = .init(ok: false, code: "invalid_request", error: "empty request")
        } else {
            let raw = String(decoding: buffer.prefix(Int(readSize)), as: UTF8.self)
            let line = raw.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: true).first.map(String.init) ?? ""
            if let data = line.data(using: .utf8),
               let request = try? JSONDecoder().decode(SleepHoldControlRequest.self, from: data) {
                response = handle(request)
            } else {
                response = .init(ok: false, code: "invalid_request", error: "invalid request")
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

    private func handle(_ request: SleepHoldControlRequest) -> SleepHoldControlResponse {
        switch request.action {
        case .ping:
            return .init(ok: true, message: "pong")
        case .status:
            manager.cleanupExpiredSessions()
            return .init(
                ok: true,
                status: manager.currentPowerStatus(),
                activeSessions: manager.activeSessionsCount()
            )
        case .sessionCreate:
            let sessionId = manager.createSession()
            return .init(
                ok: true,
                sessionId: sessionId,
                status: manager.currentPowerStatus(),
                activeSessions: manager.activeSessionsCount()
            )
        case .sessionExtend:
            guard let sessionId = request.sessionId else {
                return .init(ok: false, code: "session_id_required", error: "sessionId is required")
            }
            guard manager.extendSession(sessionId) else {
                return .init(ok: false, code: "session_not_found", error: "Session not found")
            }
            return .init(
                ok: true,
                sessionId: sessionId,
                status: manager.currentPowerStatus(),
                activeSessions: manager.activeSessionsCount()
            )
        case .sessionTerminate:
            guard let sessionId = request.sessionId else {
                return .init(ok: false, code: "session_id_required", error: "sessionId is required")
            }
            guard manager.terminateSession(sessionId) else {
                return .init(ok: false, code: "session_not_found", error: "Session not found")
            }
            return .init(
                ok: true,
                sessionId: sessionId,
                status: manager.currentPowerStatus(),
                activeSessions: manager.activeSessionsCount()
            )
        }
    }
}

private enum ServerError: Error, CustomStringConvertible {
    case message(String)

    var description: String {
        switch self {
        case let .message(message): return message
        }
    }
}

private func parseOptions(_ args: [String]) throws -> SleepHoldServiceOptions {
    var socketPath: String?
    var uid: uid_t?
    var gid: gid_t?
    var index = 0

    while index < args.count {
        switch args[index] {
        case "--socket":
            guard index + 1 < args.count else { throw ServerError.message("--socket requires a value") }
            socketPath = args[index + 1]
            index += 2
        case "--uid":
            guard index + 1 < args.count, let value = UInt32(args[index + 1]) else {
                throw ServerError.message("--uid requires a numeric value")
            }
            uid = uid_t(value)
            index += 2
        case "--gid":
            guard index + 1 < args.count, let value = UInt32(args[index + 1]) else {
                throw ServerError.message("--gid requires a numeric value")
            }
            gid = gid_t(value)
            index += 2
        default:
            throw ServerError.message("unknown argument: \(args[index])")
        }
    }

    guard let socketPath, let uid, let gid else {
        throw ServerError.message("--socket, --uid and --gid are required")
    }

    return SleepHoldServiceOptions(socketPath: socketPath, ownerUID: uid, ownerGID: gid)
}

private func copySocketPath(_ path: String, into addr: inout sockaddr_un) throws {
    let maxPathLength = MemoryLayout.size(ofValue: addr.sun_path)
    if path.utf8.count >= maxPathLength {
        throw ServerError.message("socket path is too long")
    }

    withUnsafeMutableBytes(of: &addr.sun_path) { buffer in
        buffer.initializeMemory(as: CChar.self, repeating: 0)
        _ = path.withCString { src in
            strncpy(buffer.baseAddress?.assumingMemoryBound(to: CChar.self), src, maxPathLength - 1)
        }
    }
}

guard getuid() == 0 else {
    fputs("cicada-sleephold must run as root\n", stderr)
    exit(1)
}

do {
    let options = try parseOptions(Array(CommandLine.arguments.dropFirst()))
    let manager = SleepHoldSessionManager()
    let server = SleepHoldControlServer(
        socketPath: options.socketPath,
        ownerUID: options.ownerUID,
        ownerGID: options.ownerGID,
        manager: manager
    )
    try server.start()

    signal(SIGINT, SIG_IGN)
    signal(SIGTERM, SIG_IGN)
    let queue = DispatchQueue(label: "com.cicada.sleephold.signal")
    let term = DispatchSource.makeSignalSource(signal: SIGTERM, queue: queue)
    term.setEventHandler {
        server.stop()
        exit(0)
    }
    term.resume()
    let int = DispatchSource.makeSignalSource(signal: SIGINT, queue: queue)
    int.setEventHandler {
        server.stop()
        exit(0)
    }
    int.resume()

    RunLoop.main.run()
} catch {
    fputs("cicada-sleephold failed: \(error)\n", stderr)
    exit(1)
}
