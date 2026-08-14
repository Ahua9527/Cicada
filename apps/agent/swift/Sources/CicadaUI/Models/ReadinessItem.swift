import Foundation

/// UI 展示模型定义，按 Design.md §9.1。

/// 就绪度检查项。
struct ReadinessItem: Identifiable {
    let id = UUID()
    let key: String        // "triggers"/"notifications"/"camera"/"activation"
    let label: String
    let status: ReadinessStatus
    let valueText: String
}

/// 就绪度状态。
enum ReadinessStatus {
    case ok
    case warn
    case off
}

/// 诊断信息条目。
struct Diagnostic: Identifiable {
    let id = UUID()
    let level: DiagLevel   // .warn / .danger
    let message: String

    /// 用于 UI 过渡的稳定标识，避免相同轮询结果因 `id` 变化而重复播放动效。
    var motionKey: String {
        let levelKey = switch level {
        case .warn: "warn"
        case .danger: "danger"
        }
        return "\(levelKey):\(message)"
    }
}

/// 诊断级别。
enum DiagLevel {
    case warn
    case danger
}

/// SleepHold 数据卡片展示模型。
struct SleepHoldCellData: Identifiable {
    let id = UUID()
    let label: String
    let value: String
    let isMono: Bool
    let ok: Bool
}

/// 维护页文件夹操作按钮模型。
///
/// `public` 暴露：宿主在 `MaintenanceHostInjections` 中构造 `[FolderAction]` 注入
/// `FolderGrid`（`@Environment(\.folderActions)`），需要跨模块引用此类型。
public struct FolderAction: Identifiable {
    public let id = UUID()
    public let systemImage: String
    public let label: String
    public let isDanger: Bool
    /// 是否需要按住确认。仅用于确实会删除用户文件的动作，不能由危险色样式推断。
    public let requiresHoldConfirmation: Bool
    public let action: () -> Void

    public init(
        systemImage: String,
        label: String,
        isDanger: Bool,
        requiresHoldConfirmation: Bool = false,
        action: @escaping () -> Void
    ) {
        self.systemImage = systemImage
        self.label = label
        self.isDanger = isDanger
        self.requiresHoldConfirmation = requiresHoldConfirmation
        self.action = action
    }
}
