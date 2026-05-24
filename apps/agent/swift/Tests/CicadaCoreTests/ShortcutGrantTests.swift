import XCTest
@testable import CicadaCore

final class ShortcutGrantTests: XCTestCase {
    func testCreateStoresOnlyTokenHashAndPreview() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("cicada-shortcut-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let path = tempDir.appendingPathComponent("shortcut-grants.json").path
        let store = ShortcutGrantStore(path: path)

        let result = try store.create(
            deviceId: "MAC_0123456789ABCDEF0123456789ABCDEF",
            name: "iPhone",
            commands: ["ping", "status"],
            ttlMs: 60_000,
            now: Date(timeIntervalSince1970: 1_704_067_200)
        )

        XCTAssertTrue(result.token.hasPrefix("cicada_sc_"))
        XCTAssertFalse(result.grant.tokenHash.contains(result.token))
        XCTAssertFalse(result.grant.tokenPreview.contains(result.token))
        XCTAssertEqual(result.grant.allowedCommands, ["ping", "status"])
        XCTAssertEqual(try store.list().count, 1)
    }

    func testAllCommandsExpandsToCurrentCommandSet() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("cicada-shortcut-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let store = ShortcutGrantStore(path: tempDir.appendingPathComponent("shortcut-grants.json").path)

        let result = try store.create(
            deviceId: "MAC_0123456789ABCDEF0123456789ABCDEF",
            name: "All",
            commands: ["all"],
            ttlMs: 60_000
        )

        XCTAssertEqual(
            Set(result.grant.allowedCommands),
            Set(RemoteCommand.allCases.map(\.rawValue))
        )
    }

    func testRevokeMarksGrantAndAuthorizationFails() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("cicada-shortcut-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let store = ShortcutGrantStore(path: tempDir.appendingPathComponent("shortcut-grants.json").path)
        let result = try store.create(
            deviceId: "MAC_0123456789ABCDEF0123456789ABCDEF",
            name: "iPhone",
            commands: ["ping"],
            ttlMs: 60_000
        )

        let revoked = try store.revoke(grantId: result.grant.grantId)

        XCTAssertNotNil(revoked.revokedAt)
        XCTAssertEqual(
            store.authorize(grantId: result.grant.grantId, command: "ping").code,
            "grant_revoked"
        )
    }

    func testCommandScopeIsEnforced() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("cicada-shortcut-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let store = ShortcutGrantStore(path: tempDir.appendingPathComponent("shortcut-grants.json").path)
        let result = try store.create(
            deviceId: "MAC_0123456789ABCDEF0123456789ABCDEF",
            name: "Limited",
            commands: ["ping"],
            ttlMs: 60_000
        )

        XCTAssertTrue(store.authorize(grantId: result.grant.grantId, command: "ping").allowed)
        XCTAssertEqual(
            store.authorize(grantId: result.grant.grantId, command: "lock").code,
            "command_not_allowed"
        )
    }
}
