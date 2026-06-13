import XCTest
@testable import CicadaCore

final class RuntimePathsTests: XCTestCase {
    func testHelperPathBuildsBundleHelperPath() {
        XCTAssertEqual(
            RuntimePaths.helperPath(name: RuntimePaths.cliBinaryName, inApp: "/tmp/Sentry.app"),
            "/tmp/Sentry.app/Contents/Helpers/cicada"
        )
    }

    func testCurrentSentryAppPathUsesBundlePathWhenAvailable() {
        let path = RuntimePaths.currentSentryAppPath(
            executablePath: "/tmp/ignored",
            bundlePath: "/tmp/Sentry.app",
            currentDirectoryPath: "/tmp"
        )

        XCTAssertEqual(path, "/tmp/Sentry.app")
    }

    func testCurrentSentryAppPathDerivesFromExecutableInsideAppBundle() {
        let path = RuntimePaths.currentSentryAppPath(
            executablePath: "/tmp/Sentry.app/Contents/Helpers/cicada",
            bundlePath: "/tmp/cicada",
            currentDirectoryPath: "/tmp"
        )

        XCTAssertEqual(path, "/tmp/Sentry.app")
    }

    func testDaemonSourceResolutionPrefersExplicitPath() {
        let explicit = "/custom/cicada-agent"

        let resolved = RuntimePaths.resolveDaemonSourceBinaryPath(
            explicitPath: explicit,
            currentDirectoryPath: "/repo/apps/agent",
            currentAppPath: "/tmp/Sentry.app",
            fileExists: { _ in false }
        )

        XCTAssertEqual(resolved, explicit)
    }

    func testDaemonSourceResolutionPrefersCurrentBundleHelper() {
        let currentBundleHelper = "/tmp/Sentry.app/Contents/Helpers/cicada-agent"
        let existing = Set([
            currentBundleHelper,
            RuntimePaths.bundledDaemonHelperPath,
            RuntimePaths.daemonBinaryPath,
        ])

        let resolved = RuntimePaths.resolveDaemonSourceBinaryPath(
            currentDirectoryPath: "/repo/apps/agent",
            currentAppPath: "/tmp/Sentry.app",
            fileExists: { existing.contains($0) }
        )

        XCTAssertEqual(resolved, currentBundleHelper)
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
        let currentBundleHelper = "/tmp/Sentry.app/Contents/Helpers/cicada-sleephold"
        let existing = Set([
            currentBundleHelper,
            RuntimePaths.bundledSleepHoldHelperPath,
            RuntimePaths.sleepHoldStagingBinaryPath,
        ])

        let resolved = RuntimePaths.resolveSleepHoldSourceBinaryPath(
            currentDirectoryPath: "/repo/apps/agent",
            currentAppPath: "/tmp/Sentry.app",
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

    func testSleepHoldSourceResolutionFallsBackToStagingBin() {
        let resolved = RuntimePaths.resolveSleepHoldSourceBinaryPath(
            currentDirectoryPath: "/repo/apps/agent",
            currentAppPath: nil,
            fileExists: { $0 == RuntimePaths.sleepHoldStagingBinaryPath }
        )

        XCTAssertEqual(resolved, RuntimePaths.sleepHoldStagingBinaryPath)
    }
}
