import Darwin
import Foundation
import IOKit

public protocol SleepHoldPowerControlling: AnyObject {
    func read() -> SleepHoldPowerStatus
    func set(_ status: SleepHoldPowerStatus) -> Result<Void, Error>
}

public final class SleepHoldIOPowerController: SleepHoldPowerControlling {
    public init() {}

    public func read() -> SleepHoldPowerStatus {
        let entry = IORegistryEntryFromPath(kIOMainPortDefault, "IOPower:/IOPowerConnection/IOPMrootDomain")
        guard entry != 0 else {
            return .unknown
        }
        defer { IOObjectRelease(entry) }

        var sleepDisabled = false
        let ret = "SleepDisabled".withCString { bytes in
            var valueSize = UInt32(MemoryLayout<CFBoolean>.size)
            return IORegistryEntryGetProperty(entry, bytes, &sleepDisabled, &valueSize)
        }

        guard ret == KERN_SUCCESS else {
            return .unknown
        }
        return sleepDisabled ? .hold : .canSleep
    }

    public func set(_ status: SleepHoldPowerStatus) -> Result<Void, Error> {
        let value: CFTypeRef
        switch status {
        case .canSleep:
            value = kCFBooleanFalse
        case .hold:
            value = kCFBooleanTrue
        case .unknown:
            return .failure(SleepHoldPowerError.invalidStatus)
        }

        let ret = Self.ioPMSetSystemPowerSetting("SleepDisabled" as CFString, value)
        guard ret == kIOReturnSuccess else {
            return .failure(NSError(domain: "IOPMSetSystemPowerSetting", code: Int(ret)))
        }
        return .success(())
    }

    private typealias SetSystemPowerSetting = @convention(c) (CFString, CFTypeRef) -> IOReturn

    private static let ioPMSetSystemPowerSetting: SetSystemPowerSetting = {
        guard let handle = dlopen("/System/Library/Frameworks/IOKit.framework/Versions/A/IOKit", RTLD_NOW) else {
            fatalError("Failed to load IOKit framework")
        }
        guard let symbol = dlsym(handle, "IOPMSetSystemPowerSetting") else {
            fatalError("Failed to load IOPMSetSystemPowerSetting")
        }
        return unsafeBitCast(symbol, to: SetSystemPowerSetting.self)
    }()
}

enum SleepHoldPowerError: Error {
    case invalidStatus
}
