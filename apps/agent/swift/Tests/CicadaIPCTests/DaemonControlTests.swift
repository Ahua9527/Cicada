import Darwin
import Foundation
import XCTest
@testable import CicadaCore
@testable import CicadaIPC

final class DaemonControlTests: XCTestCase {
    func testDaemonControlRequestAndResponseRoundTrip() throws {
        let request = DaemonControlRequest(action: .shortcutGrantList)
        let decodedRequest = try JSONDecoder().decode(
            DaemonControlRequest.self,
            from: try JSONEncoder().encode(request)
        )
        XCTAssertEqual(decodedRequest.action, .shortcutGrantList)

        let response = DaemonControlResponse(ok: true, shortcutGrants: [])
        let decodedResponse = try JSONDecoder().decode(
            DaemonControlResponse.self,
            from: try JSONEncoder().encode(response)
        )
        XCTAssertTrue(decodedResponse.ok)
        XCTAssertEqual(decodedResponse.shortcutGrants?.count, 0)
    }

    func testClientReportsUnavailableSocket() {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("missing-cicada-daemon-\(UUID().uuidString).sock")
            .path
        let client = UdsDaemonControlClient(socketPath: path, timeoutMs: 100)

        XCTAssertThrowsError(try client.shortcutGrantList())
        XCTAssertThrowsError(try client.powerAssertionStart())
    }

    func testShortcutGrantControlPayloadsRoundTrip() throws {
        let request = DaemonControlRequest(
            action: .shortcutGrantCreate,
            name: "Phone",
            commands: ["ping", "status"],
            ttlMs: 60_000
        )
        let decodedRequest = try JSONDecoder().decode(
            DaemonControlRequest.self,
            from: try JSONEncoder().encode(request)
        )
        XCTAssertEqual(decodedRequest.action, .shortcutGrantCreate)
        XCTAssertEqual(decodedRequest.name, "Phone")
        XCTAssertEqual(decodedRequest.commands, ["ping", "status"])
        XCTAssertEqual(decodedRequest.ttlMs, 60_000)

        let grant = ShortcutGrant(
            grantId: "grant-1",
            deviceId: "MAC_0123456789ABCDEF0123456789ABCDEF",
            name: "Phone",
            tokenHash: "hash",
            tokenPreview: "cicada_sc_ab...1234",
            allowedCommands: ["ping"],
            expiresAt: 2,
            createdAt: 1,
            updatedAt: 1
        )
        let response = DaemonControlResponse(ok: true, shortcutToken: "cicada_sc_secret", shortcutGrant: grant)
        let decodedResponse = try JSONDecoder().decode(
            DaemonControlResponse.self,
            from: try JSONEncoder().encode(response)
        )
        XCTAssertEqual(decodedResponse.shortcutToken, "cicada_sc_secret")
        XCTAssertEqual(decodedResponse.shortcutGrant?.grantId, "grant-1")
    }

    func testPowerAssertionControlPayloadsRoundTrip() throws {
        let request = DaemonControlRequest(action: .powerAssertionStart)
        let decodedRequest = try JSONDecoder().decode(
            DaemonControlRequest.self,
            from: try JSONEncoder().encode(request)
        )
        XCTAssertEqual(decodedRequest.action, .powerAssertionStart)

        let result = CommandExecutionResult(success: true, message: "防休眠已启动")
        let response = DaemonControlResponse(ok: true, commandResult: result)
        let decodedResponse = try JSONDecoder().decode(
            DaemonControlResponse.self,
            from: try JSONEncoder().encode(response)
        )
        XCTAssertEqual(decodedResponse.commandResult, result)
    }

