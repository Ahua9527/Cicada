import Carbon
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

    /// restart/shutdown 走 loginwindow 的 Finder 电源事件（kAEFinderEvents 套件），
    /// 与系统菜单行为一致；守护进程运行在用户 Aqua session，无需 root。
    func restartSystem() -> Result<Void, NativeCommandError> {
        sendLoginWindowEvent(kAERestart, label: "重启")
    }

    func shutdownSystem() -> Result<Void, NativeCommandError> {
        sendLoginWindowEvent(kAEShutDown, label: "关机")
    }

    /// 仅构造 loginwindow 电源事件描述符，不发送。
    /// 抽出独立方法：单测可校验事件类别（FNDR）、事件 ID（rest/shut）与目标，
    /// 而不真正触发重启/关机。
    static func makeLoginWindowEvent(_ eventID: AEEventID) -> NSAppleEventDescriptor {
        NSAppleEventDescriptor(
            eventClass: AEEventClass(kAEFinderEvents),
            eventID: eventID,
            targetDescriptor: NSAppleEventDescriptor(bundleIdentifier: "com.apple.loginwindow"),
            returnID: AEReturnID(kAutoGenerateReturnID),
            transactionID: AETransactionID(kAnyTransactionID)
        )
    }

    private func sendLoginWindowEvent(_ eventID: AEEventID, label: String) -> Result<Void, NativeCommandError> {
        let descriptor = Self.makeLoginWindowEvent(eventID)
        do {
            // .noReply：事件送达 loginwindow 即返回，电源动作由系统立即执行。
            _ = try descriptor.sendEvent(
                options: [.noReply],
                timeout: TimeInterval(kAEDefaultTimeout)
            )
            return .success(())
        } catch {
            return .failure(.message("\(label)失败: \(error.localizedDescription)"))
        }
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
