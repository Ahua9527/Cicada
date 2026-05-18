import Foundation
import CicadaCore
import CicadaIPC
import CicadaSystem

private func printUsage() {
    print(
        """
        Cicada CLI (Swift)

        Usage:
          cicada setup init
          cicada config init|get|set|validate|path
          cicada daemon install|start|stop|restart|status|uninstall|logs
          cicada notifier install|start|stop|restart|status|uninstall|test
          cicada exec <command>
          cicada command run <command>
          cicada doctor
        """
    )
}

private func printJSON(_ object: Any) {
    guard JSONSerialization.isValidJSONObject(object),
          let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
          let text = String(data: data, encoding: .utf8) else {
        print("{}")
        return
    }
    print(text)
}

private func maskApiKey(_ raw: String) -> String {
    if raw.isEmpty { return "" }
    if raw.count <= 8 { return String(repeating: "*", count: raw.count) }
    let prefix = raw.prefix(4)
    let suffix = raw.suffix(4)
    return "\(prefix)****\(suffix)"
}

private func loadDaemonRuntimeSnapshot() -> [String: Any]? {
    guard FileManager.default.fileExists(atPath: RuntimePaths.daemonStatePath),
          let data = try? Data(contentsOf: URL(fileURLWithPath: RuntimePaths.daemonStatePath)),
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        return nil
    }
    return object
}

private func buildEffectiveConfig(_ config: CicadaConfig?) -> [String: Any] {
    guard let config else {
        return [:]
    }

    return [
        "relayURL": config.relayURL,
        "deviceId": config.deviceId,
        "apiKey": maskApiKey(config.apiKey),
        "autoConnect": config.autoConnect,
        "showNotifications": config.showNotifications,
        "enableAutoReconnect": config.enableAutoReconnect,
        "reconnectInterval": config.reconnectInterval,
        "maxReconnectAttempts": config.maxReconnectAttempts,
        "heartbeatInterval": config.heartbeatInterval,
        "connectionTimeout": config.connectionTimeout,
    ]
}

@discardableResult
private func handleSetup(_ args: [String], configStore: ConfigStore) -> Int32 {
    guard let action = args.first else {
        fputs("❌ 用法: cicada setup init\n", stderr)
        return 1
    }

    switch action {
    case "init":
        do {
            let config = try configStore.initializeDefault()
            print("✅ 配置已初始化: \(configStore.configPath())")
            print("Device ID: \(config.deviceId)")
            print("请修改 relayURL 与 apiKey 后再启动 daemon。")
            return 0
        } catch {
            fputs("❌ 初始化配置失败: \(error)\n", stderr)
            return 1
        }
    default:
        fputs("❌ 未知 setup 子命令\n", stderr)
        return 1
    }
}

@discardableResult
private func handleConfig(_ args: [String], configStore: ConfigStore) -> Int32 {
    guard let action = args.first else {
        fputs("❌ 未知 config 子命令\n", stderr)
        return 1
    }

    switch action {
    case "init":
        return handleSetup(["init"], configStore: configStore)
    case "path":
        print(configStore.configPath())
        return 0
    case "get":
        do {
            let config = try configStore.load()
            if args.count >= 2 {
                let key = args[1]
                let value = try configStore.getValue(key: key)
                if key == "apiKey" {
                    print(maskApiKey(value))
                } else {
                    print(value)
                }
                return 0
            }

            let object: [String: Any] = [
                "relayURL": config.relayURL,
                "deviceId": config.deviceId,
                "apiKey": maskApiKey(config.apiKey),
                "autoConnect": config.autoConnect,
                "showNotifications": config.showNotifications,
                "enableAutoReconnect": config.enableAutoReconnect,
                "reconnectInterval": config.reconnectInterval,
                "maxReconnectAttempts": config.maxReconnectAttempts,
                "heartbeatInterval": config.heartbeatInterval,
                "connectionTimeout": config.connectionTimeout,
            ]
            printJSON(object)
            return 0
        } catch {
            fputs("❌ 读取配置失败: \(error)\n", stderr)
            return 1
        }
    case "set":
        guard args.count >= 3 else {
            fputs("❌ 用法: cicada config set <key> <value>\n", stderr)
            return 1
        }

        do {
            try configStore.set(key: args[1], value: args[2])
            print("✅ 配置已更新: \(args[1])")
            return 0
        } catch {
            fputs("❌ 更新配置失败: \(error)\n", stderr)
            return 1
        }
    case "validate":
        do {
            _ = try configStore.load()
            print("✅ 配置校验通过")
            return 0
        } catch {
            fputs("❌ 配置校验失败: \(error)\n", stderr)
            return 1
        }
    default:
        fputs("❌ 未知 config 子命令\n", stderr)
        return 1
    }
}

