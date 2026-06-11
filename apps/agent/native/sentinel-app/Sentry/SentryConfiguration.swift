//
//  SentryConfiguration.swift
//  Sentry
//
//  Created by 秋星桥 on 5/24/25.
//

import Foundation
import SwiftUI

@MainActor
final class SentryConfigurationManager: ObservableObject {
    static let shared = SentryConfigurationManager()

    private let sleepHoldClient: SleepHoldServiceClient
    private let now: () -> Date
    private let connectRetryInterval: TimeInterval = 3
    private let extendInterval: TimeInterval = 10

    private var isConnectInFlight = false
    private var isExtendInFlight = false
    private var nextConnectAttemptAt: Date = .distantPast
    private var nextExtendAt: Date = .distantPast
    private var sleepHoldStateToken: UInt64 = 0

    @PublishedPersist(key: "sentry.config", defaultValue: .init(), engine: UserDefaultStorage())
    var cfg: SentryConfiguration

    @Published var sleepHoldServiceIdentifier: String = ""
    @Published var sleepHoldServiceLastUpdate: Date = .init()

    init(
        sleepHoldClient: SleepHoldServiceClient = CicadaDaemonSleepHoldServiceClient(),
        now: @escaping () -> Date = Date.init,
        persistEngine: PersistProvider = UserDefaultStorage()
    ) {
        self.sleepHoldClient = sleepHoldClient
        self.now = now
        _cfg = .init(key: "sentry.config", defaultValue: .init(), engine: persistEngine)
    }

    var hasTriggerEnabled: Bool {
        cfg.sentryTriggersLidEnabled
            || cfg.sentryTriggersInternetEnabled
            || cfg.sentryTriggersPowerEnabled
    }

    var hasNotificationEnabled: Bool {
        cfg.sentryAlarmsNotificationType != .none
            || cfg.sentryAlarmsSoundsEnabled
    }

    var hasRecordingEnabled: Bool {
        cfg.sentryRecordingEnabled
    }

    var canActivate: Bool {
        hasTriggerEnabled && hasNotificationEnabled
    }

    func communicateWithSleepHoldServiceIfNeeded() {
        let currentDate = now()

        if shouldConnectSleepHold(at: currentDate) {
            startSleepHoldConnect(at: currentDate)
            return
        }

        guard shouldExtendSleepHold(at: currentDate) else { return }
        startSleepHoldExtend(at: currentDate)
    }

    private func shouldConnectSleepHold(at date: Date) -> Bool {
        sleepHoldServiceIdentifier.isEmpty
            && !isConnectInFlight
            && date >= nextConnectAttemptAt
    }

    private func shouldExtendSleepHold(at date: Date) -> Bool {
        !sleepHoldServiceIdentifier.isEmpty
            && !isExtendInFlight
            && date >= nextExtendAt
    }

    private func startSleepHoldConnect(at date: Date) {
        isConnectInFlight = true
        nextConnectAttemptAt = connectRetryDate(from: date)
        let token = sleepHoldStateToken
        sleepHoldClient.createSession { result in
            Task { @MainActor in
                self.handleSleepHoldConnectResult(result, token: token, date: self.now())
            }
        }
    }

    private func startSleepHoldExtend(at date: Date) {
        let sessionId = sleepHoldServiceIdentifier
        let token = sleepHoldStateToken
        guard !sessionId.isEmpty else {
            isExtendInFlight = false
            return
        }
        isExtendInFlight = true
        nextExtendAt = extendDate(from: date)

        sleepHoldClient.extendSession(sessionId) { ok in
            Task { @MainActor in
                self.handleSleepHoldExtendResult(ok, token: token, sessionId: sessionId, date: self.now())
            }
        }
    }

    func disconnectFromSleepHold() {
        let sessionId = sleepHoldServiceIdentifier
        sleepHoldStateToken &+= 1
        clearLocalSessionState(at: now())

        guard !sessionId.isEmpty else { return }
        terminateSleepHoldSession(
            sessionId,
            successMessage: "[*] sleep hold service disconnected successfully",
            failureMessage: "[*] sleep hold service disconnect failed"
        )
    }

    private func handleSleepHoldConnectResult(
        _ result: Result<String, Error>,
        token: UInt64,
        date: Date
    ) {
        guard token == sleepHoldStateToken else {
            if case let .success(sessionId) = result {
                cleanupStaleSleepHoldSession(sessionId)
            }
            return
        }

        isConnectInFlight = false
        switch result {
        case let .success(sessionId):
            print("[*] sleep hold service connected with sessionId: \(sessionId)")
            recordConnectedSession(sessionId, at: date)
        case let .failure(error):
            print("[*] sleep hold service connect failed: \(error)")
        }
    }

    private func handleSleepHoldExtendResult(
        _ ok: Bool,
        token: UInt64,
        sessionId: String,
        date: Date
    ) {
        guard token == sleepHoldStateToken, sessionId == sleepHoldServiceIdentifier else { return }

        isExtendInFlight = false
        if ok {
            print("[*] sleep hold session extended successfully")
            recordExtendSuccess(at: date)
        } else {
            print("[*] sleep hold session extend failed")
            recordExtendFailure(at: date)
        }
    }

    private func cleanupStaleSleepHoldSession(_ sessionId: String) {
        terminateSleepHoldSession(
            sessionId,
            successMessage: "[*] cleaned up stale sleep hold session: \(sessionId)",
            failureMessage: "[*] failed to clean up stale sleep hold session: \(sessionId)"
        )
    }

    private func connectRetryDate(from date: Date) -> Date {
        date.addingTimeInterval(connectRetryInterval)
    }

    private func extendDate(from date: Date) -> Date {
        date.addingTimeInterval(extendInterval)
    }

    private func recordConnectedSession(_ sessionId: String, at date: Date) {
        sleepHoldServiceIdentifier = sessionId
        sleepHoldServiceLastUpdate = date
        nextExtendAt = extendDate(from: date)
    }

    private func recordExtendSuccess(at date: Date) {
        sleepHoldServiceLastUpdate = date
        nextExtendAt = extendDate(from: date)
    }

    private func recordExtendFailure(at date: Date) {
        sleepHoldServiceIdentifier = ""
        nextConnectAttemptAt = connectRetryDate(from: date)
    }

    private func clearLocalSessionState(at date: Date) {
        sleepHoldServiceIdentifier = ""
        isConnectInFlight = false
        isExtendInFlight = false
        nextConnectAttemptAt = .distantPast
        nextExtendAt = .distantPast
        sleepHoldServiceLastUpdate = date
    }

    private func terminateSleepHoldSession(
        _ sessionId: String,
        successMessage: String,
        failureMessage: String
    ) {
        sleepHoldClient.terminateSession(sessionId) { ok in
            print(ok ? successMessage : failureMessage)
        }
    }
}

struct SentryConfiguration: Codable, Equatable, Hashable {
    var sentryTriggersLidEnabled: Bool = false
    var sentryTriggersInternetEnabled: Bool = false
    var sentryTriggersPowerEnabled: Bool = false

    var sentryAlarmsSoundsEnabled: Bool = false

    var sentryAlarmsNotificationType: NotificationType = .none
    enum NotificationType: String, Codable, Equatable, Hashable {
        case none
        case bark
    }

    var sentryNotificationConfigBark: NotificationConfiguration_Bark = .init()
    struct NotificationConfiguration_Bark: Codable, Equatable, Hashable {
        var endpoint: String = "https://"
    }

    var sentryRecordingEnabled: Bool = false
    var sentryRecordingDevice: String? = nil
}
