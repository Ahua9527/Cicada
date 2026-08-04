import CicadaSleepHoldCore
import CicadaSystem
import Foundation

/// 连接 sleephold IPC，提供只读维护状态。
@MainActor
final class SleepHoldModel: ObservableObject {
    @Published private(set) var cells: [SleepHoldCellData] = []
    @Published private(set) var isActive: Bool = false
    @Published private(set) var diagnostic: Diagnostic?

    private let statusProvider: () async throws -> SleepHoldControlResponse

    init(client: SleepHoldControlClient = .init()) {
        self.statusProvider = { try await client.statusAsync() }
    }

    init(statusProvider: @escaping () async throws -> SleepHoldControlResponse) {
        self.statusProvider = statusProvider
    }

    /// 轮询刷新状态。连接失败时设为 inactive 并生成诊断警告。
    /// - Returns: 是否成功拿到 sleephold 响应且 `ok == true`（用于轮询退避）。
    @discardableResult
    func refresh() async -> Bool {
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
            diagnostic = Diagnostic(level: .warn, message: String(localized: "无法连接 sleephold", bundle: .module) + ": " + error.localizedDescription)
            return false
        }
    }
}
