import CicadaBluetoothBridge
import CoreBluetooth
import Foundation

/// 蓝牙电源控制。任何 IOBluetooth 调用前先过 TCC 授权闸：
/// macOS 15 对裸 Mach-O（无 .app bundle）不认可内嵌 __info_plist 的
/// NSBluetoothAlwaysUsageDescription，未授权直接调 IOBluetooth 会被 TCC SIGABRT
/// （真机崩溃报告确认）。`CBManager.authorization` 类属性不触发访问请求，可安全读取；
/// 非 .allowedAlways 时返回明确错误而不是崩溃。
final class NativeBluetoothController: NativeBluetoothControlling {
    enum AuthorizationState {
        case allowed
        case notAllowed
    }

    private let authorizationState: () -> AuthorizationState

    init(authorizationState: @escaping () -> AuthorizationState = {
        CBManager.authorization == .allowedAlways ? .allowed : .notAllowed
    }) {
        self.authorizationState = authorizationState
    }

    func powerState() -> Result<Bool, NativeCommandError> {
        guard authorizationState() == .allowed else {
            return .failure(.message("未获得蓝牙权限，无法读取蓝牙状态"))
        }
        switch CicadaBluetoothGetControllerPowerState() {
        case 0:
            return .success(false)
        case 1:
            return .success(true)
        default:
            return .failure(.message("无法读取蓝牙状态，请确认 Cicada 已获得蓝牙权限"))
        }
    }

    func setPowerState(_ enabled: Bool) -> Result<Bool, NativeCommandError> {
        guard authorizationState() == .allowed else {
            return .failure(.message("未获得蓝牙权限，无法切换蓝牙"))
        }
        let raw = CicadaBluetoothSetControllerPowerState(enabled ? 1 : 0)
        guard raw == 0 || raw == 1 else {
            return .failure(.message("蓝牙切换失败，请确认 Cicada 已获得蓝牙权限"))
        }

        let actual = raw == 1
        guard actual == enabled else {
            return .failure(.message("蓝牙状态未按预期切换"))
        }

        return .success(actual)
    }
}
