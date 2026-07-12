import Darwin
import Foundation

struct CicadaRelayConfig: Codable, Equatable {
    var relayURL: String
    var deviceId: String
    var autoConnect: Bool
    var showNotifications: Bool
    var enableAutoReconnect: Bool
    var reconnectInterval: Int
    var maxReconnectAttempts: Int
    var heartbeatInterval: Int
    var connectionTimeout: Int

    static func defaultConfig() -> CicadaRelayConfig {
        CicadaRelayConfig(
            relayURL: "https://example.com",
            deviceId: generateDeviceId(),
            autoConnect: true,
            showNotifications: true,
            enableAutoReconnect: true,
            reconnectInterval: 5000,
            maxReconnectAttempts: 10,
            heartbeatInterval: 30000,
            connectionTimeout: 10000
        )
    }

    static func generateDeviceId() -> String {
        "MAC_\(UUID().uuidString.replacingOccurrences(of: "-", with: "").uppercased())"
    }
}

final class CicadaRelayConfigStore {
    enum StoreError: LocalizedError, Equatable {
        case emptyRelayURL
        case invalidRelayURL
        case invalidDeviceId
        case invalidReconnectInterval
        case invalidMaxReconnectAttempts
        case invalidHeartbeatInterval
        case invalidConnectionTimeout

        var errorDescription: String? {
            switch self {
            case .emptyRelayURL:
                return String(localized: "Enter a Cicada Relay address.")
            case .invalidRelayURL:
                return String(localized: "Relay URL must be an http or https URL.")
            case .invalidDeviceId:
                return String(localized: "Device ID must match MAC_ followed by 32 hexadecimal characters.")
            case .invalidReconnectInterval:
                return String(localized: "Reconnect interval must be greater than 0.")
            case .invalidMaxReconnectAttempts:
                return String(localized: "Maximum reconnect attempts cannot be negative.")
            case .invalidHeartbeatInterval:
                return String(localized: "Heartbeat interval must be greater than 0.")
            case .invalidConnectionTimeout:
                return String(localized: "Connection timeout must be greater than 0.")
            }
        }
    }

    private let path: String
    private let fileManager: FileManager
    private let decoder = JSONDecoder()

    init(
        path: String = CicadaSentinelPaths.configPath(),
        fileManager: FileManager = .default
    ) {
        self.path = path
        self.fileManager = fileManager
    }

    func configPath() -> String {
        path
    }

    func loadOrCreate() throws -> CicadaRelayConfig {
        if fileManager.fileExists(atPath: path) {
            return try load()
        }
        let config = CicadaRelayConfig.defaultConfig()
        try save(config)
        return config
    }

    @discardableResult
    func saveRelayURL(_ rawRelayURL: String) throws -> CicadaRelayConfig {
        let relayURL = rawRelayURL.trimmingCharacters(in: .whitespacesAndNewlines)
        try validateRelayURL(relayURL)

        var config = try loadOrCreate()
        config.relayURL = relayURL
        try save(config)
        return config
    }

    private func load() throws -> CicadaRelayConfig {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let config = try decoder.decode(CicadaRelayConfig.self, from: data)
        try validate(config)
        return config
    }

    private func save(_ config: CicadaRelayConfig) throws {
        try validate(config)

        let directory = (path as NSString).deletingLastPathComponent
        try fileManager.createDirectory(atPath: directory, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)
        try data.write(to: URL(fileURLWithPath: path), options: .atomic)
        _ = chmod(path, 0o600)
    }

    private func validateRelayURL(_ relayURL: String) throws {
        guard !relayURL.isEmpty else {
            throw StoreError.emptyRelayURL
        }
        guard let components = URLComponents(string: relayURL),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              components.host?.isEmpty == false else {
            throw StoreError.invalidRelayURL
        }
    }

    private func validate(_ config: CicadaRelayConfig) throws {
        try validateRelayURL(config.relayURL)
        guard config.deviceId.range(of: #"^MAC_[A-Fa-f0-9]{32}$"#, options: .regularExpression) != nil else {
            throw StoreError.invalidDeviceId
        }
        guard config.reconnectInterval > 0 else {
            throw StoreError.invalidReconnectInterval
        }
        guard config.maxReconnectAttempts >= 0 else {
            throw StoreError.invalidMaxReconnectAttempts
        }
        guard config.heartbeatInterval > 0 else {
            throw StoreError.invalidHeartbeatInterval
        }
        guard config.connectionTimeout > 0 else {
            throw StoreError.invalidConnectionTimeout
        }
    }
}
