import Foundation

public struct NativeCapabilitySnapshot: Codable, Equatable {
    public let bluetooth: String
    public let accessibilityTrusted: Bool
    public let noSleepAssertionActive: Bool
    public let sleepHoldActive: Bool

    public init(
        bluetooth: String,
        accessibilityTrusted: Bool,
        noSleepAssertionActive: Bool,
        sleepHoldActive: Bool = false
    ) {
        self.bluetooth = bluetooth
        self.accessibilityTrusted = accessibilityTrusted
        self.noSleepAssertionActive = noSleepAssertionActive
        self.sleepHoldActive = sleepHoldActive
    }

    public func dictionary() -> [String: Any] {
        [
            "bluetooth": bluetooth,
            "accessibilityTrusted": accessibilityTrusted,
            "noSleepAssertionActive": noSleepAssertionActive,
            "sleepHoldActive": sleepHoldActive,
        ]
    }
}

public final class NativeCapabilityReporter {
    private let lockController: any NativeLockControlling
    private let bluetoothController: any NativeBluetoothControlling
    private let powerController: any NativePowerControlling

    public convenience init() {
        let power = NativePowerController()
        self.init(
            lockController: NativeLockController(),
            bluetoothController: NativeBluetoothController(),
            powerController: power
        )
    }

    init(
        lockController: any NativeLockControlling,
        bluetoothController: any NativeBluetoothControlling,
        powerController: any NativePowerControlling
    ) {
        self.lockController = lockController
        self.bluetoothController = bluetoothController
        self.powerController = powerController
    }

    public func snapshot() -> NativeCapabilitySnapshot {
        let bluetooth: String
        switch bluetoothController.powerState() {
        case let .success(isEnabled):
            bluetooth = isEnabled ? "on" : "off"
        case let .failure(error):
            bluetooth = "unavailable: \(error.message)"
        }

        return NativeCapabilitySnapshot(
            bluetooth: bluetooth,
            accessibilityTrusted: lockController.isAccessibilityTrusted(),
            noSleepAssertionActive: powerController.noSleepAssertionActive
        )
    }
}
