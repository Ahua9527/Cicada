import Foundation
import XCTest

final class CommandExecutionDependencyTests: XCTestCase {
    func testCommandExecutionLayerDoesNotCallExternalCommandBinaries() throws {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let roots = [
            packageRoot.appendingPathComponent("Sources/CicadaSystem"),
            packageRoot.appendingPathComponent("Tests/CicadaSystemTests"),
        ]
        let forbidden = [
            "blue" + "util",
            "CG" + "Session",
            "osa" + "script",
            "pm" + "set",
            "/usr/bin/" + "caffeinate",
            "kill" + "all",
            "commandExists(",
            "isProcessRunning(",
        ]
        var violations: [String] = []

        for root in roots {
            guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else {
                continue
            }
            for case let file as URL in enumerator where file.pathExtension == "swift" {
                if file.lastPathComponent == "CommandExecutionDependencyTests.swift" {
                    continue
                }
                let text = try String(contentsOf: file)
                for token in forbidden where text.contains(token) {
                    violations.append("\(file.lastPathComponent): \(token)")
                }
            }
        }

        XCTAssertEqual(violations, [], violations.joined(separator: "\n"))
    }
}
