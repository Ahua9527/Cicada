import CicadaUI
import Foundation
import SwiftUI
import XCTest

@MainActor
final class CicadaUIPublicAPITests: XCTestCase {
    func testHostFacingAPICanBeUsedWithoutTestableImport() async {
        let alarmDelegate = HostAlarmDelegate()
        let appModel = AppModel()
        appModel.alarm.delegate = alarmDelegate
        appModel.alarm.activate(reason: "test alarm")

        XCTAssertTrue(appModel.alarm.isActive)
        XCTAssertEqual(appModel.alarm.reason, "test alarm")

        let startPolling: () -> Void = appModel.startPolling
        let stopPolling: () -> Void = appModel.stopPolling
        _ = startPolling
        _ = stopPolling

        _ = AlarmOverlayContent(reason: appModel.alarm.reason) {}

        let notchDelegate = HostNotchDropDelegate()
        _ = NotchPanel(delegate: notchDelegate)
        _ = NotchMenu(delegate: notchDelegate)

        await appModel.alarm.stop()

        XCTAssertFalse(appModel.alarm.isActive)
        XCTAssertEqual(appModel.alarm.reason, "")
        XCTAssertEqual(alarmDelegate.stopCallCount, 1)
    }
}

@MainActor
private final class HostAlarmDelegate: AlarmEngineDelegate {
    private(set) var stopCallCount = 0

    func alarmDidStop() async {
        stopCallCount += 1
    }
}

private final class HostNotchDropDelegate: ObservableObject, NotchDropDelegate {
    func loadTray(providers _: [NSItemProvider]) {}
    func clearTray() {}
    func airDrop(providers _: [NSItemProvider]) {}
    func airDrop(urls _: [URL]) {}
    func openTrayPicker() {}
    func close() {}
    func showSettings() {}
    func openGitHub() {}
    func openSponsor() {}
}
