import Foundation
import CicadaCore

public enum RelayURLBuilder {
    public static func buildWebSocketURL(config: CicadaConfig, timestamp: Int64 = Int64(Date().timeIntervalSince1970)) -> URL? {
        guard var components = URLComponents(string: config.relayURL) else {
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
        components.path = basePath.isEmpty ? "/ws" : "/\(basePath)/ws"
        components.queryItems = [
            URLQueryItem(name: "device_id", value: config.deviceId),
            URLQueryItem(name: "api_key", value: config.apiKey),
            URLQueryItem(name: "ts", value: String(timestamp)),
        ]

        return components.url
    }
}

public enum RelayMessageParser {
    public static func extractCommand(from raw: String) -> String? {
        guard let data = raw.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = object["type"] as? String else {
            return nil
        }

        guard type == "command" || type == "cmd" else {
            return nil
        }

        if let dataObject = object["data"] as? [String: Any] {
            if let cmd = dataObject["cmd"] as? String {
                return cmd
            }
            if let command = dataObject["command"] as? String {
                return command
            }
        }

        if let cmd = object["cmd"] as? String {
            return cmd
        }

        return object["command"] as? String
    }
}
