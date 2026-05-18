import Foundation
import CicadaCore

public struct NotifierStatus {
    public let installed: Bool
    public let running: Bool
    public let plistPath: String
    public let binaryPath: String
    public let socketPath: String

    public init(installed: Bool, running: Bool, plistPath: String, binaryPath: String, socketPath: String) {
        self.installed = installed
        self.running = running
        self.plistPath = plistPath
        self.binaryPath = binaryPath
        self.socketPath = socketPath
    }
}

public final class NotifierManager {
    private let runner: ProcessRunner
    private let fm = FileManager.default

    public init(runner: ProcessRunner = ProcessRunner()) {
        self.runner = runner
    }

    public func install(sourceBinaryPath: String? = nil) throws {
        let source = resolveSourceBinaryPath(sourceBinaryPath)
        guard fm.fileExists(atPath: source) else {
            throw CicadaError.io("notifier 二进制不存在: \(source)")
        }

        try fm.createDirectory(atPath: RuntimePaths.binDir, withIntermediateDirectories: true)
        try fm.createDirectory(atPath: RuntimePaths.runDir, withIntermediateDirectories: true)

        if source != RuntimePaths.notifierBinaryPath {
            if fm.fileExists(atPath: RuntimePaths.notifierBinaryPath) {
                try fm.removeItem(atPath: RuntimePaths.notifierBinaryPath)
            }
            try fm.copyItem(atPath: source, toPath: RuntimePaths.notifierBinaryPath)
        }
        _ = chmod(RuntimePaths.notifierBinaryPath, 0o755)

        let plist = notifierPlist(binaryPath: RuntimePaths.notifierBinaryPath)
        try plist.write(toFile: RuntimePaths.notifierPlistPath, atomically: true, encoding: .utf8)

        _ = runner.run("/bin/launchctl", args: ["unload", RuntimePaths.notifierPlistPath], timeoutMs: 5_000)
        let loadResult = runner.run("/bin/launchctl", args: ["load", RuntimePaths.notifierPlistPath], timeoutMs: 5_000)
        if loadResult.code != 0 {
            throw CicadaError.command("notifier load 失败: \(loadResult.stderr)")
        }
    }

    public func start() throws {
        _ = runner.run("/bin/launchctl", args: ["load", RuntimePaths.notifierPlistPath], timeoutMs: 5_000)
        if !startAgentWithRetry() {
            throw CicadaError.command("notifier start 失败")
        }
    }

    public func stop() {
        _ = runner.run("/bin/launchctl", args: ["stop", RuntimePaths.notifierLabel], timeoutMs: 5_000)
    }

    public func restart() throws {
        stop()
        try start()
    }

    public func uninstall() {
        _ = runner.run("/bin/launchctl", args: ["unload", RuntimePaths.notifierPlistPath], timeoutMs: 5_000)
        _ = try? fm.removeItem(atPath: RuntimePaths.notifierPlistPath)
    }

    public func ensureStarted() -> Bool {
        let current = status()
        if !current.installed {
            return false
        }

        if current.running {
            return true
        }

        do {
            try start()
        } catch {
            Logger.warn("NotifierManager", "failed to start notifier", data: ["error": String(describing: error)])
            return false
        }

        for _ in 0 ..< 20 {
            usleep(100_000)
            if FileManager.default.fileExists(atPath: RuntimePaths.notifierSocketPath) {
                return true
            }
        }

        return false
    }

    public func status() -> NotifierStatus {
        let installed = fm.fileExists(atPath: RuntimePaths.notifierPlistPath) && fm.fileExists(atPath: RuntimePaths.notifierBinaryPath)
        let listResult = runner.run("/bin/launchctl", args: ["list"], timeoutMs: 5_000)
        let listed = listResult.code == 0 && listResult.stdout.contains(RuntimePaths.notifierLabel)
        let socketReady = fm.fileExists(atPath: RuntimePaths.notifierSocketPath)

        return NotifierStatus(
            installed: installed,
            running: listed && socketReady,
            plistPath: RuntimePaths.notifierPlistPath,
            binaryPath: RuntimePaths.notifierBinaryPath,
            socketPath: RuntimePaths.notifierSocketPath
        )
    }

    private func resolveSourceBinaryPath(_ explicitPath: String?) -> String {
        if let explicitPath, !explicitPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return explicitPath
        }
        let buildPath = FileManager.default.currentDirectoryPath + "/native/notification-agent/.build/release/cicada-notifier"
        if FileManager.default.fileExists(atPath: buildPath) {
            return buildPath
        }
        if FileManager.default.fileExists(atPath: RuntimePaths.notifierBinaryPath) {
            return RuntimePaths.notifierBinaryPath
        }
        return buildPath
    }

    private func notifierPlist(binaryPath: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
          <key>Label</key>
          <string>\(RuntimePaths.notifierLabel)</string>
          <key>ProgramArguments</key>
          <array>
            <string>\(binaryPath)</string>
          </array>
          <key>RunAtLoad</key>
          <true/>
          <key>KeepAlive</key>
          <true/>
          <key>StandardOutPath</key>
          <string>\(RuntimePaths.notifierStdoutPath)</string>
          <key>StandardErrorPath</key>
          <string>\(RuntimePaths.notifierStderrPath)</string>
          <key>EnvironmentVariables</key>
          <dict>
            <key>CICADA_NOTIFIER_SOCKET</key>
            <string>\(RuntimePaths.notifierSocketPath)</string>
          </dict>
        </dict>
        </plist>
        """
    }

    private func startAgentWithRetry() -> Bool {
        for _ in 0 ..< 10 {
            let startResult = runner.run("/bin/launchctl", args: ["start", RuntimePaths.notifierLabel], timeoutMs: 5_000)
            if startResult.code == 0 || isListed() {
                return true
            }
            usleep(100_000)
        }
        return isListed()
    }

    private func isListed() -> Bool {
        let listResult = runner.run("/bin/launchctl", args: ["list"], timeoutMs: 5_000)
        return listResult.code == 0 && listResult.stdout.contains(RuntimePaths.notifierLabel)
    }
}
