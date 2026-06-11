import Foundation
import CicadaCore
import CicadaIPC
import CicadaRelayClient
import CicadaSleepHoldCore
import CicadaSystem

public protocol DaemonManaging {
    func install() throws
    func start() throws
    func stop()
    func restart() throws
    func uninstall()
    func status() -> DaemonStatus
    func logPaths() -> [String]
}

public protocol SentinelAppManaging {
    func install() throws
    func start() throws
    func stop()
    func restart() throws
    func uninstall()
    func status() -> SentinelAppStatus
}

public protocol DaemonControlClienting {
    func shortcutGrantCreate(name: String, commands: [String], ttlMs: Int64) throws -> DaemonControlResponse
    func shortcutGrantList() throws -> DaemonControlResponse
    func shortcutGrantRevoke(grantId: String) throws -> DaemonControlResponse
    func powerAssertionStart() throws -> DaemonControlResponse
    func powerAssertionStop() throws -> DaemonControlResponse
}

public protocol LocalCommandExecuting {
    func execute(command rawCommand: String) -> CommandExecutionResult
}

extension DaemonManager: DaemonManaging {
    public func install() throws {
        try install(sourceBinaryPath: nil)
    }
}

extension SentinelAppManager: SentinelAppManaging {
    public func install() throws {
        try install(sourceAppPath: nil)
    }
}
extension UdsDaemonControlClient: DaemonControlClienting {}
extension MacOSCommandGateway: LocalCommandExecuting {}

public struct CLIResult: Equatable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String

    public init(exitCode: Int32, stdout: String = "", stderr: String = "") {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }
}

public final class CicadaCLI {
    private let configStore: ConfigStore
    private let daemonManager: any DaemonManaging
    private let sentinelAppManager: any SentinelAppManaging
    private let sleepHoldManager: any SleepHoldManaging
    private let daemonControlClient: any DaemonControlClienting
    private let commandExecutor: any LocalCommandExecuting
    private let notifier: any NotifierSending
    private let nativeCapabilities: () -> [String: Any]
    private let runtimeSnapshotLoader: () -> [String: Any]?

    public convenience init() {
        self.init(
            configStore: ConfigStore(),
            daemonManager: DaemonManager(),
            sentinelAppManager: SentinelAppManager(),
            sleepHoldManager: SleepHoldServiceManager(),
            daemonControlClient: UdsDaemonControlClient(),
            commandExecutor: MacOSCommandGateway(),
            notifier: UdsNotifier(),
            nativeCapabilities: { NativeCapabilityReporter().snapshot().dictionary() },
            runtimeSnapshotLoader: Self.loadDaemonRuntimeSnapshot
        )
    }

    public init(
        configStore: ConfigStore,
        daemonManager: any DaemonManaging,
        sentinelAppManager: any SentinelAppManaging,
        sleepHoldManager: any SleepHoldManaging,
        daemonControlClient: any DaemonControlClienting,
        commandExecutor: any LocalCommandExecuting,
        notifier: any NotifierSending = UdsNotifier(),
        nativeCapabilities: @escaping () -> [String: Any],
        runtimeSnapshotLoader: @escaping () -> [String: Any]?
    ) {
        self.configStore = configStore
        self.daemonManager = daemonManager
        self.sentinelAppManager = sentinelAppManager
        self.sleepHoldManager = sleepHoldManager
        self.daemonControlClient = daemonControlClient
        self.commandExecutor = commandExecutor
        self.notifier = notifier
        self.nativeCapabilities = nativeCapabilities
        self.runtimeSnapshotLoader = runtimeSnapshotLoader
    }

    public func run(arguments: [String]) -> CLIResult {
        guard let command = arguments.first else {
            return .success(usageText)
        }

        let args = Array(arguments.dropFirst())
        switch command {
        case "setup":
            return handleSetup(args)
        case "start":
            return handleStart()
        case "stop":
            return handleStop()
        case "restart":
            return handleRestart()
        case "status":
            return handleStatus(args)
        case "shortcut":
            return handleShortcut(args)
        case "run":
            return handleRun(args)
        case "advanced":
            return handleAdvanced(args)
        case "--help", "-h", "help":
            return .success(usageText)
        default:
            return .failure("未知命令: \(command)\n\n\(usageText)")
        }
    }

