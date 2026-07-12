import Darwin
import Foundation
import CicadaCore

public struct SentinelAppStatus {
    public let installed: Bool
    public let running: Bool
    public let plistPath: String
    public let appPath: String
    public let socketPath: String
    public let notifierSocketPath: String
    public let sentinelSocketPath: String
    public let notifierSocketReady: Bool
    public let sentinelSocketReady: Bool

    public init(
        installed: Bool,
        running: Bool,
        plistPath: String,
        appPath: String,
        socketPath: String,
        sentinelSocketPath: String = RuntimePaths.sentinelSocketPath,
        notifierSocketReady: Bool = false,
        sentinelSocketReady: Bool = false
    ) {
        self.installed = installed
        self.running = running
        self.plistPath = plistPath
        self.appPath = appPath
        self.socketPath = socketPath
        self.notifierSocketPath = socketPath
        self.sentinelSocketPath = sentinelSocketPath
        self.notifierSocketReady = notifierSocketReady
        self.sentinelSocketReady = sentinelSocketReady
    }
}

struct SentinelAppRuntimePaths {
    let runDir: String
    let sentinelLabel: String
    let sentinelAppPath: String
    let legacySentinelAppPath: String
    let sentinelExecutableName: String
    let sentinelPlistPath: String
    let sentinelStdoutPath: String
    let sentinelStderrPath: String
    let notifierSocketPath: String
    let sentinelSocketPath: String
    let daemonSocketPath: String
    let notchDropDirectoryPath: String
    let legacyNotifierLabel: String
    let legacyNotifierPlistPath: String
    let legacyNotifierBinaryPath: String

    static let live = SentinelAppRuntimePaths(
        runDir: RuntimePaths.runDir,
        sentinelLabel: RuntimePaths.sentinelLabel,
        sentinelAppPath: RuntimePaths.sentinelAppPath,
        legacySentinelAppPath: RuntimePaths.legacySentinelAppPath,
        sentinelExecutableName: "Cicada",
        sentinelPlistPath: RuntimePaths.sentinelPlistPath,
        sentinelStdoutPath: RuntimePaths.sentinelStdoutPath,
        sentinelStderrPath: RuntimePaths.sentinelStderrPath,
        notifierSocketPath: RuntimePaths.notifierSocketPath,
        sentinelSocketPath: RuntimePaths.sentinelSocketPath,
        daemonSocketPath: RuntimePaths.daemonSocketPath,
        notchDropDirectoryPath: RuntimePaths.cicadaHome + "/notchdrop",
        legacyNotifierLabel: "com.cicada.notifier",
        legacyNotifierPlistPath: RuntimePaths.home + "/Library/LaunchAgents/com.cicada.notifier.plist",
        legacyNotifierBinaryPath: RuntimePaths.binDir + "/cicada-notifier"
    )
}

public final class SentinelAppManager {
    private let runner: any ProcessRunning
    private let fm = FileManager.default
    private let paths: SentinelAppRuntimePaths
    private let waitForNotifierAttempts: Int
    private let waitIntervalMicros: useconds_t

    public init(runner: any ProcessRunning = ProcessRunner()) {
        self.runner = runner
        self.paths = .live
        self.waitForNotifierAttempts = 20
        self.waitIntervalMicros = 100_000
    }

    init(
        runner: any ProcessRunning,
        paths: SentinelAppRuntimePaths,
        waitForNotifierAttempts: Int = 20,
        waitIntervalMicros: useconds_t = 100_000
    ) {
        self.runner = runner
        self.paths = paths
        self.waitForNotifierAttempts = waitForNotifierAttempts
        self.waitIntervalMicros = waitIntervalMicros
    }

