import CicadaCore
import Foundation

/// `SentryConfiguration` → `~/.cicada/sentry-config.json` 持久化。
///
/// - 原子替换目标文件，避免保存失败时先删除已有配置。
/// - 首次加载时从 UserDefaults 旧 key `"sentry.config"` 迁移；仅在写入成功后清空旧值。
/// `@unchecked Sendable`：所有实例字段（path/fm/legacyKey/legacyDefaults）均为 `let`，
/// `save(_:)` 仅调用线程安全的 FileManager/UserDefaults API，可安全跨任务逃逸。
public final class SentryConfigStore: @unchecked Sendable {
    private let path: String
    private let fm = FileManager.default
    private let legacyKey = "sentry.config"
    private let legacyDefaults: UserDefaults

    /// 创建 SentryConfigStore。
    /// - Parameter path: 配置文件路径，默认 `~/.cicada/sentry-config.json`。
    public init(
        path: String = RuntimePaths.cicadaHome + "/sentry-config.json",
        legacyDefaults: UserDefaults = .standard
    ) {
        self.path = path
        self.legacyDefaults = legacyDefaults
    }

    /// 加载配置。优先级：文件 > UserDefaults 旧值（迁移后清空） > 默认值。
    public func load() -> SentryConfiguration {
        // 1. 先尝试文件
        if fm.fileExists(atPath: path),
           let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
           let cfg = try? JSONDecoder().decode(SentryConfiguration.self, from: data) {
            if legacyDefaults.data(forKey: legacyKey) != nil, chmod(path, 0o600) == 0 {
                legacyDefaults.removeObject(forKey: legacyKey)
            }
            return cfg
        }
        // 2. 迁移 UserDefaults 旧值
        if let legacy = legacyDefaults.data(forKey: legacyKey),
           let cfg = try? JSONDecoder().decode(SentryConfiguration.self, from: legacy) {
            do {
                try save(cfg)
                legacyDefaults.removeObject(forKey: legacyKey)
            } catch {
                // 保留 legacy，下一次启动继续迁移。
            }
            return cfg
        }
        // 3. 默认值
        return .init()
    }

    /// 原子写入配置到文件。
    public func save(_ config: SentryConfiguration) throws {
        let dir = (path as NSString).deletingLastPathComponent
        try fm.createDirectory(atPath: dir, withIntermediateDirectories: true)

        let data = try JSONEncoder.pretty.encode(config)
        try data.write(to: URL(fileURLWithPath: path), options: .atomic)
        if chmod(path, 0o600) != 0 {
            throw CocoaError(.fileWriteUnknown)
        }
    }
}

private extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
