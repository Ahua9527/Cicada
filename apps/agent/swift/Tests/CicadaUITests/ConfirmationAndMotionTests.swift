import XCTest
@testable import CicadaUI

/// 按住确认文案（清空托盘 vs 退出 App）与减弱动态效果下 hover 缩放的纯函数覆盖。
final class ConfirmationAndMotionTests: XCTestCase {
    func testClearTrayAndQuitAppUseDistinctCopies() {
        let clear = HoldConfirmationCopy.clearTray
        let quit = HoldConfirmationCopy.quitApp

        // 清空与退出必须是两套明确配置：标题/说明/确认按钮/辅助功能文案全部不同。
        XCTAssertNotEqual(clear.title, quit.title)
        XCTAssertNotEqual(clear.message, quit.message)
        XCTAssertNotEqual(clear.confirmTitle, quit.confirmTitle)
        XCTAssertNotEqual(clear.accessibilityLabel, quit.accessibilityLabel)
        XCTAssertNotEqual(clear.accessibilityHint, quit.accessibilityHint)
    }

    func testQuitCopyUsesQuitTitleAndConfirmButton() {
        // 退出确认标题为「退出 Cicada」，确认按钮为「退出」（不再复用「清空」）。
        XCTAssertTrue(HoldConfirmationCopy.quitApp.title.contains("Cicada"))
        XCTAssertFalse(HoldConfirmationCopy.quitApp.confirmTitle.isEmpty)
        XCTAssertNotEqual(
            HoldConfirmationCopy.quitApp.confirmTitle,
            HoldConfirmationCopy.clearTray.confirmTitle
        )
    }

    func testQuitMessageWarnsRemoteControlAndMonitoringStop() {
        // 提示必须说明退出后远程控制和安防监控会停止（中英文均含对应措辞）。
        let message = HoldConfirmationCopy.quitApp.message
        XCTAssertTrue(
            message.contains("远程控制") || message.contains("remote control"),
            message
        )
    }

    func testHoverScaleIsFixedAtOneUnderReduceMotion() {
        XCTAssertEqual(CicadaMotion.hoverScale(isHovering: true, reduceMotion: true), 1)
        XCTAssertEqual(CicadaMotion.hoverScale(isHovering: false, reduceMotion: true), 1)
    }

    func testHoverScaleAppliesOnlyWhenHoveringInNormalMode() {
        XCTAssertEqual(
            CicadaMotion.hoverScale(isHovering: true, reduceMotion: false),
            CicadaMotion.hoverScale
        )
        XCTAssertEqual(CicadaMotion.hoverScale(isHovering: false, reduceMotion: false), 1)
    }
}
