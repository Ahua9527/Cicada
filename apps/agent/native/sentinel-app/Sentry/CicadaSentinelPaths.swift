import Foundation

enum CicadaSentinelPaths {
    static func daemonSocketPath(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: String = FileManager.default.homeDirectoryForCurrentUser.path
    ) -> String {
        environment["CICADA_DAEMON_SOCKET"] ?? runPath("daemon.sock", environment: environment, homeDirectory: homeDirectory)
    }

    static func notifierSocketPath(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: String = FileManager.default.homeDirectoryForCurrentUser.path
    ) -> String {
        environment["CICADA_NOTIFIER_SOCKET"] ?? runPath("notifier.sock", environment: environment, homeDirectory: homeDirectory)
    }

    static func sentinelSocketPath(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: String = FileManager.default.homeDirectoryForCurrentUser.path
    ) -> String {
        environment["CICADA_SENTINEL_SOCKET"] ?? runPath("sentinel.sock", environment: environment, homeDirectory: homeDirectory)
    }

    static func configPath(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: String = FileManager.default.homeDirectoryForCurrentUser.path
    ) -> String {
        URL(fileURLWithPath: cicadaHome(environment: environment, homeDirectory: homeDirectory), isDirectory: true)
            .appendingPathComponent("config.json")
            .path
    }

    static func sentryConfigPath(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: String = FileManager.default.homeDirectoryForCurrentUser.path
    ) -> String {
        URL(fileURLWithPath: cicadaHome(environment: environment, homeDirectory: homeDirectory), isDirectory: true)
            .appendingPathComponent("sentry-config.json")
            .path
    }

    static func notchDropDirectory(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: String = FileManager.default.homeDirectoryForCurrentUser.path
    ) -> URL {
        if let configured = environment["CICADA_NOTCHDROP_DIR"],
           !configured.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return URL(fileURLWithPath: configured, isDirectory: true)
        }
        return URL(fileURLWithPath: cicadaHome(environment: environment, homeDirectory: homeDirectory), isDirectory: true)
            .appendingPathComponent("notchdrop", isDirectory: true)
    }

    private static func runPath(
        _ name: String,
        environment: [String: String],
        homeDirectory: String
    ) -> String {
        URL(fileURLWithPath: cicadaHome(environment: environment, homeDirectory: homeDirectory), isDirectory: true)
            .appendingPathComponent("run", isDirectory: true)
            .appendingPathComponent(name)
            .path
    }

    private static func cicadaHome(environment: [String: String], homeDirectory: String) -> String {
        if let configured = environment["CICADA_HOME"],
           !configured.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return configured
        }
        return URL(fileURLWithPath: homeDirectory, isDirectory: true)
            .appendingPathComponent(".cicada", isDirectory: true)
            .path
    }
}
