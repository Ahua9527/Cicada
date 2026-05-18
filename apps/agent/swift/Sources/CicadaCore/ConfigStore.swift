import Foundation

public final class ConfigStore {
    private let path: String
    private let fm = FileManager.default

    public init(path: String = RuntimePaths.configPath) {
        self.path = path
    }

    public func configPath() -> String {
        path
    }

    public func exists() -> Bool {
        fm.fileExists(atPath: path)
    }

    public func load() throws -> CicadaConfig {
        guard exists() else {
            throw CicadaError.io("配置文件不存在: \(path)")
        }
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let config = try JSONDecoder().decode(CicadaConfig.self, from: data)
        try config.validate()
        return config
    }

    public func save(_ config: CicadaConfig) throws {
        try config.validate()
        let dir = (path as NSString).deletingLastPathComponent
        try fm.createDirectory(atPath: dir, withIntermediateDirectories: true)

        let tempPath = path + ".tmp"
        let data = try JSONEncoder.pretty.encode(config)
        try data.write(to: URL(fileURLWithPath: tempPath), options: .atomic)

        _ = chmod(tempPath, 0o600)
        if fm.fileExists(atPath: path) {
            try fm.removeItem(atPath: path)
        }
        try fm.moveItem(atPath: tempPath, toPath: path)
    }

    public func initializeDefault() throws -> CicadaConfig {
        if exists() {
            return try load()
        }
        let config = CicadaConfig.defaultConfig()
        try save(config)
        return config
    }

    public func set(key: String, value: String) throws {
        var config = try load()
        switch key {
        case "relayURL":
            config.relayURL = value
        case "deviceId":
            config.deviceId = value
        case "apiKey":
            config.apiKey = value
        case "autoConnect":
            config.autoConnect = try parseBool(value, key: key)
        case "showNotifications":
            config.showNotifications = try parseBool(value, key: key)
        case "enableAutoReconnect":
            config.enableAutoReconnect = try parseBool(value, key: key)
        case "reconnectInterval":
            config.reconnectInterval = try parseInt(value, key: key)
        case "maxReconnectAttempts":
            config.maxReconnectAttempts = try parseInt(value, key: key)
        case "heartbeatInterval":
            config.heartbeatInterval = try parseInt(value, key: key)
        case "connectionTimeout":
            config.connectionTimeout = try parseInt(value, key: key)
        default:
            throw CicadaError.validation("不支持的配置项: \(key)")
        }
        try save(config)
    }

    public func getValue(key: String) throws -> String {
        let config = try load()
        switch key {
        case "relayURL":
            return config.relayURL
        case "deviceId":
            return config.deviceId
        case "apiKey":
            return config.apiKey
        case "autoConnect":
            return String(config.autoConnect)
        case "showNotifications":
            return String(config.showNotifications)
        case "enableAutoReconnect":
            return String(config.enableAutoReconnect)
        case "reconnectInterval":
            return String(config.reconnectInterval)
        case "maxReconnectAttempts":
            return String(config.maxReconnectAttempts)
        case "heartbeatInterval":
            return String(config.heartbeatInterval)
        case "connectionTimeout":
            return String(config.connectionTimeout)
        default:
            throw CicadaError.validation("不支持的配置项: \(key)")
        }
    }

    private func parseBool(_ raw: String, key: String) throws -> Bool {
        switch raw.lowercased() {
        case "true":
            return true
        case "false":
            return false
        default:
            throw CicadaError.validation("\(key) 仅允许 true|false")
        }
    }

    private func parseInt(_ raw: String, key: String) throws -> Int {
        guard let value = Int(raw) else {
            throw CicadaError.validation("\(key) 必须是数字")
        }
        return value
    }
}

private extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
