import Foundation

public enum RuntimePaths {
    public static let home = FileManager.default.homeDirectoryForCurrentUser.path
    public static let cicadaHome = home + "/.cicada"
    public static let runDir = cicadaHome + "/run"
    public static let binDir = cicadaHome + "/bin"
    public static let daemonDir = cicadaHome + "/daemon"

    public static let configPath = cicadaHome + "/config.json"
    public static let agentIdentityPath = cicadaHome + "/agent.identity.json"
    public static let shortcutGrantPath = cicadaHome + "/shortcut-grants.json"
    public static let notifierSocketPath = runDir + "/notifier.sock"
    public static let daemonSocketPath = runDir + "/daemon.sock"
    public static let sentinelSocketPath = runDir + "/sentinel.sock"
    public static let daemonBinaryPath = binDir + "/cicada-agent"
    public static let sentinelAppPath = cicadaHome + "/apps/Sentry.app"
    public static let sleepHoldStagingBinaryPath = binDir + "/cicada-sleephold"
    public static let sleepHoldSocketPath = runDir + "/sleephold.sock"
    public static let sleepHoldBinaryPath = "/usr/local/sbin/cicada-sleephold"

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
}
