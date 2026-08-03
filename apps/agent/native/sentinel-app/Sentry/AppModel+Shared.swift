//
//  AppModel+Shared.swift
//  Sentry
//
//  P4 宿主接入：为 CicadaUI 的 AppModel 提供宿主级单例。
//

import CicadaCore
import CicadaIPC
import CicadaSystem
import CicadaUI

extension AppModel {
    /// 宿主级单例。供 SentinelController / Sentry 等非-SwiftUI-Scene 代码访问
    /// （警戒窗口由 SkyLightOperator 创建在 Scene 之外，@EnvironmentObject 不可达）。
    ///
    /// 放宿主侧扩展而非改 CicadaUI：CicadaUI 是纯 SwiftUI 库，不应假定「宿主唯一实例」
    /// 语义；单例是宿主编排决策，放宿主扩展更干净。
    ///
    /// 路径对齐宿主服务端：Sentinel socket / relay config / sentry config 均走
    /// `CicadaSentinelPaths`（环境感知 CICADA_HOME / CICADA_SENTINEL_SOCKET），
    /// 与宿主 Sentinel IPC 服务端、relay 配置读写同一文件、连同一 socket。
    /// SleepHold 客户端保持默认固定路径——sleephold 二进制用固定 `RuntimePaths`，
    /// 宿主无对应环境感知服务端，跟随其固定路径以保持连通。
    static let shared = AppModel(
        sentinelClient: .init(socketPath: CicadaSentinelPaths.sentinelSocketPath()),
        sleepHoldClient: .init(),
        configStore: .init(path: CicadaSentinelPaths.configPath()),
        sentryConfigStore: .init(path: CicadaSentinelPaths.sentryConfigPath())
    )
}