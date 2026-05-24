import CryptoKit
import Foundation

public enum RelayIdentityError: Error, CustomStringConvertible {
    case invalidBase64(String)
    case invalidStoredIdentity

    public var description: String {
        switch self {
        case let .invalidBase64(field):
            return "invalid base64: \(field)"
        case .invalidStoredIdentity:
            return "invalid stored relay identity"
        }
    }
}

public struct RelayIdentity {
    public let identityId: String
    private let signingPrivateKey: Curve25519.Signing.PrivateKey

    public var signingPublicKeyBase64: String {
        signingPrivateKey.publicKey.rawRepresentation.base64EncodedString()
    }

    public static func generate(identityId: String) -> RelayIdentity {
        RelayIdentity(
            identityId: identityId,
            signingPrivateKey: Curve25519.Signing.PrivateKey()
        )
    }

    public static func verifySignature(
        publicKeyBase64: String,
        message: Data,
        signatureBase64: String
    ) -> Bool {
        guard let keyData = Data(base64Encoded: publicKeyBase64),
              let signature = Data(base64Encoded: signatureBase64),
              let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData) else {
            return false
        }
        return publicKey.isValidSignature(signature, for: message)
    }

    public func signBase64(_ message: Data) throws -> String {
        try signingPrivateKey.signature(for: message).base64EncodedString()
    }

    fileprivate var stored: StoredRelayIdentity {
        StoredRelayIdentity(
            version: 1,
            identityId: identityId,
            signingPrivateKey: signingPrivateKey.rawRepresentation.base64EncodedString()
        )
    }

    fileprivate init(stored: StoredRelayIdentity) throws {
        guard let signingData = Data(base64Encoded: stored.signingPrivateKey) else {
            throw RelayIdentityError.invalidStoredIdentity
        }
        self.identityId = stored.identityId
        self.signingPrivateKey = try Curve25519.Signing.PrivateKey(rawRepresentation: signingData)
    }

    private init(
        identityId: String,
        signingPrivateKey: Curve25519.Signing.PrivateKey
    ) {
        self.identityId = identityId
        self.signingPrivateKey = signingPrivateKey
    }
}

private struct StoredRelayIdentity: Codable {
    let version: Int
    let identityId: String
    let signingPrivateKey: String
}

public final class RelayIdentityStore {
    private let path: String
    private let fm: FileManager

    public init(path: String, fileManager: FileManager = .default) {
        self.path = path
        self.fm = fileManager
    }

    public convenience init(agentPath: String = RuntimePaths.agentIdentityPath) {
        self.init(path: agentPath)
    }

    public func loadOrCreate(identityId: String) throws -> RelayIdentity {
        if fm.fileExists(atPath: path) {
            return try load()
        }
        let identity = RelayIdentity.generate(identityId: identityId)
        try save(identity)
        return identity
    }

    public func load() throws -> RelayIdentity {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let stored = try JSONDecoder().decode(StoredRelayIdentity.self, from: data)
        return try RelayIdentity(stored: stored)
    }

    public func save(_ identity: RelayIdentity) throws {
        let directory = (path as NSString).deletingLastPathComponent
        try fm.createDirectory(atPath: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder.prettyIdentity.encode(identity.stored)
        let tempPath = path + ".tmp"
        try data.write(to: URL(fileURLWithPath: tempPath), options: .atomic)
        _ = chmod(tempPath, 0o600)
        if fm.fileExists(atPath: path) {
            try fm.removeItem(atPath: path)
        }
        try fm.moveItem(atPath: tempPath, toPath: path)
    }
}

private extension JSONEncoder {
    static var prettyIdentity: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
