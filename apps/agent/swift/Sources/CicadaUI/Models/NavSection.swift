import Foundation

/// 侧栏导航分区枚举。
///
/// 定义在 CicadaUI（而非 ControlCenterRoot），供 NavRow 和 ControlCenterRoot 共用。
///
/// `public` 暴露：宿主 commands（`ControlCenterRouter.shared.open(.settings)`）与
/// `ControlCenterRouter` 需跨模块引用此类型。
public enum NavSection: String, Hashable, CaseIterable, Identifiable {
    case overview
    case settings
    case maintenance

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .overview: return String(localized: "概览", bundle: .module)
        case .settings: return String(localized: "设置", bundle: .module)
        case .maintenance: return String(localized: "维护", bundle: .module)
        }
    }

    public var systemImage: String {
        switch self {
        case .overview: return "eye"
        case .settings: return "slider.horizontal.3"
        case .maintenance: return "wrench.and.screwdriver"
        }
    }

    public var statusText: String {
        switch self {
        case .overview: return String(localized: "运行中", bundle: .module)
        case .settings: return String(localized: "就绪", bundle: .module)
        case .maintenance: return String(localized: "睡眠保持空闲", bundle: .module)
        }
    }
}