    private var usageText: String {
        """
        Cicada CLI

        Typical flow:
          cicada setup --relay-url https://relay.example.com
          cicada start
          cicada shortcut create
          cicada status
          cicada run ping

        Commands:
          cicada setup [--relay-url <url>]
          cicada start
          cicada stop
          cicada restart
          cicada status [--json]
          cicada shortcut create|list|revoke
          cicada run <command>

        Troubleshooting:
          cicada advanced --help
        """
    }

    private var advancedUsageText: String {
        """
        Cicada advanced commands

        Commands:
          cicada advanced config get|set|validate|path
          cicada advanced daemon install|start|stop|restart|status|uninstall|logs
          cicada advanced sleep install|uninstall|status|ping|create|extend|terminate
          cicada advanced doctor --json
        """
    }

    private func handleSetup(_ args: [String]) -> CLIResult {
        let relayURL: String?
        do {
            relayURL = try parseOptionalValue(args, flag: "--relay-url")
        } catch {
            return .failure(String(describing: error))
        }

        if let unknown = firstUnknownFlag(args, allowed: ["--relay-url"]) {
            return .failure("未知参数: \(unknown)")
        }

        do {
            let config = configStore.exists() ? try configStore.load() : CicadaConfig.defaultConfig()
            var updated = config
            if let relayURL {
                updated.relayURL = relayURL
            }
            try configStore.save(updated)

            var lines = [
                "Cicada 已准备好配置。",
                "Config: \(configStore.configPath())",
                "Device ID: \(updated.deviceId)",
                "Relay URL: \(updated.relayURL)",
            ]
            if relayURL == nil || updated.relayURL == "https://example.com" {
                lines.append("下一步: cicada setup --relay-url <url>")
            } else {
                lines.append("下一步: cicada start")
            }
            return .success(lines.joined(separator: "\n"))
        } catch {
            return .failure("setup 失败: \(error)")
        }
    }

    private func handleStart() -> CLIResult {
        do {
            _ = try configStore.load()
        } catch {
            return .failure("缺少有效配置。请先运行: cicada setup --relay-url <url>")
        }

        do {
            let daemonStatus = daemonManager.status()
            if !daemonStatus.installed {
                try daemonManager.install()
            }
            try daemonManager.start()

            let sentinelStatus = sentinelAppManager.status()
            if !sentinelStatus.installed {
                try sentinelAppManager.install()
            }
            try sentinelAppManager.start()

            return .success("Cicada 已启动。\n下一步: cicada shortcut create")
        } catch {
            return .failure("start 失败: \(error)")
        }
    }

    private func handleStop() -> CLIResult {
        daemonManager.stop()
        sentinelAppManager.stop()
        return .success("Cicada 已停止。")
    }

    private func handleRestart() -> CLIResult {
        daemonManager.stop()
        sentinelAppManager.stop()
        return handleStart()
    }

    private func handleStatus(_ args: [String]) -> CLIResult {
        let json = args.contains("--json")
        let report = statusReport()
        if json {
            return .success(formatJSON(report))
        }

        let health = report["health"] as? String ?? "unknown"
        let config = report["config"] as? [String: Any] ?? [:]
        let daemon = report["daemon"] as? [String: Any] ?? [:]
        let sentinel = report["sentinel"] as? [String: Any] ?? [:]
        let sleepHold = report["sleepHold"] as? [String: Any] ?? [:]
        let runtime = report["runtime"] as? [String: Any] ?? [:]
        let native = report["nativeCapabilities"] as? [String: Any] ?? [:]
        var lines = [
            "Cicada: \(health)",
            "Config: \(boolText(config["valid"] as? Bool)) \(config["path"] as? String ?? "")",
            "Daemon: \(runningText(daemon))",
            "Sentinel: \(runningText(sentinel))",
            "SleepHold: \(runningText(sleepHold)) \(sleepHold["powerStatus"] as? String ?? "unknown")",
            "Runtime: \(runtime["connectionState"] as? String ?? "unknown")",
            "Bluetooth: \(native["bluetooth"] as? String ?? "unknown")",
            "Accessibility: \(boolText(native["accessibilityTrusted"] as? Bool))",
            "No-sleep: \(boolText(native["noSleepAssertionActive"] as? Bool))",
        ]
        if health == "needs_setup" {
            lines.append("下一步: cicada setup --relay-url <url>")
        } else if health == "stopped" {
            lines.append("下一步: cicada start")
        }
        return .success(lines.joined(separator: "\n"))
    }

