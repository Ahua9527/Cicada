import Foundation
import XCTest
@testable import CicadaCore
@testable import CicadaIPC
@testable import CicadaSystem

private final class FakeLockController: NativeLockControlling {
    var result: Result<Void, NativeCommandError> = .success(())
    private(set) var callCount = 0
    var accessibilityTrusted = true

    func lockScreen() -> Result<Void, NativeCommandError> {
        callCount += 1
        return result
    }

    func isAccessibilityTrusted() -> Bool {
        accessibilityTrusted
    }
}

private final class FakeBluetoothController: NativeBluetoothControlling {
    var powerResult: Result<Bool, NativeCommandError> = .success(true)
    var setResult: Result<Bool, NativeCommandError> = .success(false)
    private(set) var setValues: [Bool] = []

    func powerState() -> Result<Bool, NativeCommandError> {
        powerResult
    }

    func setPowerState(_ enabled: Bool) -> Result<Bool, NativeCommandError> {
        setValues.append(enabled)
        return setResult
    }
}

private final class FakeAudioController: NativeAudioControlling {
    var result: Result<Bool, NativeCommandError> = .success(true)
    var setMutedResult: Result<Void, NativeCommandError> = .success(())
    var setVolumeResult: Result<Float, NativeCommandError> = .success(0.5)
    var adjustVolumeResult: Result<Float, NativeCommandError> = .success(0.6)
    var currentVolumeResult: Result<Float, NativeCommandError> = .success(0.5)
    private(set) var callCount = 0
    private(set) var mutedValues: [Bool] = []
    private(set) var volumeValues: [Float] = []

    func toggleSystemMute() -> Result<Bool, NativeCommandError> {
        callCount += 1
        return result
    }

    func setMuted(_ muted: Bool) -> Result<Void, NativeCommandError> {
        mutedValues.append(muted)
        return setMutedResult
    }

    func setVolume(_ level: Float) -> Result<Float, NativeCommandError> {
        volumeValues.append(level)
        return setVolumeResult
    }

    func adjustVolume(by delta: Float) -> Result<Float, NativeCommandError> {
        adjustVolumeResult
    }

    func currentVolume() -> Result<Float, NativeCommandError> {
        currentVolumeResult
    }
}

private final class FakePowerController: NativePowerControlling {
    var sleepResult: Result<Void, NativeCommandError> = .success(())
    var startResult: Result<String, NativeCommandError> = .success("started")
    var stopResult: Result<String, NativeCommandError> = .success("stopped")
    var battery: String? = "88%（接通电源）"
    var noSleepAssertionActive = false
    private(set) var sleepCount = 0

    func sleepNow() -> Result<Void, NativeCommandError> {
        sleepCount += 1
        return sleepResult
    }

    func restartSystem() -> Result<Void, NativeCommandError> {
        .success(())
    }

    func shutdownSystem() -> Result<Void, NativeCommandError> {
        .success(())
    }

    func startNoSleepAssertion() -> Result<String, NativeCommandError> {
        noSleepAssertionActive = true
        return startResult
    }

    func stopNoSleepAssertion() -> Result<String, NativeCommandError> {
        noSleepAssertionActive = false
        return stopResult
    }

    func batteryDescription() -> String? {
        battery
    }
}

private final class FakeDisplayController: NativeDisplayControlling {
    var result: Result<Void, NativeCommandError> = .success(())
    private(set) var callCount = 0

    func sleepDisplays() -> Result<Void, NativeCommandError> {
        callCount += 1
        return result
    }

    func wakeDisplays() -> Result<Void, NativeCommandError> {
        .success(())
    }

    func setBrightness(_ level: Float) -> Result<Float, NativeCommandError> {
        .success(level)
    }

    func adjustBrightness(by delta: Float) -> Result<Float, NativeCommandError> {
        .success(0.5 + delta)
    }

    func captureScreen(to directory: String) -> Result<String, NativeCommandError> {
        .success("\(directory)/screenshot-test.png")
    }
}

private final class FakeSleepHoldLeaseController: SleepHoldLeasing {
    var active = false
    var startResult: Result<SleepHoldLeaseState, NativeCommandError> = .success(
        SleepHoldLeaseState(status: "active", sessionId: "sleep-1")
    )
    var stopResult: Result<SleepHoldLeaseState, NativeCommandError> = .success(
        SleepHoldLeaseState(status: "stopped", sessionId: "sleep-1")
    )

    var isActive: Bool {
        active
    }

    func start() -> Result<SleepHoldLeaseState, NativeCommandError> {
        if case .success = startResult {
            active = true
        }
        return startResult
    }

    func stop() -> Result<SleepHoldLeaseState, NativeCommandError> {
        if case .success = stopResult {
            active = false
        }
        return stopResult
    }
}

