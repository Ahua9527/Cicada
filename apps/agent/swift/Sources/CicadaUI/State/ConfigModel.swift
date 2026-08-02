import CicadaCore
import Foundation

/// 聚合 `CicadaConfig`（连接层）+ `SentryConfiguration`（防护层）双轨配置。
@MainActor
public final class ConfigModel: ObservableObject {
    /// 连接层编辑态。
    @Published public var draft: CicadaConfig
    /// 防护层编辑态。
    @Published public var sentry: SentryConfiguration {
        didSet {
            guard !isLoading else { return }
            scheduleSentrySave()
        }
    }
    /// 保存状态。
    @Published public private(set) var saveState: SaveState = .idle

    public enum SaveState: Equatable {
        case idle
        case saving
        case ok
        case err(String)
    }

    private let store: ConfigStore            // ~/.cicada/config.json
    private let sentryStore: SentryConfigStore // ~/.cicada/sentry-config.json
    private var isLoading = false

    /// 防抖用保存任务：连续 Toggle 时合并为一次落盘。
    private var saveSentryTask: Task<Void, Never>?
    /// 防抖间隔：避免高频 Toggle 期间反复写盘。
    private let saveSentryDebounce: UInt64 = 150_000_000 // 150ms

    public init(store: ConfigStore = .init(), sentryStore: SentryConfigStore = .init()) {
        self.store = store
        self.sentryStore = sentryStore
        self.draft = (try? store.load()) ?? .defaultConfig()
        self.sentry = sentryStore.load()
    }

    /// 加载双轨配置。
    public func load() {
        isLoading = true
        defer { isLoading = false }
        draft = (try? store.load()) ?? .defaultConfig()
        sentry = sentryStore.load()
    }

    /// 保存连接层配置。
    public func saveConnection() async {
        saveState = .saving
        do {
            try store.save(draft)
            saveState = .ok
        } catch {
            saveState = .err(error.localizedDescription)
        }
    }

    /// 防抖调度落盘：取消上一个未执行的写盘任务再起新的。
    /// didSet 频繁触发时（连续 Toggle），仅最后一次真正写盘。
    private func scheduleSentrySave() {
        saveSentryTask?.cancel()
        saveSentryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: self?.saveSentryDebounce ?? 0)
            guard !Task.isCancelled, let self else { return }
            await self.persistSentry()
        }
    }

    /// 实际落盘：把同步 I/O 移到 `Task.detached`，主线程不阻塞。
    private func persistSentry() async {
        saveState = .saving
        let snapshot = sentry
        let store = sentryStore
        do {
            try await Task.detached(priority: .utility) {
                try store.save(snapshot)
            }.value
            saveState = .ok
        } catch {
            saveState = .err(error.localizedDescription)
        }
    }
}