    private func handleShortcut(_ args: [String]) -> CLIResult {
        guard let action = args.first else {
            return .failure("用法: cicada shortcut create|list|revoke")
        }

        switch action {
        case "create":
            return handleShortcutCreate(Array(args.dropFirst()))
        case "list":
            return handleShortcutList()
        case "revoke":
            guard args.count >= 2 else {
                return .failure("用法: cicada shortcut revoke <id>")
            }
            return handleShortcutRevoke(args[1])
        default:
            return .failure("用法: cicada shortcut create|list|revoke")
        }
    }

    private func handleShortcutCreate(_ args: [String]) -> CLIResult {
        guard daemonManager.status().running else {
            return .failure("daemon 未运行。请先运行: cicada start")
        }

        var name = "Shortcut"
        var commands = ["ping", "status"]
        var ttl: String?
        var index = 0
        while index < args.count {
            switch args[index] {
            case "--name":
                guard index + 1 < args.count else { return .failure("--name 需要值") }
                name = args[index + 1]
                index += 2
            case "--commands":
                guard index + 1 < args.count else { return .failure("--commands 需要值") }
                commands = ShortcutGrantStore.normalizeCommands(
                    args[index + 1].split(separator: ",").map(String.init)
                )
                index += 2
            case "--ttl":
                guard index + 1 < args.count else { return .failure("--ttl 需要值") }
                ttl = args[index + 1]
                index += 2
            default:
                return .failure("未知参数: \(args[index])")
            }
        }

        do {
            let response = try daemonControlClient.shortcutGrantCreate(
                name: name,
                commands: commands,
                ttlMs: parseDurationMs(ttl)
            )
            guard response.ok, let token = response.shortcutToken, let grant = response.shortcutGrant else {
                return .failure(response.error ?? "shortcut create 失败")
            }
            return .success(shortcutCreateText(token: token, grant: grant))
        } catch {
            return .failure("daemon 未运行或控制通道不可用。请先运行: cicada start")
        }
    }

    private func handleShortcutList() -> CLIResult {
        do {
            let response = try daemonControlClient.shortcutGrantList()
            guard response.ok else {
                return .failure(response.error ?? "shortcut list 失败")
            }
            let grants = response.shortcutGrants ?? []
            if grants.isEmpty {
                return .success("没有 Shortcuts token。")
            }
            return .success(grants.map { "\($0.grantId)  \($0.name)  \($0.tokenPreview)  \($0.allowedCommands.joined(separator: ","))" }.joined(separator: "\n"))
        } catch {
            return .failure("daemon 未运行或控制通道不可用。请先运行: cicada start")
        }
    }

    private func handleShortcutRevoke(_ grantId: String) -> CLIResult {
        do {
            let response = try daemonControlClient.shortcutGrantRevoke(grantId: grantId)
            guard response.ok else {
                return .failure(response.error ?? "shortcut revoke 失败")
            }
            return .success("Shortcuts token 已撤销: \(grantId)")
        } catch {
            return .failure("daemon 未运行或控制通道不可用。请先运行: cicada start")
        }
    }