@discardableResult
private func handleDaemon(_ args: [String]) -> Int32 {
    guard let action = args.first else {
        fputs("❌ 未知 daemon 子命令\n", stderr)
        return 1
    }

    let manager = DaemonManager()

    do {
        switch action {
        case "install":
            try manager.install()
            print("✅ daemon 已安装并启动")
            return 0
        case "start":
            try manager.start()
            print("✅ daemon 已启动")
            return 0
        case "stop":
            manager.stop()
            print("✅ daemon 已停止")
            return 0
        case "restart":
            try manager.restart()
            print("✅ daemon 已重启")
            return 0
        case "status":
            let status = manager.status()
            printJSON([
                "installed": status.installed,
                "running": status.running,
                "plistPath": status.plistPath,
                "binaryPath": status.binaryPath,
            ])
            return status.running ? 0 : 1
        case "uninstall":
            manager.uninstall()
            print("✅ daemon 已卸载")
            return 0
        case "logs":
            print(manager.logPaths().joined(separator: "\n"))
            return 0
        default:
            fputs("❌ 未知 daemon 子命令\n", stderr)
            return 1
        }
    } catch {
        fputs("❌ daemon 操作失败: \(error)\n", stderr)
        return 1
    }
}

@discardableResult
private func handleNotifier(_ args: [String]) -> Int32 {
    guard let action = args.first else {
        fputs("❌ 未知 notifier 子命令\n", stderr)
        return 1
    }

    let manager = NotifierManager()

    do {
        switch action {
        case "install":
            try manager.install()
            print("✅ notifier 已安装")
            return 0
        case "start":
            try manager.start()
            print("✅ notifier 已启动")
            return 0
        case "stop":
            manager.stop()
            print("✅ notifier 已停止")
            return 0
        case "restart":
            try manager.restart()
            print("✅ notifier 已重启")
            return 0
        case "status":
            let status = manager.status()
            printJSON([
                "installed": status.installed,
                "running": status.running,
                "plistPath": status.plistPath,
                "binaryPath": status.binaryPath,
                "socketPath": status.socketPath,
            ])
            return status.running ? 0 : 1
        case "uninstall":
            manager.uninstall()
            print("✅ notifier 已卸载")
            return 0
        case "test":
            let notifier = UdsNotifier()
            let response = notifier.notifyQuick(
                source: "cli",
                level: .info,
                title: "Cicada 通知测试",
                message: "dynamic island 通知链路正常",
                durationMs: 2500
            )
            if response.ok {
                print("✅ notifier 测试成功")
                return 0
            }

            fputs("❌ notifier 测试失败: \(response.code ?? "") \(response.error ?? "")\n", stderr)
            return 1
        default:
            fputs("❌ 未知 notifier 子命令\n", stderr)
            return 1
        }
    } catch {
        fputs("❌ notifier 操作失败: \(error)\n", stderr)
        return 1
    }
}