private final class FakeSentinelControlClient: SentinelControlClienting {
    private(set) var actions: [SentinelControlAction] = []
    var queuedResults: [Result<SentinelControlResponse, Error>] = []
    var response = SentinelControlResponse(
        ok: true,
        message: "Sentry started",
        status: SentinelStatusSnapshot(
            state: "Running",
            activityHint: "",
            recordingEnabled: false,
            sleepHoldActive: true,
            sleepHoldSessionId: "cicada-daemon-power-assertion"
        )
    )

    func request(_ request: SentinelControlRequest) throws -> SentinelControlResponse {
        actions.append(request.action)
        if !queuedResults.isEmpty {
            return try queuedResults.removeFirst().get()
        }
        return response
    }
}

final class MacOSCommandGatewayTests: XCTestCase {
    func testNineCommandsUseNativeControllers() {
        let fixture = GatewayFixture()

        XCTAssertTrue(fixture.gateway.execute(command: "lock").success)
        XCTAssertEqual(fixture.lock.callCount, 1)

        let bluetooth = fixture.gateway.execute(command: "bt_toggle")
        XCTAssertTrue(bluetooth.success)
        XCTAssertEqual(fixture.bluetooth.setValues, [false])

        XCTAssertEqual(fixture.gateway.execute(command: "ping").message, "pong")

        let mute = fixture.gateway.execute(command: "volume_mute")
        XCTAssertTrue(mute.success)
        XCTAssertEqual(fixture.audio.callCount, 1)

        XCTAssertTrue(fixture.gateway.execute(command: "sleep").success)
        XCTAssertEqual(fixture.power.sleepCount, 1)

        XCTAssertTrue(fixture.gateway.execute(command: "sleep_displays").success)
        XCTAssertEqual(fixture.display.callCount, 1)

        XCTAssertTrue(fixture.gateway.execute(command: "caffeinate").success)
        XCTAssertTrue(fixture.gateway.execute(command: "decaffeinate").success)

        let status = fixture.gateway.execute(command: "status")
        XCTAssertTrue(status.success)
        XCTAssertEqual(status.data?["battery"], "88%（接通电源）")
        XCTAssertEqual(status.data?["bluetooth"], "开启")
    }

