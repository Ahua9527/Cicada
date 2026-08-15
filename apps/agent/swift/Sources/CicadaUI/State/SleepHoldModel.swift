import CicadaCore
import CicadaSleepHoldCore
import CicadaSystem
import Foundation

/// 连接 sleephold IPC，提供只读维护状态。
@MainActor
final class SleepHoldModel: ObservableObject {
    @Published private(set) var cells: [SleepHoldCellData] = []
    @Published private(set) var isActive: Bool = false
    /// 轮询诊断：3 秒自动刷新产出的连接/状态警告。
    @Published private(set) var diagnostic: Diagnostic?
    /// launchd 服务是否已安装（plist 落盘即视为已装）。默认 true 避免预览/测试闪现安装入口；
    /// 每次 `refresh()` 现场重查。
    @Published private(set) var serviceInstalled: Bool = true
    /// 服务是否真正返回有效状态（区别于 plist 是否落盘）。
    /// 默认 true：与 serviceInstalled 默认值一致，预览/首轮轮询前不闪现修复入口；
    /// 首轮 `refresh()` 后即反映真实连通性。
    @Published private(set) var serviceResponding: Bool = true

    /// 安装/修复入口状态。
    enum RecoveryAction: Equatable {
        /// 未安装：显示手动安装指引。
        case install
        /// plist 存在但服务无响应（部分安装/服务挂掉）：显示重装指引。
        case reinstall
    }

    /// 安装/修复入口：由 serviceInstalled + serviceResponding 计算。
    /// 未安装 → .install；已装未响应 → .reinstall；健康 → nil（隐藏指引）。
    var recoveryAction: RecoveryAction? {
        guard serviceInstalled else { return .install }
        return serviceResponding ? nil : .reinstall
    }

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

    /// 已安装判定：plist 落盘即视为已装（安装只走 CLI sudo 路径，见 issue #9）。
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
            serviceResponding = false
            cells = []
            diagnostic = Diagnostic(level: .warn, message: String(localized: "SleepHold 服务未安装", bundle: .module))
            return false
        }
        do {
            let resp = try await statusProvider()
            guard resp.ok else {
                isActive = false
                serviceResponding = false
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
            serviceResponding = true
            diagnostic = nil
            return true
        } catch {
            isActive = false
            serviceResponding = false
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

    private func describe(_ error: Error) -> String {
        (error as? CustomStringConvertible)?.description ?? error.localizedDescription
    }
}
