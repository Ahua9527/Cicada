import Darwin
import Foundation
import CicadaCore
import CicadaSleepHoldCore

public struct SleepHoldServiceStatus {
    public let installed: Bool
    public let running: Bool
    public let plistPath: String
    public let binaryPath: String
    public let socketPath: String
    public let powerStatus: SleepHoldPowerStatus
    public let activeSessions: Int

    public init(
        installed: Bool,
        running: Bool,
        plistPath: String,
        binaryPath: String,
        socketPath: String,
        powerStatus: SleepHoldPowerStatus,
        activeSessions: Int
    ) {
        self.installed = installed
        self.running = running
        self.plistPath = plistPath
        self.binaryPath = binaryPath
        self.socketPath = socketPath
        self.powerStatus = powerStatus
        self.activeSessions = activeSessions
    }

    public func dictionary() -> [String: Any] {
        [
            "installed": installed,
            "running": running,
            "plistPath": plistPath,
            "binaryPath": binaryPath,
            "socketPath": socketPath,
            "powerStatus": powerStatus.rawValue,
            "activeSessions": activeSessions,
        ]
    }
}

public protocol SleepHoldManaging {
    func install() throws
    func uninstall()
    func status() -> SleepHoldServiceStatus
    func ping() throws -> SleepHoldControlResponse
    func createSession() throws -> SleepHoldControlResponse
    func extendSession(_ sessionId: String) throws -> SleepHoldControlResponse
    func terminateSession(_ sessionId: String) throws -> SleepHoldControlResponse
}

public enum SleepHoldControlError: Error, CustomStringConvertible {
    case unavailable(String)
    case invalidPayload
    case socketPathTooLong

    public var description: String {
        switch self {
        case let .unavailable(message): return message
        case .invalidPayload: return "invalid sleephold payload"
        case .socketPathTooLong: return "sleephold socket path is too long"
        }
    }
}

public final class SleepHoldControlClient {
    private let socketPath: String
    private let timeoutMs: Int

    public init(socketPath: String = RuntimePaths.sleepHoldSocketPath, timeoutMs: Int = 1000) {
        self.socketPath = socketPath
        self.timeoutMs = timeoutMs
    }

    public func ping() throws -> SleepHoldControlResponse {
        try request(.init(action: .ping))
    }

    public func status() throws -> SleepHoldControlResponse {
        try request(.init(action: .status))
    }

    public func createSession() throws -> SleepHoldControlResponse {
        try request(.init(action: .sessionCreate))
    }

    public func extendSession(_ sessionId: String) throws -> SleepHoldControlResponse {
        try request(.init(action: .sessionExtend, sessionId: sessionId))
    }

    public func terminateSession(_ sessionId: String) throws -> SleepHoldControlResponse {
        try request(.init(action: .sessionTerminate, sessionId: sessionId))
    }

    public func request(_ request: SleepHoldControlRequest) throws -> SleepHoldControlResponse {
        var payload = try JSONEncoder().encode(request)
        payload.append(0x0A)

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        if fd < 0 {
            throw SleepHoldControlError.unavailable("sleephold socket create failed")
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
            throw SleepHoldControlError.unavailable(String(cString: strerror(errno)))
        }

        let sent = payload.withUnsafeBytes {
            send(fd, $0.baseAddress, payload.count, 0)
        }
        guard sent > 0 else {
            throw SleepHoldControlError.unavailable("sleephold send failed")
        }

        var buffer = [UInt8](repeating: 0, count: 8192)
        let readSize = recv(fd, &buffer, buffer.count, 0)
        guard readSize > 0 else {
            throw SleepHoldControlError.unavailable("sleephold timeout")
        }

        let raw = String(decoding: buffer.prefix(Int(readSize)), as: UTF8.self)
        let line = raw.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: true).first.map(String.init) ?? ""
        guard let data = line.data(using: .utf8) else {
            throw SleepHoldControlError.invalidPayload
        }
        return try JSONDecoder().decode(SleepHoldControlResponse.self, from: data)
    }
}

