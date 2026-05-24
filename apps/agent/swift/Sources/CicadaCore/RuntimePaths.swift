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
    public static let notifierBinaryPath = binDir + "/cicada-notifier"
    public static let daemonBinaryPath = binDir + "/cicada-agent"

    public static let daemonLabel = "com.cicada.agent"
    public static let notifierLabel = "com.cicada.notifier"

    public static let daemonPlistPath = home + "/Library/LaunchAgents/com.cicada.agent.plist"
    public static let notifierPlistPath = home + "/Library/LaunchAgents/com.cicada.notifier.plist"

    public static let daemonStdoutPath = cicadaHome + "/daemon.stdout.log"
    public static let daemonStderrPath = cicadaHome + "/daemon.stderr.log"
    public static let daemonLogPath = cicadaHome + "/daemon.log"
    public static let daemonStatePath = cicadaHome + "/daemon.state.json"
    public static let notifierStdoutPath = cicadaHome + "/notifier.stdout.log"
    public static let notifierStderrPath = cicadaHome + "/notifier.stderr.log"
}
