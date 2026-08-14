import Foundation

enum NativeCommandError: Error {
    case message(String)

    var message: String {
        switch self {
        case let .message(text):
            return text
        }
    }
}

protocol NativeLockControlling {
    func lockScreen() -> Result<Void, NativeCommandError>
    func isAccessibilityTrusted() -> Bool
}

protocol NativeBluetoothControlling {
    func powerState() -> Result<Bool, NativeCommandError>
    func setPowerState(_ enabled: Bool) -> Result<Bool, NativeCommandError>
}

protocol NativeAudioControlling {
    func toggleSystemMute() -> Result<Bool, NativeCommandError>
    func setMuted(_ muted: Bool) -> Result<Void, NativeCommandError>
    func setVolume(_ level: Float) -> Result<Float, NativeCommandError>
    func adjustVolume(by delta: Float) -> Result<Float, NativeCommandError>
    func currentVolume() -> Result<Float, NativeCommandError>
}

protocol NativePowerControlling: AnyObject {
    var noSleepAssertionActive: Bool { get }

    func sleepNow() -> Result<Void, NativeCommandError>
    func restartSystem() -> Result<Void, NativeCommandError>
    func shutdownSystem() -> Result<Void, NativeCommandError>
    func startNoSleepAssertion() -> Result<String, NativeCommandError>
    func stopNoSleepAssertion() -> Result<String, NativeCommandError>
    func batteryDescription() -> String?
}

protocol NativeDisplayControlling {
    func sleepDisplays() -> Result<Void, NativeCommandError>
    func wakeDisplays() -> Result<Void, NativeCommandError>
    func setBrightness(_ level: Float) -> Result<Float, NativeCommandError>
    func adjustBrightness(by delta: Float) -> Result<Float, NativeCommandError>
    func captureScreen(to directory: String) -> Result<String, NativeCommandError>
}

protocol NativeAppControlling {
    func openApplication(named name: String) -> Result<Void, NativeCommandError>
    func closeApplication(named name: String) -> Result<Void, NativeCommandError>
    func switchToApplication(named name: String) -> Result<Void, NativeCommandError>
    func listRunningApplications() -> [String]
}