    private func handleRun(_ args: [String]) -> CLIResult {
        guard let command = args.first else {
            return .failure("用法: cicada run <command>")
        }

        if command == RemoteCommand.caffeinate.rawValue || command == RemoteCommand.decaffeinate.rawValue {
            do {
                let response = command == RemoteCommand.caffeinate.rawValue
                    ? try daemonControlClient.powerAssertionStart()
                    : try daemonControlClient.powerAssertionStop()
                let result = response.commandResult ?? CommandExecutionResult(
                    success: response.ok,
                    message: response.error ?? (response.ok ? "daemon 操作成功" : "daemon 操作失败")
                )
                return cliResult(from: result)
            } catch {
                return .failure("daemon 未运行或控制通道不可用，无法持久执行 \(command)。请先运行: cicada start")
            }
        }

        let result = commandExecutor.execute(command: command)
        if let config = try? configStore.load(), config.showNotifications {
            let level: NotificationLevel = result.success ? .success : .error
            _ = notifier.notifyQuick(
                source: "cli",
                level: level,
                title: NotificationTitles.command(command),
                message: result.message,
                durationMs: 2500
            )
        }
        return cliResult(from: result)
    }

    private func handleAdvanced(_ args: [String]) -> CLIResult {
        guard let action = args.first else {
            return .success(advancedUsageText)
        }
        if action == "--help" || action == "-h" || action == "help" {
            return .success(advancedUsageText)
        }
        let subArgs = Array(args.dropFirst())
        switch action {
        case "config":
            return handleConfig(subArgs)
        case "daemon":
            return handleDaemon(subArgs)
        case "sleep":
            return handleSleep(subArgs)
        case "doctor":
            guard subArgs.isEmpty || subArgs == ["--json"] else {
                return .failure("用法: cicada advanced doctor --json")
            }
            return .success(formatJSON(statusReport()))
        default:
            return .failure("未知 advanced 命令: \(action)\n\n\(advancedUsageText)")
        }
    }

    private func handleConfig(_ args: [String]) -> CLIResult {
        guard let action = args.first else {
            return .failure("用法: cicada advanced config get|set|validate|path")
        }
        do {
            switch action {
            case "get":
                let config = try configStore.load()
                if args.count >= 2 {
                    return .success(try configStore.getValue(key: args[1]))
                }
                return .success(formatJSON(effectiveConfig(config)))
            case "set":
                guard args.count >= 3 else {
                    return .failure("用法: cicada advanced config set <key> <value>")
                }
                try configStore.set(key: args[1], value: args[2])
                return .success("配置已更新: \(args[1])")
            case "validate":
                _ = try configStore.load()
                return .success("配置校验通过")
            case "path":
                return .success(configStore.configPath())
            default:
                return .failure("用法: cicada advanced config get|set|validate|path")
            }
        } catch {
            return .failure("config 操作失败: \(error)")
        }
    }

    private func handleDaemon(_ args: [String]) -> CLIResult {
        guard let action = args.first else {
            return .failure("用法: cicada advanced daemon install|start|stop|restart|status|uninstall|logs")
        }
        do {
            switch action {
            case "install":
                try daemonManager.install()
                return .success("daemon 已安装并启动")
            case "start":
                try daemonManager.start()
                return .success("daemon 已启动")
            case "stop":
                daemonManager.stop()
                return .success("daemon 已停止")
            case "restart":
                try daemonManager.restart()
                return .success("daemon 已重启")
            case "status":
                return .success(formatJSON(daemonObject(daemonManager.status())))
            case "uninstall":
                daemonManager.uninstall()
                return .success("daemon 已卸载")
            case "logs":
                return .success(daemonManager.logPaths().joined(separator: "\n"))
            default:
                return .failure("用法: cicada advanced daemon install|start|stop|restart|status|uninstall|logs")
            }
        } catch {
            return .failure("daemon 操作失败: \(error)")
        }
    }

