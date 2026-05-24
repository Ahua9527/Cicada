import CryptoKit
import Foundation
import Security

public struct ShortcutGrant: Codable, Equatable {
    public let grantId: String
    public let deviceId: String
    public let name: String
    public let tokenHash: String
    public let tokenPreview: String
    public let allowedCommands: [String]
    public let expiresAt: Int64
    public let revokedAt: Int64?
    public let createdAt: Int64
    public let updatedAt: Int64

    public init(
        grantId: String,
        deviceId: String,
        name: String,
        tokenHash: String,
        tokenPreview: String,
        allowedCommands: [String],
        expiresAt: Int64,
        revokedAt: Int64? = nil,
        createdAt: Int64,
        updatedAt: Int64
    ) {
        self.grantId = grantId
        self.deviceId = deviceId
        self.name = name
        self.tokenHash = tokenHash
        self.tokenPreview = tokenPreview
        self.allowedCommands = allowedCommands
        self.expiresAt = expiresAt
        self.revokedAt = revokedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var active: Bool {
        revokedAt == nil && expiresAt > Int64(Date().timeIntervalSince1970 * 1000)
    }

    public func revoked(now: Int64) -> ShortcutGrant {
        ShortcutGrant(
            grantId: grantId,
            deviceId: deviceId,
            name: name,
            tokenHash: tokenHash,
            tokenPreview: tokenPreview,
            allowedCommands: allowedCommands,
            expiresAt: expiresAt,
            revokedAt: now,
            createdAt: createdAt,
            updatedAt: now
        )
    }
}

public struct ShortcutGrantCreateResult {
    public let grant: ShortcutGrant
    public let token: String
}

public struct ShortcutGrantAuthorization {
    public let allowed: Bool
    public let code: String?
    public let error: String?
}

public final class ShortcutGrantStore {
    public static let defaultTtlMs: Int64 = 30 * 24 * 60 * 60 * 1000
    public static let maxTtlMs: Int64 = 180 * 24 * 60 * 60 * 1000

    private let path: String
    private let fm: FileManager

    public init(path: String = RuntimePaths.shortcutGrantPath, fileManager: FileManager = .default) {
        self.path = path
        self.fm = fileManager
    }

    public func create(
        deviceId: String,
        name: String,
        commands: [String],
        ttlMs: Int64,
        now: Date = Date()
    ) throws -> ShortcutGrantCreateResult {
        let nowMs = Int64(now.timeIntervalSince1970 * 1000)
        let ttl = min(max(ttlMs, 1), Self.maxTtlMs)
        let token = "cicada_sc_\(Self.randomBase64URL(byteCount: 32))"
        let grant = ShortcutGrant(
            grantId: "grant-\(UUID().uuidString.lowercased())",
            deviceId: deviceId,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Shortcut" : name,
            tokenHash: Self.hashToken(token),
            tokenPreview: Self.previewToken(token),
            allowedCommands: Self.normalizeCommands(commands),
            expiresAt: nowMs + ttl,
            createdAt: nowMs,
            updatedAt: nowMs
        )
        var grants = try list()
        grants.append(grant)
        try save(grants)
        return ShortcutGrantCreateResult(grant: grant, token: token)
    }

    public func list() throws -> [ShortcutGrant] {
        guard fm.fileExists(atPath: path) else {
            return []
        }
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        return try JSONDecoder().decode([ShortcutGrant].self, from: data)
    }

    public func activeGrants(now: Date = Date()) throws -> [ShortcutGrant] {
        let nowMs = Int64(now.timeIntervalSince1970 * 1000)
        return try list().filter { $0.revokedAt == nil && $0.expiresAt > nowMs }
    }

    public func revoke(grantId: String, now: Date = Date()) throws -> ShortcutGrant {
        let nowMs = Int64(now.timeIntervalSince1970 * 1000)
        var grants = try list()
        guard let index = grants.firstIndex(where: { $0.grantId == grantId }) else {
            throw ShortcutGrantStoreError.notFound
        }
        let revoked = grants[index].revoked(now: nowMs)
        grants[index] = revoked
        try save(grants)
        return revoked
    }

    public func authorize(grantId: String, command: String, now: Date = Date()) -> ShortcutGrantAuthorization {
        guard let grants = try? list(),
              let grant = grants.first(where: { $0.grantId == grantId }) else {
            return ShortcutGrantAuthorization(allowed: false, code: "invalid_token", error: "Shortcut grant is unknown.")
        }
        let nowMs = Int64(now.timeIntervalSince1970 * 1000)
        if grant.revokedAt != nil {
            return ShortcutGrantAuthorization(allowed: false, code: "grant_revoked", error: "Shortcut grant has been revoked.")
        }
        if nowMs >= grant.expiresAt {
            return ShortcutGrantAuthorization(allowed: false, code: "grant_expired", error: "Shortcut grant has expired.")
        }
        if !grant.allowedCommands.contains(command) {
            return ShortcutGrantAuthorization(allowed: false, code: "command_not_allowed", error: "Shortcut grant does not allow this command.")
        }
        return ShortcutGrantAuthorization(allowed: true, code: nil, error: nil)
    }

    private func save(_ grants: [ShortcutGrant]) throws {
        let directory = (path as NSString).deletingLastPathComponent
        try fm.createDirectory(atPath: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(grants)
        let tempPath = path + ".tmp"
        try data.write(to: URL(fileURLWithPath: tempPath), options: .atomic)
        _ = chmod(tempPath, 0o600)
        if fm.fileExists(atPath: path) {
            try fm.removeItem(atPath: path)
        }
        try fm.moveItem(atPath: tempPath, toPath: path)
    }

    public static func normalizeCommands(_ commands: [String]) -> [String] {
        let trimmed = commands.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        if trimmed.contains("all") {
            return RemoteCommand.allCases.map(\.rawValue)
        }
        let valid = Set(RemoteCommand.allCases.map(\.rawValue))
        let normalized = trimmed.filter { valid.contains($0) }
        let unique = Array(NSOrderedSet(array: normalized)) as? [String] ?? []
        return unique.isEmpty ? ["ping", "status"] : unique
    }

    public static func hashToken(_ token: String) -> String {
        let digest = SHA256.hash(data: Data(token.utf8))
        return base64URL(Data(digest))
    }

    public static func previewToken(_ token: String) -> String {
        let prefix = token.prefix(14)
        let suffix = token.suffix(4)
        return "\(prefix)...\(suffix)"
    }

    private static func randomBase64URL(byteCount: Int) -> String {
        var bytes = Data(count: byteCount)
        bytes.withUnsafeMutableBytes { buffer in
            _ = SecRandomCopyBytes(kSecRandomDefault, buffer.count, buffer.baseAddress!)
        }
        return base64URL(bytes)
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

public enum ShortcutGrantStoreError: Error {
    case notFound
}
