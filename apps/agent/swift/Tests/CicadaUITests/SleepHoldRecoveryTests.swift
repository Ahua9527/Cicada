import XCTest
@testable import CicadaUI
import CicadaSleepHoldCore
import CicadaSystem

/// SleepHold 安装失败恢复：serviceInstalled / serviceResponding 双状态、
/// 安装诊断与轮询诊断分离（安装错误不被 3 秒轮询覆盖，恢复后自动清除）。
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

    func testInstallDiagnosticSurvivesPollingFailures() async {
        let model = SleepHoldModel(
            statusProvider: { throw SleepHoldControlError.unavailable("No such file or directory") },
            isInstalled: { true }
        )
        model.setInstallDiagnostic("授权已取消或超时")

        // 多次轮询失败不得覆盖具体安装错误。
        for _ in 0 ..< 3 {
            await model.refresh()
        }

        XCTAssertEqual(model.diagnostic?.message, "授权已取消或超时")
    }

    func testInstallDiagnosticClearsAfterRecovery() async {
        var reachable = false
        let model = SleepHoldModel(
            statusProvider: {
                if reachable {
                    return SleepHoldControlResponse(ok: true, status: .canSleep, activeSessions: 0)
                }
                throw SleepHoldControlError.unavailable("No such file or directory")
            },
            isInstalled: { true }
        )
        model.setInstallDiagnostic("安装失败：command failed")
        await model.refresh()
        XCTAssertEqual(model.diagnostic?.message, "安装失败：command failed")

        // 服务迟到恢复：refresh 成功后安装错误自动清除，修复入口隐藏。
        reachable = true
        await model.refresh()

        XCTAssertNil(model.diagnostic)
        XCTAssertNil(model.recoveryAction)
    }

    func testRetryStartClearsStaleInstallDiagnostic() async {
        let model = SleepHoldModel(
            statusProvider: { throw SleepHoldControlError.unavailable("No such file or directory") },
            isInstalled: { true }
        )
        model.setInstallDiagnostic("授权已取消或超时")
        XCTAssertEqual(model.diagnostic?.message, "授权已取消或超时")

        model.clearInstallDiagnostic()

        XCTAssertNil(model.diagnostic)
    }

    func testPollingDiagnosticShowsWhenNoInstallDiagnostic() async {
        let model = SleepHoldModel(
            statusProvider: { throw SleepHoldControlError.unavailable("No such file or directory") },
            isInstalled: { true }
        )

        await model.refresh()

        // 无安装诊断时展示轮询诊断（连接失败细节）。
        XCTAssertTrue(
            model.diagnostic?.message.hasSuffix("No such file or directory") == true,
            "\(String(describing: model.diagnostic))"
        )
    }
}