@discardableResult
private func handleExec(_ args: [String], configStore: ConfigStore) -> Int32 {
    guard let command = args.first else {
        fputs("❌ 用法: cicada exec <command>\n", stderr)
        return 1
    }

    let gateway = MacOSCommandGateway()
    let result = gateway.execute(command: command)

    if let config = try? configStore.load(), config.showNotifications {
        let notifier = UdsNotifier()
        let level: NotificationLevel = result.success ? .success : .error
        _ = notifier.notifyQuick(
            source: "cli",
            level: level,
            title: NotificationTitles.command(command),
            message: result.message,
            durationMs: 2500
        )
    }

    if let data = result.data {
        printJSON(["success": result.success, "message": result.message, "data": data])
    } else {
        printJSON(["success": result.success, "message": result.message])
    }

    return result.success ? 0 : 1
}

@discardableResult
private func handleDoctor(configStore: ConfigStore) -> Int32 {
    var ok = true

    let configExists = configStore.exists()
    if !configExists {
        ok = false
    }

    let loadedConfig = try? configStore.load()
    var configValid = false
    if configExists, loadedConfig != nil {
        configValid = true
    } else if configExists {
        ok = false
    }

    let daemonStatus = DaemonManager().status()
    let notifierStatus = NotifierManager().status()
    let runtimeSnapshot = loadDaemonRuntimeSnapshot()

    let derivedMode: String = {
        guard daemonStatus.running else { return "local_only" }
        guard let config = loadedConfig else { return "unknown" }
        return config.autoConnect ? "connected" : "idle"
    }()

    let derivedConnectionState: String = {
        guard daemonStatus.running else { return "stopped" }
        guard let config = loadedConfig else { return "unknown" }
        return config.autoConnect ? "connecting" : "idle"
    }()

    var runtime: [String: Any] = [
        "mode": derivedMode,
        "connectionState": derivedConnectionState,
        "effectiveConfig": buildEffectiveConfig(loadedConfig),
    ]

    if daemonStatus.running, let runtimeSnapshot {
        if let mode = runtimeSnapshot["mode"] {
            runtime["mode"] = mode
        }
        if let state = runtimeSnapshot["connectionState"] {
            runtime["connectionState"] = state
        }
        if let updatedAt = runtimeSnapshot["updatedAt"] {
            runtime["updatedAt"] = updatedAt
        }
    }

    let report: [String: Any] = [
        "config": [
            "path": configStore.configPath(),
            "exists": configExists,
            "valid": configValid,
        ],
        "daemon": [
            "installed": daemonStatus.installed,
            "running": daemonStatus.running,
            "plistPath": daemonStatus.plistPath,
            "binaryPath": daemonStatus.binaryPath,
        ],
        "notifier": [
            "installed": notifierStatus.installed,
            "running": notifierStatus.running,
            "plistPath": notifierStatus.plistPath,
            "binaryPath": notifierStatus.binaryPath,
            "socketPath": notifierStatus.socketPath,
        ],
        "runtime": runtime,
    ]

    printJSON(report)
    return ok ? 0 : 1
}

let args = Array(CommandLine.arguments.dropFirst())
let configStore = ConfigStore()

if args.isEmpty {
    printUsage()
    exit(0)
}

let command = args[0]
let subArgs = Array(args.dropFirst())
let exitCode: Int32

switch command {
case "setup":
    exitCode = handleSetup(subArgs, configStore: configStore)
case "config":
    exitCode = handleConfig(subArgs, configStore: configStore)
case "daemon":
    exitCode = handleDaemon(subArgs)
case "notifier":
    exitCode = handleNotifier(subArgs)
case "exec":
    exitCode = handleExec(subArgs, configStore: configStore)
case "command":
    if subArgs.first == "run" {
        exitCode = handleExec(Array(subArgs.dropFirst()), configStore: configStore)
    } else {
        fputs("❌ 用法: cicada command run <command>\n", stderr)
        exitCode = 1
    }
case "doctor":
    exitCode = handleDoctor(configStore: configStore)
default:
    printUsage()
    exitCode = 1
}

exit(exitCode)
