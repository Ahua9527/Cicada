import CicadaBluetoothBridge
import Foundation

final class NativeBluetoothController: NativeBluetoothControlling {
    func powerState() -> Result<Bool, NativeCommandError> {
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
