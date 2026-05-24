import Foundation
import XCTest
@testable import CicadaCore
@testable import CicadaIPC

final class DaemonControlTests: XCTestCase {
    func testDaemonControlRequestAndResponseRoundTrip() throws {
        let request = DaemonControlRequest(action: .shortcutGrantList)
        let decodedRequest = try JSONDecoder().decode(
            DaemonControlRequest.self,
            from: try JSONEncoder().encode(request)
        )
        XCTAssertEqual(decodedRequest.action, .shortcutGrantList)

        let response = DaemonControlResponse(ok: true, shortcutGrants: [])
        let decodedResponse = try JSONDecoder().decode(
            DaemonControlResponse.self,
            from: try JSONEncoder().encode(response)
        )
        XCTAssertTrue(decodedResponse.ok)
        XCTAssertEqual(decodedResponse.shortcutGrants?.count, 0)
    }

    func testClientReportsUnavailableSocket() {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("missing-cicada-daemon-\(UUID().uuidString).sock")
            .path
        let client = UdsDaemonControlClient(socketPath: path, timeoutMs: 100)

        XCTAssertThrowsError(try client.shortcutGrantList())
        XCTAssertThrowsError(try client.powerAssertionStart())
    }

    func testShortcutGrantControlPayloadsRoundTrip() throws {
        let request = DaemonControlRequest(
            action: .shortcutGrantCreate,
            name: "Phone",
            commands: ["ping", "status"],
            ttlMs: 60_000
        )
        let decodedRequest = try JSONDecoder().decode(
            DaemonControlRequest.self,
            from: try JSONEncoder().encode(request)
        )
        XCTAssertEqual(decodedRequest.action, .shortcutGrantCreate)
        XCTAssertEqual(decodedRequest.name, "Phone")
        XCTAssertEqual(decodedRequest.commands, ["ping", "status"])
        XCTAssertEqual(decodedRequest.ttlMs, 60_000)

        let grant = ShortcutGrant(
            grantId: "grant-1",
            deviceId: "MAC_0123456789ABCDEF0123456789ABCDEF",
            name: "Phone",
            tokenHash: "hash",
            tokenPreview: "cicada_sc_ab...1234",
            allowedCommands: ["ping"],
            expiresAt: 2,
            createdAt: 1,
            updatedAt: 1
        )
        let response = DaemonControlResponse(ok: true, shortcutToken: "cicada_sc_secret", shortcutGrant: grant)
        let decodedResponse = try JSONDecoder().decode(
            DaemonControlResponse.self,
            from: try JSONEncoder().encode(response)
        )
        XCTAssertEqual(decodedResponse.shortcutToken, "cicada_sc_secret")
        XCTAssertEqual(decodedResponse.shortcutGrant?.grantId, "grant-1")
    }

    func testPowerAssertionControlPayloadsRoundTrip() throws {
        let request = DaemonControlRequest(action: .powerAssertionStart)
        let decodedRequest = try JSONDecoder().decode(
            DaemonControlRequest.self,
            from: try JSONEncoder().encode(request)
        )
        XCTAssertEqual(decodedRequest.action, .powerAssertionStart)

        let result = CommandExecutionResult(success: true, message: "防休眠已启动")
        let response = DaemonControlResponse(ok: true, commandResult: result)
        let decodedResponse = try JSONDecoder().decode(
            DaemonControlResponse.self,
            from: try JSONEncoder().encode(response)
        )
        XCTAssertEqual(decodedResponse.commandResult, result)
    }
}