    private func handleSleep(_ args: [String]) -> CLIResult {
        guard let action = args.first else {
            return .failure("用法: cicada advanced sleep install|uninstall|status|ping|create|extend|terminate")
        }
        do {
            switch action {
            case "install":
                try sleepHoldManager.install()
                return .success("SleepHold service 已安装并启动")
            case "uninstall":
                sleepHoldManager.uninstall()
                return .success("SleepHold service 已卸载")
            case "status":
                return .success(formatJSON(sleepHoldObject(sleepHoldManager.status())))
            case "ping":
                let response = try sleepHoldManager.ping()
                guard response.ok else {
                    return .failure(response.error ?? "SleepHold ping 失败")
                }
                return .success(response.message ?? "pong")
            case "create":
                return sleepResponseResult(try sleepHoldManager.createSession())
            case "extend":
                guard args.count >= 2 else {
                    return .failure("用法: cicada advanced sleep extend <sessionId>")
                }
                return sleepResponseResult(try sleepHoldManager.extendSession(args[1]))
            case "terminate":
                guard args.count >= 2 else {
                    return .failure("用法: cicada advanced sleep terminate <sessionId>")
                }
                return sleepResponseResult(try sleepHoldManager.terminateSession(args[1]))
            default:
                return .failure("用法: cicada advanced sleep install|uninstall|status|ping|create|extend|terminate")
            }
        } catch {
            return .failure("SleepHold 操作失败: \(error)")
        }
    }

    private func statusReport() -> [String: Any] {
        let configExists = configStore.exists()
        let loadedConfig = try? configStore.load()
        let daemonStatus = daemonManager.status()
        let sentinelStatus = sentinelAppManager.status()
        let sleepHoldStatus = sleepHoldManager.status()
        let runtimeSnapshot = runtimeSnapshotLoader()
        var native = nativeCapabilities()
        if let daemonNative = runtimeSnapshot?["nativeCapabilities"] as? [String: Any] {
            native["daemonSnapshot"] = daemonNative
        }

        let configValid = configExists && loadedConfig != nil
        let health: String = {
            if !configValid { return "needs_setup" }
            if !daemonStatus.running { return "stopped" }
            if !sentinelStatus.running { return "degraded" }
            return "ready"
        }()

        var runtime: [String: Any] = [
            "mode": daemonStatus.running ? (loadedConfig?.autoConnect == true ? "connected" : "idle") : "local_only",
            "connectionState": daemonStatus.running ? (loadedConfig?.autoConnect == true ? "connecting" : "idle") : "stopped",
            "effectiveConfig": effectiveConfig(loadedConfig),
        ]
        if daemonStatus.running, let runtimeSnapshot {
            for key in ["mode", "connectionState", "updatedAt"] {
                if let value = runtimeSnapshot[key] {
                    runtime[key] = value
                }
            }
        }

        return [
            "health": health,
            "config": [
                "path": configStore.configPath(),
                "exists": configExists,
                "valid": configValid,
            ],
            "daemon": daemonObject(daemonStatus),
            "sentinel": sentinelObject(sentinelStatus),
            "sleepHold": sleepHoldObject(sleepHoldStatus),
            "runtime": runtime,
            "nativeCapabilities": native,
        ]
    }

    private func shortcutCreateText(token: String, grant: ShortcutGrant) -> String {
        let relayURL = (try? configStore.load().relayURL) ?? "https://relay.example.com"
        return """
        Shortcuts token:
        \(token)

        Grant:
          id: \(grant.grantId)
          commands: \(grant.allowedCommands.joined(separator: ","))
          token preview: \(grant.tokenPreview)

        iOS Shortcuts:
          URL: \(relayURL)/v1/shortcuts/command
          Method: POST
          Header: Authorization: Bearer \(token)
          Header: Content-Type: application/json
          Body: {"device_id":"\(grant.deviceId)","command":"ping","request_id":"shortcut-ping"}
        """
    }

    private func cliResult(from result: CommandExecutionResult) -> CLIResult {
        let body: [String: Any]
        if let data = result.data {
            body = ["success": result.success, "message": result.message, "data": data]
        } else {
            body = ["success": result.success, "message": result.message]
        }
        return CLIResult(exitCode: result.success ? 0 : 1, stdout: formatJSON(body))
    }

    private func effectiveConfig(_ config: CicadaConfig?) -> [String: Any] {
        guard let config else { return [:] }
        return [
            "relayURL": config.relayURL,
            "deviceId": config.deviceId,
            "autoConnect": config.autoConnect,
            "showNotifications": config.showNotifications,
            "enableAutoReconnect": config.enableAutoReconnect,
            "reconnectInterval": config.reconnectInterval,
            "maxReconnectAttempts": config.maxReconnectAttempts,
            "heartbeatInterval": config.heartbeatInterval,
            "connectionTimeout": config.connectionTimeout,
        ]
    }