    func testSentinelInstallRemovesLegacyNotifierLaunchAgentAndBinary() throws {
        let fixture = try SentinelAppManagerFixture()
        try fixture.createSourceApp()
        try fixture.createLegacyNotifierArtifacts()

        try fixture.manager.install(sourceAppPath: fixture.sourceAppPath)

        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.paths.legacyNotifierPlistPath))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.paths.legacyNotifierBinaryPath))
        XCTAssertTrue(fixture.runner.calls.contains(.init("/bin/launchctl", ["stop", fixture.paths.legacyNotifierLabel])))
        XCTAssertTrue(fixture.runner.calls.contains(.init("/bin/launchctl", ["unload", fixture.paths.legacyNotifierPlistPath])))
    }

    func testSentinelInstallUsesCrashOnlyKeepAlive() throws {
        let fixture = try SentinelAppManagerFixture()
        try fixture.createSourceApp()

        try fixture.manager.install(sourceAppPath: fixture.sourceAppPath)

        let data = try Data(contentsOf: URL(fileURLWithPath: fixture.paths.sentinelPlistPath))
        let plist = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
        )
        let keepAlive = try XCTUnwrap(plist["KeepAlive"] as? [String: Any])
        XCTAssertEqual(keepAlive["Crashed"] as? Bool, true)
        XCTAssertFalse(plist["KeepAlive"] is Bool)
    }

    func testSentinelStopLeavesLaunchAgentLoaded() throws {
        let fixture = try SentinelAppManagerFixture()

        fixture.manager.stop()

        XCTAssertTrue(fixture.runner.calls.contains(.init("/bin/launchctl", ["stop", fixture.paths.sentinelLabel])))
        XCTAssertFalse(fixture.runner.calls.contains(.init("/bin/launchctl", ["unload", fixture.paths.sentinelPlistPath])))
    }

    func testSentinelEnsureStartedWaitsForNotifierSocketInsteadOfControlSocketOnly() throws {
        let fixture = try SentinelAppManagerFixture()
        try fixture.createInstalledSentinel()
        try FileManager.default.createDirectory(
            atPath: (fixture.paths.sentinelSocketPath as NSString).deletingLastPathComponent,
            withIntermediateDirectories: true
        )
        FileManager.default.createFile(atPath: fixture.paths.sentinelSocketPath, contents: Data())
        fixture.runner.listStdout = fixture.paths.sentinelLabel

        XCTAssertFalse(fixture.manager.ensureStarted())
    }

    func testSentinelStatusIgnoresStaleNotifierSocketFile() throws {
        let fixture = try SentinelAppManagerFixture()
        try fixture.createInstalledSentinel()
        try FileManager.default.createDirectory(
            atPath: (fixture.paths.notifierSocketPath as NSString).deletingLastPathComponent,
            withIntermediateDirectories: true
        )
        FileManager.default.createFile(atPath: fixture.paths.notifierSocketPath, contents: Data())
        fixture.runner.listStdout = fixture.paths.sentinelLabel

        let status = fixture.manager.status()

        XCTAssertFalse(status.notifierSocketReady)
        XCTAssertFalse(status.running)
        XCTAssertFalse(fixture.manager.ensureStarted())
    }

    func testSentinelStatusRequiresNotifierAndControlSockets() throws {
        let fixture = try SentinelAppManagerFixture()
        try fixture.createInstalledSentinel()
        fixture.runner.listStdout = fixture.paths.sentinelLabel

        let notifierServer = try UnixSocketServer(path: fixture.paths.notifierSocketPath)
        var status = fixture.manager.status()
        XCTAssertTrue(status.notifierSocketReady)
        XCTAssertFalse(status.sentinelSocketReady)
        XCTAssertFalse(status.running)

        let sentinelServer = try UnixSocketServer(path: fixture.paths.sentinelSocketPath)
        status = fixture.manager.status()
        XCTAssertTrue(status.notifierSocketReady)
        XCTAssertTrue(status.sentinelSocketReady)
        XCTAssertTrue(status.running)

        _ = notifierServer
        _ = sentinelServer
    }
}

private struct ProcessCall: Equatable {
    let command: String
    let args: [String]

    init(_ command: String, _ args: [String]) {
        self.command = command
        self.args = args
    }
}

private final class RecordingProcessRunner: ProcessRunning {
    private(set) var calls: [ProcessCall] = []
    var listStdout = ""

    func run(_ command: String, args: [String], timeoutMs _: Int) -> ProcessResult {
        calls.append(.init(command, args))
        if command == "/bin/launchctl", args == ["list"] {
            return ProcessResult(stdout: listStdout, stderr: "", code: 0)
        }
        return ProcessResult(stdout: "", stderr: "", code: 0)
    }
}

private final class SentinelAppManagerFixture {
    let root: URL
    let paths: SentinelAppRuntimePaths
    let runner = RecordingProcessRunner()
    let manager: SentinelAppManager
    let sourceAppPath: String

