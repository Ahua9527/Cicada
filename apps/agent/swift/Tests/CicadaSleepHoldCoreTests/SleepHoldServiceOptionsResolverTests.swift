import XCTest
@testable import CicadaSleepHoldCore

/// daemon 启动参数解析：CLI 旧 plist（三参数齐全）原样透传；
/// SMAppService 静态 plist（零参数）由 console 用户推导补齐。
final class SleepHoldServiceOptionsResolverTests: XCTestCase {
    private let consoleUser = SleepHoldOwnerInfo(uid: 501, gid: 20, homeDirectory: "/Users/dora-k")

    func testExplicitOptionsAreUsedAsIsWithoutTouchingConsoleUser() {
        var consoleQueried = false

        let resolved = SleepHoldServiceOptionsResolver.resolve(
            socketPath: "/custom/sleephold.sock",
            ownerUID: 501,
            ownerGID: 20
        ) {
            consoleQueried = true
            return nil // 即使 console 用户不可得，显式参数也必须可用
        }

        XCTAssertEqual(
            resolved,
            ResolvedSleepHoldServiceOptions(
                socketPath: "/custom/sleephold.sock",
                ownerUID: 501,
                ownerGID: 20,
                homeDirectory: nil
            )
        )
        XCTAssertFalse(consoleQueried)
    }

    func testZeroArgumentsResolveFromConsoleUser() {
        let resolved = SleepHoldServiceOptionsResolver.resolve(
            socketPath: nil,
            ownerUID: nil,
            ownerGID: nil
        ) { self.consoleUser }

        XCTAssertEqual(resolved?.socketPath, "/Users/dora-k/.cicada/run/sleephold.sock")
        XCTAssertEqual(resolved?.ownerUID, 501)
        XCTAssertEqual(resolved?.ownerGID, 20)
        XCTAssertEqual(resolved?.homeDirectory, "/Users/dora-k")
    }

    func testPartialOverridesKeepExplicitFieldsAndFillTheRest() {
        let resolved = SleepHoldServiceOptionsResolver.resolve(
            socketPath: "/custom/sleephold.sock",
            ownerUID: nil,
            ownerGID: nil
        ) { self.consoleUser }

        XCTAssertEqual(resolved?.socketPath, "/custom/sleephold.sock")
        XCTAssertEqual(resolved?.ownerUID, 501)
        XCTAssertEqual(resolved?.ownerGID, 20)
    }

    func testMissingFieldsWithNoConsoleUserReturnNilForRetry() {
        let resolved = SleepHoldServiceOptionsResolver.resolve(
            socketPath: nil,
            ownerUID: nil,
            ownerGID: nil
        ) { nil }

        XCTAssertNil(resolved)
    }

    func testDefaultSocketPathMatchesRuntimePathsContract() {
        XCTAssertEqual(
            SleepHoldServiceOptionsResolver.defaultSocketPath(homeDirectory: "/Users/x"),
            "/Users/x/.cicada/run/sleephold.sock"
        )
    }

    func testCurrentConsoleUserFiltersOutNonLoginSessions() {
        let fakeHome: (uid_t) -> String? = { _ in "/Users/whatever" }

        for name in ["loginwindow", "_mbsetupuser"] {
            XCTAssertNil(
                SleepHoldServiceOptionsResolver.currentConsoleUser(
                    consoleUserName: { outUID, outGID in
                        outUID.pointee = 501
                        outGID.pointee = 20
                        return name
                    },
                    homeDirectory: fakeHome
                ),
                name
            )
        }

        // root 会话同样不算真实用户
        XCTAssertNil(
            SleepHoldServiceOptionsResolver.currentConsoleUser(
                consoleUserName: { outUID, outGID in
                    outUID.pointee = 0
                    outGID.pointee = 0
                    return "root"
                },
                homeDirectory: fakeHome
            )
        )

        let real = SleepHoldServiceOptionsResolver.currentConsoleUser(
            consoleUserName: { outUID, outGID in
                outUID.pointee = 501
                outGID.pointee = 20
                return "dora-k"
            },
            homeDirectory: { $0 == 501 ? "/Users/dora-k" : nil }
        )
        XCTAssertEqual(real, consoleUser)
    }
}
