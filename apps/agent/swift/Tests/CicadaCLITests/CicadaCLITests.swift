import Foundation
import XCTest
@testable import CicadaCLI
@testable import CicadaCore
@testable import CicadaIPC
@testable import CicadaSleepHoldCore
@testable import CicadaSystem

private final class FakeDaemonManager: DaemonManaging {
    var statusValue = DaemonStatus(installed: true, running: true, plistPath: "/tmp/agent.plist", binaryPath: "/tmp/cicada-agent")
    private(set) var calls: [String] = []

    func install() throws { calls.append("install") }
    func start() throws { calls.append("start") }
    func stop() { calls.append("stop") }
    func restart() throws { calls.append("restart") }
    func uninstall() { calls.append("uninstall") }
    func status() -> DaemonStatus { statusValue }
    func logPaths() -> [String] { ["/tmp/daemon.log"] }
}

private final class FakeNotifierManager: NotifierManaging {
    var statusValue = NotifierStatus(
        installed: true,
        running: true,
        plistPath: "/tmp/notifier.plist",
        binaryPath: "/tmp/cicada-notifier",
        socketPath: "/tmp/notifier.sock"
    )
    private(set) var calls: [String] = []

    func install() throws { calls.append("install") }
    func start() throws { calls.append("start") }
    func stop() { calls.append("stop") }
    func restart() throws { calls.append("restart") }
    func uninstall() { calls.append("uninstall") }
    func status() -> NotifierStatus { statusValue }
}

private final class FakeSleepHoldManager: SleepHoldManaging {
    var statusValue = SleepHoldServiceStatus(
        installed: true,
        running: true,
        plistPath: "/Library/LaunchDaemons/com.cicada.sleephold.plist",
        binaryPath: "/tmp/cicada-sleephold",
        socketPath: "/tmp/sleephold.sock",
        powerStatus: .canSleep,
        activeSessions: 0
    )
    private(set) var calls: [String] = []

    func install() throws { calls.append("install") }
    func uninstall() { calls.append("uninstall") }
    func status() -> SleepHoldServiceStatus { statusValue }

    func ping() throws -> SleepHoldControlResponse {
        calls.append("ping")
        return SleepHoldControlResponse(ok: true, message: "pong")
    }

    func createSession() throws -> SleepHoldControlResponse {
        calls.append("create")
        return SleepHoldControlResponse(ok: true, sessionId: "sleep-session-1", status: .hold, activeSessions: 1)
    }

    func extendSession(_ sessionId: String) throws -> SleepHoldControlResponse {
        calls.append("extend:\(sessionId)")
        return SleepHoldControlResponse(ok: true, sessionId: sessionId, status: .hold, activeSessions: 1)
    }

    func terminateSession(_ sessionId: String) throws -> SleepHoldControlResponse {
        calls.append("terminate:\(sessionId)")
        return SleepHoldControlResponse(ok: true, sessionId: sessionId, status: .canSleep, activeSessions: 0)
    }
}

private final class FakeDaemonControlClient: DaemonControlClienting {
    var createCommands: [String] = []
    var createToken = "cicada_sc_secret"
    var unavailable = false

    func shortcutGrantCreate(name: String, commands: [String], ttlMs: Int64) throws -> DaemonControlResponse {
        if unavailable { throw DaemonControlError.unavailable("missing socket") }
        createCommands = commands
        return DaemonControlResponse(
            ok: true,
            shortcutToken: createToken,
            shortcutGrant: ShortcutGrant(
                grantId: "grant-1",
                deviceId: "MAC_0123456789ABCDEF0123456789ABCDEF",
                name: name,
                tokenHash: "hash",
                tokenPreview: "cicada_sc_se...cret",
                allowedCommands: ShortcutGrantStore.normalizeCommands(commands),
                expiresAt: 2,
                createdAt: 1,
                updatedAt: 1
            )
        )
    }

    func shortcutGrantList() throws -> DaemonControlResponse {
        DaemonControlResponse(ok: true, shortcutGrants: [])
    }

