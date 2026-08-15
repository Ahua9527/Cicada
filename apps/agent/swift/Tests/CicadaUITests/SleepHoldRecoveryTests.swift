import XCTest
@testable import CicadaUI
import CicadaSleepHoldCore
import CicadaSystem

/// SleepHold 安装失败恢复入口：serviceInstalled / serviceResponding 双状态
/// 驱动维护页「手动安装指引」的展示与隐藏（安装本身走终端命令，见 issue #9）。
@MainActor
final class SleepHoldRecoveryTests: XCTestCase {
    func testNotInstalledShowsInstallAction() async {
        let model = SleepHoldModel(
            statusProvider: { throw SleepHoldControlError.unavailable("should not be called") },
            isInstalled: { false }
        )

        await model.refresh()

        XCTAssertFalse(model.serviceInstalled)
        XCTAssertFalse(model.serviceResponding)
        XCTAssertEqual(model.recoveryAction, .install)
    }

    func testInstalledButNotRespondingShowsReinstallAction() async {
        // 部分安装：plist 存在但服务无响应 → 显示「重新安装…」。
        let model = SleepHoldModel(
            statusProvider: { throw SleepHoldControlError.unavailable("No such file or directory") },
            isInstalled: { true }
        )

        await model.refresh()

        XCTAssertTrue(model.serviceInstalled)
        XCTAssertFalse(model.serviceResponding)
        XCTAssertEqual(model.recoveryAction, .reinstall)
    }

    func testInstalledRejectedResponseShowsReinstallAction() async {
        // plist 存在、socket 可连但服务返回 ok=false，同样视为无响应。
        let model = SleepHoldModel(
            statusProvider: { SleepHoldControlResponse(ok: false, error: "service unavailable") },
            isInstalled: { true }
        )

        await model.refresh()

        XCTAssertTrue(model.serviceInstalled)
        XCTAssertFalse(model.serviceResponding)
        XCTAssertEqual(model.recoveryAction, .reinstall)
    }

    func testHealthyServiceHidesRecoveryAction() async {
        let model = SleepHoldModel(
            statusProvider: { SleepHoldControlResponse(ok: true, status: .canSleep, activeSessions: 0) },
            isInstalled: { true }
        )

        await model.refresh()

        XCTAssertTrue(model.serviceInstalled)
        XCTAssertTrue(model.serviceResponding)
        XCTAssertNil(model.recoveryAction)
    }

    func testPollingDiagnosticShowsConnectionFailureDetail() async {
        let model = SleepHoldModel(
            statusProvider: { throw SleepHoldControlError.unavailable("No such file or directory") },
            isInstalled: { true }
        )

        await model.refresh()

        // 连接失败的轮询诊断给出可读细节，不泄露内部错误类型名。
        XCTAssertTrue(
            model.diagnostic?.message.hasSuffix("No such file or directory") == true,
            "\(String(describing: model.diagnostic))"
        )
    }
}
