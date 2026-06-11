import Foundation
import XCTest
@testable import CicadaCLI
@testable import CicadaCore
@testable import CicadaIPC
@testable import CicadaSleepHoldCore
@testable import CicadaSystem

private final class FakeDaemonManager: DaemonManaging {
    var statusValue = DaemonStatus(installed: true, running: true, plistPath: "/tmp/agent.plist", binaryPath: "/tmp/cicada-agent")
    var recordCall: ((String) -> Void)?
    private(set) var calls: [String] = []

    func install() throws { append("install") }
    func start() throws { append("start") }
    func stop() { append("stop") }
    func restart() throws { append("restart") }
    func uninstall() { append("uninstall") }
    func status() -> DaemonStatus { statusValue }
    func logPaths() -> [String] { ["/tmp/daemon.log"] }

    private func append(_ call: String) {
        calls.append(call)
        recordCall?("daemon.\(call)")
    }
}

private final class FakeSentinelAppManager: SentinelAppManaging {
    var statusValue = SentinelAppStatus(
        installed: true,
        running: true,
        plistPath: "/tmp/sentinel.plist",
        appPath: "/tmp/Sentry.app",
        socketPath: "/tmp/notifier.sock",
        sentinelSocketPath: "/tmp/sentinel.sock",
        notifierSocketReady: true,
        sentinelSocketReady: true
    )
    var recordCall: ((String) -> Void)?
    private(set) var calls: [String] = []

    func install() throws { append("install") }
    func start() throws { append("start") }
    func stop() { append("stop") }
    func restart() throws { append("restart") }
    func uninstall() { append("uninstall") }
    func status() -> SentinelAppStatus { statusValue }

