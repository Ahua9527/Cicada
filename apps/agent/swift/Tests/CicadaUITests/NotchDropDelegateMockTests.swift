import XCTest
@testable import CicadaUI

/// `NotchDropDelegate` 协议 conform 编译验证 + Mock 调用计数验证。
///
/// 本轮单测以「协议可 conform + 编译通过 + 方法被调用」为最低要求，
/// 深度交互测试（`.onDrop` 转发、`NSItemProvider` 模拟）留 P4 宿主联调。
final class NotchDropDelegateMockTests: XCTestCase {

    func testPreviewMockConformsToProtocol() {
        let mock = NotchDropDelegatePreviewMock()
        // 编译通过 + 可向上转型到协议存在类型，即证明 NotchDropDelegate 协议可被
        // ObservableObject 类 conform（无需运行时 'is' 始终为真的冗余断言）。
        let _: any NotchDropDelegate = mock
        let _: any ObservableObject = mock
        XCTAssertEqual(mock.loadTrayCallCount, 0)
    }

    func testLoadTrayIncrementsCount() {
        let mock = NotchDropDelegatePreviewMock()
        XCTAssertEqual(mock.loadTrayCallCount, 0)
        mock.loadTray(providers: [])
        XCTAssertEqual(mock.loadTrayCallCount, 1)
        mock.loadTray(providers: [])
        XCTAssertEqual(mock.loadTrayCallCount, 2)
    }

    func testClearTrayIncrementsCount() {
        let mock = NotchDropDelegatePreviewMock()
        mock.clearTray()
        XCTAssertEqual(mock.clearTrayCallCount, 1)
    }

    func testAirDropProvidersEntry() {
        let mock = NotchDropDelegatePreviewMock()
        mock.airDrop(providers: [])
        XCTAssertEqual(mock.airDropProvidersCallCount, 1)
        XCTAssertEqual(mock.airDropUrlsCallCount, 0)
    }

    func testAirDropUrlsEntry() {
        let mock = NotchDropDelegatePreviewMock()
        mock.airDrop(urls: [])
        XCTAssertEqual(mock.airDropUrlsCallCount, 1)
        XCTAssertEqual(mock.airDropProvidersCallCount, 0)
    }

    func testOpenTrayPicker() {
        let mock = NotchDropDelegatePreviewMock()
        mock.openTrayPicker()
        XCTAssertEqual(mock.openTrayPickerCallCount, 1)
    }

    func testClose() {
        let mock = NotchDropDelegatePreviewMock()
        mock.close()
        XCTAssertEqual(mock.closeCallCount, 1)
    }

    func testShowSettings() {
        let mock = NotchDropDelegatePreviewMock()
        mock.showSettings()
        XCTAssertEqual(mock.showSettingsCallCount, 1)
    }

    func testOpenGitHub() {
        let mock = NotchDropDelegatePreviewMock()
        mock.openGitHub()
        XCTAssertEqual(mock.openGitHubCallCount, 1)
    }

    func testOpenSponsor() {
        let mock = NotchDropDelegatePreviewMock()
        mock.openSponsor()
        XCTAssertEqual(mock.openSponsorCallCount, 1)
    }

    func testAllEightMethodsCovered() {
        // 验证协议 8 方法在 Mock 上均可调用且独立计数。
        let mock = NotchDropDelegatePreviewMock()
        mock.loadTray(providers: [])
        mock.clearTray()
        mock.airDrop(providers: [])
        mock.airDrop(urls: [])
        mock.openTrayPicker()
        mock.close()
        mock.showSettings()
        mock.openGitHub()
        mock.openSponsor()
        XCTAssertEqual(mock.loadTrayCallCount, 1)
        XCTAssertEqual(mock.clearTrayCallCount, 1)
        XCTAssertEqual(mock.airDropProvidersCallCount, 1)
        XCTAssertEqual(mock.airDropUrlsCallCount, 1)
        XCTAssertEqual(mock.openTrayPickerCallCount, 1)
        XCTAssertEqual(mock.closeCallCount, 1)
        XCTAssertEqual(mock.showSettingsCallCount, 1)
        XCTAssertEqual(mock.openGitHubCallCount, 1)
        XCTAssertEqual(mock.openSponsorCallCount, 1)
    }
}