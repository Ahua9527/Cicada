import CoreGraphics
import Foundation
import IOKit

final class NativeDisplayController: NativeDisplayControlling {
    /// DisplayServices 私有框架绑定。真实签名以显示器 ID 为首参：
    /// `int DisplayServicesGetBrightness(CGDirectDisplayID, float *)`
    /// `int DisplayServicesSetBrightness(CGDirectDisplayID, float)`
    /// 封装为内部可注入结构，单测可验证显示器 ID 与数值确实传递。
    struct BrightnessServices {
        var get: (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
        var set: (CGDirectDisplayID, Float) -> Int32

        /// 线上绑定：dlopen DisplayServices。Apple Silicon 上 IOKit 的
        /// IODisplayGetFloatParameter 已失效，与 SleepHoldPowerController 一致走
        /// dlopen 模式；框架或符号缺失时回退为恒失败（-1），由调用方报可读错误。
        static let live: BrightnessServices = {
            let fallback = BrightnessServices(get: { _, _ in -1 }, set: { _, _ in -1 })
            guard let handle = dlopen(
                "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices",
                RTLD_NOW
            ) else {
                return fallback
            }
            typealias GetBrightnessFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
            typealias SetBrightnessFn = @convention(c) (CGDirectDisplayID, Float) -> Int32
            guard let getSym = dlsym(handle, "DisplayServicesGetBrightness"),
                  let setSym = dlsym(handle, "DisplayServicesSetBrightness") else {
                return fallback
            }
            return BrightnessServices(
                get: unsafeBitCast(getSym, to: GetBrightnessFn.self),
                set: unsafeBitCast(setSym, to: SetBrightnessFn.self)
            )
        }()
    }

    private let brightness: BrightnessServices
    private let mainDisplayID: () -> CGDirectDisplayID

    /// 亮度只控制主显示器（CGMainDisplayID）；多显示器选择不在此扩展。
    init(
        brightness: BrightnessServices = .live,
        mainDisplayID: @escaping () -> CGDirectDisplayID = { CGMainDisplayID() }
    ) {
        self.brightness = brightness
        self.mainDisplayID = mainDisplayID
    }

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
        let status = brightness.set(mainDisplayID(), clamped)
        guard status == 0 else {
            return .failure(.message("设置亮度失败: DisplayServices(\(status))"))
        }
        return .success(clamped)
    }

    func adjustBrightness(by delta: Float) -> Result<Float, NativeCommandError> {
        var current: Float = 0
        let status = brightness.get(mainDisplayID(), &current)
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

        let path = Self.makeScreenshotPath(directory: directory)

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

    /// 截屏路径：毫秒时间戳 + UUID。同一秒（甚至同一毫秒）连续截图不会互相覆盖；
    /// 目录与返回字段（data.path）保持不变。
    static func makeScreenshotPath(
        directory: String,
        date: Date = Date(),
        uuid: UUID = UUID()
    ) -> String {
        let millis = Int((date.timeIntervalSince1970 * 1_000).rounded())
        return "\(directory)/screenshot-\(millis)-\(uuid.uuidString).png"
    }

    private func describeIOStatus(_ status: IOReturn) -> String {
        if let message = mach_error_string(status) {
            return String(cString: message)
        }
        return "IOReturn(\(status))"
    }
}