    private func daemonObject(_ status: DaemonStatus) -> [String: Any] {
        [
            "installed": status.installed,
            "running": status.running,
            "plistPath": status.plistPath,
            "binaryPath": status.binaryPath,
        ]
    }

    private func sentinelObject(_ status: SentinelAppStatus) -> [String: Any] {
        [
            "installed": status.installed,
            "running": status.running,
            "plistPath": status.plistPath,
            "appPath": status.appPath,
            "socketPath": status.socketPath,
            "notifierSocketPath": status.notifierSocketPath,
            "notifierSocketReady": status.notifierSocketReady,
            "controlSocketPath": status.sentinelSocketPath,
            "controlSocketReady": status.sentinelSocketReady,
        ]
    }

    private func sleepHoldObject(_ status: SleepHoldServiceStatus) -> [String: Any] {
        status.dictionary()
    }

    private func sleepResponseResult(_ response: SleepHoldControlResponse) -> CLIResult {
        guard response.ok else {
            return .failure(response.error ?? "SleepHold 操作失败")
        }
        return .success(formatJSON(sleepResponseObject(response)))
    }

    private func sleepResponseObject(_ response: SleepHoldControlResponse) -> [String: Any] {
        var object: [String: Any] = ["ok": response.ok]
        if let message = response.message { object["message"] = message }
        if let sessionId = response.sessionId { object["sessionId"] = sessionId }
        if let status = response.status { object["status"] = status.rawValue }
        if let activeSessions = response.activeSessions { object["activeSessions"] = activeSessions }
        return object
    }

    private func parseDurationMs(_ raw: String?) -> Int64 {
        guard let raw, !raw.isEmpty else {
            return ShortcutGrantStore.defaultTtlMs
        }
        if let days = Int64(String(raw.dropLast())), raw.hasSuffix("d") {
            return days * 24 * 60 * 60 * 1000
        }
        if let hours = Int64(String(raw.dropLast())), raw.hasSuffix("h") {
            return hours * 60 * 60 * 1000
        }
        if let minutes = Int64(String(raw.dropLast())), raw.hasSuffix("m") {
            return minutes * 60 * 1000
        }
        return Int64(raw) ?? ShortcutGrantStore.defaultTtlMs
    }

    private func parseOptionalValue(_ args: [String], flag: String) throws -> String? {
        guard let index = args.firstIndex(of: flag) else { return nil }
        guard index + 1 < args.count else {
            throw CLIArgumentError.message("\(flag) 需要值")
        }
        return args[index + 1]
    }

    private func firstUnknownFlag(_ args: [String], allowed: Set<String>) -> String? {
        var index = 0
        while index < args.count {
            let item = args[index]
            if item.hasPrefix("--") {
                if !allowed.contains(item) { return item }
                index += 2
            } else {
                return item
            }
        }
        return nil
    }

    private func formatJSON(_ object: Any) -> String {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return text
    }

    private func boolText(_ value: Bool?) -> String {
        value == true ? "yes" : "no"
    }

    private func runningText(_ object: [String: Any]) -> String {
        guard object["installed"] as? Bool == true else { return "not installed" }
        return object["running"] as? Bool == true ? "running" : "stopped"
    }

    private static func loadDaemonRuntimeSnapshot() -> [String: Any]? {
        guard FileManager.default.fileExists(atPath: RuntimePaths.daemonStatePath),
              let data = try? Data(contentsOf: URL(fileURLWithPath: RuntimePaths.daemonStatePath)),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return object
    }
}

private enum CLIArgumentError: Error, CustomStringConvertible {
    case message(String)

    var description: String {
        switch self {
        case let .message(message):
            return message
        }
    }
}

private extension CLIResult {
    static func success(_ stdout: String) -> CLIResult {
        CLIResult(exitCode: 0, stdout: stdout)
    }

    static func failure(_ stderr: String) -> CLIResult {
        CLIResult(exitCode: 1, stderr: stderr)
    }
}
