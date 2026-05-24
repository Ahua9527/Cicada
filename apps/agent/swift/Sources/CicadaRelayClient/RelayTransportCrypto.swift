import Foundation

public enum RelayCloseCodes {
    public static let invalidSessionOrRole = 4000
    public static let agentReplaced = 4001
    public static let agentUnavailable = 4002
    public static let agentTemporarilyUnavailable = 4004

    public static func isRetryableAgentAbsence(_ code: Int) -> Bool {
        code == agentUnavailable || code == agentTemporarilyUnavailable
    }
}

public enum RelayTranscript {
    public static func agentRegistration(
        deviceId: String,
        sessionId: String,
        agentIdentityPublicKey: String,
        timestamp: Int64,
        nonce: String
    ) -> Data {
        lengthPrefixed([
            "cicada-agent-registration-v1",
            deviceId,
            sessionId,
            agentIdentityPublicKey,
            String(timestamp),
            nonce,
        ])
    }

    private static func lengthPrefixed(_ fields: [String]) -> Data {
        var output = Data()
        for field in fields {
            let data = Data(field.utf8)
            var length = UInt32(data.count).bigEndian
            withUnsafeBytes(of: &length) { output.append(contentsOf: $0) }
            output.append(data)
        }
        return output
    }
}
