import Foundation
import XCTest
@testable import CicadaRelayClient

final class RelayTransportCryptoTests: XCTestCase {
    func testAgentRegistrationTranscriptUsesLengthPrefixedBytes() {
        let transcript = RelayTranscript.agentRegistration(
            deviceId: "device-1",
            sessionId: "session-1",
            agentIdentityPublicKey: "agent-key",
            timestamp: 456,
            nonce: "nonce-2"
        )

        XCTAssertEqual(
            Array(transcript),
            expectedLengthPrefixedBytes([
                "cicada-agent-registration-v1",
                "device-1",
                "session-1",
                "agent-key",
                "456",
                "nonce-2",
            ])
        )
        XCTAssertNotEqual(String(data: transcript, encoding: .utf8), [
            "cicada-agent-registration-v1",
            "device-1",
            "session-1",
            "agent-key",
            "456",
            "nonce-2",
        ].joined(separator: "\n"))
    }

    func testRelayCloseCodesClassifyRetryableAgentAbsence() {
        XCTAssertEqual(RelayCloseCodes.invalidSessionOrRole, 4000)
        XCTAssertEqual(RelayCloseCodes.agentUnavailable, 4002)
        XCTAssertEqual(RelayCloseCodes.agentTemporarilyUnavailable, 4004)
        XCTAssertTrue(RelayCloseCodes.isRetryableAgentAbsence(4002))
        XCTAssertTrue(RelayCloseCodes.isRetryableAgentAbsence(4004))
        XCTAssertFalse(RelayCloseCodes.isRetryableAgentAbsence(4001))
    }

    private func expectedLengthPrefixedBytes(_ fields: [String]) -> [UInt8] {
        fields.flatMap { field -> [UInt8] in
            let data = Array(field.data(using: .utf8) ?? Data())
            let length = UInt32(data.count).bigEndian
            let lengthBytes = withUnsafeBytes(of: length) { Array($0) }
            return lengthBytes + data
        }
    }
}
