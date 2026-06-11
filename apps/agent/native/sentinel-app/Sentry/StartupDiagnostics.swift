import CoreAudio
import Foundation

struct StartupDiagnostic: Identifiable, Equatable, Hashable {
    let id: String
    let message: String
}

extension StartupDiagnostic {
    private static let genericStartupFailureMessage = String(localized: "Unable to configure Sentry. Please try again later.")

    private static func make(id: String, message: String) -> Self {
        .init(id: id, message: message)
    }

    static var sandboxDisabledLocalBuild: Self {
        make(
            id: "sandbox-disabled-local-build",
            message: String(localized: "Sentry is running outside of the App Sandbox in a local debug or unsigned build. Permissions, file access, and release behavior may differ from the signed app.")
        )
    }

    static var sandboxDisabledDebug: Self {
        sandboxDisabledLocalBuild
    }

    static func startupFailure(id: String) -> Self {
        make(id: id, message: genericStartupFailureMessage)
    }

    static var defaultSpeakerUnavailable: Self {
        make(
            id: "default-speaker",
            message: String(localized: "Unable to locate default speaker device. Please ensure your audio output is configured correctly.")
        )
    }
}

enum StartupLaunchDecision: Equatable {
    case allow
    case allowWithDiagnostics([StartupDiagnostic])
    case block(String)
}

enum StartupLaunchPolicy {
    private static let sandboxRequiredMessage = "This app should not run outside of sandbox which may cause trouble."

    static func evaluate(
        isRunningTests: Bool,
        isDebugBuild: Bool,
        isSandboxEnabled: Bool,
        allowsLocalUnsignedLaunch: Bool = false
    ) -> StartupLaunchDecision {
        guard !isRunningTests else { return .allow }
        guard !isSandboxEnabled else { return .allow }
        guard isDebugBuild || allowsLocalUnsignedLaunch else {
            return .block(sandboxRequiredMessage)
        }
        return .allowWithDiagnostics([.sandboxDisabledLocalBuild])
    }
}

enum PendingStartupDiagnostics {
    private static let lock = NSLock()
    private static var diagnostics: [StartupDiagnostic] = []

    static func publish(_ newDiagnostics: [StartupDiagnostic]) {
        guard !newDiagnostics.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        for diagnostic in newDiagnostics {
            appendIfNeeded(diagnostic)
        }
    }

    static func consume() -> [StartupDiagnostic] {
        lock.lock()
        defer { lock.unlock() }
        let pending = diagnostics
        diagnostics.removeAll()
        return pending
    }

    private static func appendIfNeeded(_ diagnostic: StartupDiagnostic) {
        guard !diagnostics.contains(where: { $0.id == diagnostic.id }) else { return }
        diagnostics.append(diagnostic)
    }
}

struct SandboxEnvironmentProbe {
    var fileManager: FileManager = .default
    var temporaryDirectory: URL = URL(fileURLWithPath: "/tmp", isDirectory: true)

    func isSandboxEnabled() -> Bool {
        let probeURL = temporaryDirectory.appendingPathComponent("sandbox.test.\(UUID().uuidString)")
        _ = fileManager.createFile(atPath: probeURL.path, contents: nil, attributes: nil)
        defer {
            try? fileManager.removeItem(at: probeURL)
        }
        return !fileManager.fileExists(atPath: probeURL.path)
    }
}

struct StartupCheckSnapshot {
    let clamshellClosed: Bool?
    let screenLocked: Bool?
    let wifiConnected: Bool
    let powerConnected: Bool
    let batteryLevel: Int?
    let hasDefaultSpeaker: Bool
    let systemVolume: Float?
}

protocol StartupCheckProviding {
    func snapshot() -> StartupCheckSnapshot
}

struct DeviceStartupCheckProvider: StartupCheckProviding {
    func snapshot() -> StartupCheckSnapshot {
        .init(
            clamshellClosed: DeviceCheck.isMacLidClosed(),
            screenLocked: DeviceCheck.isMacLocked(),
            wifiConnected: DeviceCheck.isConnectedToWirelessNetwork(),
            powerConnected: DeviceCheck.isConnectedToPower(),
            batteryLevel: DeviceCheck.getBatteryLevel(),
            hasDefaultSpeaker: AlarmEngine.defaultSpeakerDevice() != kAudioDeviceUnknown,
            systemVolume: AlarmEngine.readSystemVolume()
        )
    }
}

enum StartupDiagnosticsEvaluator {
    static func evaluate(_ snapshot: StartupCheckSnapshot) -> [StartupDiagnostic] {
        var diagnostics: [StartupDiagnostic] = []

        appendFailureIfNil(snapshot.clamshellClosed, id: "clamshell-state", to: &diagnostics)
        appendFailureIfNil(snapshot.screenLocked, id: "screen-lock-state", to: &diagnostics)
        appendFailureIfNil(snapshot.batteryLevel, id: "battery-level", to: &diagnostics)

        if !snapshot.hasDefaultSpeaker {
            diagnostics.append(.defaultSpeakerUnavailable)
        }

        return diagnostics
    }

    private static func appendFailureIfNil<T>(
        _ value: T?,
        id: String,
        to diagnostics: inout [StartupDiagnostic]
    ) {
        guard value == nil else { return }
        diagnostics.append(.startupFailure(id: id))
    }
}
