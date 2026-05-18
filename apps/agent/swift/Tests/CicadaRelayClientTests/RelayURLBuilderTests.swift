import XCTest
@testable import CicadaCore
@testable import CicadaRelayClient

final class RelayURLBuilderTests: XCTestCase {
    func testBuildWebSocketURLFromHttps() {
        let config = CicadaConfig(
            relayURL: "https://relay.example.com",
            deviceId: "MAC_0123456789ABCDEF0123456789ABCDEF",
            apiKey: "k1",
            autoConnect: true,
            showNotifications: true,
            enableAutoReconnect: true,
            reconnectInterval: 5000,
            maxReconnectAttempts: 10,
            heartbeatInterval: 30000,
            connectionTimeout: 10000
        )

        let url = RelayURLBuilder.buildWebSocketURL(config: config, timestamp: 123)
        XCTAssertEqual(
            url?.absoluteString,
            "wss://relay.example.com/ws?device_id=MAC_0123456789ABCDEF0123456789ABCDEF&api_key=k1&ts=123"
        )
    }

    func testExtractCommandFromLegacyMessageShape() {
        let message = "{\"type\":\"command\",\"data\":{\"cmd\":\"ping\"}}"
        XCTAssertEqual(RelayMessageParser.extractCommand(from: message), "ping")
    }

    func testExtractCommandFromCanonicalMessageShape() {
        let message = "{\"type\":\"command\",\"data\":{\"command\":\"ping\"}}"
        XCTAssertEqual(RelayMessageParser.extractCommand(from: message), "ping")
    }

    func testExtractCommandFromFlatMessageShape() {
        let message = "{\"type\":\"cmd\",\"cmd\":\"status\"}"
        XCTAssertEqual(RelayMessageParser.extractCommand(from: message), "status")
    }

    func testExtractCommandFromFlatCanonicalMessageShape() {
        let message = "{\"type\":\"command\",\"command\":\"status\"}"
        XCTAssertEqual(RelayMessageParser.extractCommand(from: message), "status")
    }
}
