//
//  ControlCenterRouter+Host.swift
//  Sentry
//
//  P4.2 宿主接入：为 CicadaUI 的 ControlCenterRouter 提供宿主级单例与路由桥接。
//

import CicadaUI
import Foundation

extension ControlCenterRouter {
    /// 宿主级单例。供 commands（Scene 外的 Button action）与 SentinelController 等
    /// 非 SwiftUI-Scene 代码设 `selection` 并 `openMainWindow`。
    ///
    /// 放宿主侧扩展而非 CicadaUI：单例是宿主编排决策，库不应假定「宿主唯一实例」语义
    /// （与 `AppModel.shared` 同构）。`@MainActor` 由 ControlCenterRouter 自身约束。
    static let shared = ControlCenterRouter()

    /// 打开控制中心并切到指定分区。镜像旧 `SentryControlCenterRouter.open`：
    /// 先设 `selection`（驱动 `ControlCenterRoot` 侧栏 + detail 切换），
    /// 再调 `SentinelController.shared.openMainWindow()`（通过已注册的
    /// `mainWindowOpener` 调 `openWindow(id:"main")`）。
    /// `tab` 非空时同时下发一次性设置子页命令（`SettingsPane` 消费）。
    @discardableResult
    func open(_ section: NavSection = .overview, tab: SettingsTab? = nil) -> SentinelCommandResult {
        selection = section
        if let tab {
            pendingSettingsTab = tab
        }
        return SentinelController.shared.openMainWindow()
    }
}