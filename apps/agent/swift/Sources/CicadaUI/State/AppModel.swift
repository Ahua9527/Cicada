import CicadaCore
import CicadaIPC
import CicadaSystem
import Foundation

/// 全局单源状态聚合 + 3 秒轮询 Task。
///
/// `@StateObject` 在 App 入口创建，`@EnvironmentObject` 注入。
/// 子模型由 AppModel 持有（聚合），各自 `@MainActor`。
@MainActor
public final class AppModel: ObservableObject {
    @Published var sentinels: SentinelsModel
    @Published public private(set) var config: ConfigModel
    @Published var sleepHold: SleepHoldModel
    @Published public private(set) var alarm: AlarmModel

    private var pollTask: Task<Void, Never>?

    /// 轮询基础周期（纳秒）。连续失败时会按指数退避拉长，恢复后回到此值。
    private static let basePollInterval: UInt64 = 3_000_000_000
    /// 退避上限，避免无限拉长。
    private static let maxPollInterval: UInt64 = 30_000_000_000

    public convenience init() {
        self.init(
            sentinelClient: .init(),
            sleepHoldClient: .init(),
            configStore: .init(),
            sentryConfigStore: .init()
        )
    }

    init(
        sentinelClient: UdsSentinelControlClient,
        sleepHoldClient: SleepHoldControlClient,
        configStore: ConfigStore,
        sentryConfigStore: SentryConfigStore
    ) {
        let sentinelsModel = SentinelsModel(client: sentinelClient)
        let configModel = ConfigModel(store: configStore, sentryStore: sentryConfigStore)
        // 注入 ConfigModel 弱引用，供 readiness 映射拿 triggersOn/notifOn
        sentinelsModel.setConfigProvider(configModel)

        self.sentinels = sentinelsModel
        self.config = configModel
        self.sleepHold = SleepHoldModel(client: sleepHoldClient)
        self.alarm = AlarmModel()
    }

    /// 启动轮询。周期稳定（sleep 不计入 IPC 耗时），连续失败时指数退避拉长间隔，
    /// 恢复成功后立即回到 base 周期。在 `applicationDidFinishLaunching` 或 `.onAppear` 调。
    public func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            var consecutiveFailures = 0
            while !Task.isCancelled {
                let tickStart = ContinuousClock.now
                let ok = await self?.refreshAll() ?? false
                if ok {
                    consecutiveFailures = 0
                } else {
                    consecutiveFailures += 1
                }
                // 退避：连续失败时每次翻倍，上限 maxPollInterval；成功立即回 base。
                var interval = Self.basePollInterval
                if consecutiveFailures > 0 {
                    let backoffShift = min(consecutiveFailures - 1, 10) // 最多 2^10 ≈ 17min
                    interval = Self.basePollInterval &<< backoffShift
                    if interval > Self.maxPollInterval || interval < Self.basePollInterval {
                        interval = Self.maxPollInterval
                    }
                }
                // 减去本 tick 已耗时的 IPC 时间，保证周期稳定（不短于 0）。
                let elapsed = ContinuousClock.now - tickStart
                let elapsedNs = UInt64(elapsed.components.seconds) * 1_000_000_000
                    + UInt64(elapsed.components.attoseconds / 1_000_000_000)
                if elapsedNs < interval {
                    let remaining = interval - elapsedNs
                    try? await Task.sleep(nanoseconds: remaining)
                }
            }
        }
    }

    /// 停止轮询。
    public func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    /// 手动触发一次全量刷新。返回 false 表示任一上游失败（用于轮询退避）。
    @discardableResult
    func refreshAll() async -> Bool {
        async let s = sentinels.refresh()
        async let h = sleepHold.refresh()
        let (sentinelOk, sleepOk) = await (s, h)
        return sentinelOk && sleepOk
    }
}
