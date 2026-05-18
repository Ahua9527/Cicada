import Foundation
import XCTest
@testable import CicadaCore
@testable import CicadaRelayClient

private final class MockCommandGateway: CommandExecuting {
    private(set) var executedCommands: [String] = []

    func execute(command rawCommand: String) -> CommandExecutionResult {
        executedCommands.append(rawCommand)
        return CommandExecutionResult(success: true, message: "ok")
    }
}

private final class MockNotifier: NotifierSending {
    private(set) var notifyCount = 0

    func notifyQuick(
        source: String,
        level: NotificationLevel,
        title: String,
        message: String?,
        durationMs: Int?
    ) -> NotifyResponse {
        notifyCount += 1
        return NotifyResponse(ok: true)
    }
}

final class RelayDaemonServiceTests: XCTestCase {
    func testStartStaysIdleWhenAutoConnectDisabled() {
        let config = makeConfig(autoConnect: false)
        let commandGateway = MockCommandGateway()
        let notifier = MockNotifier()
        let service = RelayDaemonService(config: config, commandGateway: commandGateway, notifier: notifier)

        service.start()

        XCTAssertEqual(service.mode, "idle")
        XCTAssertEqual(service.connectionState, .idle)

        service.stop()
    }

    func testShowNotificationsDisabledSkipsNotifierOnCommand() {
        let config = makeConfig(autoConnect: false, showNotifications: false)
        let commandGateway = MockCommandGateway()
        let notifier = MockNotifier()
        let service = RelayDaemonService(config: config, commandGateway: commandGateway, notifier: notifier)

        service.debugHandleRawMessage("{\"type\":\"command\",\"data\":{\"cmd\":\"ping\"}}")

        XCTAssertEqual(commandGateway.executedCommands, ["ping"])
        XCTAssertEqual(notifier.notifyCount, 0)

        service.stop()
    }

    func testConnectionTimeoutTransitionsToReconnectWait() {
        let config = makeConfig(
            autoConnect: true,
            showNotifications: true,
            enableAutoReconnect: true,
            reconnectInterval: 5000,
            connectionTimeout: 2000
        )
        let service = RelayDaemonService(
            config: config,
            commandGateway: MockCommandGateway(),
            notifier: MockNotifier()
        )

        service.debugSetConnectionState(.connected)
        service.debugSetLastPong(Date(timeIntervalSince1970: 0))
        service.debugCheckConnectionHealth(now: Date(timeIntervalSince1970: 3))

        XCTAssertEqual(service.connectionState, .reconnectWait)

        service.stop()
    }

    private func makeConfig(
        autoConnect: Bool,
        showNotifications: Bool = true,
        enableAutoReconnect: Bool = true,
        reconnectInterval: Int = 5000,
        connectionTimeout: Int = 10000
    ) -> CicadaConfig {
        CicadaConfig(
            relayURL: "https://relay.example.com",
            deviceId: "MAC_0123456789ABCDEF0123456789ABCDEF",
            apiKey: "k1",
            autoConnect: autoConnect,
            showNotifications: showNotifications,
            enableAutoReconnect: enableAutoReconnect,
            reconnectInterval: reconnectInterval,
            maxReconnectAttempts: 10,
            heartbeatInterval: 30000,
            connectionTimeout: connectionTimeout
        )
    }
}
