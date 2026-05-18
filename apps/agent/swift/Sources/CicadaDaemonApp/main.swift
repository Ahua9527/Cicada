import Foundation
import CicadaCore
import CicadaIPC
import CicadaRelayClient
import CicadaSystem

final class DaemonRuntime {
    private var service: RelayDaemonService?

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
        service?.stop()
        Logger.info("Daemon", "cicada-agent stopped")
        exit(0)
    }
}

let runtime = DaemonRuntime()
exit(runtime.start())