    func testNativeVolumeFailureReturnsErrorWithoutFallback() {
        let fixture = GatewayFixture()
        fixture.audio.result = .failure(.message("core audio denied"))

        let result = fixture.gateway.execute(command: "volume_mute")

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.message, "core audio denied")
        XCTAssertEqual(fixture.audio.callCount, 1)
    }

    func testNativeSleepFailureReturnsErrorWithoutFallback() {
        let fixture = GatewayFixture()
        fixture.power.sleepResult = .failure(.message("iokit denied"))

        let result = fixture.gateway.execute(command: "sleep")

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.message, "iokit denied")
        XCTAssertEqual(fixture.power.sleepCount, 1)
    }

    func testStatusSucceedsWhenBluetoothStateIsUnavailable() {
        let fixture = GatewayFixture()
        fixture.bluetooth.powerResult = .failure(.message("bluetooth permission missing"))

        let result = fixture.gateway.execute(command: "status")

        XCTAssertTrue(result.success)
        XCTAssertEqual(result.data?["bluetooth"], "未知")
        XCTAssertEqual(result.data?["battery"], "88%（接通电源）")
    }

    func testCaffeinateStartsSleepHoldLeaseWhenAvailable() {
        let fixture = GatewayFixture()

        let result = fixture.gateway.execute(command: "caffeinate")

        XCTAssertTrue(result.success)
        XCTAssertEqual(result.data?["sleep_hold"], "active")
        XCTAssertTrue(result.message.contains("合盖防睡眠"))
        XCTAssertTrue(fixture.sleepHold.active)
    }

    func testCaffeinateReportsSleepHoldUnavailableWithoutLosingNativeAssertion() {
        let fixture = GatewayFixture()
        fixture.sleepHold.startResult = .failure(.message("SleepHold helper is not installed"))

        let result = fixture.gateway.execute(command: "caffeinate")

        XCTAssertTrue(result.success)
        XCTAssertEqual(result.data?["sleep_hold"], "unavailable")
        XCTAssertTrue(result.message.contains("合盖防睡眠未启用"))
        XCTAssertTrue(fixture.power.noSleepAssertionActive)
    }

    func testDecaffeinateStopsSleepHoldLease() {
        let fixture = GatewayFixture()
        _ = fixture.gateway.execute(command: "caffeinate")

        let result = fixture.gateway.execute(command: "decaffeinate")

        XCTAssertTrue(result.success)
        XCTAssertEqual(result.data?["sleep_hold"], "stopped")
        XCTAssertFalse(fixture.sleepHold.active)
    }

    func testSentryCommandsUseSentinelIPC() {
        let fixture = GatewayFixture()
        let commands: [(String, SentinelControlAction)] = [
            ("sentry_start", .start),
            ("sentry_stop", .stop),
            ("sentry_status", .status),
            ("sentry_unlock", .unlock),
            ("sentry_open", .open),
        ]

        for (command, action) in commands {
            let result = fixture.gateway.execute(command: command)

            XCTAssertTrue(result.success, command)
            XCTAssertEqual(result.message, "Sentry started", command)
            XCTAssertEqual(result.data?["state"], "Running", command)
            XCTAssertEqual(result.data?["sleep_hold_active"], "true", command)
            XCTAssertEqual(fixture.sentinel.actions.last, action, command)
        }
        XCTAssertEqual(fixture.sentinel.actions, commands.map { $0.1 })
    }

    func testSentryOpenReportsAppOpenFailureWithoutIPC() {
        let fixture = GatewayFixture(sentinelAppOpener: { .failure(.message("launch denied")) })

        let result = fixture.gateway.execute(command: "sentry_open")

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.message, "Sentinel 打开失败: launch denied")
        XCTAssertTrue(fixture.sentinel.actions.isEmpty)
    }

    func testNewHardwareCommandsUseNativeControllers() {
        let fixture = GatewayFixture()

        XCTAssertTrue(fixture.gateway.execute(command: "bt_on").success)
        XCTAssertEqual(fixture.bluetooth.setValues, [true])
        XCTAssertTrue(fixture.gateway.execute(command: "bt_off").success)
        XCTAssertEqual(fixture.bluetooth.setValues, [true, false])

        let btStatus = fixture.gateway.execute(command: "bt_status")
        XCTAssertTrue(btStatus.success)
        XCTAssertEqual(btStatus.data?["bluetooth"], "on")

        XCTAssertTrue(fixture.gateway.execute(command: "brightness_up").success)
        let brightness = fixture.gateway.execute(command: "brightness_set", params: ["level": 0.8])
        XCTAssertTrue(brightness.success)
        XCTAssertTrue(brightness.message.contains("80%"))
        XCTAssertFalse(
            fixture.gateway.execute(command: "brightness_set", params: [:]).success
        )

        XCTAssertTrue(fixture.gateway.execute(command: "mute").success)
        XCTAssertEqual(fixture.audio.mutedValues, [true])
        XCTAssertTrue(fixture.gateway.execute(command: "unmute").success)
        XCTAssertEqual(fixture.audio.mutedValues, [true, false])
        XCTAssertTrue(fixture.gateway.execute(command: "volume_up").success)
        let volume = fixture.gateway.execute(command: "volume_set", params: ["level": "0.3"])
        XCTAssertTrue(volume.success)
        XCTAssertEqual(fixture.audio.volumeValues, [0.3])

        XCTAssertTrue(fixture.gateway.execute(command: "wake").success)
        XCTAssertTrue(fixture.gateway.execute(command: "restart").success)
        XCTAssertTrue(fixture.gateway.execute(command: "shutdown").success)

        let shot = fixture.gateway.execute(command: "screenshot")
        XCTAssertTrue(shot.success)
        XCTAssertNotNil(shot.data?["path"])

        XCTAssertFalse(fixture.gateway.execute(command: "app_open", params: [:]).success)
    }

    func testSentryOpenRetriesIPCWhileSentinelAppStarts() {
        let fixture = GatewayFixture(sentinelOpenRetryAttempts: 2, sentinelOpenRetryDelayMicros: 0)
        fixture.sentinel.queuedResults = [
            .failure(DaemonControlError.unavailable("No such file or directory")),
            .success(fixture.sentinel.response),
        ]

        let result = fixture.gateway.execute(command: "sentry_open")

        XCTAssertTrue(result.success)
        XCTAssertEqual(fixture.sentinel.actions, [.open, .open])
    }
}

private final class GatewayFixture {
    let lock = FakeLockController()
    let bluetooth = FakeBluetoothController()
    let audio = FakeAudioController()
    let power = FakePowerController()
    let display = FakeDisplayController()
    let sleepHold = FakeSleepHoldLeaseController()
    let sentinel = FakeSentinelControlClient()
    let gateway: MacOSCommandGateway

    init(
        sentinelAppOpener: @escaping () -> Result<Void, NativeCommandError> = { .success(()) },
        sentinelOpenRetryAttempts: Int = 1,
        sentinelOpenRetryDelayMicros: useconds_t = 100_000
    ) {
        gateway = MacOSCommandGateway(
            lockController: lock,
            bluetoothController: bluetooth,
            audioController: audio,
            powerController: power,
            displayController: display,
            sleepHoldLeaseController: sleepHold,
            sentinelControlClient: sentinel,
            sentinelAppOpener: sentinelAppOpener,
            sentinelOpenRetryAttempts: sentinelOpenRetryAttempts,
            sentinelOpenRetryDelayMicros: sentinelOpenRetryDelayMicros
        )
    }
}
