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
    func testRelayMessageCodecRecognizesIncomingMessages() {
        XCTAssertTrue(RelayMessageCodec.isPong("{\"type\":\"pong\"}"))
        XCTAssertFalse(RelayMessageCodec.isPong("{\"type\":\"ping\"}"))
        XCTAssertEqual(
            RelayMessageCodec.shortcutGrantUpdateAcknowledgement(
                "{\"type\":\"shortcut_grant_update_ack\",\"ok\":false,\"code\":\"rejected\"}"
            ),
            ShortcutGrantUpdateAcknowledgement(accepted: false, code: "rejected")
        )
        XCTAssertEqual(
            RelayMessageCodec.shortcutCommand(
                "{\"type\":\"shortcut_command\",\"id\":\"fallback\",\"data\":{\"grantId\":\"grant-1\",\"command\":\"ping\"}}"
            ),
            ShortcutRelayCommand(requestId: "fallback", grantId: "grant-1", command: "ping")
        )
    }

    func testRelayMessageCodecPreservesOutgoingWireShape() throws {
        let ping = try XCTUnwrap(RelayMessageCodec.ping(timestamp: 123))
        let pingObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(ping.utf8)) as? [String: Any]
        )
        XCTAssertEqual(pingObject["type"] as? String, "ping")
        XCTAssertEqual(pingObject["timestamp"] as? String, "123")

        let result = try XCTUnwrap(RelayMessageCodec.shortcutResult(
            requestId: "req-1",
            command: "ping",
            ok: true,
            success: true,
            message: "ok",
            data: ["value": "ready"],
            sentAt: 456
        ))
        let resultObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(result.utf8)) as? [String: Any]
        )
        let resultData = try XCTUnwrap(resultObject["data"] as? [String: Any])
        XCTAssertEqual(resultObject["type"] as? String, "shortcut_result")
        XCTAssertEqual(resultObject["sent_at"] as? Int64, 456)
        XCTAssertEqual(resultData["requestId"] as? String, "req-1")
        XCTAssertEqual(resultData["success"] as? Bool, true)
    }

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

    func testShowNotificationsDisabledSkipsNotifierOnCommand() throws {
        let config = makeConfig(autoConnect: false, showNotifications: false)
        let commandGateway = MockCommandGateway()
        let notifier = MockNotifier()
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("cicada-shortcut-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let grantStore = ShortcutGrantStore(path: tempDir.appendingPathComponent("shortcut-grants.json").path)
        let grant = try grantStore.create(
            deviceId: config.deviceId,
            name: "test",
            commands: ["ping"],
            ttlMs: 60_000
        ).grant
        let service = RelayDaemonService(
            config: config,
            commandGateway: commandGateway,
            notifier: notifier,
            shortcutGrantStore: grantStore
        )

        service.debugHandleRawMessage("""
        {"type":"shortcut_command","id":"req-1","data":{"requestId":"req-1","grantId":"\(grant.grantId)","command":"ping"}}
        """)

        XCTAssertEqual(commandGateway.executedCommands, ["ping"])
        XCTAssertEqual(notifier.notifyCount, 0)

        service.stop()
    }

    func testPongMessageDoesNotExecuteCommandOrNotify() {
        let config = makeConfig(autoConnect: false, showNotifications: true)
        let commandGateway = MockCommandGateway()
        let notifier = MockNotifier()
        let service = RelayDaemonService(config: config, commandGateway: commandGateway, notifier: notifier)

        service.debugHandleRawMessage("{\"type\":\"pong\",\"timestamp\":123,\"data\":{\"deviceId\":\"MAC_0123456789ABCDEF0123456789ABCDEF\"}}")

        XCTAssertEqual(commandGateway.executedCommands, [])
        XCTAssertEqual(notifier.notifyCount, 0)

        service.stop()
    }

    func testShortcutGrantAckDoesNotExecuteCommandOrNotify() {
        let config = makeConfig(autoConnect: false, showNotifications: true)
        let commandGateway = MockCommandGateway()
        let notifier = MockNotifier()
        let service = RelayDaemonService(config: config, commandGateway: commandGateway, notifier: notifier)

        service.debugHandleRawMessage("{\"type\":\"shortcut_grant_update_ack\",\"ok\":true,\"sent_at\":123}")

        XCTAssertEqual(commandGateway.executedCommands, [])
        XCTAssertEqual(notifier.notifyCount, 0)

        service.stop()
    }

    func testShortcutCommandExecutesAndReturnsPlainResult() throws {
        let config = makeConfig(autoConnect: false, showNotifications: false)
        let commandGateway = MockCommandGateway()
        let notifier = MockNotifier()
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("cicada-shortcut-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let grantStore = ShortcutGrantStore(path: tempDir.appendingPathComponent("shortcut-grants.json").path)
        let grant = try grantStore.create(
            deviceId: config.deviceId,
            name: "test",
            commands: ["ping"],
            ttlMs: 60_000
        ).grant
        let service = RelayDaemonService(
            config: config,
            commandGateway: commandGateway,
            notifier: notifier,
            shortcutGrantStore: grantStore
        )

        service.debugHandleRawMessage("""
        {"type":"shortcut_command","id":"req-1","data":{"requestId":"req-1","grantId":"\(grant.grantId)","command":"ping"}}
        """)

        XCTAssertEqual(commandGateway.executedCommands, ["ping"])
        let outgoing = service.debugOutgoingMessages()
        XCTAssertEqual(outgoing.count, 1)
        let response = try JSONSerialization.jsonObject(with: Data(outgoing[0].utf8)) as? [String: Any]
        let data = response?["data"] as? [String: Any]
        XCTAssertEqual(response?["type"] as? String, "shortcut_result")
        XCTAssertEqual(data?["requestId"] as? String, "req-1")
        XCTAssertEqual(data?["success"] as? Bool, true)

        service.stop()
    }

    func testShortcutCommandDeniedByScopeDoesNotExecute() throws {
        let config = makeConfig(autoConnect: false, showNotifications: false)
        let commandGateway = MockCommandGateway()
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("cicada-shortcut-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let grantStore = ShortcutGrantStore(path: tempDir.appendingPathComponent("shortcut-grants.json").path)
        let grant = try grantStore.create(
            deviceId: config.deviceId,
            name: "test",
            commands: ["ping"],
            ttlMs: 60_000
        ).grant
        let service = RelayDaemonService(
            config: config,
            commandGateway: commandGateway,
            notifier: MockNotifier(),
            shortcutGrantStore: grantStore
        )

        service.debugHandleRawMessage("""
        {"type":"shortcut_command","id":"req-2","data":{"requestId":"req-2","grantId":"\(grant.grantId)","command":"lock"}}
        """)

        XCTAssertEqual(commandGateway.executedCommands, [])
        let response = try JSONSerialization.jsonObject(with: Data(service.debugOutgoingMessages()[0].utf8)) as? [String: Any]
        let data = response?["data"] as? [String: Any]
        XCTAssertEqual(data?["ok"] as? Bool, false)
        XCTAssertEqual(data?["code"] as? String, "command_not_allowed")

        service.stop()
    }

    func testExecuteLocalCommandUsesCommandGateway() {
        let config = makeConfig(autoConnect: false, showNotifications: false)
        let commandGateway = MockCommandGateway()
        let service = RelayDaemonService(
            config: config,
            commandGateway: commandGateway,
            notifier: MockNotifier()
        )

        let result = service.executeLocalCommand("caffeinate")

        XCTAssertTrue(result.success)
        XCTAssertEqual(commandGateway.executedCommands, ["caffeinate"])
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
