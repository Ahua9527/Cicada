import Darwin
import XCTest
@testable import CicadaUI
import CicadaCore
import CicadaIPC
import CicadaSleepHoldCore
import CicadaSystem

final class CicadaUITests: XCTestCase {
    func testSnapshotMapperToStateRunning() {
        let snap = SentinelStatusSnapshot(
            state: "Running",
            activityHint: "",
            recordingEnabled: true,
            sleepHoldActive: true,
            sleepHoldSessionId: "abc"
        )
        XCTAssertEqual(SnapshotMapper.toState(snap), .running)
    }

    func testSnapshotMapperToStateAlarming() {
        let snap = SentinelStatusSnapshot(
            state: "Activity Detected",
            activityHint: "电源断开",
            recordingEnabled: false,
            sleepHoldActive: false,
            sleepHoldSessionId: ""
        )
        XCTAssertEqual(SnapshotMapper.toState(snap), .warning)
    }

    func testSnapshotMapperToStateReadyAndCompleted() {
        for state in ["Ready", "Completed"] {
            let snap = SentinelStatusSnapshot(
                state: state,
                activityHint: "",
                recordingEnabled: false,
                sleepHoldActive: false,
                sleepHoldSessionId: ""
            )
            XCTAssertEqual(SnapshotMapper.toState(snap), .idle, state)
        }
    }

    func testSnapshotMapperToStateNil() {
        XCTAssertEqual(SnapshotMapper.toState(nil), .idle)
    }

    func testSnapshotMapperToReadiness() {
        let snap = SentinelStatusSnapshot(
            state: "running",
            activityHint: "",
            recordingEnabled: true,
            sleepHoldActive: true,
            sleepHoldSessionId: "abc"
        )
        let items = SnapshotMapper.toReadiness(snap, triggersOn: true, notifOn: true)
        XCTAssertEqual(items.count, 4)
        XCTAssertEqual(items[0].status, .ok)
        XCTAssertEqual(items[1].status, .ok)
        XCTAssertEqual(items[2].status, .ok)
        XCTAssertEqual(items[3].status, .ok)
    }

    func testReadinessProgress() {
        let items = [
            ReadinessItem(key: "a", label: "A", status: .ok, valueText: "ok"),
            ReadinessItem(key: "b", label: "B", status: .off, valueText: "off"),
            ReadinessItem(key: "c", label: "C", status: .ok, valueText: "ok"),
            ReadinessItem(key: "d", label: "D", status: .ok, valueText: "ok"),
        ]
        XCTAssertEqual(SnapshotMapper.readinessProgress(items), 0.75, accuracy: 0.001)
    }

    func testSnapshotMapperToDiagnostic() {
        let snap = SentinelStatusSnapshot(
            state: "Activity Detected",
            activityHint: "检测到异常",
            recordingEnabled: false,
            sleepHoldActive: false,
            sleepHoldSessionId: ""
        )
        let diag = SnapshotMapper.toDiagnostic(snap)
        XCTAssertNotNil(diag)
        XCTAssertEqual(diag?.level, .danger)
        XCTAssertEqual(diag?.message, "检测到异常")
    }

    func testSnapshotMapperToDiagnosticEmpty() {
        let snap = SentinelStatusSnapshot(
            state: "running",
            activityHint: "",
            recordingEnabled: false,
            sleepHoldActive: false,
            sleepHoldSessionId: ""
        )
        XCTAssertNil(SnapshotMapper.toDiagnostic(snap))
    }

    func testSentryConfigurationDefaults() {
        let cfg = SentryConfiguration()
        XCTAssertFalse(cfg.hasTriggerEnabled)
        XCTAssertFalse(cfg.hasNotificationEnabled)
        XCTAssertFalse(cfg.canActivate)
    }

    func testSentryConfigurationCanActivate() {
        var cfg = SentryConfiguration()
        cfg.sentryTriggersLidEnabled = true
        cfg.sentryAlarmsNotificationType = .bark
        XCTAssertTrue(cfg.hasTriggerEnabled)
        XCTAssertTrue(cfg.hasNotificationEnabled)
        XCTAssertTrue(cfg.canActivate)
    }