    private func append(_ call: String) {
        calls.append(call)
        recordCall?("sentinel.\(call)")
    }
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
    var sentryCommands: [String] = []
    var createToken = "cicada_sc_secret"
    var recordCall: ((String) -> Void)?
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
        recordCall?("daemonControl.power_assertion_stop")
        return DaemonControlResponse(
            ok: true,
            commandResult: CommandExecutionResult(success: true, message: "power assertion stopped")
        )
    }

    func sentryStart() throws -> DaemonControlResponse {
        sentry("sentry_start")
    }

    func sentryStop() throws -> DaemonControlResponse {
        sentry("sentry_stop")
    }

    func sentryStatus() throws -> DaemonControlResponse {
        sentry("sentry_status")
    }

    func sentryUnlock() throws -> DaemonControlResponse {
        sentry("sentry_unlock")
    }

    func sentryOpen() throws -> DaemonControlResponse {
        sentry("sentry_open")
    }

    private func sentry(_ command: String) -> DaemonControlResponse {
        sentryCommands.append(command)
        recordCall?("daemonControl.\(command)")
        return DaemonControlResponse(
            ok: true,
            commandResult: CommandExecutionResult(success: true, message: "\(command) ok")
        )
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

    func testSetupWithRelayURLMigratesLegacyApiKeyConfig() throws {
        let fixture = CLIFixture()
        let raw = """
        {
          "relayURL": "https://old-relay.example.com",
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
        try raw.write(toFile: fixture.configStore.configPath(), atomically: true, encoding: .utf8)

        let result = fixture.cli.run(arguments: ["setup", "--relay-url", "https://relay.example.com"])

        XCTAssertEqual(result.exitCode, 0)
        let config = try fixture.configStore.load()
        XCTAssertEqual(config.relayURL, "https://relay.example.com")
        let saved = try String(contentsOfFile: fixture.configStore.configPath(), encoding: .utf8)
        XCTAssertFalse(saved.contains("apiKey"))
    }

    func testStartInstallsMissingServices() {
        let fixture = CLIFixture()
        _ = fixture.cli.run(arguments: ["setup", "--relay-url", "https://relay.example.com"])
        fixture.daemon.statusValue = DaemonStatus(installed: false, running: false, plistPath: "/tmp/agent.plist", binaryPath: "/tmp/cicada-agent")
        fixture.sentinelApp.statusValue = SentinelAppStatus(
            installed: false,
            running: false,
            plistPath: "/tmp/sentinel.plist",
            appPath: "/tmp/Sentry.app",
            socketPath: "/tmp/notifier.sock"
        )

        let result = fixture.cli.run(arguments: ["start"])

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(fixture.daemon.calls, ["install", "start"])
        XCTAssertEqual(fixture.sentinelApp.calls, ["install", "start"])
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
        let sentinel = try XCTUnwrap(object["sentinel"] as? [String: Any])
        XCTAssertEqual(sentinel["notifierSocketPath"] as? String, "/tmp/notifier.sock")
        XCTAssertEqual(sentinel["notifierSocketReady"] as? Bool, true)
        XCTAssertEqual(sentinel["controlSocketPath"] as? String, "/tmp/sentinel.sock")
        XCTAssertEqual(sentinel["controlSocketReady"] as? Bool, true)
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

    func testRunSentryCommandsUseDaemonControl() {
        let fixture = CLIFixture()
        let commands = ["sentry_start", "sentry_stop", "sentry_status", "sentry_unlock", "sentry_open"]

        for command in commands {
            let result = fixture.cli.run(arguments: ["run", command])

            XCTAssertEqual(result.exitCode, 0, command)
            XCTAssertTrue(result.stdout.contains("\(command) ok"), command)
        }
        XCTAssertEqual(fixture.daemonControl.sentryCommands, commands)
        XCTAssertTrue(fixture.commandExecutor.commands.isEmpty)
    }

    func testStopStopsSentinelBeforeDaemon() {
        let fixture = CLIFixture()

        let result = fixture.cli.run(arguments: ["stop"])

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(
            fixture.callOrder.calls,
            [
                "daemonControl.sentry_stop",
                "daemonControl.power_assertion_stop",
                "sentinel.stop",
                "daemon.stop",
            ]
        )
    }

    func testRestartStopsSentinelBeforeDaemonThenStartsBoth() {
        let fixture = CLIFixture()
        _ = fixture.cli.run(arguments: ["setup", "--relay-url", "https://relay.example.com"])

        let result = fixture.cli.run(arguments: ["restart"])

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(
            fixture.callOrder.calls,
            [
                "daemonControl.sentry_stop",
                "daemonControl.power_assertion_stop",
                "sentinel.stop",
                "daemon.stop",
                "daemon.start",
                "sentinel.start",
            ]
        )
    }

    func testAdvancedRoutesRemainAvailable() {
        let fixture = CLIFixture()

        XCTAssertEqual(fixture.cli.run(arguments: ["advanced", "config", "path"]).exitCode, 0)
        XCTAssertEqual(fixture.cli.run(arguments: ["advanced", "daemon", "logs"]).exitCode, 0)
        XCTAssertEqual(fixture.cli.run(arguments: ["advanced", "sleep", "status"]).exitCode, 0)
        XCTAssertEqual(fixture.cli.run(arguments: ["advanced", "doctor", "--json"]).exitCode, 0)
    }

    func testAdvancedNotifierCommandsAreRemoved() {
        let fixture = CLIFixture()

        let help = fixture.cli.run(arguments: ["advanced", "--help"])
        let result = fixture.cli.run(arguments: ["advanced", "notifier", "status"])

        XCTAssertEqual(help.exitCode, 0)
        XCTAssertFalse(help.stdout.contains("advanced notifier"))
        XCTAssertEqual(result.exitCode, 1)
        XCTAssertTrue(result.stderr.contains("未知 advanced 命令: notifier"))
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

private final class CallOrder {
    private(set) var calls: [String] = []

    func append(_ call: String) {
        calls.append(call)
    }
}

private final class CLIFixture {
    let directory: URL
    let configStore: ConfigStore
    let callOrder = CallOrder()
    let daemon = FakeDaemonManager()
    let sentinelApp = FakeSentinelAppManager()
    let sleepHold = FakeSleepHoldManager()
    let daemonControl = FakeDaemonControlClient()
    let commandExecutor = FakeCommandExecutor()
    let cli: CicadaCLI

    init() {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("cicada-cli-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        configStore = ConfigStore(path: directory.appendingPathComponent("config.json").path)
        daemon.recordCall = { [callOrder] call in callOrder.append(call) }
        sentinelApp.recordCall = { [callOrder] call in callOrder.append(call) }
        daemonControl.recordCall = { [callOrder] call in callOrder.append(call) }
        cli = CicadaCLI(
            configStore: configStore,
            daemonManager: daemon,
            sentinelAppManager: sentinelApp,
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
