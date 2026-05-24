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
}

protocol NativePowerControlling: AnyObject {
    var noSleepAssertionActive: Bool { get }

    func sleepNow() -> Result<Void, NativeCommandError>
    func startNoSleepAssertion() -> Result<String, NativeCommandError>
    func stopNoSleepAssertion() -> Result<String, NativeCommandError>
    func batteryDescription() -> String?
}

protocol NativeDisplayControlling {
    func sleepDisplays() -> Result<Void, NativeCommandError>
}
