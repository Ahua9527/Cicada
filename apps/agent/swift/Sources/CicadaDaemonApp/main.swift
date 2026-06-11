import Foundation
import CicadaCore
import CicadaIPC
import CicadaRelayClient
import CicadaSystem

final class DaemonRuntime {
    private var service: RelayDaemonService?
    private var controlServer: UdsDaemonControlServer?

    func start() -> Int32 {
        let store = ConfigStore()
        let config: CicadaConfig

        do {
            config = try store.load()
        } catch {
            Logger.error("Daemon", "启动失败: 配置读取错误", data: ["error": String(describing: error)])
            return 1
        }

        let gateway = MacOSCommandGateway()
        let notifier = UdsNotifier(autoStart: true)
        let relayService = RelayDaemonService(config: config, commandGateway: gateway, notifier: notifier)
        service = relayService
        relayService.start()
        startControlServer(relayService)

        setupSignalHandlers()
        Logger.info(
            "Daemon",
            "cicada-agent started",
            data: [
                "deviceId": config.deviceId,
                "mode": relayService.mode,
                "connectionState": relayService.connectionState.rawValue,
            ]
        )
        RunLoop.main.run()

        return 0
    }

    private func startControlServer(_ relayService: RelayDaemonService) {
        let server = UdsDaemonControlServer()
        do {
            try server.start { request in
                switch request.action {
                case .shortcutGrantCreate:
                    do {
                        let result = try relayService.createShortcutGrant(
                            name: request.name ?? "Shortcut",
                            commands: request.commands ?? ["ping", "status"],
                            ttlMs: request.ttlMs ?? ShortcutGrantStore.defaultTtlMs
                        )
                        return DaemonControlResponse(
                            ok: true,
                            shortcutToken: result.token,
                            shortcutGrant: result.grant
                        )
                    } catch {
                        return DaemonControlResponse(
                            ok: false,
                            code: "shortcut_grant_create_failed",
                            error: String(describing: error)
                        )
                    }
                case .shortcutGrantList:
                    do {
                        return DaemonControlResponse(ok: true, shortcutGrants: try relayService.listShortcutGrants())
                    } catch {
                        return DaemonControlResponse(
                            ok: false,
                            code: "shortcut_grant_list_failed",
                            error: String(describing: error)
                        )
                    }
                case .shortcutGrantRevoke:
                    guard let grantId = request.grantId else {
                        return DaemonControlResponse(
                            ok: false,
                            code: "shortcut_grant_id_required",
                            error: "grantId is required"
                        )
                    }
                    do {
                        let grant = try relayService.revokeShortcutGrant(grantId: grantId)
                        return DaemonControlResponse(ok: true, shortcutGrant: grant)
                    } catch {
                        return DaemonControlResponse(
                            ok: false,
                            code: "shortcut_grant_revoke_failed",
                            error: String(describing: error)
                        )
                    }
                case .powerAssertionStart:
                    let result = relayService.executeLocalCommand(RemoteCommand.caffeinate.rawValue)
                    return DaemonControlResponse(
                        ok: result.success,
                        code: result.success ? nil : "power_assertion_start_failed",
                        error: result.success ? nil : result.message,
                        commandResult: result
                    )
                case .powerAssertionStop:
                    let result = relayService.executeLocalCommand(RemoteCommand.decaffeinate.rawValue)
                    return DaemonControlResponse(
                        ok: result.success,
                        code: result.success ? nil : "power_assertion_stop_failed",
                        error: result.success ? nil : result.message,
                        commandResult: result
                    )
                case .sentryStart, .sentryStop, .sentryStatus, .sentryUnlock, .sentryOpen:
                    let result = relayService.executeLocalCommand(request.action.rawValue)
                    return DaemonControlResponse(
                        ok: result.success,
                        code: result.success ? nil : "sentry_command_failed",
                        error: result.success ? nil : result.message,
                        commandResult: result
                    )
                }
            }
            controlServer = server
        } catch {
            Logger.warn("Daemon", "daemon control server failed", data: ["error": String(describing: error)])
        }
    }

    private func setupSignalHandlers() {
        signal(SIGINT, SIG_IGN)
        signal(SIGTERM, SIG_IGN)

        let queue = DispatchQueue(label: "com.cicada.agent.signal")

        let intSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: queue)
        intSource.setEventHandler { [weak self] in
            self?.shutdown()
        }
        intSource.resume()

        let termSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: queue)
        termSource.setEventHandler { [weak self] in
            self?.shutdown()
        }
        termSource.resume()
    }

    private func shutdown() {
        controlServer?.stop()
        service?.stop()
        Logger.info("Daemon", "cicada-agent stopped")
        exit(0)
    }
}

let runtime = DaemonRuntime()
exit(runtime.start())
