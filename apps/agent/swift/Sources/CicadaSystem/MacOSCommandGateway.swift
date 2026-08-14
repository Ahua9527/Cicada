import Darwin
import Foundation
import CicadaCore
import CicadaIPC

public final class MacOSCommandGateway {
    private let lockController: any NativeLockControlling
    private let bluetoothController: any NativeBluetoothControlling
    private let audioController: any NativeAudioControlling
    private let powerController: any NativePowerControlling
    private let displayController: any NativeDisplayControlling
    private let sleepHoldLeaseController: any SleepHoldLeasing
    private let sentinelControlClient: any SentinelControlClienting
    private let appController: any NativeAppControlling
    private let sentinelAppOpener: () -> Result<Void, NativeCommandError>
    private let sentinelOpenRetryAttempts: Int
    private let sentinelOpenRetryDelayMicros: useconds_t

    public convenience init() {
        let powerController = NativePowerController()
        self.init(
            lockController: NativeLockController(),
            bluetoothController: NativeBluetoothController(),
            audioController: NativeAudioController(),
            powerController: powerController,
            displayController: NativeDisplayController(),
            sleepHoldLeaseController: SleepHoldLeaseController(),
            sentinelControlClient: UdsSentinelControlClient(),
            appController: NativeAppController(),
            sentinelAppOpener: MacOSCommandGateway.openInstalledSentinelApp
        )
    }

    init(
        lockController: any NativeLockControlling,
        bluetoothController: any NativeBluetoothControlling,
        audioController: any NativeAudioControlling,
        powerController: any NativePowerControlling,
        displayController: any NativeDisplayControlling,
        sleepHoldLeaseController: any SleepHoldLeasing,
        sentinelControlClient: any SentinelControlClienting = UdsSentinelControlClient(),
        appController: any NativeAppControlling = NativeAppController(),
        sentinelAppOpener: @escaping () -> Result<Void, NativeCommandError> = MacOSCommandGateway.openInstalledSentinelApp,
        sentinelOpenRetryAttempts: Int = 20,
        sentinelOpenRetryDelayMicros: useconds_t = 100_000
    ) {
        self.lockController = lockController
        self.bluetoothController = bluetoothController
        self.audioController = audioController
        self.powerController = powerController
        self.displayController = displayController
        self.sleepHoldLeaseController = sleepHoldLeaseController
        self.sentinelControlClient = sentinelControlClient
        self.appController = appController
        self.sentinelAppOpener = sentinelAppOpener
        self.sentinelOpenRetryAttempts = max(1, sentinelOpenRetryAttempts)
        self.sentinelOpenRetryDelayMicros = sentinelOpenRetryDelayMicros
    }

    public func execute(command rawCommand: String) -> CommandExecutionResult {
        execute(command: rawCommand, params: [:])
    }

