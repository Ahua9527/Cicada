import Foundation

public struct ProcessResult {
    public let stdout: String
    public let stderr: String
    public let code: Int32

    public init(stdout: String, stderr: String, code: Int32) {
        self.stdout = stdout
        self.stderr = stderr
        self.code = code
    }
}

public final class ProcessRunner {
    public init() {}

    public func run(_ command: String, args: [String] = [], timeoutMs: Int = 10_000) -> ProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = args

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        do {
            try process.run()
        } catch {
            return ProcessResult(stdout: "", stderr: "命令执行失败: \(error)", code: 127)
        }

        let timeout = DispatchTime.now() + .milliseconds(timeoutMs)
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
            process.waitUntilExit()
            group.leave()
        }

        if group.wait(timeout: timeout) == .timedOut {
            process.terminate()
            return ProcessResult(stdout: "", stderr: "命令执行超时 (\(timeoutMs)ms)", code: 124)
        }

        let stdout = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return ProcessResult(stdout: stdout.trimmingCharacters(in: .whitespacesAndNewlines), stderr: stderr.trimmingCharacters(in: .whitespacesAndNewlines), code: process.terminationStatus)
    }

    public func runDetached(_ command: String, args: [String] = []) -> Result<Int32, CicadaError> {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = args
        process.standardInput = nil
        process.standardOutput = nil
        process.standardError = nil

        do {
            try process.run()
            return .success(process.processIdentifier)
        } catch {
            return .failure(.command("后台命令启动失败: \(error.localizedDescription)"))
        }
    }

    public func commandExists(_ name: String) -> Bool {
        let result = run("/usr/bin/which", args: [name], timeoutMs: 2_000)
        return result.code == 0 && !result.stdout.isEmpty
    }

    public func isProcessRunning(_ processName: String) -> Bool {
        let result = run("/usr/bin/pgrep", args: ["-x", processName], timeoutMs: 2_000)
        return result.code == 0
    }
}
