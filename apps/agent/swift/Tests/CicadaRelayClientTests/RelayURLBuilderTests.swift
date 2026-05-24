import XCTest
@testable import CicadaCore
@testable import CicadaRelayClient

final class RelayURLBuilderTests: XCTestCase {
    func testBuildAgentWebSocketURLFromHttps() {
        let config = CicadaConfig(
            relayURL: "https://relay.example.com",
            deviceId: "MAC_0123456789ABCDEF0123456789ABCDEF",
            autoConnect: true,
            showNotifications: true,
            enableAutoReconnect: true,
            reconnectInterval: 5000,
            maxReconnectAttempts: 10,
            heartbeatInterval: 30000,
            connectionTimeout: 10000
        )

        let url = RelayURLBuilder.buildAgentWebSocketURL(config: config, liveSessionId: "live-session-1")
        XCTAssertEqual(
            url?.absoluteString,
            "wss://relay.example.com/relay/live-session-1"
        )
    }

    func testBuildAgentWebSocketRequestDoesNotSetRelayRole() throws {
        let config = CicadaConfig(
            relayURL: "https://relay.example.com",
            deviceId: "MAC_0123456789ABCDEF0123456789ABCDEF",
            autoConnect: true,
            showNotifications: true,
            enableAutoReconnect: true,
            reconnectInterval: 5000,
            maxReconnectAttempts: 10,
            heartbeatInterval: 30000,
            connectionTimeout: 10000
        )
        let identity = RelayIdentity.generate(identityId: config.deviceId)

        let request = try XCTUnwrap(
            RelayURLBuilder.buildAgentWebSocketRequest(
                config: config,
                liveSessionId: "live-session-1",
                identity: identity
            )
        )

        XCTAssertNil(request.value(forHTTPHeaderField: "x-role"))
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-device-id"), config.deviceId)
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "x-agent-identity-public-key"),
            identity.signingPublicKeyBase64
        )
        XCTAssertNotNil(request.value(forHTTPHeaderField: "x-agent-registration-timestamp"))
        XCTAssertNotNil(request.value(forHTTPHeaderField: "x-agent-registration-nonce"))
        XCTAssertNotNil(request.value(forHTTPHeaderField: "x-agent-registration-signature"))
    }
}
