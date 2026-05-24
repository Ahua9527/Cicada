import Foundation
import IOKit

final class NativeDisplayController: NativeDisplayControlling {
    func sleepDisplays() -> Result<Void, NativeCommandError> {
        let service = IORegistryEntryFromPath(kIOMainPortDefault, "IOService:/IOResources/IODisplayWrangler")
        guard service != 0 else {
            return .failure(.message("无法连接显示器电源管理服务"))
        }
        defer { IOObjectRelease(service) }

        let result = IORegistryEntrySetCFProperty(service, "IORequestIdle" as CFString, kCFBooleanTrue)
        guard result == kIOReturnSuccess else {
            return .failure(.message("显示器休眠调用失败: \(describeIOStatus(result))"))
        }

        return .success(())
    }

    private func describeIOStatus(_ status: IOReturn) -> String {
        if let message = mach_error_string(status) {
            return String(cString: message)
        }
        return "IOReturn(\(status))"
    }
}
