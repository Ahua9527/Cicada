import Foundation
import CicadaCore

public final class MacOSCommandGateway {
    private let lockController: any NativeLockControlling
    private let bluetoothController: any NativeBluetoothControlling
    private let audioController: any NativeAudioControlling
    private let powerController: any NativePowerControlling
    private let displayController: any NativeDisplayControlling
    private let sleepHoldLeaseController: any SleepHoldLeasing

    public convenience init() {
        let powerController = NativePowerController()
        self.init(
            lockController: NativeLockController(),
            bluetoothController: NativeBluetoothController(),
            audioController: NativeAudioController(),
            powerController: powerController,
            displayController: NativeDisplayController(),
            sleepHoldLeaseController: SleepHoldLeaseController()
        )
    }

    init(
        lockController: any NativeLockControlling,
        bluetoothController: any NativeBluetoothControlling,
        audioController: any NativeAudioControlling,
        powerController: any NativePowerControlling,
        displayController: any NativeDisplayControlling,
        sleepHoldLeaseController: any SleepHoldLeasing
    ) {
        self.lockController = lockController
        self.bluetoothController = bluetoothController
        self.audioController = audioController
        self.powerController = powerController
        self.displayController = displayController
        self.sleepHoldLeaseController = sleepHoldLeaseController
    }

    public func execute(command rawCommand: String) -> CommandExecutionResult {
        guard let command = RemoteCommand(rawValue: rawCommand) else {
            return CommandExecutionResult(success: false, message: "未知命令: \(rawCommand)")
        }

        switch command {
        case .lock:
            return lockScreen()
        case .btToggle:
            return toggleBluetooth()
        case .ping:
            return CommandExecutionResult(success: true, message: "pong")
        case .volumeMute:
            return toggleMute()
        case .sleep:
            return sleep()
        case .sleepDisplays:
            return sleepDisplays()
        case .caffeinate:
            return startCaffeinate()
        case .decaffeinate:
            return stopCaffeinate()
        case .status:
            return systemStatus()
        }
    }

    private func lockScreen() -> CommandExecutionResult {
        switch lockController.lockScreen() {
        case .success:
            return CommandExecutionResult(success: true, message: "锁屏命令已执行")
        case let .failure(error):
            return CommandExecutionResult(success: false, message: error.message)
        }
    }

    private func toggleBluetooth() -> CommandExecutionResult {
        let current = bluetoothController.powerState()
        guard case let .success(isEnabled) = current else {
            if case let .failure(error) = current {
                return CommandExecutionResult(success: false, message: error.message)
            }
            return CommandExecutionResult(success: false, message: "读取蓝牙状态失败")
        }

        let target = !isEnabled
        switch bluetoothController.setPowerState(target) {
        case .success:
            return CommandExecutionResult(success: true, message: "蓝牙已\(target ? "开启" : "关闭")")
        case let .failure(error):
            return CommandExecutionResult(success: false, message: error.message)
        }
    }

    private func toggleMute() -> CommandExecutionResult {
        let native = audioController.toggleSystemMute()
        switch native {
        case let .success(isMuted):
            return CommandExecutionResult(success: true, message: isMuted ? "静音已开启" : "静音已关闭")
        case let .failure(error):
            return CommandExecutionResult(success: false, message: error.message)
        }
    }

    private func sleep() -> CommandExecutionResult {
        let native = powerController.sleepNow()
        switch native {
        case .success:
            return CommandExecutionResult(success: true, message: "系统休眠命令已执行")
        case let .failure(error):
            return CommandExecutionResult(success: false, message: error.message)
        }
    }

    private func sleepDisplays() -> CommandExecutionResult {
        switch displayController.sleepDisplays() {
        case .success:
            return CommandExecutionResult(success: true, message: "显示器休眠命令已执行")
        case let .failure(error):
            return CommandExecutionResult(success: false, message: error.message)
        }
    }

    private func startCaffeinate() -> CommandExecutionResult {
        switch powerController.startNoSleepAssertion() {
        case let .success(state):
            let nativeMessage = state == "already_running" ? "防休眠已在运行" : "防休眠已启动"
            switch sleepHoldLeaseController.start() {
            case .success:
                return CommandExecutionResult(
                    success: true,
                    message: "\(nativeMessage)，合盖防睡眠已启动",
                    data: ["sleep_hold": "active"]
                )
            case let .failure(error):
                return CommandExecutionResult(
                    success: true,
                    message: "\(nativeMessage)，合盖防睡眠未启用: \(error.message)",
                    data: [
                        "sleep_hold": "unavailable",
                        "sleep_hold_error": error.message,
                    ]
                )
            }
        case let .failure(error):
            return CommandExecutionResult(success: false, message: error.message)
        }
    }

    private func stopCaffeinate() -> CommandExecutionResult {
        switch powerController.stopNoSleepAssertion() {
        case let .success(state):
            let nativeMessage = state == "not_running" ? "防休眠未运行" : "防休眠已停止"
            switch sleepHoldLeaseController.stop() {
            case .success:
                return CommandExecutionResult(
                    success: true,
                    message: "\(nativeMessage)，合盖防睡眠已停止",
                    data: ["sleep_hold": "stopped"]
                )
            case let .failure(error):
                return CommandExecutionResult(
                    success: true,
                    message: "\(nativeMessage)，合盖防睡眠停止失败: \(error.message)",
                    data: [
                        "sleep_hold": "error",
                        "sleep_hold_error": error.message,
                    ]
                )
            }
        case let .failure(error):
            return CommandExecutionResult(success: false, message: error.message)
        }
    }

    private func systemStatus() -> CommandExecutionResult {
        let uptime = formatDuration(ProcessInfo.processInfo.systemUptime)
        let battery = batteryInfo()
        let bluetooth = bluetoothInfo()
        let message = "系统已运行 \(uptime)，电量 \(battery)，蓝牙\(bluetooth)"

        return CommandExecutionResult(
            success: true,
            message: message,
            data: [
                "uptime": uptime,
                "battery": battery,
                "bluetooth": bluetooth,
            ]
        )
    }

    private func batteryInfo() -> String {
        if let native = powerController.batteryDescription() {
            return native
        }

        return "未知"
    }

    private func bluetoothInfo() -> String {
        guard case let .success(isEnabled) = bluetoothController.powerState() else {
            return "未知"
        }

        return isEnabled ? "开启" : "关闭"
    }

    private func formatDuration(_ uptimeSeconds: TimeInterval) -> String {
        let total = Int(uptimeSeconds)
        let days = total / 86_400
        let hours = (total % 86_400) / 3_600
        let minutes = (total % 3_600) / 60
        let seconds = total % 60

        if days > 0 {
            return "\(days)天\(hours)小时"
        }
        if hours > 0 {
            return "\(hours)小时\(minutes)分钟"
        }
        if minutes > 0 {
            return "\(minutes)分钟\(seconds)秒"
        }
        return "\(seconds)秒"
    }

    public func nativeCapabilitySnapshot() -> NativeCapabilitySnapshot {
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
            noSleepAssertionActive: powerController.noSleepAssertionActive,
            sleepHoldActive: sleepHoldLeaseController.isActive
        )
    }
}
