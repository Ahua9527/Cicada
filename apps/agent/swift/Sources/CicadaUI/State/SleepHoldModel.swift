import CicadaCore
import CicadaSleepHoldCore
import CicadaSystem
import Foundation

/// 连接 sleephold IPC，提供只读维护状态。
@MainActor
final class SleepHoldModel: ObservableObject {
    @Published private(set) var cells: [SleepHoldCellData] = []
    @Published private(set) var isActive: Bool = false
    @Published private(set) var diagnostic: Diagnostic?
    /// launchd 服务是否已安装（plist 落盘即视为已装）。默认 true 避免预览/测试闪现安装按钮；
    /// 每次 `refresh()` 现场重查。
    @Published private(set) var serviceInstalled: Bool = true

    private let statusProvider: () async throws -> SleepHoldControlResponse
    private let isInstalledProvider: () -> Bool

    init(
        client: SleepHoldControlClient = .init(),
        isInstalled: @escaping () -> Bool = SleepHoldModel.defaultIsInstalled
    ) {
        self.statusProvider = { try await client.statusAsync() }
        self.isInstalledProvider = isInstalled
    }

    init(
        statusProvider: @escaping () async throws -> SleepHoldControlResponse,
        isInstalled: @escaping () -> Bool = SleepHoldModel.defaultIsInstalled
    ) {
        self.statusProvider = statusProvider
        self.isInstalledProvider = isInstalled
    }

    nonisolated static func defaultIsInstalled() -> Bool {
        FileManager.default.fileExists(atPath: RuntimePaths.sleepHoldPlistPath)
    }

    /// 轮询刷新状态。连接失败时设为 inactive 并生成诊断警告。
    /// - Returns: 是否成功拿到 sleephold 响应且 `ok == true`（用于轮询退避）。
    @discardableResult
    func refresh() async -> Bool {
        serviceInstalled = isInstalledProvider()
        guard serviceInstalled else {
            // 服务未安装时连 socket 必失败（ENOENT），直接给出可行动诊断，不做无谓连接。
            isActive = false
            cells = []
            diagnostic = Diagnostic(level: .warn, message: String(localized: "SleepHold 服务未安装", bundle: .module))
            return false
        }
        do {
            let resp = try await statusProvider()
            guard resp.ok else {
                isActive = false
                cells = []
                diagnostic = Diagnostic(
                    level: .warn,
                    message: resp.error ?? resp.message ?? String(localized: "sleephold 状态请求失败", bundle: .module)
                )
                return false
            }

            let activeSessions = resp.activeSessions ?? 0
            isActive = resp.status == .hold || activeSessions > 0
            cells = [
                SleepHoldCellData(
                    label: String(localized: "状态", bundle: .module),
                    value: isActive ? String(localized: "活跃", bundle: .module) : String(localized: "空闲", bundle: .module),
                    isMono: false,
                    ok: isActive
                ),
                SleepHoldCellData(
                    label: String(localized: "电源", bundle: .module),
                    value: resp.status?.rawValue ?? String(localized: "未知", bundle: .module),
                    isMono: false,
                    ok: resp.status == .hold
                ),
                SleepHoldCellData(
                    label: String(localized: "活跃会话数", bundle: .module),
                    value: "\(activeSessions)",
                    isMono: true,
                    ok: activeSessions > 0
                ),
            ]
            diagnostic = nil
            return true
        } catch {
            isActive = false
            cells = []
            // 已安装但连不上：服务可能未运行。错误细节用 `description`（如
            // SleepHoldControlError.unavailable 的 errno 短句），不走
            // `localizedDescription`——NSError 桥接会产出
            // “CicadaSystem.SleepHoldControlError 错误0” 这类带内部类型名的文案。
            diagnostic = Diagnostic(
                level: .warn,
                message: String(localized: "无法连接 sleephold 服务（可能未运行）", bundle: .module)
                    + ": " + describe(error)
            )
            return false
        }
    }

    /// 供安装流程写入结果诊断（授权取消/安装失败等）。
    func setDiagnostic(_ message: String) {
        diagnostic = Diagnostic(level: .warn, message: message)
    }

    private func describe(_ error: Error) -> String {
        (error as? CustomStringConvertible)?.description ?? error.localizedDescription
    }
}
