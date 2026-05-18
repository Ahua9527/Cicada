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
        config.apiKey = "abc123456789"

        try store.save(config)
        let loaded = try store.load()

        XCTAssertEqual(loaded.relayURL, config.relayURL)
        XCTAssertEqual(loaded.apiKey, config.apiKey)
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
