import CicadaIPC
import Foundation

/// 连接 sentinel IPC，轮询状态，映射到展示模型。
@MainActor
final class SentinelsModel: ObservableObject {
    @Published private(set) var state: SentinelState = .idle
    @Published private(set) var readiness: [ReadinessItem] = []
    @Published private(set) var diagnostic: Diagnostic?
    @Published private(set) var activeTriggerCount: Int = 0
    @Published private(set) var lastSnapshot: SentinelStatusSnapshot?

    private let client: UdsSentinelControlClient
    fileprivate weak var configProvider: ConfigModel?

    init(client: UdsSentinelControlClient = .init()) {
        self.client = client
    }

    /// 轮询刷新状态。连接失败时设为 idle 并生成诊断警告。
    /// - Returns: 是否成功拿到 sentinel 响应（用于轮询退避）。
    @discardableResult
    func refresh() async -> Bool {
        do {
            let resp = try await client.statusAsync()
            if let snap = resp.status {
                lastSnapshot = snap
                state = SnapshotMapper.toState(snap)
                let triggersOn = configProvider?.sentry.hasTriggerEnabled ?? false
                let notifOn = configProvider?.sentry.hasNotificationEnabled ?? false
                readiness = SnapshotMapper.toReadiness(snap, triggersOn: triggersOn, notifOn: notifOn)
                diagnostic = SnapshotMapper.toDiagnostic(snap)
                activeTriggerCount = configProvider?.sentry.enabledTriggerCount ?? 0
            } else {
                // snap 为 nil：清空陈旧状态，避免 UI 展示与真实状态不一致。
                lastSnapshot = nil
                readiness = []
                diagnostic = nil
                activeTriggerCount = 0
                state = .idle
            }
            return true
        } catch {
            state = .idle
            diagnostic = Diagnostic(level: .warn, message: "无法连接 sentinel: \(error.localizedDescription)")
            return false
        }
    }

    /// 启动 sentinel。
    func start() async { _ = try? await client.startAsync() }
    /// 停止 sentinel。
    func stop() async { _ = try? await client.stopAsync() }
    /// 解锁 sentinel 警戒。
    func unlock() async { _ = try? await client.unlockAsync() }
}

/// 允许 AppModel 在 init 后注入 ConfigModel 弱引用。
extension SentinelsModel {
    func setConfigProvider(_ provider: ConfigModel) {
        configProvider = provider
    }
}