    func shortcutGrantRevoke(grantId: String) throws -> DaemonControlResponse {
        DaemonControlResponse(ok: true)
    }

    func powerAssertionStart() throws -> DaemonControlResponse {
        throw DaemonControlError.unavailable("missing socket")
    }

    func powerAssertionStop() throws -> DaemonControlResponse {
        throw DaemonControlError.unavailable("missing socket")
    }
}

private final class FakeCommandExecutor: LocalCommandExecuting {
    private(set) var commands: [String] = []

    func execute(command rawCommand: String) -> CommandExecutionResult {
        commands.append(rawCommand)
        if rawCommand == "ping" {
            return CommandExecutionResult(success: true, message: "pong")
        }
        return CommandExecutionResult(success: false, message: "nope")
    }
}

final class CicadaCLITests: XCTestCase {
    func testDefaultHelpShowsOnlyUserFacingCommands() {
        let fixture = CLIFixture()

        let result = fixture.cli.run(arguments: [])

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("cicada setup --relay-url"))
        XCTAssertTrue(result.stdout.contains("cicada shortcut create"))
        XCTAssertFalse(result.stdout.contains("daemon install|start"))
        XCTAssertFalse(result.stdout.contains("relay shortcut grant"))
        XCTAssertFalse(result.stdout.contains("command run"))
    }

    func testSetupWithRelayURLCreatesConfig() throws {
        let fixture = CLIFixture()

        let result = fixture.cli.run(arguments: ["setup", "--relay-url", "https://relay.example.com"])

        XCTAssertEqual(result.exitCode, 0)
        let config = try fixture.configStore.load()
        XCTAssertEqual(config.relayURL, "https://relay.example.com")
        XCTAssertTrue(result.stdout.contains("cicada start"))
    }

    func testStartInstallsMissingServices() {
        let fixture = CLIFixture()
        _ = fixture.cli.run(arguments: ["setup", "--relay-url", "https://relay.example.com"])
        fixture.daemon.statusValue = DaemonStatus(installed: false, running: false, plistPath: "/tmp/agent.plist", binaryPath: "/tmp/cicada-agent")
        fixture.notifier.statusValue = NotifierStatus(
            installed: false,
            running: false,
            plistPath: "/tmp/notifier.plist",
            binaryPath: "/tmp/cicada-notifier",
            socketPath: "/tmp/notifier.sock"
        )

        let result = fixture.cli.run(arguments: ["start"])

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(fixture.daemon.calls, ["install", "start"])
        XCTAssertEqual(fixture.notifier.calls, ["install", "start"])
    }

    func testStatusJSONIncludesHealthSections() throws {
        let fixture = CLIFixture()
        _ = fixture.cli.run(arguments: ["setup", "--relay-url", "https://relay.example.com"])

        let result = fixture.cli.run(arguments: ["status", "--json"])

        XCTAssertEqual(result.exitCode, 0)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(result.stdout.utf8)) as? [String: Any])
        XCTAssertEqual(object["health"] as? String, "ready")
        XCTAssertNotNil(object["config"])
        XCTAssertNotNil(object["daemon"])
        XCTAssertNotNil(object["notifier"])
        XCTAssertNotNil(object["nativeCapabilities"])
        XCTAssertNotNil(object["sleepHold"])
    }

    func testShortcutCreateDefaultsAndAllCommands() {
        let fixture = CLIFixture()

        let defaultResult = fixture.cli.run(arguments: ["shortcut", "create"])
        XCTAssertEqual(defaultResult.exitCode, 0)
        XCTAssertEqual(fixture.daemonControl.createCommands, ["ping", "status"])
        XCTAssertTrue(defaultResult.stdout.contains("Authorization: Bearer cicada_sc_secret"))

        let allResult = fixture.cli.run(arguments: ["shortcut", "create", "--commands", "all"])
        XCTAssertEqual(allResult.exitCode, 0)
        XCTAssertEqual(Set(fixture.daemonControl.createCommands), Set(RemoteCommand.allCases.map(\.rawValue)))
    }

    func testRunPingExecutesLocalCommand() {
        let fixture = CLIFixture()

        let result = fixture.cli.run(arguments: ["run", "ping"])

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(fixture.commandExecutor.commands, ["ping"])
        XCTAssertTrue(result.stdout.contains("pong"))
    }

    func testRunCaffeinateWithoutDaemonSuggestsStart() {
        let fixture = CLIFixture()

        let result = fixture.cli.run(arguments: ["run", "caffeinate"])

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertTrue(result.stderr.contains("cicada start"))
    }

    func testAdvancedRoutesRemainAvailable() {
        let fixture = CLIFixture()

        XCTAssertEqual(fixture.cli.run(arguments: ["advanced", "config", "path"]).exitCode, 0)
        XCTAssertEqual(fixture.cli.run(arguments: ["advanced", "daemon", "logs"]).exitCode, 0)
        XCTAssertEqual(fixture.cli.run(arguments: ["advanced", "notifier", "status"]).exitCode, 0)
        XCTAssertEqual(fixture.cli.run(arguments: ["advanced", "sleep", "status"]).exitCode, 0)
        XCTAssertEqual(fixture.cli.run(arguments: ["advanced", "doctor", "--json"]).exitCode, 0)
    }

    func testAdvancedSleepHelpListsFullSleepHoldServiceCapabilities() {
        let fixture = CLIFixture()

        let result = fixture.cli.run(arguments: ["advanced", "--help"])

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("cicada advanced sleep install|uninstall|status|ping|create|extend|terminate"))
    }

    func testAdvancedSleepRoutesCoverSleepHoldServiceSessionLifecycle() throws {
        let fixture = CLIFixture()

        XCTAssertEqual(fixture.cli.run(arguments: ["advanced", "sleep", "install"]).exitCode, 0)
        XCTAssertEqual(fixture.sleepHold.calls, ["install"])

        let status = fixture.cli.run(arguments: ["advanced", "sleep", "status"])
        XCTAssertEqual(status.exitCode, 0)
        let statusObject = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(status.stdout.utf8)) as? [String: Any])
        XCTAssertEqual(statusObject["powerStatus"] as? String, "sleep_enabled")

        XCTAssertEqual(fixture.cli.run(arguments: ["advanced", "sleep", "ping"]).stdout.trimmingCharacters(in: .whitespacesAndNewlines), "pong")
        XCTAssertTrue(fixture.cli.run(arguments: ["advanced", "sleep", "create"]).stdout.contains("sleep-session-1"))
        XCTAssertEqual(fixture.cli.run(arguments: ["advanced", "sleep", "extend", "sleep-session-1"]).exitCode, 0)
        XCTAssertEqual(fixture.cli.run(arguments: ["advanced", "sleep", "terminate", "sleep-session-1"]).exitCode, 0)
        XCTAssertEqual(fixture.cli.run(arguments: ["advanced", "sleep", "uninstall"]).exitCode, 0)

        XCTAssertEqual(
            fixture.sleepHold.calls,
            ["install", "ping", "create", "extend:sleep-session-1", "terminate:sleep-session-1", "uninstall"]
        )
    }
}

private final class CLIFixture {
    let directory: URL
    let configStore: ConfigStore
    let daemon = FakeDaemonManager()
    let notifier = FakeNotifierManager()
    let sleepHold = FakeSleepHoldManager()
    let daemonControl = FakeDaemonControlClient()
    let commandExecutor = FakeCommandExecutor()
    let cli: CicadaCLI

    init() {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("cicada-cli-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        configStore = ConfigStore(path: directory.appendingPathComponent("config.json").path)
        cli = CicadaCLI(
            configStore: configStore,
            daemonManager: daemon,
            notifierManager: notifier,
            sleepHoldManager: sleepHold,
            daemonControlClient: daemonControl,
            commandExecutor: commandExecutor,
            nativeCapabilities: {
                [
                    "bluetooth": "on",
                    "accessibilityTrusted": true,
                    "noSleepAssertionActive": false,
                ]
            },
            runtimeSnapshotLoader: { nil }
        )
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }
}
