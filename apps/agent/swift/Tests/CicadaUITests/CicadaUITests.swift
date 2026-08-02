import Darwin
import XCTest
@testable import CicadaUI
import CicadaCore
import CicadaIPC
import CicadaSleepHoldCore

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

        // 防抖 + Task.detached 落盘：轮询等待 saveState 到 .ok 且文件反映新值。
        var savedOK = false
        for _ in 0..<100 {
            if model.saveState == .ok, sentryStore.load().sentryRecordingEnabled {
                savedOK = true
                break
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertTrue(savedOK, "sentry 配置在防抖窗口后应落盘成功")
        XCTAssertEqual(model.saveState, .ok)
        XCTAssertTrue(sentryStore.load().sentryRecordingEnabled)
    }

    @MainActor
    func testSleepHoldReachableWithZeroSessionsIsInactive() async {
        let model = SleepHoldModel(statusProvider: {
            SleepHoldControlResponse(ok: true, status: .canSleep, activeSessions: 0)
        })

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
            let model = SleepHoldModel(statusProvider: { response })
            await model.refresh()
            XCTAssertTrue(model.isActive, "\(response)")
        }
    }

    @MainActor
    func testSleepHoldReportsServiceAndConnectionFailures() async {
        let rejected = SleepHoldModel(statusProvider: {
            SleepHoldControlResponse(ok: false, error: "service unavailable")
        })
        await rejected.refresh()
        XCTAssertFalse(rejected.isActive)
        XCTAssertEqual(rejected.diagnostic?.message, "service unavailable")

        let disconnected = SleepHoldModel(statusProvider: {
            throw NSError(domain: "SleepHoldTests", code: 1)
        })
        await disconnected.refresh()
        XCTAssertFalse(disconnected.isActive)
        XCTAssertNotNil(disconnected.diagnostic)
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
