import Foundation
import CicadaCore

public final class MacOSCommandGateway {
    private let runner: ProcessRunner
    private let audioController: NativeAudioController
    private let powerController: NativePowerController
    private let processName: String

    public init(runner: ProcessRunner = ProcessRunner()) {
        self.runner = runner
        self.audioController = NativeAudioController()
        self.powerController = NativePowerController()
        self.processName = ProcessInfo.processInfo.processName
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
        let commandPath = "/System/Library/CoreServices/Menu Extras/User.menu/Contents/Resources/CGSession"
        let result = runner.run(commandPath, args: ["-suspend"])
        if result.code != 0 {
            return CommandExecutionResult(success: false, message: result.stderr.isEmpty ? "锁屏命令执行失败" : result.stderr)
        }
        return CommandExecutionResult(success: true, message: "锁屏命令已执行")
    }

    private func toggleBluetooth() -> CommandExecutionResult {
        guard runner.commandExists("blueutil") else {
            return CommandExecutionResult(success: false, message: "缺少 blueutil，无法执行蓝牙切换")
        }

        let current = runner.run("/usr/local/bin/blueutil", args: ["-p"], timeoutMs: 5_000)
        let currentFallback = current.code == 127 ? runner.run("/opt/homebrew/bin/blueutil", args: ["-p"], timeoutMs: 5_000) : current
        let readResult = currentFallback
        if readResult.code != 0 {
            return CommandExecutionResult(success: false, message: readResult.stderr.isEmpty ? "读取蓝牙状态失败" : readResult.stderr)
        }

        let isEnabled = readResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "1"
        let target = isEnabled ? "0" : "1"

        let toggle = runner.run("/usr/local/bin/blueutil", args: ["--power", target], timeoutMs: 5_000)
        let toggleFallback = toggle.code == 127 ? runner.run("/opt/homebrew/bin/blueutil", args: ["--power", target], timeoutMs: 5_000) : toggle
        if toggleFallback.code != 0 {
            return CommandExecutionResult(success: false, message: toggleFallback.stderr.isEmpty ? "蓝牙切换失败" : toggleFallback.stderr)
        }

        return CommandExecutionResult(success: true, message: "蓝牙已\(target == "1" ? "开启" : "关闭")")
    }

    private func toggleMute() -> CommandExecutionResult {
        let native = audioController.toggleSystemMute()
        switch native {
        case let .success(isMuted):
            return CommandExecutionResult(success: true, message: isMuted ? "静音已开启" : "静音已关闭")
        case let .failure(error):
            Logger.warn("MacOSCommandGateway", "native volume_mute failed, fallback to osascript", data: ["error": error.message])
            return toggleMuteByAppleScript()
        }
    }

    private func toggleMuteByAppleScript() -> CommandExecutionResult {
        let script = "set volume output muted not (output muted of (get volume settings))"
        let result = runner.run("/usr/bin/osascript", args: ["-e", script], timeoutMs: 5_000)
        if result.code != 0 {
            return CommandExecutionResult(success: false, message: result.stderr.isEmpty ? "静音切换失败" : result.stderr)
        }
        return CommandExecutionResult(success: true, message: "静音状态已切换（脚本回退）")
    }

    private func sleep() -> CommandExecutionResult {
        let native = powerController.sleepNow()
        switch native {
        case .success:
            return CommandExecutionResult(success: true, message: "系统休眠命令已执行")
        case let .failure(error):
            Logger.warn("MacOSCommandGateway", "native sleep failed, fallback to pmset", data: ["error": error.message])
            return sleepViaPmset()
        }
    }

    private func sleepViaPmset() -> CommandExecutionResult {
        let result = runner.run("/usr/bin/pmset", args: ["sleepnow"], timeoutMs: 5_000)
        if result.code != 0 {
            return CommandExecutionResult(success: false, message: result.stderr.isEmpty ? "系统休眠失败" : result.stderr)
        }
        return CommandExecutionResult(success: true, message: "系统休眠命令已执行（pmset 回退）")
    }

    private func sleepDisplays() -> CommandExecutionResult {
        let result = runner.run("/usr/bin/pmset", args: ["displaysleepnow"], timeoutMs: 5_000)
        if result.code != 0 {
            return CommandExecutionResult(success: false, message: result.stderr.isEmpty ? "显示器休眠失败" : result.stderr)
        }
        return CommandExecutionResult(success: true, message: "显示器休眠命令已执行")
    }

    private func startCaffeinate() -> CommandExecutionResult {
        if runsInDaemon {
            let native = powerController.startNoSleepAssertion()
            switch native {
            case let .success(state):
                if state == "already_running" {
                    return CommandExecutionResult(success: true, message: "防休眠已在运行")
                }
                return CommandExecutionResult(success: true, message: "防休眠已启动（原生）")
            case let .failure(error):
                Logger.warn("MacOSCommandGateway", "native caffeinate failed, fallback to process", data: ["error": error.message])
                return startCaffeinateByProcess()
            }
        }

        return startCaffeinateByProcess()
    }

    private func startCaffeinateByProcess() -> CommandExecutionResult {
        if runner.isProcessRunning("caffeinate") {
            return CommandExecutionResult(success: true, message: "防休眠已在运行")
        }
        let detached = runner.runDetached("/usr/bin/caffeinate", args: ["-dmi"])
        switch detached {
        case .success:
            return CommandExecutionResult(success: true, message: "防休眠已启动（进程模式）")
        case let .failure(error):
            return CommandExecutionResult(success: false, message: error.description)
        }
    }

    private func stopCaffeinate() -> CommandExecutionResult {
        if runsInDaemon {
            let native = powerController.stopNoSleepAssertion()
            switch native {
            case let .success(state):
                if state == "not_running" {
                    return stopCaffeinateByProcess()
                }
                return CommandExecutionResult(success: true, message: "防休眠已停止（原生）")
            case let .failure(error):
                Logger.warn("MacOSCommandGateway", "native decaffeinate failed, fallback to process", data: ["error": error.message])
                return stopCaffeinateByProcess()
            }
        }

        return stopCaffeinateByProcess()
    }

    private func stopCaffeinateByProcess() -> CommandExecutionResult {
        if !runner.isProcessRunning("caffeinate") {
            return CommandExecutionResult(success: true, message: "防休眠未运行")
        }
        let result = runner.run("/usr/bin/killall", args: ["caffeinate"], timeoutMs: 5_000)
        if result.code != 0 {
            return CommandExecutionResult(success: false, message: result.stderr.isEmpty ? "停止防休眠失败" : result.stderr)
        }
        return CommandExecutionResult(success: true, message: "防休眠已停止（进程模式）")
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

        let result = runner.run("/usr/bin/pmset", args: ["-g", "batt"], timeoutMs: 3_000)
        guard result.code == 0 else {
            return "未知"
        }

        let source = result.stdout.contains("'AC Power'") ? "接通电源" : "电池供电"
        if let match = result.stdout.range(of: #"\d+%"#, options: .regularExpression) {
            return "\(result.stdout[match])（\(source)）"
        }

        return source
    }

    private func bluetoothInfo() -> String {
        guard runner.commandExists("blueutil") else {
            return "未知"
        }

        let primary = runner.run("/usr/local/bin/blueutil", args: ["-p"], timeoutMs: 3_000)
        let result = primary.code == 127 ? runner.run("/opt/homebrew/bin/blueutil", args: ["-p"], timeoutMs: 3_000) : primary
        guard result.code == 0 else {
            return "未知"
        }

        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "1" ? "开启" : "关闭"
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

    private var runsInDaemon: Bool {
        processName.contains("cicada-agent")
    }
}
