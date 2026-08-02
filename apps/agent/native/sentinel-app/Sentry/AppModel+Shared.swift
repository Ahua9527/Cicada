//
//  AppModel+Shared.swift
//  Sentry
//
//  P4 宿主接入：为 CicadaUI 的 AppModel 提供宿主级单例。
//

import CicadaUI

extension AppModel {
    /// 宿主级单例。供 SentinelController / Sentry 等非-SwiftUI-Scene 代码访问
    /// （警戒窗口由 SkyLightOperator 创建在 Scene 之外，@EnvironmentObject 不可达）。
    ///
    /// 放宿主侧扩展而非改 CicadaUI：CicadaUI 是纯 SwiftUI 库，不应假定「宿主唯一实例」
    /// 语义；单例是宿主编排决策，放宿主扩展更干净。AppModel.init 默认参数已自带
    /// UdsSentinelControlClient / SleepHoldControlClient / ConfigStore / SentryConfigStore。
    static let shared = AppModel()
}