import Foundation
import CicadaCore

struct ShortcutRelayCommand: Equatable {
    let requestId: String
    let grantId: String
    let command: String
}

struct ShortcutGrantUpdateAcknowledgement: Equatable {
    let accepted: Bool
    let code: String
}

enum RelayMessageCodec {
    static func isPong(_ raw: String) -> Bool {
        guard let object = jsonObject(raw), let type = object["type"] as? String else {
            return raw.contains("\"type\":\"pong\"") || raw.contains("\"type\": \"pong\"")
        }
        return type == "pong"
    }

    static func shortcutGrantUpdateAcknowledgement(
        _ raw: String
    ) -> ShortcutGrantUpdateAcknowledgement? {
        guard let object = jsonObject(raw), let type = object["type"] as? String else {
            let recognized = raw.contains("\"type\":\"shortcut_grant_update_ack\"")
                || raw.contains("\"type\": \"shortcut_grant_update_ack\"")
            return recognized
                ? ShortcutGrantUpdateAcknowledgement(accepted: true, code: "unknown")
                : nil
        }
        guard type == "shortcut_grant_update_ack" else { return nil }
        return ShortcutGrantUpdateAcknowledgement(
            accepted: object["ok"] as? Bool != false,
            code: object["code"] as? String ?? "unknown"
        )
    }

    static func shortcutCommand(_ raw: String) -> ShortcutRelayCommand? {
        guard let object = jsonObject(raw),
              object["type"] as? String == "shortcut_command",
              let data = object["data"] as? [String: Any] else {
            return nil
        }
        return ShortcutRelayCommand(
            requestId: data["requestId"] as? String ?? object["id"] as? String ?? "",
            grantId: data["grantId"] as? String ?? "",
            command: data["command"] as? String ?? ""
        )
    }

    static func shortcutResult(
        requestId: String,
        command: String,
        ok: Bool,
        success: Bool,
        message: String,
        data: [String: String]? = nil,
        code: String? = nil,
        error: String? = nil,
        sentAt: Int64
    ) -> String? {
        var result: [String: Any] = [
            "requestId": requestId,
            "command": command,
            "ok": ok,
            "success": success,
            "message": message,
        ]
        if let data { result["data"] = data }
        if let code { result["code"] = code }
        if let error { result["error"] = error }

        return serialize([
            "type": "shortcut_result",
            "id": requestId,
            "from": "agent",
            "sent_at": sentAt,
            "data": result,
        ])
    }

    static func shortcutGrantUpdate(
        state: String,
        grant: ShortcutGrant,
        sentAt: Int64
    ) -> String? {
        var grantObject: [String: Any] = [
            "grantId": grant.grantId,
            "deviceId": grant.deviceId,
            "name": grant.name,
            "tokenHash": grant.tokenHash,
            "tokenPreview": grant.tokenPreview,
            "allowedCommands": grant.allowedCommands,
            "expiresAt": grant.expiresAt,
            "createdAt": grant.createdAt,
            "updatedAt": grant.updatedAt,
        ]
        if let revokedAt = grant.revokedAt { grantObject["revokedAt"] = revokedAt }

        return serialize([
            "type": "shortcut_grant_update",
            "from": "agent",
            "sent_at": sentAt,
            "data": [
                "state": state,
                "grant": grantObject,
            ],
        ])
    }

    static func ping(timestamp: Int64) -> String? {
        serialize([
            "type": "ping",
            "timestamp": String(timestamp),
        ])
    }

    private static func jsonObject(_ raw: String) -> [String: Any]? {
        guard let data = raw.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private static func serialize(_ object: [String: Any]) -> String? {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
}
