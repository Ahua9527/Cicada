import Foundation
import XCTest
@testable import CicadaSleepHoldCore

final class SleepHoldSessionManagerTests: XCTestCase {
    func testSessionLifecycleControlsSleepDisabledState() {
        let power = FakeSleepHoldPowerController()
        let manager = SleepHoldSessionManager(sessionDuration: 30, powerController: power)

        let sessionId = manager.createSession()

        XCTAssertFalse(sessionId.isEmpty)
        XCTAssertEqual(power.states, [.canSleep, .hold])
        XCTAssertEqual(manager.activeSessionsCount(), 1)

        XCTAssertTrue(manager.extendSession(sessionId))
        XCTAssertEqual(power.states, [.canSleep, .hold])

        XCTAssertTrue(manager.terminateSession(sessionId))
        XCTAssertEqual(power.states, [.canSleep, .hold, .canSleep])
        XCTAssertEqual(manager.activeSessionsCount(), 0)
    }

    func testExpiredSessionsRestoreSleep() {
        let power = FakeSleepHoldPowerController()
        var now = Date(timeIntervalSince1970: 100)
        let manager = SleepHoldSessionManager(
            sessionDuration: 1,
            powerController: power,
            now: { now }
        )

        _ = manager.createSession()
        now = Date(timeIntervalSince1970: 102)
        manager.cleanupExpiredSessions()

        XCTAssertEqual(manager.activeSessionsCount(), 0)
        XCTAssertEqual(power.states, [.canSleep, .hold, .canSleep])
    }

    func testUnknownSessionCannotBeExtendedOrTerminated() {
        let manager = SleepHoldSessionManager(powerController: FakeSleepHoldPowerController())

        XCTAssertFalse(manager.extendSession("missing"))
        XCTAssertFalse(manager.terminateSession("missing"))
    }

    func testClearSessionsRestoresSleep() {
        let power = FakeSleepHoldPowerController()
        let manager = SleepHoldSessionManager(powerController: power)

        _ = manager.createSession()
        manager.clearSessions()

        XCTAssertEqual(manager.activeSessionsCount(), 0)
        XCTAssertEqual(power.states, [.canSleep, .hold, .canSleep])
    }
}

private final class FakeSleepHoldPowerController: SleepHoldPowerControlling {
    private(set) var states: [SleepHoldPowerStatus] = []
    private var current: SleepHoldPowerStatus = .unknown

    func read() -> SleepHoldPowerStatus {
        current
    }

    func set(_ status: SleepHoldPowerStatus) -> Result<Void, Error> {
        current = status
        states.append(status)
        return .success(())
    }
}
