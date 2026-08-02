import SwiftUI

/// Sentinel 运行状态枚举，供 StatusHeroCard/StatusBadge/NavRow 共用。
enum SentinelState {
    case running
    case warning
    case idle

    /// 状态标题。
    var title: String {
        switch self {
        case .running: return "运行中"
        case .warning: return "警告"
        case .idle: return "空闲"
        }
    }

    /// 状态描述。
    var description: String {
        switch self {
        case .running: return "监控已激活，正在守护你的 Mac"
        case .warning: return "检测到异常活动，请查看诊断信息"
        case .idle: return "监控未启动，点击下方按钮开启守护"
        }
    }

    /// SF Symbol 名称。
    var systemImage: String {
        switch self {
        case .running: return "eye.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .idle: return "eye.slash"
        }
    }

    /// 状态徽章颜色。
    var badgeColor: Color {
        switch self {
        case .running: return .cicadaAccent
        case .warning: return .cicadaWarn
        case .idle: return .cicadaTextTertiary
        }
    }
}