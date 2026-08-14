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

    /// 与 sleepDisplays 对称：IORequestIdle=false 即唤醒
    func wakeDisplays() -> Result<Void, NativeCommandError> {
        let service = IORegistryEntryFromPath(kIOMainPortDefault, "IOService:/IOResources/IODisplayWrangler")
        guard service != 0 else {
            return .failure(.message("无法连接显示器电源管理服务"))
        }
        defer { IOObjectRelease(service) }

        let result = IORegistryEntrySetCFProperty(service, "IORequestIdle" as CFString, kCFBooleanFalse)
        guard result == kIOReturnSuccess else {
            return .failure(.message("唤醒显示器失败: \(describeIOStatus(result))"))
        }
        return .success(())
    }

    func setBrightness(_ level: Float) -> Result<Float, NativeCommandError> {
        let clamped = max(0, min(1, level))
        let services = Self.displayServices
        let status = services.set(clamped)
        guard status == 0 else {
            return .failure(.message("设置亮度失败: DisplayServices(\(status))"))
        }
        return .success(clamped)
    }

    func adjustBrightness(by delta: Float) -> Result<Float, NativeCommandError> {
        var current: Float = 0
        let services = Self.displayServices
        let status = services.get(&current)
        guard status == 0 else {
            return .failure(.message("读取亮度失败: DisplayServices(\(status))"))
        }
        return setBrightness(current + delta)
    }

    func captureScreen(to directory: String) -> Result<String, NativeCommandError> {
        do {
            try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        } catch {
            return .failure(.message("无法创建截屏目录: \(error.localizedDescription)"))
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let path = "\(directory)/screenshot-\(formatter.string(from: Date())).png"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-x", path]
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return .failure(.message("截屏进程启动失败: \(error.localizedDescription)"))
        }
        guard process.terminationStatus == 0,
              FileManager.default.fileExists(atPath: path) else {
            return .failure(.message("截屏失败：可能需要「屏幕录制」权限"))
        }
        return .success(path)
    }

    /// DisplayServices 私有框架：Apple Silicon 上 IOKit 的 IODisplayGetFloatParameter 已失效，
    /// 与 SleepHoldPowerController 一致的 dlopen 模式。
    private typealias GetBrightnessFn = @convention(c) (UnsafeMutablePointer<Float>) -> Int32
    private typealias SetBrightnessFn = @convention(c) (Float) -> Int32

    private static let displayServices: (get: GetBrightnessFn, set: SetBrightnessFn) = {
        let fallbackGet: GetBrightnessFn = { _ in -1 }
        let fallbackSet: SetBrightnessFn = { _ in -1 }
        guard let handle = dlopen(
            "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices",
            RTLD_NOW
        ) else {
            return (fallbackGet, fallbackSet)
        }
        guard let getSym = dlsym(handle, "DisplayServicesGetBrightness"),
              let setSym = dlsym(handle, "DisplayServicesSetBrightness") else {
            return (fallbackGet, fallbackSet)
        }
        return (
            unsafeBitCast(getSym, to: GetBrightnessFn.self),
            unsafeBitCast(setSym, to: SetBrightnessFn.self)
        )
    }()

    private func describeIOStatus(_ status: IOReturn) -> String {
        if let message = mach_error_string(status) {
            return String(cString: message)
        }
        return "IOReturn(\(status))"
    }
}
