import Foundation
import XCTest
@testable import CicadaCore

final class ConfigStoreTests: XCTestCase {
    func testDefaultConfigValidation() throws {
        let config = CicadaConfig.defaultConfig()
        XCTAssertNoThrow(try config.validate())
    }

    func testConfigStoreRoundtrip() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("cicada-swift-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let configPath = tempDir.appendingPathComponent("config.json").path
        let store = ConfigStore(path: configPath)

        var config = CicadaConfig.defaultConfig()
        config.relayURL = "https://example.com"

        try store.save(config)
        let loaded = try store.load()

        XCTAssertEqual(loaded.relayURL, config.relayURL)
        XCTAssertEqual(loaded.deviceId, config.deviceId)
    }

    func testConfigLoadIgnoresObsoleteApiKeyFieldAndSaveDropsIt() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("cicada-swift-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let configPath = tempDir.appendingPathComponent("config.json").path
        let store = ConfigStore(path: configPath)
        let raw = """
        {
          "relayURL": "https://example.com",
          "deviceId": "MAC_0123456789ABCDEF0123456789ABCDEF",
          "apiKey": "legacy-unused",
          "autoConnect": true,
          "showNotifications": true,
          "enableAutoReconnect": true,
          "reconnectInterval": 5000,
          "maxReconnectAttempts": 10,
          "heartbeatInterval": 30000,
          "connectionTimeout": 10000
        }
        """
        try raw.write(toFile: configPath, atomically: true, encoding: .utf8)

        let loaded = try store.load()
        XCTAssertEqual(loaded.relayURL, "https://example.com")
        XCTAssertEqual(loaded.deviceId, "MAC_0123456789ABCDEF0123456789ABCDEF")

        try store.save(loaded)
        let saved = try String(contentsOfFile: configPath, encoding: .utf8)
        XCTAssertFalse(saved.contains("apiKey"))
    }

    func testConfigValidationRejectsInvalidDeviceIdFormat() {
        var config = CicadaConfig.defaultConfig()
        config.deviceId = "dev_1"
        XCTAssertThrowsError(try config.validate())
    }

    func testConfigValidationRejectsInvalidConnectionTimeout() {
        var config = CicadaConfig.defaultConfig()
        config.connectionTimeout = 0
        XCTAssertThrowsError(try config.validate())
    }
}