    func testSentryConfigurationEnabledTriggerCountReflectsAllThreeFlags() {
        var cfg = SentryConfiguration()
        XCTAssertEqual(cfg.enabledTriggerCount, 0)
        XCTAssertFalse(cfg.hasTriggerEnabled)

        cfg.sentryTriggersLidEnabled = true
        XCTAssertEqual(cfg.enabledTriggerCount, 1)

        cfg.sentryTriggersInternetEnabled = true
        XCTAssertEqual(cfg.enabledTriggerCount, 2)

        cfg.sentryTriggersPowerEnabled = true
        XCTAssertEqual(cfg.enabledTriggerCount, 3)
        XCTAssertTrue(cfg.hasTriggerEnabled)

        cfg.sentryTriggersInternetEnabled = false
        XCTAssertEqual(cfg.enabledTriggerCount, 2)
    }

    func testSnapshotMapperDangerStatesIsSharedConstant() {
        // M2: dangerStates 应作为共享 Set<String> 供 toState/toDiagnostic 复用。
        XCTAssertEqual(
            SnapshotMapper.dangerStates,
            ["activity detected", "alarming", "warning"]
        )
        // 验证两端基于同一来源：危险态字符串都应能映射为 warning/danger。
        for state in SnapshotMapper.dangerStates {
            let snap = SentinelStatusSnapshot(
                state: state,
                activityHint: "x",
                recordingEnabled: false,
                sleepHoldActive: false,
                sleepHoldSessionId: ""
            )
            XCTAssertEqual(SnapshotMapper.toState(snap), .warning, state)
            XCTAssertEqual(SnapshotMapper.toDiagnostic(snap)?.level, .danger, state)
        }
    }

    func testSentryConfigStoreMigratesLegacyAndSetsPrivatePermissions() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let (suiteName, defaults) = try makeUserDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let path = directory.appendingPathComponent("sentry-config.json").path
        let legacy = SentryConfiguration(
            sentryTriggersLidEnabled: true,
            sentryAlarmsNotificationType: .bark
        )
        defaults.set(try JSONEncoder().encode(legacy), forKey: "sentry.config")

        let store = SentryConfigStore(path: path, legacyDefaults: defaults)
        XCTAssertEqual(store.load(), legacy)
        XCTAssertNil(defaults.data(forKey: "sentry.config"))

