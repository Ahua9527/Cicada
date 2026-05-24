import Foundation
import XCTest
@testable import CicadaCore
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
    private(set) var callCount = 0

    func toggleSystemMute() -> Result<Bool, NativeCommandError> {
        callCount += 1
        return result
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
}

private final class GatewayFixture {
    let lock = FakeLockController()
    let bluetooth = FakeBluetoothController()
    let audio = FakeAudioController()
    let power = FakePowerController()
    let display = FakeDisplayController()
    let sleepHold = FakeSleepHoldLeaseController()
    let gateway: MacOSCommandGateway

    init() {
        gateway = MacOSCommandGateway(
            lockController: lock,
            bluetoothController: bluetooth,
            audioController: audio,
            powerController: power,
            displayController: display,
            sleepHoldLeaseController: sleepHold
        )
    }
}
