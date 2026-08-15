import XCTest
@testable import CicadaSystem

/// SleepHold 安装上下文：sudo/root 运行时必须还原真实登录用户，
/// 否则 daemon 会被配到 /var/root、socket 属主 root:root，App 永远连不上（真机复现）。
final class SleepHoldInstallContextTests: XCTestCase {
    private func homeLookup(_ uid: uid_t) -> String? { "/Users/u\(uid)" }

    func testNonRootProcessUsesItsOwnIdentity() throws {
        let context = try SleepHoldInstallContext.resolve(
            processUID: 501,
            processGID: 20,
            env: [:],
            homeForUID: homeLookup,
            consoleUser: { nil }
        )

        XCTAssertEqual(context.uid, 501)
        XCTAssertEqual(context.gid, 20)
        XCTAssertEqual(context.homeDirectory, "/Users/u501")
        XCTAssertEqual(context.socketPath, "/Users/u501/.cicada/run/sleephold.sock")
        XCTAssertEqual(context.stdoutPath, "/Users/u501/.cicada/sleephold.stdout.log")
        XCTAssertEqual(context.stderrPath, "/Users/u501/.cicada/sleephold.stderr.log")
    }

    func testRootWithSudoEnvRestoresInvokingUser() throws {
        let context = try SleepHoldInstallContext.resolve(
            processUID: 0,
            processGID: 0,
            env: ["SUDO_UID": "501", "SUDO_GID": "20"],
            homeForUID: homeLookup,
            consoleUser: { nil }
        )

        XCTAssertEqual(context.uid, 501)
        XCTAssertEqual(context.gid, 20)
        XCTAssertEqual(context.socketPath, "/Users/u501/.cicada/run/sleephold.sock")
    }

    func testRootWithoutSudoEnvFallsBackToConsoleUser() throws {
        // AppleScript 管理员授权提权场景：root 但无 SUDO_*，取当前图形会话用户。
        let context = try SleepHoldInstallContext.resolve(
            processUID: 0,
            processGID: 0,
            env: [:],
            homeForUID: homeLookup,
            consoleUser: { (501, 20) }
        )

        XCTAssertEqual(context.uid, 501)
        XCTAssertEqual(context.gid, 20)
        XCTAssertEqual(context.homeDirectory, "/Users/u501")
    }

    func testRootWithZeroSudoUIDDoesNotAcceptRoot() throws {
        // SUDO_UID=0（root 套 sudo）不得解析为 root 安装目标，继续走 console 兜底。
        let context = try SleepHoldInstallContext.resolve(
            processUID: 0,
            processGID: 0,
            env: ["SUDO_UID": "0", "SUDO_GID": "0"],
            homeForUID: homeLookup,
            consoleUser: { (502, 20) }
        )

        XCTAssertEqual(context.uid, 502)
    }

    func testRootWithoutAnyIdentitySourceThrowsActionableError() {
        XCTAssertThrowsError(
            try SleepHoldInstallContext.resolve(
                processUID: 0,
                processGID: 0,
                env: [:],
                homeForUID: homeLookup,
                consoleUser: { nil }
            )
        ) { error in
            XCTAssertTrue(
                String(describing: error).contains("去掉 sudo"),
                "错误应给出可执行指引: \(error)"
            )
        }
    }
}
