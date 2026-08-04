import CicadaIPC
import Foundation

/// 将 `SentinelStatusSnapshot` 映射为 UI 展示模型（ReadinessItem / SentinelState / Diagnostic）。
enum SnapshotMapper {
    /// 视为告警/危险态的 state 字符串白名单（小写、trimmed），供 toState/toDiagnostic 共用。
    static let dangerStates: Set<String> = ["activity detected", "alarming", "warning"]

    /// 将 snapshot.state 字符串映射为 SentinelState 枚举。
    static func toState(_ snap: SentinelStatusSnapshot?) -> SentinelState {
        guard let snap else { return .idle }
        let state = normalizedState(snap.state)
        if dangerStates.contains(state) {
            return .warning
        }
        switch state {
        case "running":
            return .running
        case "ready", "completed":
            return .idle
        default: return .idle
        }
    }

    /// 将 snapshot 映射为就绪度列表。
    /// - Parameters:
    ///   - snap: sentinel 状态快照。
    ///   - triggersOn: 触发器是否已启用（来自 SentryConfiguration）。
    ///   - notifOn: 通知是否已配置（来自 SentryConfiguration）。
    static func toReadiness(_ snap: SentinelStatusSnapshot?, triggersOn: Bool, notifOn: Bool) -> [ReadinessItem] {
        guard let snap else { return [] }
        return [
            ReadinessItem(
                key: "triggers",
                label: String(localized: "触发器", bundle: .module),
                status: triggersOn ? .ok : .off,
                valueText: triggersOn ? String(localized: "已启用", bundle: .module) : String(localized: "未启用", bundle: .module)
            ),
            ReadinessItem(
                key: "notifications",
                label: String(localized: "通知", bundle: .module),
                status: notifOn ? .ok : .off,
                valueText: notifOn ? String(localized: "已配置", bundle: .module) : String(localized: "未配置", bundle: .module)
            ),
            ReadinessItem(
                key: "camera",
                label: String(localized: "录像", bundle: .module),
                status: snap.recordingEnabled ? .ok : .off,
                // recordingEnabled 是配置开关而非运行态：空闲/完成时也常为 true，
                // 标「录制中」会谎称正在录制，故显示「已启用」。
                valueText: snap.recordingEnabled ? String(localized: "已启用", bundle: .module) : String(localized: "关闭", bundle: .module)
            ),
            ReadinessItem(
                key: "activation",
                label: String(localized: "睡眠保持", bundle: .module),
                status: snap.sleepHoldActive ? .ok : .warn,
                valueText: snap.sleepHoldActive ? String(localized: "活跃", bundle: .module) : String(localized: "空闲", bundle: .module)
            ),
        ]
    }

    /// 将 snapshot.activityHint 映射为 Diagnostic（空则返回 nil）。
    static func toDiagnostic(_ snap: SentinelStatusSnapshot?) -> Diagnostic? {
        guard let snap else { return nil }
        let message = snap.activityHint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return nil }
        let state = normalizedState(snap.state)
        let level: DiagLevel = dangerStates.contains(state) ? .danger : .warn
        return Diagnostic(level: level, message: message)
    }

    /// 计算就绪度百分比（ok 项数 / 总项数）。
    static func readinessProgress(_ items: [ReadinessItem]) -> Double {
        guard !items.isEmpty else { return 0 }
        let okCount = items.filter { $0.status == .ok }.count
        return Double(okCount) / Double(items.count)
    }

    private static func normalizedState(_ state: String) -> String {
        state.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
