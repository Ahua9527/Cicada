import Foundation
import XCTest
import CicadaCore
@testable import CicadaRelayClient

final class RelayTransportFixtureTests: XCTestCase {
    func testParsesSharedShortcutCommand() throws {
        let raw = try loadFixture("shortcut_command")
        let fixture = try jsonObject(raw)
        XCTAssertEqual(Set(fixture.keys), ["type", "id", "sent_at", "data"])
        XCTAssertEqual(fixture["type"] as? String, "shortcut_command")
        XCTAssertEqual(fixture["id"] as? String, "fixture-request-1")
        XCTAssertNotNil(fixture["sent_at"] as? Int64)
        let data = try XCTUnwrap(fixture["data"] as? [String: Any])
        XCTAssertEqual(Set(data.keys), ["requestId", "grantId", "command", "params"])
        XCTAssertEqual(data["requestId"] as? String, fixture["id"] as? String)
        XCTAssertEqual(
            RelayMessageCodec.shortcutCommand(raw),
            ShortcutRelayCommand(
                requestId: "fixture-request-1",
                grantId: "fixture-grant-1",
                command: "ping",
                params: ["value": "fixture-input"]
            )
        )
    }

    func testParsesSharedShortcutGrantUpdateAcknowledgement() throws {
        let raw = try loadFixture("shortcut_grant_update_ack")
        let fixture = try jsonObject(raw)
        XCTAssertEqual(Set(fixture.keys), ["type", "ok", "grantId", "state", "sent_at"])
        XCTAssertEqual(fixture["type"] as? String, "shortcut_grant_update_ack")
        XCTAssertEqual(fixture["ok"] as? Bool, true)
        XCTAssertEqual(fixture["grantId"] as? String, "fixture-grant-1")
        XCTAssertEqual(fixture["state"] as? String, "active")
        XCTAssertNotNil(fixture["sent_at"] as? Int64)
        XCTAssertEqual(
            RelayMessageCodec.shortcutGrantUpdateAcknowledgement(raw),
            ShortcutGrantUpdateAcknowledgement(accepted: true, code: "unknown")
        )
    }

    func testEmitsSharedShortcutResultSuccess() throws {
        let raw = try XCTUnwrap(RelayMessageCodec.shortcutResult(
            requestId: "fixture-request-1",
            command: "ping",
            ok: true,
            success: true,
            message: "pong",
            data: ["value": "ready"],
            sentAt: 1_704_067_200_000
        ))
        try assertMessage(raw, matchesFixture: "shortcut_result_success")
    }

    func testEmitsSharedShortcutResultFailure() throws {
        let raw = try XCTUnwrap(RelayMessageCodec.shortcutResult(
            requestId: "fixture-request-1",
            command: "ping",
            ok: false,
            success: false,
            message: "Command denied",
            data: ["reason": "not_allowed"],
            code: "command_not_allowed",
            error: "Shortcut grant does not allow this command.",
            sentAt: 1_704_067_200_000
        ))
        try assertMessage(raw, matchesFixture: "shortcut_result_failure")
    }

    func testEmitsSharedShortcutGrantUpdate() throws {
        let grant = ShortcutGrant(
            grantId: "fixture-grant-1",
            deviceId: "MAC_1234567890ABCDEF1234567890ABCDEF",
            name: "Fixture Shortcut",
            tokenHash: "FAKE_TOKEN_HASH_FOR_TESTS_ONLY",
            tokenPreview: "FAKE_TOKEN_PREVIEW",
            allowedCommands: ["ping", "status"],
            expiresAt: 1_706_659_200_000,
            createdAt: 1_704_067_200_000,
            updatedAt: 1_704_067_200_000
        )
        let raw = try XCTUnwrap(RelayMessageCodec.shortcutGrantUpdate(
            state: "active", grant: grant, sentAt: 1_704_067_200_000
        ))
        try assertMessage(raw, matchesFixture: "shortcut_grant_update")
    }

    private func assertMessage(
        _ raw: String,
        matchesFixture name: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let actual = try jsonObject(raw)
        let expected = try jsonObject(loadFixture(name))
        // Full JSON equality also rejects renamed or extra keys, including nested objects.
        XCTAssertEqual(actual as NSDictionary, expected as NSDictionary, file: file, line: line)
    }

    private func jsonObject(_ raw: String) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any])
    }

    private func loadFixture(_ name: String) throws -> String {
        var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let relativePath = "packages/shared/protocol/fixtures/\(name).json"
        while directory.path != "/" {
            let candidate = directory.appendingPathComponent(relativePath)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return try String(contentsOf: candidate, encoding: .utf8)
            }
            directory.deleteLastPathComponent()
        }
        XCTFail("Missing shared transport fixture: \(name)")
        throw CocoaError(.fileNoSuchFile)
    }
}