    public func install(sourceAppPath: String? = nil) throws {
        cleanupLegacyNotifier()
        let source = resolveSourceAppPath(sourceAppPath)
        guard fm.fileExists(atPath: source) else {
            throw CicadaError.io("Sentinel app 不存在: \(source)")
        }

        try fm.createDirectory(atPath: paths.runDir, withIntermediateDirectories: true)
        try fm.createDirectory(atPath: (paths.sentinelAppPath as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try fm.createDirectory(atPath: (paths.sentinelPlistPath as NSString).deletingLastPathComponent, withIntermediateDirectories: true)

        if source != paths.sentinelAppPath {
            if fm.fileExists(atPath: paths.sentinelAppPath) {
                try fm.removeItem(atPath: paths.sentinelAppPath)
            }
            try fm.copyItem(atPath: source, toPath: paths.sentinelAppPath)
        }
        try removeLegacySentinelAppIfNeeded()
        try normalizeInstalledAppBundle()

        let plist = sentinelPlist(appPath: paths.sentinelAppPath)
        try plist.write(toFile: paths.sentinelPlistPath, atomically: true, encoding: .utf8)

        _ = runner.run("/bin/launchctl", args: ["unload", paths.sentinelPlistPath], timeoutMs: 5_000)
        let loadResult = runner.run("/bin/launchctl", args: ["load", paths.sentinelPlistPath], timeoutMs: 5_000)
        if loadResult.code != 0 {
            throw CicadaError.command("Sentinel load 失败: \(loadResult.stderr)")
        }
    }

    public func start() throws {
        cleanupLegacyNotifier()
        _ = runner.run("/bin/launchctl", args: ["load", paths.sentinelPlistPath], timeoutMs: 5_000)
        if !startAgentWithRetry() {
            throw CicadaError.command("Sentinel start 失败")
        }
    }

    public func stop() {
        _ = runner.run("/bin/launchctl", args: ["stop", paths.sentinelLabel], timeoutMs: 5_000)
        waitForSentinelSocketsToClose()
        _ = runner.run("/bin/launchctl", args: ["stop", paths.legacyNotifierLabel], timeoutMs: 5_000)
    }

    public func restart() throws {
        stop()
        try start()
    }

    public func uninstall() {
        _ = runner.run("/bin/launchctl", args: ["unload", paths.sentinelPlistPath], timeoutMs: 5_000)
        _ = try? fm.removeItem(atPath: paths.sentinelPlistPath)
        cleanupLegacyNotifier()
    }

    public func ensureStarted() -> Bool {
        let current = status()
        if !current.installed {
            return false
        }

        if current.notifierSocketReady {
            return true
        }

        do {
            try start()
        } catch {
            Logger.warn("SentinelAppManager", "failed to start Sentinel", data: ["error": String(describing: error)])
            return false
        }

        for _ in 0 ..< waitForNotifierAttempts {
            usleep(waitIntervalMicros)
            if isSocketReady(paths.notifierSocketPath) {
                return true
            }
        }

        return false
    }

    public func status() -> SentinelAppStatus {
        let installed = fm.fileExists(atPath: paths.sentinelPlistPath)
            && fm.fileExists(atPath: executablePath(appPath: paths.sentinelAppPath))
        let listResult = runner.run("/bin/launchctl", args: ["list"], timeoutMs: 5_000)
        let listed = listResult.code == 0 && listResult.stdout.contains(paths.sentinelLabel)
        let notifierSocketReady = isSocketReady(paths.notifierSocketPath)
        let sentinelSocketReady = isSocketReady(paths.sentinelSocketPath)

        return SentinelAppStatus(
            installed: installed,
            running: listed && notifierSocketReady && sentinelSocketReady,
            plistPath: paths.sentinelPlistPath,
            appPath: paths.sentinelAppPath,
            socketPath: paths.notifierSocketPath,
            sentinelSocketPath: paths.sentinelSocketPath,
            notifierSocketReady: notifierSocketReady,
            sentinelSocketReady: sentinelSocketReady
        )
    }

    private func resolveSourceAppPath(_ explicitPath: String?) -> String {
        if let explicitPath, !explicitPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return explicitPath
        }
        let productsDir = FileManager.default.currentDirectoryPath
            + "/native/sentinel-app/.build/DerivedData/Build/Products/Release"
        let candidates = [
            productsDir + "/" + RuntimePaths.sentinelAppName,
            paths.sentinelAppPath,
        ]
        for candidate in candidates where fm.fileExists(atPath: candidate) {
            return candidate
        }
        return candidates[0]
    }

    private func executablePath(appPath: String) -> String {
        appPath + "/Contents/MacOS/" + paths.sentinelExecutableName
    }

    private func normalizeInstalledAppBundle() throws {
        let contents = URL(fileURLWithPath: paths.sentinelAppPath)
            .appendingPathComponent("Contents", isDirectory: true)
        let executable = contents
            .appendingPathComponent("MacOS", isDirectory: true)
            .appendingPathComponent(paths.sentinelExecutableName)
        let legacyExecutable = contents
            .appendingPathComponent("MacOS", isDirectory: true)
            .appendingPathComponent("Sentry")

        if !fm.fileExists(atPath: executable.path), fm.fileExists(atPath: legacyExecutable.path) {
            try fm.copyItem(at: legacyExecutable, to: executable)
        }
        _ = chmod(executable.path, 0o755)
        try normalizeInfoPlist(at: contents.appendingPathComponent("Info.plist"))
    }

    private func normalizeInfoPlist(at url: URL) throws {
        guard fm.fileExists(atPath: url.path) else {
            return
        }

        let data = try Data(contentsOf: url)
        var format = PropertyListSerialization.PropertyListFormat.xml
        guard var plist = try PropertyListSerialization.propertyList(
            from: data,
            options: .mutableContainers,
            format: &format
        ) as? [String: Any] else {
            return
        }

        var changed = false
        if plist["CFBundleExecutable"] as? String != paths.sentinelExecutableName {
            plist["CFBundleExecutable"] = paths.sentinelExecutableName
            changed = true
        }
        if plist["CFBundleDisplayName"] as? String != "Cicada" {
            plist["CFBundleDisplayName"] = "Cicada"
            changed = true
        }
        guard changed else {
            return
        }

        let outputFormat: PropertyListSerialization.PropertyListFormat = format == .binary ? .binary : .xml
        let output = try PropertyListSerialization.data(
            fromPropertyList: plist,
            format: outputFormat,
            options: 0
        )
        try output.write(to: url, options: .atomic)
    }

    private func sentinelPlist(appPath: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
          <key>Label</key>
          <string>\(paths.sentinelLabel)</string>
          <key>ProgramArguments</key>
          <array>
            <string>\(executablePath(appPath: appPath))</string>
          </array>
          <key>RunAtLoad</key>
          <true/>
          <key>KeepAlive</key>
          <dict>
            <key>Crashed</key>
            <true/>
          </dict>
          <key>StandardOutPath</key>
          <string>\(paths.sentinelStdoutPath)</string>
          <key>StandardErrorPath</key>
          <string>\(paths.sentinelStderrPath)</string>
          <key>EnvironmentVariables</key>
          <dict>
            <key>CICADA_DAEMON_SOCKET</key>
            <string>\(paths.daemonSocketPath)</string>
            <key>CICADA_NOTCHDROP_DIR</key>
            <string>\(paths.notchDropDirectoryPath)</string>
            <key>CICADA_NOTIFIER_SOCKET</key>
            <string>\(paths.notifierSocketPath)</string>
            <key>CICADA_SENTINEL_SOCKET</key>
            <string>\(paths.sentinelSocketPath)</string>
          </dict>
        </dict>
        </plist>
        """
    }

    private func cleanupLegacyNotifier() {
        _ = runner.run("/bin/launchctl", args: ["stop", paths.legacyNotifierLabel], timeoutMs: 5_000)
        _ = runner.run("/bin/launchctl", args: ["unload", paths.legacyNotifierPlistPath], timeoutMs: 5_000)
        _ = try? fm.removeItem(atPath: paths.legacyNotifierPlistPath)
        _ = try? fm.removeItem(atPath: paths.legacyNotifierBinaryPath)
    }

    private func removeLegacySentinelAppIfNeeded() throws {
        guard paths.legacySentinelAppPath != paths.sentinelAppPath,
              fm.fileExists(atPath: paths.legacySentinelAppPath)
        else {
            return
        }
        try fm.removeItem(atPath: paths.legacySentinelAppPath)
    }

    private func startAgentWithRetry() -> Bool {
        for _ in 0 ..< 10 {
            let startResult = runner.run("/bin/launchctl", args: ["start", paths.sentinelLabel], timeoutMs: 5_000)
            if startResult.code == 0 || isListed() {
                return true
            }
            usleep(100_000)
        }
        return isListed()
    }

    private func isListed() -> Bool {
        let listResult = runner.run("/bin/launchctl", args: ["list"], timeoutMs: 5_000)
        return listResult.code == 0 && listResult.stdout.contains(paths.sentinelLabel)
    }

    private func waitForSentinelSocketsToClose() {
        for _ in 0 ..< waitForNotifierAttempts {
            if !isSocketReady(paths.notifierSocketPath), !isSocketReady(paths.sentinelSocketPath) {
                return
            }
            usleep(waitIntervalMicros)
        }
    }

    private func isSocketReady(_ path: String) -> Bool {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let maxPathLength = MemoryLayout.size(ofValue: addr.sun_path)
        guard path.utf8.count < maxPathLength else { return false }

        withUnsafeMutableBytes(of: &addr.sun_path) { buffer in
            buffer.initializeMemory(as: CChar.self, repeating: 0)
            _ = path.withCString { source in
                strncpy(buffer.baseAddress?.assumingMemoryBound(to: CChar.self), source, maxPathLength - 1)
            }
        }

        return withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        } == 0
    }
}
