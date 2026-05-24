import Foundation
import CicadaCore

public enum RelayURLBuilder {
    public static func buildAgentWebSocketURL(config: CicadaConfig, liveSessionId: String) -> URL? {
        buildRelayURL(relayURL: config.relayURL, target: liveSessionId)
    }

    public static func buildAgentWebSocketRequest(
        config: CicadaConfig,
        liveSessionId: String,
        identity: RelayIdentity
    ) -> URLRequest? {
        guard let url = buildAgentWebSocketURL(config: config, liveSessionId: liveSessionId) else {
            return nil
        }
        var request = URLRequest(url: url)
        request.setValue(config.deviceId, forHTTPHeaderField: "x-device-id")
        request.setValue(identity.signingPublicKeyBase64, forHTTPHeaderField: "x-agent-identity-public-key")
        let timestamp = Int64(Date().timeIntervalSince1970 * 1000)
        let nonce = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        let transcript = RelayTranscript.agentRegistration(
            deviceId: config.deviceId,
            sessionId: liveSessionId,
            agentIdentityPublicKey: identity.signingPublicKeyBase64,
            timestamp: timestamp,
            nonce: nonce
        )
        if let signature = try? identity.signBase64(transcript) {
            request.setValue(String(timestamp), forHTTPHeaderField: "x-agent-registration-timestamp")
            request.setValue(nonce, forHTTPHeaderField: "x-agent-registration-nonce")
            request.setValue(signature, forHTTPHeaderField: "x-agent-registration-signature")
        }
        return request
    }

    private static func buildRelayURL(relayURL: String, target: String) -> URL? {
        guard var components = URLComponents(string: relayURL) else {
            return nil
        }

        switch components.scheme {
        case "https":
            components.scheme = "wss"
        case "http":
            components.scheme = "ws"
        case "wss", "ws":
            break
        default:
            return nil
        }

        let basePath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let encodedTarget = target.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? target
        components.path = basePath.isEmpty ? "/relay/\(encodedTarget)" : "/\(basePath)/relay/\(encodedTarget)"
        components.queryItems = nil

        return components.url
    }
}
