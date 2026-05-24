import Foundation

public enum NotificationStyle: String, Codable {
    case dynamicIsland = "dynamic_island"
}

public enum NotificationLevel: String, Codable {
    case info
    case success
    case warning
    case error
}

public struct NotifyRequest: Codable {
    public let version: Int
    public let id: String
    public let source: String
    public let style: NotificationStyle
    public let level: NotificationLevel
    public let title: String
    public let message: String?
    public let durationMs: Int?
    public let timestamp: Int64

    public init(
        version: Int = 1,
        id: String,
        source: String,
        style: NotificationStyle = .dynamicIsland,
        level: NotificationLevel,
        title: String,
        message: String?,
        durationMs: Int?,
        timestamp: Int64
    ) {
        self.version = version
        self.id = id
        self.source = source
        self.style = style
        self.level = level
        self.title = title
        self.message = message
        self.durationMs = durationMs
        self.timestamp = timestamp
    }
}

public struct NotifyResponse: Codable {
    public let ok: Bool
    public let code: String?
    public let error: String?

    public init(ok: Bool, code: String? = nil, error: String? = nil) {
        self.ok = ok
        self.code = code
        self.error = error
    }
}

public enum RemoteCommand: String, CaseIterable {
    case lock
    case btToggle = "bt_toggle"
    case ping
    case volumeMute = "volume_mute"
    case sleep
    case sleepDisplays = "sleep_displays"
    case caffeinate
    case decaffeinate
    case status
}

public struct CommandExecutionResult: Codable, Equatable {
    public let success: Bool
    public let message: String
    public let data: [String: String]?

    public init(success: Bool, message: String, data: [String: String]? = nil) {
        self.success = success
        self.message = message
        self.data = data
    }
}

public struct CicadaConfig: Codable {
    public var relayURL: String
    public var deviceId: String
    public var apiKey: String
    public var autoConnect: Bool
    public var showNotifications: Bool
    public var enableAutoReconnect: Bool
    public var reconnectInterval: Int
    public var maxReconnectAttempts: Int
    public var heartbeatInterval: Int
    public var connectionTimeout: Int

    public init(
        relayURL: String,
        deviceId: String,
        apiKey: String,
        autoConnect: Bool,
        showNotifications: Bool,
        enableAutoReconnect: Bool,
        reconnectInterval: Int,
        maxReconnectAttempts: Int,
        heartbeatInterval: Int,
        connectionTimeout: Int
    ) {
        self.relayURL = relayURL
        self.deviceId = deviceId
        self.apiKey = apiKey
        self.autoConnect = autoConnect
        self.showNotifications = showNotifications
        self.enableAutoReconnect = enableAutoReconnect
        self.reconnectInterval = reconnectInterval
        self.maxReconnectAttempts = maxReconnectAttempts
        self.heartbeatInterval = heartbeatInterval
        self.connectionTimeout = connectionTimeout
    }

    public static func defaultConfig() -> CicadaConfig {
        CicadaConfig(
            relayURL: "https://example.com",
            deviceId: Self.generateDeviceId(),
            apiKey: "replace-with-your-api-key",
            autoConnect: true,
            showNotifications: true,
            enableAutoReconnect: true,
            reconnectInterval: 5000,
            maxReconnectAttempts: 10,
            heartbeatInterval: 30000,
            connectionTimeout: 10000
        )
    }

    public static func generateDeviceId() -> String {
        let raw = UUID().uuidString.replacingOccurrences(of: "-", with: "").uppercased()
        return "MAC_\(raw)"
    }

    public func validate() throws {
        guard let url = URL(string: relayURL), let scheme = url.scheme, ["http", "https"].contains(scheme) else {
            throw CicadaError.validation("relayURL 必须是 http/https URL")
        }
        let normalizedDeviceId = deviceId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedDeviceId.isEmpty else {
            throw CicadaError.validation("deviceId 不能为空")
        }
        guard normalizedDeviceId.range(of: #"^MAC_[A-Fa-f0-9]{32}$"#, options: .regularExpression) != nil else {
            throw CicadaError.validation("deviceId 必须匹配 MAC_[32位十六进制]")
        }
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CicadaError.validation("apiKey 不能为空")
        }
        guard reconnectInterval > 0 else {
            throw CicadaError.validation("reconnectInterval 必须大于 0")
        }
        guard maxReconnectAttempts >= 0 else {
            throw CicadaError.validation("maxReconnectAttempts 不能小于 0")
        }
        guard heartbeatInterval > 0 else {
            throw CicadaError.validation("heartbeatInterval 必须大于 0")
        }
        guard connectionTimeout > 0 else {
            throw CicadaError.validation("connectionTimeout 必须大于 0")
        }
    }
}

public extension NotifyRequest {
    static func quick(
        source: String,
        level: NotificationLevel,
        title: String,
        message: String? = nil,
        durationMs: Int? = 2500
    ) -> NotifyRequest {
        NotifyRequest(
            id: "ntf_\(Int(Date().timeIntervalSince1970 * 1000))_\(Int.random(in: 1000 ... 9999))",
            source: source,
            level: level,
            title: title,
            message: message,
            durationMs: durationMs,
            timestamp: Int64(Date().timeIntervalSince1970 * 1000)
        )
    }
}