public final class SleepHoldServiceManager: SleepHoldManaging {
    private let runner: ProcessRunner
    private let client: SleepHoldControlClient
    private let fm = FileManager.default

    public init(runner: ProcessRunner = ProcessRunner(), client: SleepHoldControlClient = SleepHoldControlClient()) {
        self.runner = runner
        self.client = client
    }

    public func install() throws {
        try fm.createDirectory(atPath: RuntimePaths.cicadaHome, withIntermediateDirectories: true)
        try fm.createDirectory(atPath: RuntimePaths.runDir, withIntermediateDirectories: true)

        let binaryPath = RuntimePaths.sleepHoldBinaryPath
        guard fm.fileExists(atPath: binaryPath) else {
            throw CicadaError.io("SleepHold helper 不存在: \(binaryPath)。请先将 Cicada.app 安装到 /Applications")
        }

        let plistPath = RuntimePaths.runDir + "/com.cicada.sleephold.plist"
        try sleepHoldPlist().write(toFile: plistPath, atomically: true, encoding: .utf8)
        try runSudo(["/bin/cp", "-f", plistPath, RuntimePaths.sleepHoldPlistPath])
        try runSudo(["/usr/sbin/chown", "root:wheel", RuntimePaths.sleepHoldPlistPath])
        try runSudo(["/bin/chmod", "644", RuntimePaths.sleepHoldPlistPath])

        _ = runner.run("/usr/bin/sudo", args: ["/bin/launchctl", "unload", RuntimePaths.sleepHoldPlistPath], timeoutMs: 5_000)
        try runSudo(["/bin/launchctl", "load", RuntimePaths.sleepHoldPlistPath])
    }

    public func uninstall() {
        _ = runner.run("/usr/bin/sudo", args: ["/bin/launchctl", "unload", RuntimePaths.sleepHoldPlistPath], timeoutMs: 5_000)
        _ = runner.run("/usr/bin/sudo", args: ["/bin/rm", "-f", RuntimePaths.sleepHoldPlistPath], timeoutMs: 5_000)
        _ = unlink(RuntimePaths.sleepHoldSocketPath)
    }

    public func status() -> SleepHoldServiceStatus {
        let installed = fm.fileExists(atPath: RuntimePaths.sleepHoldPlistPath)
            && fm.fileExists(atPath: RuntimePaths.sleepHoldBinaryPath)
        let response = try? client.status()
        let running = response?.ok == true
        return SleepHoldServiceStatus(
            installed: installed,
            running: running,
            plistPath: RuntimePaths.sleepHoldPlistPath,
            binaryPath: RuntimePaths.sleepHoldBinaryPath,
            socketPath: RuntimePaths.sleepHoldSocketPath,
            powerStatus: response?.status ?? .unknown,
            activeSessions: response?.activeSessions ?? 0
        )
    }

    public func ping() throws -> SleepHoldControlResponse {
        try client.ping()
    }

    public func createSession() throws -> SleepHoldControlResponse {
        try client.createSession()
    }

    public func extendSession(_ sessionId: String) throws -> SleepHoldControlResponse {
        try client.extendSession(sessionId)
    }

    public func terminateSession(_ sessionId: String) throws -> SleepHoldControlResponse {
        try client.terminateSession(sessionId)
    }

