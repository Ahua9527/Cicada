import Foundation

public enum RuntimePaths {
    public static let home = FileManager.default.homeDirectoryForCurrentUser.path
    public static let cicadaHome = home + "/.cicada"
    public static let runDir = cicadaHome + "/run"
    public static let binDir = cicadaHome + "/bin"
    public static let daemonDir = cicadaHome + "/daemon"
    public static let applicationsDir = "/Applications"

    public static let cliBinaryName = "cicada"
    public static let daemonBinaryName = "cicada-agent"
    public static let sleepHoldBinaryName = "cicada-sleephold"
    public static let sentinelAppName = "Cicada.app"
    public static let legacySentinelAppName = "Sentry.app"

    public static let configPath = cicadaHome + "/config.json"
    public static let agentIdentityPath = cicadaHome + "/agent.identity.json"
    public static let shortcutGrantPath = cicadaHome + "/shortcut-grants.json"
    public static let notifierSocketPath = runDir + "/notifier.sock"
    public static let daemonSocketPath = runDir + "/daemon.sock"
    public static let sentinelSocketPath = runDir + "/sentinel.sock"
    public static let sentinelAppPath = applicationsDir + "/" + sentinelAppName
    public static let legacySentinelAppPath = cicadaHome + "/apps/" + legacySentinelAppName
    public static let sentinelHelpersDir = sentinelAppPath + "/Contents/Helpers"
    public static let bundledCLIHelperPath = sentinelHelpersDir + "/" + cliBinaryName
    public static let bundledDaemonHelperPath = sentinelHelpersDir + "/" + daemonBinaryName
    public static let bundledSleepHoldHelperPath = sentinelHelpersDir + "/" + sleepHoldBinaryName
    public static let cliBinaryPath = bundledCLIHelperPath
    public static let daemonBinaryPath = bundledDaemonHelperPath
    public static let sleepHoldStagingBinaryPath = bundledSleepHoldHelperPath
    public static let sleepHoldSocketPath = runDir + "/sleephold.sock"
    public static let sleepHoldBinaryPath = bundledSleepHoldHelperPath

    public static let daemonLabel = "com.cicada.agent"
    public static let sentinelLabel = "com.cicada.sentinel"
    public static let sleepHoldLabel = "com.cicada.sleephold"

    public static let daemonPlistPath = home + "/Library/LaunchAgents/com.cicada.agent.plist"
    public static let sentinelPlistPath = home + "/Library/LaunchAgents/com.cicada.sentinel.plist"
    public static let sleepHoldPlistPath = "/Library/LaunchDaemons/com.cicada.sleephold.plist"

    public static let daemonStdoutPath = cicadaHome + "/daemon.stdout.log"
    public static let daemonStderrPath = cicadaHome + "/daemon.stderr.log"
    public static let daemonLogPath = cicadaHome + "/daemon.log"
    public static let daemonStatePath = cicadaHome + "/daemon.state.json"
    public static let sentinelStdoutPath = cicadaHome + "/sentinel.stdout.log"
    public static let sentinelStderrPath = cicadaHome + "/sentinel.stderr.log"
    public static let sleepHoldStdoutPath = cicadaHome + "/sleephold.stdout.log"
    public static let sleepHoldStderrPath = cicadaHome + "/sleephold.stderr.log"

    public static func helperPath(name: String, inApp appPath: String = sentinelAppPath) -> String {
        appPath + "/Contents/Helpers/" + name
    }

    public static func currentSentryAppPath(
        executablePath: String = CommandLine.arguments.first ?? "",
        bundlePath: String = Bundle.main.bundlePath,
        currentDirectoryPath: String = FileManager.default.currentDirectoryPath
    ) -> String? {
        if bundlePath.hasSuffix(".app") {
            return bundlePath
        }
        let absoluteExecutablePath: String
        if executablePath.hasPrefix("/") {
            absoluteExecutablePath = executablePath
        } else {
            absoluteExecutablePath = currentDirectoryPath + "/" + executablePath
        }
        return appBundlePath(containing: absoluteExecutablePath)
    }

    public static func bundledHelperSourceCandidates(
        named name: String,
        currentAppPath: String? = currentSentryAppPath()
    ) -> [String] {
        var candidates: [String] = []
        if let currentAppPath {
            candidates.append(helperPath(name: name, inApp: currentAppPath))
        }
        candidates.append(helperPath(name: name, inApp: sentinelAppPath))
        return uniquePaths(candidates)
    }

    public static func swiftBuildBinaryCandidates(
        named name: String,
        currentDirectoryPath: String = FileManager.default.currentDirectoryPath
    ) -> [String] {
        uniquePaths([
            currentDirectoryPath + "/swift/.build/release/" + name,
            currentDirectoryPath + "/.build/release/" + name,
            currentDirectoryPath + "/apps/agent/swift/.build/release/" + name,
        ])
    }

    public static func daemonSourceBinaryCandidates(
        currentDirectoryPath: String = FileManager.default.currentDirectoryPath,
        currentAppPath: String? = currentSentryAppPath()
    ) -> [String] {
        bundledHelperSourceCandidates(named: daemonBinaryName, currentAppPath: currentAppPath)
            + swiftBuildBinaryCandidates(named: daemonBinaryName, currentDirectoryPath: currentDirectoryPath)
    }

    public static func sleepHoldSourceBinaryCandidates(
        currentDirectoryPath: String = FileManager.default.currentDirectoryPath,
        currentAppPath: String? = currentSentryAppPath()
    ) -> [String] {
        bundledHelperSourceCandidates(named: sleepHoldBinaryName, currentAppPath: currentAppPath)
            + swiftBuildBinaryCandidates(named: sleepHoldBinaryName, currentDirectoryPath: currentDirectoryPath)
    }

    public static func firstExistingPath(
        in candidates: [String],
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) -> String? {
        candidates.first { fileExists($0) }
    }

    public static func resolveDaemonSourceBinaryPath(
        explicitPath: String? = nil,
        currentDirectoryPath: String = FileManager.default.currentDirectoryPath,
        currentAppPath: String? = currentSentryAppPath(),
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) -> String {
        if let explicitPath, !explicitPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return explicitPath
        }
        let candidates = daemonSourceBinaryCandidates(
            currentDirectoryPath: currentDirectoryPath,
            currentAppPath: currentAppPath
        )
        return firstExistingPath(in: candidates, fileExists: fileExists) ?? candidates[0]
    }

    public static func resolveSleepHoldSourceBinaryPath(
        currentDirectoryPath: String = FileManager.default.currentDirectoryPath,
        currentAppPath: String? = currentSentryAppPath(),
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) -> String {
        let candidates = sleepHoldSourceBinaryCandidates(
            currentDirectoryPath: currentDirectoryPath,
            currentAppPath: currentAppPath
        )
        return firstExistingPath(in: candidates, fileExists: fileExists) ?? candidates[0]
    }

    private static func appBundlePath(containing path: String) -> String? {
        let marker = ".app/Contents/"
        guard let range = path.range(of: marker) else {
            return nil
        }
        return String(path[..<range.lowerBound]) + ".app"
    }

    private static func uniquePaths(_ paths: [String]) -> [String] {
        var seen = Set<String>()
        return paths.filter { seen.insert($0).inserted }
    }
}
