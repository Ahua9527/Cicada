import Darwin
import Foundation
import IOKit.pwr_mgt
import IOKit.ps

final class NativePowerController: NativePowerControlling {
    private let lock = NSLock()
    private var assertionID: IOPMAssertionID = 0
    private var assertionActive = false

    var noSleepAssertionActive: Bool {
        lock.lock()
        defer { lock.unlock() }
        return assertionActive
    }

    func sleepNow() -> Result<Void, NativeCommandError> {
        let connect = IOPMFindPowerManagement(mach_port_t(MACH_PORT_NULL))
        guard connect != 0 else {
            return .failure(.message("无法连接系统电源管理服务"))
        }
        defer { IOServiceClose(connect) }

        let result = IOPMSleepSystem(connect)
        guard result == kIOReturnSuccess else {
            return .failure(.message("原生休眠调用失败: \(describeIOStatus(result))"))
        }

        return .success(())
    }

    func startNoSleepAssertion() -> Result<String, NativeCommandError> {
        lock.lock()
        defer { lock.unlock() }

        if assertionActive {
            return .success("already_running")
        }

        var createdID = IOPMAssertionID(0)
        let result = IOPMAssertionCreateWithDescription(
            kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
            "Cicada Prevent Sleep" as CFString,
            "Cicada remote command requested no-sleep mode" as CFString,
            "Cicada is keeping this Mac awake" as CFString,
            nil,
            0,
            nil,
            &createdID
        )
        guard result == kIOReturnSuccess else {
            return .failure(.message("原生防休眠创建失败: \(describeIOStatus(result))"))
        }

        assertionID = createdID
        assertionActive = true
        return .success("started")
    }

    func stopNoSleepAssertion() -> Result<String, NativeCommandError> {
        lock.lock()
        defer { lock.unlock() }

        if !assertionActive {
            return .success("not_running")
        }

        let result = IOPMAssertionRelease(assertionID)
        guard result == kIOReturnSuccess else {
            return .failure(.message("原生防休眠释放失败: \(describeIOStatus(result))"))
        }

        assertionID = 0
        assertionActive = false
        return .success("stopped")
    }

    func batteryDescription() -> String? {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef],
              let source = sources.first,
              let detail = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any],
              let current = detail[kIOPSCurrentCapacityKey as String] as? Int,
              let max = detail[kIOPSMaxCapacityKey as String] as? Int,
              max > 0 else {
            return nil
        }

        let percentage = Int((Double(current) / Double(max) * 100).rounded())
        let state = detail[kIOPSPowerSourceStateKey as String] as? String
        let sourceText = state == (kIOPSACPowerValue as String) ? "接通电源" : "电池供电"
        return "\(percentage)%（\(sourceText)）"
    }

    private func describeIOStatus(_ status: IOReturn) -> String {
        if let message = mach_error_string(status) {
            return String(cString: message)
        }
        return "IOReturn(\(status))"
    }
}
