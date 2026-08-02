//
//  AppDelegate.swift
//  Sentry
//
//  Created by 秋星桥 on 5/24/25.
//

import Cocoa
import CicadaUI
import CoreAudio
import Foundation
import IOKit
import IOKit.pwr_mgt
import LaunchAtLogin
import SwiftUI

@MainActor
final class AppDelegate: NSObject, ObservableObject, NSApplicationDelegate {
    private var sleepAssertionID: IOPMAssertionID = 0
    private var displayAssertionID: IOPMAssertionID = 0
    private let startupCheckProvider: StartupCheckProviding
    private let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

    @Published private(set) var startupDiagnostics: [StartupDiagnostic] = []

    override init() {
        startupCheckProvider = DeviceStartupCheckProvider()
        super.init()
        print("[*] AppDelegate initialized")
    }

    init(startupCheckProvider: StartupCheckProviding) {
        self.startupCheckProvider = startupCheckProvider
        super.init()
        print("[*] AppDelegate initialized")
    }

    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        false
    }

    func applicationDidFinishLaunching(_: Notification) {
        NSApp.setActivationPolicy(.accessory)
        startupDiagnostics = PendingStartupDiagnostics.consume()
        // ⭐ P4 新增：启动 AppModel 3s 轮询（sentinels / sleepHold）
        AppModel.shared.startPolling()
        // ⭐ P4.2 迁移：1s 状态机驱动接线，从旧 ContentView.onAppear 迁到 AppDelegate，
        // 一次性接线、全程生效（与 3s 轮询是两条独立链路：1s 驱动 lock 状态机，3s 拉 IPC 快照）。
        ViewModel.shared.setTimerCallback { SentinelController.shared.handleTimerTick() }
        guard !isRunningTests else { return }
        NotchDropCoordinator.shared.start(openInitialWindow: !LaunchAtLogin.wasLaunchedAtLogin)
        SentinelIPCServer.shared.start()
        SentinelNotifierServer.shared.start()
        runStartupChecks()
    }

    func applicationWillTerminate(_: Notification) {
        // ⭐ P4 新增：停止 AppModel 轮询
        AppModel.shared.stopPolling()
        SentinelNotifierServer.shared.stop()
        SentinelIPCServer.shared.stop()
        NotchDropCoordinator.shared.stop()
        SentryConfigurationManager.shared.disconnectFromSleepHold()
    }

    private func preventSleep() {
        createAssertion(
            type: kIOPMAssertionTypeNoIdleSleep,
            name: "Cicada app is monitoring system",
            storedIn: &sleepAssertionID,
            logPrefix: "failed to create sleep assertion",
            diagnosticID: "sleep-assertion"
        )
    }

    private func allowSleep() {
        releaseAssertion(&sleepAssertionID)
    }

    private func preventDisplaySleep() {
        createAssertion(
            type: kIOPMAssertionTypeNoDisplaySleep,
            name: "Cicada app is monitoring display",
            storedIn: &displayAssertionID,
            logPrefix: "failed to create display assertion",
            diagnosticID: "display-assertion"
        )
    }

    private func allowDisplaySleep() {
        releaseAssertion(&displayAssertionID)
    }

    func runStartupChecks() {
        let snapshot = startupCheckProvider.snapshot()
        logStartupSnapshot(snapshot)
        StartupDiagnosticsEvaluator.evaluate(snapshot).forEach(recordStartupDiagnostic)
    }

    private func recordStartupDiagnostic(_ diagnostic: StartupDiagnostic) {
        guard !startupDiagnostics.contains(where: { $0.id == diagnostic.id }) else { return }
        startupDiagnostics.append(diagnostic)
    }

    private func recordAssertionFailure(
        _ result: IOReturn,
        logPrefix: String,
        diagnosticID: String
    ) {
        guard result != kIOReturnSuccess else { return }
        print("[*] \(logPrefix): \(result)")
        recordStartupDiagnostic(.startupFailure(id: diagnosticID))
    }

    private func createAssertion(
        type: String,
        name: String,
        storedIn assertionID: inout IOPMAssertionID,
        logPrefix: String,
        diagnosticID: String
    ) {
        let result = IOPMAssertionCreateWithName(
            type as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            name as CFString,
            &assertionID
        )
        recordAssertionFailure(
            result,
            logPrefix: logPrefix,
            diagnosticID: diagnosticID
        )
    }

    private func releaseAssertion(_ assertionID: inout IOPMAssertionID) {
        guard assertionID != 0 else { return }
        IOPMAssertionRelease(assertionID)
        assertionID = 0
    }

    private func logStartupSnapshot(_ snapshot: StartupCheckSnapshot) {
        logOptionalStartupValue(snapshot.clamshellClosed, success: "device check reporting clamshell closed", failure: "failed to get clamshell state")
        logOptionalStartupValue(snapshot.screenLocked, success: "device check reporting screen locked", failure: "failed to get screen lock state")
        logStartupValue(snapshot.wifiConnected, prefix: "device check reporting wifi connected")
        logStartupValue(snapshot.powerConnected, prefix: "device check reporting power connected")
        logOptionalStartupValue(snapshot.batteryLevel, success: "device check reporting battery level", failure: "failed to get battery level")
        if !snapshot.hasDefaultSpeaker {
            print("[*] no default speaker device found")
        }
        logStartupValue(snapshot.systemVolume?.description ?? "???", prefix: "current system volume")
    }

    private func logStartupValue<T>(_ value: T, prefix: String) {
        print("[*] \(prefix): \(value)")
    }

    private func logOptionalStartupValue<T>(
        _ value: T?,
        success: String,
        failure: String
    ) {
        guard let value else {
            print("[*] \(failure)")
            return
        }
        logStartupValue(value, prefix: success)
    }
}
