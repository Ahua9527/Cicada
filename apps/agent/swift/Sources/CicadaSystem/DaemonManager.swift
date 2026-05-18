import Foundation
import CicadaCore

public struct DaemonStatus {
    public let installed: Bool
    public let running: Bool
    public let plistPath: String
    public let binaryPath: String

    public init(installed: Bool, running: Bool, plistPath: String, binaryPath: String) {
        self.installed = installed
        self.running = running
        self.plistPath = plistPath
        self.binaryPath = binaryPath
    }
}

public final class DaemonManager {
    private let runner: ProcessRunner
    private let fm = FileManager.default

    public init(runner: ProcessRunner = ProcessRunner()) {
        self.runner = runner
    }

    public func install(sourceBinaryPath: String? = nil) throws {
        guard fm.fileExists(atPath: RuntimePaths.configPath) else {
            throw CicadaError.io("缺少配置文件: \(RuntimePaths.configPath)。请先执行 cicada config init")
        }

        let source = resolveSourceBinaryPath(sourceBinaryPath)
        guard fm.fileExists(atPath: source) else {
            throw CicadaError.io("daemon 二进制不存在: \(source)")
        }

        try fm.createDirectory(atPath: RuntimePaths.binDir, withIntermediateDirectories: true)
        if source != RuntimePaths.daemonBinaryPath {
            if fm.fileExists(atPath: RuntimePaths.daemonBinaryPath) {
                try fm.removeItem(atPath: RuntimePaths.daemonBinaryPath)
            }
            try fm.copyItem(atPath: source, toPath: RuntimePaths.daemonBinaryPath)
        }
        _ = chmod(RuntimePaths.daemonBinaryPath, 0o755)

        let legacyScriptPath = RuntimePaths.cicadaHome + "/cicada-agent.js"
        if fm.fileExists(atPath: legacyScriptPath) {
            try? fm.removeItem(atPath: legacyScriptPath)
        }

        let plist = daemonPlist(binaryPath: RuntimePaths.daemonBinaryPath)
        try plist.write(toFile: RuntimePaths.daemonPlistPath, atomically: true, encoding: .utf8)

        _ = runner.run("/bin/launchctl", args: ["unload", RuntimePaths.daemonPlistPath], timeoutMs: 5_000)
        let load = runner.run("/bin/launchctl", args: ["load", RuntimePaths.daemonPlistPath], timeoutMs: 5_000)
        if load.code != 0 {
            throw CicadaError.command("daemon load 失败: \(load.stderr)")
        }

        if !startAgentWithRetry() {
            throw CicadaError.command("daemon start 失败")
        }
    }

    public func start() throws {
        _ = runner.run("/bin/launchctl", args: ["load", RuntimePaths.daemonPlistPath], timeoutMs: 5_000)
        if !startAgentWithRetry() {
            throw CicadaError.command("daemon start 失败")
        }
    }

    public func stop() {
        _ = runner.run("/bin/launchctl", args: ["stop", RuntimePaths.daemonLabel], timeoutMs: 5_000)
    }

    public func restart() throws {
        stop()
        try start()
    }

    public func uninstall() {
        _ = runner.run("/bin/launchctl", args: ["unload", RuntimePaths.daemonPlistPath], timeoutMs: 5_000)
        _ = try? fm.removeItem(atPath: RuntimePaths.daemonPlistPath)
    }

    public func status() -> DaemonStatus {
        let installed = fm.fileExists(atPath: RuntimePaths.daemonPlistPath) && fm.fileExists(atPath: RuntimePaths.daemonBinaryPath)
        let list = runner.run("/bin/launchctl", args: ["list"], timeoutMs: 5_000)
        let running = list.code == 0 && list.stdout.contains(RuntimePaths.daemonLabel)

        return DaemonStatus(
            installed: installed,
            running: running,
            plistPath: RuntimePaths.daemonPlistPath,
            binaryPath: RuntimePaths.daemonBinaryPath
        )
    }

    public func logPaths() -> [String] {
        [RuntimePaths.daemonLogPath, RuntimePaths.daemonStdoutPath, RuntimePaths.daemonStderrPath]
    }

    private func resolveSourceBinaryPath(_ explicitPath: String?) -> String {
        if let explicitPath, !explicitPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return explicitPath
        }
        let buildPath = FileManager.default.currentDirectoryPath + "/swift/.build/release/cicada-agent"
        if FileManager.default.fileExists(atPath: buildPath) {
            return buildPath
        }
        if FileManager.default.fileExists(atPath: RuntimePaths.daemonBinaryPath) {
            return RuntimePaths.daemonBinaryPath
        }
        return buildPath
    }

    private func daemonPlist(binaryPath: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
          <key>Label</key>
          <string>\(RuntimePaths.daemonLabel)</string>
          <key>ProgramArguments</key>
          <array>
            <string>\(binaryPath)</string>
          </array>
          <key>RunAtLoad</key>
          <true/>
          <key>KeepAlive</key>
          <true/>
          <key>WorkingDirectory</key>
          <string>\(RuntimePaths.cicadaHome)</string>
          <key>StandardOutPath</key>
          <string>\(RuntimePaths.daemonStdoutPath)</string>
          <key>StandardErrorPath</key>
          <string>\(RuntimePaths.daemonStderrPath)</string>
        </dict>
        </plist>
        """
    }

    private func startAgentWithRetry() -> Bool {
        for _ in 0 ..< 10 {
            let start = runner.run("/bin/launchctl", args: ["start", RuntimePaths.daemonLabel], timeoutMs: 5_000)
            if start.code == 0 || isListed() {
                return true
            }
            usleep(100_000)
        }
        return isListed()
    }

    private func isListed() -> Bool {
        let list = runner.run("/bin/launchctl", args: ["list"], timeoutMs: 5_000)
        return list.code == 0 && list.stdout.contains(RuntimePaths.daemonLabel)
    }
}
