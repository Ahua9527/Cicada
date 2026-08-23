import AppKit
import Darwin
import Foundation

enum ProcessLockAcquisition: Equatable {
    case acquired
    case contended
    case unavailable
}

final class SingleInstanceProcessLock {
    private var descriptor: Int32 = -1

    deinit {
        guard descriptor >= 0 else { return }
        flock(descriptor, LOCK_UN)
        close(descriptor)
    }

    func acquire(at path: String) -> ProcessLockAcquisition {
        guard descriptor < 0 else { return .acquired }

        do {
            try FileManager.default.createDirectory(
                at: URL(fileURLWithPath: path).deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        } catch {
            return .unavailable
        }

        let candidate = open(path, O_CREAT | O_RDWR | O_CLOEXEC, mode_t(0o600))
        guard candidate >= 0 else { return .unavailable }
        guard flock(candidate, LOCK_EX | LOCK_NB) == 0 else {
            let acquisition = errno == EWOULDBLOCK ? ProcessLockAcquisition.contended : .unavailable
            close(candidate)
            return acquisition
        }

        descriptor = candidate
        return .acquired
    }
}

enum SingleInstanceLaunchDecision: Equatable {
    case launch
    case activateExisting(pid_t)
    case replaceExisting([pid_t])
}

enum StartupRegistrationAction: Equatable {
    case none
    case disableLoginItem
}

enum StartupRegistrationPolicy {
    static func isManagedLaunch(environment: [String: String]) -> Bool {
        guard let socketPath = environment["CICADA_SENTINEL_SOCKET"] else { return false }
        return !socketPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func action(
        isRunningTests: Bool,
        environment: [String: String],
        isLoginItemEnabled: () -> Bool
    ) -> StartupRegistrationAction {
        guard !isRunningTests,
              isManagedLaunch(environment: environment),
              isLoginItemEnabled()
        else {
            return .none
        }
        return .disableLoginItem
    }
}

enum SingleInstanceLaunchPolicy {
    static func evaluate(
        currentProcessIdentifier: pid_t,
        isManagedLaunch: Bool,
        runningProcessIdentifiers: [pid_t]
    ) -> SingleInstanceLaunchDecision {
        let existingProcessIdentifiers = runningProcessIdentifiers
            .filter { $0 != currentProcessIdentifier }
            .sorted()
        guard let firstExistingProcessIdentifier = existingProcessIdentifiers.first else {
            return .launch
        }
        return isManagedLaunch
            ? .replaceExisting(existingProcessIdentifiers)
            : .activateExisting(firstExistingProcessIdentifier)
    }
}

enum SingleInstanceLaunchCoordinator {
    private static let processLock = SingleInstanceProcessLock()

    static func shouldLaunch(isManagedLaunch: Bool) -> Bool {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return true }

        let currentProcessIdentifier = getpid()
        let runningApplications = otherRunningApplications(
            bundleIdentifier: bundleIdentifier,
            currentProcessIdentifier: currentProcessIdentifier
        )
        let decision = SingleInstanceLaunchPolicy.evaluate(
            currentProcessIdentifier: currentProcessIdentifier,
            isManagedLaunch: isManagedLaunch,
            runningProcessIdentifiers: runningApplications.map(\.processIdentifier)
        )

        switch decision {
        case .launch:
            break
        case let .activateExisting(processIdentifier):
            runningApplications
                .first { $0.processIdentifier == processIdentifier }?
                .activate(options: [.activateIgnoringOtherApps])
            return false
        case let .replaceExisting(processIdentifiers):
            let duplicates = runningApplications.filter {
                processIdentifiers.contains($0.processIdentifier)
            }
            guard terminateAndWait(for: duplicates) else { return false }
        }

        let lockPath = CicadaSentinelPaths.sentinelSocketPath() + ".instance.lock"
        switch processLock.acquire(at: lockPath) {
        case .acquired, .unavailable:
            return true
        case .contended:
            return resolveLockContention(
                bundleIdentifier: bundleIdentifier,
                currentProcessIdentifier: currentProcessIdentifier,
                isManagedLaunch: isManagedLaunch,
                lockPath: lockPath
            )
        }
    }

    private static func resolveLockContention(
        bundleIdentifier: String,
        currentProcessIdentifier: pid_t,
        isManagedLaunch: Bool,
        lockPath: String
    ) -> Bool {
        let runningApplications = waitForOtherRunningApplications(
            bundleIdentifier: bundleIdentifier,
            currentProcessIdentifier: currentProcessIdentifier
        )
        guard isManagedLaunch else {
            runningApplications.first?.activate(options: [.activateIgnoringOtherApps])
            return false
        }
        guard !runningApplications.isEmpty,
              terminateAndWait(for: runningApplications)
        else {
            return false
        }
        return processLock.acquire(at: lockPath) == .acquired
    }

    private static func otherRunningApplications(
        bundleIdentifier: String,
        currentProcessIdentifier: pid_t
    ) -> [NSRunningApplication] {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
            .filter {
                $0.processIdentifier != currentProcessIdentifier && !$0.isTerminated
            }
    }

    private static func waitForOtherRunningApplications(
        bundleIdentifier: String,
        currentProcessIdentifier: pid_t,
        timeout: TimeInterval = 1
    ) -> [NSRunningApplication] {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            let applications = otherRunningApplications(
                bundleIdentifier: bundleIdentifier,
                currentProcessIdentifier: currentProcessIdentifier
            )
            if !applications.isEmpty {
                return applications
            }
            Thread.sleep(forTimeInterval: 0.05)
        } while Date() < deadline
        return []
    }

    private static func terminateAndWait(for applications: [NSRunningApplication]) -> Bool {
        let processIdentifiers = applications.map(\.processIdentifier)
        applications.forEach { $0.terminate() }
        if waitForTermination(of: processIdentifiers, timeout: 2) {
            return true
        }

        applications.filter { !$0.isTerminated }.forEach { $0.forceTerminate() }
        return waitForTermination(of: processIdentifiers, timeout: 1)
    }

    private static func waitForTermination(
        of processIdentifiers: [pid_t],
        timeout: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if processIdentifiers.allSatisfy({
                NSRunningApplication(processIdentifier: $0)?.isTerminated != false
            }) {
                return true
            }
            Thread.sleep(forTimeInterval: 0.05)
        } while Date() < deadline
        return processIdentifiers.allSatisfy {
            NSRunningApplication(processIdentifier: $0)?.isTerminated != false
        }
    }
}
