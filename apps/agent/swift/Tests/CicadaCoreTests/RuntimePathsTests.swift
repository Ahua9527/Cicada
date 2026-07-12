import XCTest
@testable import CicadaCore

final class RuntimePathsTests: XCTestCase {
    func testHelperPathBuildsBundleHelperPath() {
        XCTAssertEqual(
            RuntimePaths.helperPath(name: RuntimePaths.cliBinaryName, inApp: "/tmp/Cicada.app"),
            "/tmp/Cicada.app/Contents/Helpers/cicada"
        )
    }

    func testCurrentSentryAppPathUsesBundlePathWhenAvailable() {
        let path = RuntimePaths.currentSentryAppPath(
            executablePath: "/tmp/ignored",
            bundlePath: "/tmp/Cicada.app",
            currentDirectoryPath: "/tmp"
        )

        XCTAssertEqual(path, "/tmp/Cicada.app")
    }

    func testCurrentSentryAppPathDerivesFromExecutableInsideAppBundle() {
        let path = RuntimePaths.currentSentryAppPath(
            executablePath: "/tmp/Cicada.app/Contents/Helpers/cicada",
            bundlePath: "/tmp/cicada",
            currentDirectoryPath: "/tmp"
        )

        XCTAssertEqual(path, "/tmp/Cicada.app")
    }

    func testDaemonSourceResolutionPrefersExplicitPath() {
        let explicit = "/custom/cicada-agent"

        let resolved = RuntimePaths.resolveDaemonSourceBinaryPath(
            explicitPath: explicit,
            currentDirectoryPath: "/repo/apps/agent",
            currentAppPath: "/tmp/Cicada.app",
            fileExists: { _ in false }
        )

        XCTAssertEqual(resolved, explicit)
    }

    func testDaemonSourceResolutionPrefersCurrentBundleHelper() {
        let currentBundleHelper = "/tmp/Cicada.app/Contents/Helpers/cicada-agent"
        let existing = Set([
            currentBundleHelper,
            RuntimePaths.bundledDaemonHelperPath,
        ])

        let resolved = RuntimePaths.resolveDaemonSourceBinaryPath(
            currentDirectoryPath: "/repo/apps/agent",
            currentAppPath: "/tmp/Cicada.app",
            fileExists: { existing.contains($0) }
        )

        XCTAssertEqual(resolved, currentBundleHelper)
    }

    func testDaemonSourceResolutionPrefersInstalledBundleBeforeSwiftBuild() {
        let swiftBuildHelper = "/repo/apps/agent/swift/.build/release/cicada-agent"
        let existing = Set([
            RuntimePaths.bundledDaemonHelperPath,
            swiftBuildHelper,
        ])

        let resolved = RuntimePaths.resolveDaemonSourceBinaryPath(
            currentDirectoryPath: "/repo/apps/agent",
            currentAppPath: nil,
            fileExists: { existing.contains($0) }
        )

        XCTAssertEqual(resolved, RuntimePaths.bundledDaemonHelperPath)
    }

    func testDaemonSourceResolutionDoesNotUseLegacyBundleAsSource() {
        let legacyBundleHelper = RuntimePaths.helperPath(
            name: RuntimePaths.daemonBinaryName,
            inApp: RuntimePaths.legacySentinelAppPath
        )

        let resolved = RuntimePaths.resolveDaemonSourceBinaryPath(
            currentDirectoryPath: "/repo/apps/agent",
            currentAppPath: nil,
            fileExists: { $0 == legacyBundleHelper }
        )

        XCTAssertEqual(resolved, RuntimePaths.bundledDaemonHelperPath)
    }

    func testDaemonSourceResolutionFallsBackToSwiftBuild() {
        let swiftBuildHelper = "/repo/apps/agent/swift/.build/release/cicada-agent"
        let resolved = RuntimePaths.resolveDaemonSourceBinaryPath(
            currentDirectoryPath: "/repo/apps/agent",
            currentAppPath: nil,
            fileExists: { $0 == swiftBuildHelper }
        )

        XCTAssertEqual(resolved, swiftBuildHelper)
    }

    func testSleepHoldSourceResolutionPrefersCurrentBundleHelper() {
        let currentBundleHelper = "/tmp/Cicada.app/Contents/Helpers/cicada-sleephold"
        let existing = Set([
            currentBundleHelper,
            RuntimePaths.bundledSleepHoldHelperPath,
            RuntimePaths.sleepHoldStagingBinaryPath,
        ])

        let resolved = RuntimePaths.resolveSleepHoldSourceBinaryPath(
            currentDirectoryPath: "/repo/apps/agent",
            currentAppPath: "/tmp/Cicada.app",
            fileExists: { existing.contains($0) }
        )

        XCTAssertEqual(resolved, currentBundleHelper)
    }

    func testSleepHoldSourceResolutionPrefersInstalledBundleHelper() {
        let swiftBuildHelper = "/repo/apps/agent/swift/.build/release/cicada-sleephold"
        let existing = Set([
            RuntimePaths.bundledSleepHoldHelperPath,
            swiftBuildHelper,
        ])

        let resolved = RuntimePaths.resolveSleepHoldSourceBinaryPath(
            currentDirectoryPath: "/repo/apps/agent",
            currentAppPath: nil,
            fileExists: { existing.contains($0) }
        )

        XCTAssertEqual(resolved, RuntimePaths.bundledSleepHoldHelperPath)
    }

    func testSleepHoldSourceResolutionDoesNotUseLegacyBundleAsSource() {
        let legacyBundleHelper = RuntimePaths.helperPath(
            name: RuntimePaths.sleepHoldBinaryName,
            inApp: RuntimePaths.legacySentinelAppPath
        )

        let resolved = RuntimePaths.resolveSleepHoldSourceBinaryPath(
            currentDirectoryPath: "/repo/apps/agent",
            currentAppPath: nil,
            fileExists: { $0 == legacyBundleHelper }
        )

        XCTAssertEqual(resolved, RuntimePaths.bundledSleepHoldHelperPath)
    }

    func testSleepHoldSourceResolutionFallsBackToSwiftBuild() {
        let swiftBuildHelper = "/repo/apps/agent/swift/.build/release/cicada-sleephold"
        let resolved = RuntimePaths.resolveSleepHoldSourceBinaryPath(
            currentDirectoryPath: "/repo/apps/agent",
            currentAppPath: nil,
            fileExists: { $0 == swiftBuildHelper }
        )

        XCTAssertEqual(resolved, swiftBuildHelper)
    }
}
