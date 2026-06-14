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

    func testSentinelAppPathCandidatesKeepLegacyFallback() {
        XCTAssertEqual(
            RuntimePaths.sentinelAppPathCandidates,
            [RuntimePaths.sentinelAppPath, RuntimePaths.legacySentinelAppPath]
        )
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
            RuntimePaths.daemonBinaryPath,
        ])

        let resolved = RuntimePaths.resolveDaemonSourceBinaryPath(
            currentDirectoryPath: "/repo/apps/agent",
            currentAppPath: "/tmp/Cicada.app",
            fileExists: { existing.contains($0) }
        )

        XCTAssertEqual(resolved, currentBundleHelper)
    }

    func testDaemonSourceResolutionPrefersInstalledBundleBeforeLegacyBundle() {
        let legacyBundleHelper = RuntimePaths.helperPath(
            name: RuntimePaths.daemonBinaryName,
            inApp: RuntimePaths.legacySentinelAppPath
        )
        let existing = Set([
            RuntimePaths.bundledDaemonHelperPath,
            legacyBundleHelper,
            RuntimePaths.daemonBinaryPath,
        ])

        let resolved = RuntimePaths.resolveDaemonSourceBinaryPath(
            currentDirectoryPath: "/repo/apps/agent",
            currentAppPath: nil,
            fileExists: { existing.contains($0) }
        )

        XCTAssertEqual(resolved, RuntimePaths.bundledDaemonHelperPath)
    }

    func testDaemonSourceResolutionFallsBackToLegacyBundleBeforeRuntimeBin() {
        let legacyBundleHelper = RuntimePaths.helperPath(
            name: RuntimePaths.daemonBinaryName,
            inApp: RuntimePaths.legacySentinelAppPath
        )
        let existing = Set([
            legacyBundleHelper,
            RuntimePaths.daemonBinaryPath,
        ])

        let resolved = RuntimePaths.resolveDaemonSourceBinaryPath(
            currentDirectoryPath: "/repo/apps/agent",
            currentAppPath: nil,
            fileExists: { existing.contains($0) }
        )

        XCTAssertEqual(resolved, legacyBundleHelper)
    }

    func testDaemonSourceResolutionFallsBackToRuntimeBin() {
        let resolved = RuntimePaths.resolveDaemonSourceBinaryPath(
            currentDirectoryPath: "/repo/apps/agent",
            currentAppPath: nil,
            fileExists: { $0 == RuntimePaths.daemonBinaryPath }
        )

        XCTAssertEqual(resolved, RuntimePaths.daemonBinaryPath)
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
        let existing = Set([
            RuntimePaths.bundledSleepHoldHelperPath,
            RuntimePaths.sleepHoldStagingBinaryPath,
            RuntimePaths.sleepHoldBinaryPath,
        ])

        let resolved = RuntimePaths.resolveSleepHoldSourceBinaryPath(
            currentDirectoryPath: "/repo/apps/agent",
            currentAppPath: nil,
            fileExists: { existing.contains($0) }
        )

        XCTAssertEqual(resolved, RuntimePaths.bundledSleepHoldHelperPath)
    }

    func testSleepHoldSourceResolutionFallsBackToLegacyBundleBeforeStagingBin() {
        let legacyBundleHelper = RuntimePaths.helperPath(
            name: RuntimePaths.sleepHoldBinaryName,
            inApp: RuntimePaths.legacySentinelAppPath
        )
        let existing = Set([
            legacyBundleHelper,
            RuntimePaths.sleepHoldStagingBinaryPath,
            RuntimePaths.sleepHoldBinaryPath,
        ])

        let resolved = RuntimePaths.resolveSleepHoldSourceBinaryPath(
            currentDirectoryPath: "/repo/apps/agent",
            currentAppPath: nil,
            fileExists: { existing.contains($0) }
        )

        XCTAssertEqual(resolved, legacyBundleHelper)
    }

    func testSleepHoldSourceResolutionFallsBackToStagingBin() {
        let resolved = RuntimePaths.resolveSleepHoldSourceBinaryPath(
            currentDirectoryPath: "/repo/apps/agent",
            currentAppPath: nil,
            fileExists: { $0 == RuntimePaths.sleepHoldStagingBinaryPath }
        )

        XCTAssertEqual(resolved, RuntimePaths.sleepHoldStagingBinaryPath)
    }
}