        var fileStat = stat()
        XCTAssertEqual(lstat(path, &fileStat), 0)
        XCTAssertEqual(fileStat.st_mode & 0o777, 0o600)
        XCTAssertEqual(SentryConfigStore(path: path, legacyDefaults: defaults).load(), legacy)
    }

    func testSentryConfigStorePrefersJSONOverLegacy() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let (suiteName, defaults) = try makeUserDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let path = directory.appendingPathComponent("sentry-config.json").path
        let fileConfig = SentryConfiguration(sentryTriggersPowerEnabled: true)
        let legacy = SentryConfiguration(sentryTriggersLidEnabled: true)
        let store = SentryConfigStore(path: path, legacyDefaults: defaults)
        try store.save(fileConfig)
        defaults.set(try JSONEncoder().encode(legacy), forKey: "sentry.config")

        XCTAssertEqual(store.load(), fileConfig)
        XCTAssertNil(defaults.data(forKey: "sentry.config"))
    }

    func testSentryConfigStoreKeepsLegacyWhenMigrationWriteFails() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let (suiteName, defaults) = try makeUserDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let blocker = directory.appendingPathComponent("not-a-directory")
        try Data().write(to: blocker)
        let path = blocker.appendingPathComponent("sentry-config.json").path
        let legacy = SentryConfiguration(sentryAlarmsSoundsEnabled: true)
        let legacyData = try JSONEncoder().encode(legacy)
        defaults.set(legacyData, forKey: "sentry.config")

        let store = SentryConfigStore(path: path, legacyDefaults: defaults)
        XCTAssertEqual(store.load(), legacy)
        XCTAssertEqual(defaults.data(forKey: "sentry.config"), legacyData)
    }

    @MainActor
    func testConfigModelAutomaticallyPersistsSentryChanges() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let (suiteName, defaults) = try makeUserDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let sentryPath = directory.appendingPathComponent("sentry-config.json").path
        let sentryStore = SentryConfigStore(path: sentryPath, legacyDefaults: defaults)
        let model = ConfigModel(
            store: ConfigStore(path: directory.appendingPathComponent("config.json").path),
            sentryStore: sentryStore
        )

        model.sentry.sentryRecordingEnabled = true

        // 防抖 + Task.detached 落盘：轮询等待 sentrySaveState 到 .ok 且文件反映新值。
        var savedOK = false
        for _ in 0..<100 {
            if model.sentrySaveState == .ok, sentryStore.load().sentryRecordingEnabled {
                savedOK = true
                break
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertTrue(savedOK, "sentry 配置在防抖窗口后应落盘成功")
        XCTAssertEqual(model.sentrySaveState, .ok)
        XCTAssertTrue(sentryStore.load().sentryRecordingEnabled)
    }

    @MainActor
    func testConfigModelRetriesFailedSentrySave() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let (suiteName, defaults) = try makeUserDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let blocker = directory.appendingPathComponent("not-a-directory")
        try Data().write(to: blocker)
        let sentryStore = SentryConfigStore(
            path: blocker.appendingPathComponent("sentry-config.json").path,
            legacyDefaults: defaults
        )
        let model = ConfigModel(
            store: ConfigStore(path: directory.appendingPathComponent("config.json").path),
            sentryStore: sentryStore
        )

        model.sentry.sentryRecordingEnabled = true

        var failed = false
        for _ in 0..<100 {
            if case .err = model.sentrySaveState {
                failed = true
                break
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertTrue(failed, "写入路径不可用时应公开保存失败状态")

        try FileManager.default.removeItem(at: blocker)
        try FileManager.default.createDirectory(at: blocker, withIntermediateDirectories: true)
        await model.retrySentrySave()

        XCTAssertEqual(model.sentrySaveState, .ok)
        XCTAssertTrue(sentryStore.load().sentryRecordingEnabled)
    }

    @MainActor
    func testSleepHoldReachableWithZeroSessionsIsInactive() async {
        let model = SleepHoldModel(statusProvider: {
            SleepHoldControlResponse(ok: true, status: .canSleep, activeSessions: 0)
        }, isInstalled: { true })

        await model.refresh()

        XCTAssertFalse(model.isActive)
        XCTAssertEqual(model.cells.count, 3)
        XCTAssertNil(model.diagnostic)
    }

    @MainActor
    func testSleepHoldUsesHoldOrActiveSessionCountForActiveState() async {
        for response in [
            SleepHoldControlResponse(ok: true, status: .hold, activeSessions: 0),
            SleepHoldControlResponse(ok: true, status: .canSleep, activeSessions: 2),
        ] {
            let model = SleepHoldModel(statusProvider: { response }, isInstalled: { true })
            await model.refresh()
            XCTAssertTrue(model.isActive, "\(response)")
        }
    }

    @MainActor
    func testSleepHoldReportsServiceAndConnectionFailures() async throws {
        let rejected = SleepHoldModel(statusProvider: {
            SleepHoldControlResponse(ok: false, error: "service unavailable")
        }, isInstalled: { true })
        await rejected.refresh()
        XCTAssertFalse(rejected.isActive)
        XCTAssertEqual(rejected.diagnostic?.message, "service unavailable")

        // 已安装但连不上：诊断必须给出可读描述，且不泄露内部错误类型名
        // （旧实现用 localizedDescription，会产出 “CicadaSystem.SleepHoldControlError 错误0”）。
        let disconnected = SleepHoldModel(statusProvider: {
            throw SleepHoldControlError.unavailable("No such file or directory")
        }, isInstalled: { true })
        await disconnected.refresh()
        XCTAssertFalse(disconnected.isActive)
        let message = try XCTUnwrap(disconnected.diagnostic?.message)
        XCTAssertTrue(message.hasSuffix("No such file or directory"), message)
        XCTAssertFalse(message.contains("SleepHoldControlError"), message)
    }

    @MainActor
    func testSleepHoldNotInstalledSkipsSocketAndExposesInstallState() async {
        // 服务未安装时不应再尝试连接 socket（必然 ENOENT），直接给出可行动诊断。
        // provider 返回可达快照：若 refresh 仍调用了 provider，cells 会被填成 3 个。
        let model = SleepHoldModel(statusProvider: {
            SleepHoldControlResponse(ok: true, status: .hold, activeSessions: 1)
        }, isInstalled: { false })

        let ok = await model.refresh()

        XCTAssertFalse(ok)
        XCTAssertFalse(model.serviceInstalled)
        XCTAssertTrue(model.cells.isEmpty)
        XCTAssertNotNil(model.diagnostic)
    }

    @MainActor
    func testAlarmResetDoesNotNotifyDelegate() async {
        let delegate = AlarmDelegateSpy()
        let alarm = AlarmModel()
        alarm.delegate = delegate
        alarm.activate(reason: "旧告警")

        alarm.reset()

        XCTAssertFalse(alarm.isActive)
        XCTAssertEqual(alarm.reason, "")
        XCTAssertEqual(delegate.stopCount, 0)
    }

    @MainActor
    func testSentinelsModelCatchClearsStaleState() async {
        let snap = SentinelStatusSnapshot(
            state: "running",
            activityHint: "",
            recordingEnabled: true,
            sleepHoldActive: true,
            sleepHoldSessionId: "abc"
        )
        var shouldThrow = false
        let model = SentinelsModel(statusProvider: {
            if shouldThrow { throw NSError(domain: "SentinelsModelTests", code: 1) }
            return SentinelControlResponse(ok: true, message: "", status: snap)
        })

        let ok = await model.refresh()
        XCTAssertTrue(ok)
        XCTAssertEqual(model.state, .running)
        XCTAssertEqual(model.readiness.count, 4)
        XCTAssertNotNil(model.lastSnapshot)

        // 连接失败：catch 分支应清空陈旧快照/就绪项/触发数，与 nil 分支一致，
        // 避免 Overview/菜单栏把上一次成功的过期状态当实时。
        shouldThrow = true
        let ok2 = await model.refresh()
        XCTAssertFalse(ok2)
        XCTAssertEqual(model.state, .idle)
        XCTAssertNil(model.lastSnapshot)
        XCTAssertTrue(model.readiness.isEmpty)
        XCTAssertEqual(model.activeTriggerCount, 0)
        XCTAssertNotNil(model.diagnostic)
    }

    @MainActor
    func testConfigModelSaveConnectionMergesConcurrentChanges() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let configPath = directory.appendingPathComponent("config.json").path
        let store = ConfigStore(path: configPath)

        var initial = CicadaConfig.defaultConfig()
        initial.relayURL = "https://a.example.com"
        initial.deviceId = "MAC_AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
        try store.save(initial)

        let model = ConfigModel(
            store: store,
            sentryStore: SentryConfigStore(path: directory.appendingPathComponent("sentry-config.json").path)
        )

        // 模拟控制中心打开后，CLI 并发改了 deviceId（盘上最新值）。
        var concurrent = try store.load()
        concurrent.deviceId = "MAC_BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB"
        try store.save(concurrent)

        // 用户在控制中心只改 relayURL 并保存。
        model.draft.relayURL = "https://b.example.com"
        await model.saveConnection()

        // 盘上：relayURL=B（用户编辑），deviceId=DEV2（并发修改保留，未被陈旧 draft 回滚）。
        let reloaded = try store.load()
        XCTAssertEqual(reloaded.relayURL, "https://b.example.com")
        XCTAssertEqual(reloaded.deviceId, "MAC_BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB")
        // draft 同步为合并结果。
        XCTAssertEqual(model.draft.relayURL, "https://b.example.com")
        XCTAssertEqual(model.draft.deviceId, "MAC_BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB")
    }

    func testFolderActionDoesNotRequireHoldByDefault() {
        let action = FolderAction(systemImage: "trash", label: "Clear", isDanger: true, action: {})

        XCTAssertFalse(action.requiresHoldConfirmation)
    }

    func testHoldConfirmationDoesNotCompleteAfterCancellation() {
        var confirmation = HoldConfirmationState()

        confirmation.begin()
        confirmation.cancel()

        XCTAssertFalse(confirmation.complete())
    }

    func testHoldConfirmationCompletesOnlyOncePerPress() {
        var confirmation = HoldConfirmationState()

        confirmation.begin()

        XCTAssertTrue(confirmation.complete())
        XCTAssertFalse(confirmation.complete())
        XCTAssertTrue(confirmation.hasCompleted)
    }

    func testDiagnosticMotionKeyIsStableForUnchangedDiagnostic() {
        let baseline = Diagnostic(level: .warn, message: "sentinel unavailable")
        let identical = Diagnostic(level: .warn, message: "sentinel unavailable")
        let differentLevel = Diagnostic(level: .danger, message: "sentinel unavailable")
        let differentMessage = Diagnostic(level: .warn, message: "sleephold unavailable")

        XCTAssertEqual(baseline.motionKey, identical.motionKey)
        XCTAssertNotEqual(baseline.motionKey, differentLevel.motionKey)
        XCTAssertNotEqual(baseline.motionKey, differentMessage.motionKey)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cicada-ui-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func makeUserDefaults() throws -> (String, UserDefaults) {
        let suiteName = "com.cicada.tests.\(UUID().uuidString)"
        return (suiteName, try XCTUnwrap(UserDefaults(suiteName: suiteName)))
    }
}

@MainActor
private final class AlarmDelegateSpy: AlarmEngineDelegate {
    private(set) var stopCount = 0

    func alarmDidStop() async {
        stopCount += 1
    }
}