    public func execute(command rawCommand: String, params: [String: Any]) -> CommandExecutionResult {
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
        case .sentryStart:
            return executeSentinelAction(.start)
        case .sentryStop:
            return executeSentinelAction(.stop)
        case .sentryStatus:
            return executeSentinelAction(.status)
        case .sentryUnlock:
            return executeSentinelAction(.unlock)
        case .sentryOpen:
            return openSentinel()
        case .wake:
            return wakeDisplays()
        case .restart:
            return restartSystem()
        case .shutdown:
            return shutdownSystem()
        case .btOn:
            return setBluetooth(true)
        case .btOff:
            return setBluetooth(false)
        case .btStatus:
            return bluetoothStatus()
        case .brightnessUp:
            return adjustBrightness(by: 0.1)
        case .brightnessDown:
            return adjustBrightness(by: -0.1)
        case .brightnessSet:
            return setBrightness(params: params)
        case .screenshot:
            return captureScreen()
        case .mute:
            return setMuted(true)
        case .unmute:
            return setMuted(false)
        case .volumeUp:
            return adjustVolume(by: 0.1)
        case .volumeDown:
            return adjustVolume(by: -0.1)
        case .volumeSet:
            return setVolume(params: params)
        case .appOpen:
            return appAction(params: params, action: appController.openApplication, verb: "打开")
        case .appClose:
            return appAction(params: params, action: appController.closeApplication, verb: "关闭")
        case .appSwitch:
            return appAction(params: params, action: appController.switchToApplication, verb: "切换到")
        case .appList:
            return listApplications()
        }
    }

    private func wakeDisplays() -> CommandExecutionResult {
        switch displayController.wakeDisplays() {
        case .success:
            return CommandExecutionResult(success: true, message: "显示器已唤醒")
        case let .failure(error):
            return CommandExecutionResult(success: false, message: error.message)
        }
    }

    private func restartSystem() -> CommandExecutionResult {
        switch powerController.restartSystem() {
        case .success:
            return CommandExecutionResult(success: true, message: "系统重启命令已执行")
        case let .failure(error):
            return CommandExecutionResult(success: false, message: error.message)
        }
    }

    private func shutdownSystem() -> CommandExecutionResult {
        switch powerController.shutdownSystem() {
        case .success:
            return CommandExecutionResult(success: true, message: "系统关机命令已执行")
        case let .failure(error):
            return CommandExecutionResult(success: false, message: error.message)
        }
    }

    private func setBluetooth(_ enabled: Bool) -> CommandExecutionResult {
        switch bluetoothController.setPowerState(enabled) {
        case .success:
            return CommandExecutionResult(success: true, message: "蓝牙已\(enabled ? "开启" : "关闭")")
        case let .failure(error):
            return CommandExecutionResult(success: false, message: error.message)
        }
    }

    private func bluetoothStatus() -> CommandExecutionResult {
        switch bluetoothController.powerState() {
        case let .success(isEnabled):
            return CommandExecutionResult(
                success: true,
                message: "蓝牙\(isEnabled ? "开启" : "关闭")",
                data: ["bluetooth": isEnabled ? "on" : "off"]
            )
        case let .failure(error):
            return CommandExecutionResult(success: false, message: error.message)
        }
    }

    private func adjustBrightness(by delta: Float) -> CommandExecutionResult {
        switch displayController.adjustBrightness(by: delta) {
        case let .success(level):
            return CommandExecutionResult(
                success: true,
                message: "亮度 \(Int((level * 100).rounded()))%",
                data: ["brightness": String(level)]
            )
        case let .failure(error):
            return CommandExecutionResult(success: false, message: error.message)
        }
    }

    private func setBrightness(params: [String: Any]) -> CommandExecutionResult {
        guard let level = Self.levelParam(params) else {
            return CommandExecutionResult(success: false, message: "brightness_set 需要 params.level（0-1）")
        }
        switch displayController.setBrightness(level) {
        case let .success(applied):
            return CommandExecutionResult(
                success: true,
                message: "亮度已设为 \(Int((applied * 100).rounded()))%",
                data: ["brightness": String(applied)]
            )
        case let .failure(error):
            return CommandExecutionResult(success: false, message: error.message)
        }
    }

    private func captureScreen() -> CommandExecutionResult {
        switch displayController.captureScreen(to: RuntimePaths.cicadaHome + "/screenshots") {
        case let .success(path):
            return CommandExecutionResult(
                success: true,
                message: "截屏已保存: \(path)",
                data: ["path": path]
            )
        case let .failure(error):
            return CommandExecutionResult(success: false, message: error.message)
        }
    }

    private func setMuted(_ muted: Bool) -> CommandExecutionResult {
        switch audioController.setMuted(muted) {
        case .success:
            return CommandExecutionResult(success: true, message: muted ? "静音已开启" : "静音已关闭")
        case let .failure(error):
            return CommandExecutionResult(success: false, message: error.message)
        }
    }

    private func adjustVolume(by delta: Float) -> CommandExecutionResult {
        switch audioController.adjustVolume(by: delta) {
        case let .success(level):
            return CommandExecutionResult(
                success: true,
                message: "音量 \(Int((level * 100).rounded()))%",
                data: ["volume": String(level)]
            )
        case let .failure(error):
            return CommandExecutionResult(success: false, message: error.message)
        }
    }

    private func setVolume(params: [String: Any]) -> CommandExecutionResult {
        guard let level = Self.levelParam(params) else {
            return CommandExecutionResult(success: false, message: "volume_set 需要 params.level（0-1）")
        }
        switch audioController.setVolume(level) {
        case let .success(applied):
            return CommandExecutionResult(
                success: true,
                message: "音量已设为 \(Int((applied * 100).rounded()))%",
                data: ["volume": String(applied)]
            )
        case let .failure(error):
            return CommandExecutionResult(success: false, message: error.message)
        }
    }

    private func appAction(
        params: [String: Any],
        action: (String) -> Result<Void, NativeCommandError>,
        verb: String
    ) -> CommandExecutionResult {
        guard let name = Self.nameParam(params) else {
            return CommandExecutionResult(success: false, message: "需要 params.name（应用名或 bundle id）")
        }
        switch action(name) {
        case .success:
            return CommandExecutionResult(success: true, message: "已\(verb) \(name)")
        case let .failure(error):
            return CommandExecutionResult(success: false, message: error.message)
        }
    }

    private func listApplications() -> CommandExecutionResult {
        let apps = appController.listRunningApplications()
        return CommandExecutionResult(
            success: true,
            message: "运行中应用 \(apps.count) 个: \(apps.joined(separator: ", "))",
            data: ["apps": apps.joined(separator: ","), "count": String(apps.count)]
        )
    }

    /// 兼容数字/字符串两种 JSON 形式的 level 参数
    private static func levelParam(_ params: [String: Any]) -> Float? {
        if let value = params["level"] as? NSNumber { return value.floatValue }
        if let value = params["level"] as? String { return Float(value) }
        return nil
    }

    private static func nameParam(_ params: [String: Any]) -> String? {
        guard let raw = params["name"] as? String else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
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

    private func openSentinel() -> CommandExecutionResult {
        switch sentinelAppOpener() {
        case .success:
            return executeSentinelAction(
                .open,
                attempts: sentinelOpenRetryAttempts,
                retryDelayMicros: sentinelOpenRetryDelayMicros
            )
        case let .failure(error):
            return CommandExecutionResult(success: false, message: "Sentinel 打开失败: \(error.message)")
        }
    }

    private static func openInstalledSentinelApp() -> Result<Void, NativeCommandError> {
        guard FileManager.default.fileExists(atPath: RuntimePaths.sentinelAppPath) else {
            return .success(())
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = [RuntimePaths.sentinelAppPath]
        do {
            try process.run()
            process.waitUntilExit()
            return .success(())
        } catch {
            return .failure(.message(String(describing: error)))
        }
    }

    private func executeSentinelAction(
        _ action: SentinelControlAction,
        attempts: Int = 1,
        retryDelayMicros: useconds_t = 0
    ) -> CommandExecutionResult {
        var lastError: Error?
        let totalAttempts = max(1, attempts)

        for attempt in 0 ..< totalAttempts {
            do {
                let response = try sentinelControlClient.request(SentinelControlRequest(action: action))
                return CommandExecutionResult(
                    success: response.ok,
                    message: response.message,
                    data: response.status.map(Self.sentinelStatusData)
                )
            } catch {
                lastError = error
                if attempt < totalAttempts - 1 {
                    usleep(retryDelayMicros)
                }
            }
        }

        return CommandExecutionResult(
            success: false,
            message: "Sentinel 不可用: \(lastError.map(String.init(describing:)) ?? "unknown error")"
        )
    }

    private static func sentinelStatusData(_ status: SentinelStatusSnapshot) -> [String: String] {
        [
            "state": status.state,
            "activity_hint": status.activityHint,
            "recording_enabled": status.recordingEnabled ? "true" : "false",
            "sleep_hold_active": status.sleepHoldActive ? "true" : "false",
            "sleep_hold_session_id": status.sleepHoldSessionId,
        ]
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