    private func sleepHoldPlist() -> String {
        let uid = getuid()
        let gid = getgid()
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
          <key>Label</key>
          <string>\(RuntimePaths.sleepHoldLabel)</string>
          <key>ProgramArguments</key>
          <array>
            <string>\(RuntimePaths.sleepHoldBinaryPath)</string>
            <string>--socket</string>
            <string>\(RuntimePaths.sleepHoldSocketPath)</string>
            <string>--uid</string>
            <string>\(uid)</string>
            <string>--gid</string>
            <string>\(gid)</string>
          </array>
          <key>RunAtLoad</key>
          <true/>
          <key>KeepAlive</key>
          <dict>
            <key>Crashed</key>
            <true/>
          </dict>
          <key>StandardOutPath</key>
          <string>\(RuntimePaths.sleepHoldStdoutPath)</string>
          <key>StandardErrorPath</key>
          <string>\(RuntimePaths.sleepHoldStderrPath)</string>
        </dict>
        </plist>
        """
    }

    private func runSudo(_ args: [String]) throws {
        let result = runner.run("/usr/bin/sudo", args: args, timeoutMs: 30_000)
        guard result.code == 0 else {
            throw CicadaError.command(result.stderr.isEmpty ? result.stdout : result.stderr)
        }
    }
}

struct SleepHoldLeaseState: Equatable {
    let status: String
    let sessionId: String?
}

protocol SleepHoldLeasing: AnyObject {
    var isActive: Bool { get }
    func start() -> Result<SleepHoldLeaseState, NativeCommandError>
    func stop() -> Result<SleepHoldLeaseState, NativeCommandError>
}

final class SleepHoldLeaseController: SleepHoldLeasing {
    private let client: SleepHoldControlClient
    private let lock = NSLock()
    private var sessionId: String?
    private var timer: DispatchSourceTimer?

    init(client: SleepHoldControlClient = SleepHoldControlClient()) {
        self.client = client
    }

    var isActive: Bool {
        lock.lock()
        defer { lock.unlock() }
        return sessionId != nil
    }

    func start() -> Result<SleepHoldLeaseState, NativeCommandError> {
        lock.lock()
        if let sessionId {
            lock.unlock()
            return extendKnownSession(sessionId)
        }
        lock.unlock()

        do {
            let response = try client.createSession()
            guard response.ok, let newSessionId = response.sessionId else {
                return .failure(.message(response.error ?? "SleepHold session create failed"))
            }
            lock.lock()
            sessionId = newSessionId
            scheduleRefreshLocked()
            lock.unlock()
            return .success(SleepHoldLeaseState(status: "active", sessionId: newSessionId))
        } catch {
            return .failure(.message(String(describing: error)))
        }
    }

    func stop() -> Result<SleepHoldLeaseState, NativeCommandError> {
        lock.lock()
        let current = sessionId
        sessionId = nil
        let currentTimer = timer
        timer = nil
        lock.unlock()
        currentTimer?.cancel()

        guard let current else {
            return .success(SleepHoldLeaseState(status: "stopped", sessionId: nil))
        }

        do {
            let response = try client.terminateSession(current)
            guard response.ok else {
                return .failure(.message(response.error ?? "SleepHold session terminate failed"))
            }
            return .success(SleepHoldLeaseState(status: "stopped", sessionId: current))
        } catch {
            return .failure(.message(String(describing: error)))
        }
    }

    private func extendKnownSession(_ sessionId: String) -> Result<SleepHoldLeaseState, NativeCommandError> {
        do {
            let response = try client.extendSession(sessionId)
            guard response.ok else {
                return .failure(.message(response.error ?? "SleepHold session extend failed"))
            }
            return .success(SleepHoldLeaseState(status: "active", sessionId: sessionId))
        } catch {
            return .failure(.message(String(describing: error)))
        }
    }

    private func scheduleRefreshLocked() {
        timer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "com.cicada.sleephold.lease"))
        timer.schedule(deadline: .now() + 15, repeating: 15)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            self.lock.lock()
            let current = self.sessionId
            self.lock.unlock()
            guard let current else { return }
            _ = try? self.client.extendSession(current)
        }
        timer.resume()
        self.timer = timer
    }
}

private func copySocketPath(_ path: String, into addr: inout sockaddr_un) throws {
    let maxPathLength = MemoryLayout.size(ofValue: addr.sun_path)
    if path.utf8.count >= maxPathLength {
        throw SleepHoldControlError.socketPathTooLong
    }

    withUnsafeMutableBytes(of: &addr.sun_path) { buffer in
        buffer.initializeMemory(as: CChar.self, repeating: 0)
        _ = path.withCString { src in
            strncpy(buffer.baseAddress?.assumingMemoryBound(to: CChar.self), src, maxPathLength - 1)
        }
    }
}