    init() throws {
        root = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("csm-\(UUID().uuidString)", isDirectory: true)
        let home = root.appendingPathComponent("home", isDirectory: true)
        let cicadaHome = home.appendingPathComponent(".cicada", isDirectory: true)
        let runDir = cicadaHome.appendingPathComponent("run", isDirectory: true)
        let appsDir = cicadaHome.appendingPathComponent("apps", isDirectory: true)
        let binDir = cicadaHome.appendingPathComponent("bin", isDirectory: true)
        let launchAgentsDir = home.appendingPathComponent("Library/LaunchAgents", isDirectory: true)
        paths = SentinelAppRuntimePaths(
            runDir: runDir.path,
            sentinelLabel: "com.cicada.sentinel.test",
            sentinelAppPath: appsDir.appendingPathComponent("Sentry.app", isDirectory: true).path,
            sentinelPlistPath: launchAgentsDir.appendingPathComponent("com.cicada.sentinel.test.plist").path,
            sentinelStdoutPath: cicadaHome.appendingPathComponent("sentinel.stdout.log").path,
            sentinelStderrPath: cicadaHome.appendingPathComponent("sentinel.stderr.log").path,
            notifierSocketPath: runDir.appendingPathComponent("notifier.sock").path,
            sentinelSocketPath: runDir.appendingPathComponent("sentinel.sock").path,
            daemonSocketPath: runDir.appendingPathComponent("daemon.sock").path,
            notchDropDirectoryPath: cicadaHome.appendingPathComponent("notchdrop", isDirectory: true).path,
            legacyNotifierLabel: "com.cicada.notifier.test",
            legacyNotifierPlistPath: launchAgentsDir.appendingPathComponent("com.cicada.notifier.test.plist").path,
            legacyNotifierBinaryPath: binDir.appendingPathComponent("cicada-notifier").path
        )
        sourceAppPath = root.appendingPathComponent("source/Sentry.app", isDirectory: true).path
        manager = SentinelAppManager(
            runner: runner,
            paths: paths,
            waitForNotifierAttempts: 1,
            waitIntervalMicros: 0
        )
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    func createSourceApp() throws {
        let executable = URL(fileURLWithPath: sourceAppPath)
            .appendingPathComponent("Contents/MacOS/Sentry")
        try FileManager.default.createDirectory(
            at: executable.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        FileManager.default.createFile(atPath: executable.path, contents: Data())
    }

    func createLegacyNotifierArtifacts() throws {
        try FileManager.default.createDirectory(
            atPath: (paths.legacyNotifierPlistPath as NSString).deletingLastPathComponent,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            atPath: (paths.legacyNotifierBinaryPath as NSString).deletingLastPathComponent,
            withIntermediateDirectories: true
        )
        FileManager.default.createFile(atPath: paths.legacyNotifierPlistPath, contents: Data())
        FileManager.default.createFile(atPath: paths.legacyNotifierBinaryPath, contents: Data())
    }

    func createInstalledSentinel() throws {
        let executable = URL(fileURLWithPath: paths.sentinelAppPath)
            .appendingPathComponent("Contents/MacOS/Sentry")
        try FileManager.default.createDirectory(
            at: executable.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        FileManager.default.createFile(atPath: executable.path, contents: Data())
        try FileManager.default.createDirectory(
            atPath: (paths.sentinelPlistPath as NSString).deletingLastPathComponent,
            withIntermediateDirectories: true
        )
        FileManager.default.createFile(atPath: paths.sentinelPlistPath, contents: Data())
    }
}

private final class UnixSocketServer {
    private let fd: Int32
    private let path: String

    init(path: String) throws {
        self.path = path
        try FileManager.default.createDirectory(
            atPath: (path as NSString).deletingLastPathComponent,
            withIntermediateDirectories: true
        )

        fd = socket(AF_UNIX, SOCK_STREAM, 0)
        if fd < 0 {
            throw POSIXError(.EIO)
        }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let maxPathLength = MemoryLayout.size(ofValue: addr.sun_path)
        guard path.utf8.count < maxPathLength else {
            close(fd)
            throw DaemonControlError.socketPathTooLong
        }

        unlink(path)
        withUnsafeMutableBytes(of: &addr.sun_path) { buffer in
            buffer.initializeMemory(as: CChar.self, repeating: 0)
            _ = path.withCString { source in
                strncpy(buffer.baseAddress?.assumingMemoryBound(to: CChar.self), source, maxPathLength - 1)
            }
        }

        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        if bound != 0 {
            close(fd)
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }

        if listen(fd, 4) != 0 {
            close(fd)
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    deinit {
        close(fd)
        unlink(path)
    }
}
