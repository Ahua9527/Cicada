import Foundation

/// 控制中心共享路由器：持有侧栏选中态，供 `ControlCenterRoot` / `MenuBarDropdown`
/// 通过 `@EnvironmentObject` 响应，供宿主 commands 通过单例 `ControlCenterRouter.shared`
/// 外部驱动。CicadaUI 库内不定义单例（单例是宿主编排决策，放 `ControlCenterRouter+Host`）。
///
/// 与旧宿主 `SentryControlCenterRouter` 一一对应，case 与 `NavSection` 对齐，消除双路由。
@MainActor
public final class ControlCenterRouter: ObservableObject {
    /// 当前选中的侧栏分区。默认 `.overview`，`nil` 时 detail 回退到概览。
    @Published public var selection: NavSection? = .overview

    /// 一次性设置子页路由命令：外部（如 NotchDrop 齿轮）要求设置页切到指定 tab；
    /// `SettingsPane` onAppear/onChange 消费后置回 `nil`。
    @Published public var pendingSettingsTab: SettingsTab?

    public init() {}
}