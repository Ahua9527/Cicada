import Foundation
import XCTest
@testable import CicadaCore

final class CommandContractTests: XCTestCase {
    private struct CommandContract: Decodable {
        let protocolVersion: Int
        let commands: [String]

        enum CodingKeys: String, CodingKey {
            case protocolVersion = "protocol_version"
            case commands
        }
    }

    func testSwiftCommandsMatchSharedContract() throws {
        let contract = try loadContract()

        XCTAssertEqual(contract.protocolVersion, 2)
        XCTAssertEqual(contract.commands, RemoteCommand.allCases.map(\.rawValue))
    }

    private func loadContract() throws -> CommandContract {
        var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let relativePath = "packages/shared/protocol/command-contract.json"

        while directory.path != "/" {
            let candidate = directory.appendingPathComponent(relativePath)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return try JSONDecoder().decode(CommandContract.self, from: Data(contentsOf: candidate))
            }
            directory.deleteLastPathComponent()
        }

        XCTFail("Missing shared command contract fixture")
        throw CocoaError(.fileNoSuchFile)
    }
}
