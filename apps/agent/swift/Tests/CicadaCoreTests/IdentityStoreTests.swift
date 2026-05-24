import Foundation
import XCTest
@testable import CicadaCore

final class IdentityStoreTests: XCTestCase {
    func testGeneratesPersistsAndSignsWithIdentity() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("cicada-identity-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let path = tempDir.appendingPathComponent("identity.json").path
        let store = RelayIdentityStore(path: path)
        let first = try store.loadOrCreate(identityId: "agent-1")
        let second = try store.loadOrCreate(identityId: "agent-1")

        XCTAssertEqual(first.identityId, "agent-1")
        XCTAssertEqual(first.signingPublicKeyBase64, second.signingPublicKeyBase64)

        let transcript = Data("cicada-test-transcript".utf8)
        let signature = try first.signBase64(transcript)
        XCTAssertTrue(RelayIdentity.verifySignature(
            publicKeyBase64: first.signingPublicKeyBase64,
            message: transcript,
            signatureBase64: signature
        ))
    }
}
