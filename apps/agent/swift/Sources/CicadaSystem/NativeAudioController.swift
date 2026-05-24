import CoreAudio
import Foundation

final class NativeAudioController: NativeAudioControlling {
    func toggleSystemMute() -> Result<Bool, NativeCommandError> {
        let deviceResult = defaultOutputDevice()
        guard case let .success(deviceID) = deviceResult else {
            if case let .failure(error) = deviceResult {
                return .failure(error)
            }
            return .failure(.message("无法获取默认输出设备"))
        }

        var muteAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        guard AudioObjectHasProperty(deviceID, &muteAddress) else {
            return .failure(.message("当前输出设备不支持静音切换"))
        }

        var muteRaw: UInt32 = 0
        var muteSize = UInt32(MemoryLayout<UInt32>.size)
        let readStatus = AudioObjectGetPropertyData(
            deviceID,
            &muteAddress,
            0,
            nil,
            &muteSize,
            &muteRaw
        )
        guard readStatus == noErr else {
            return .failure(.message("读取静音状态失败: \(describeStatus(readStatus))"))
        }

        let targetMuted = muteRaw == 0
        var targetRaw: UInt32 = targetMuted ? 1 : 0
        let writeStatus = AudioObjectSetPropertyData(
            deviceID,
            &muteAddress,
            0,
            nil,
            muteSize,
            &targetRaw
        )
        guard writeStatus == noErr else {
            return .failure(.message("写入静音状态失败: \(describeStatus(writeStatus))"))
        }

        return .success(targetMuted)
    }

    private func defaultOutputDevice() -> Result<AudioObjectID, NativeCommandError> {
        var deviceID = AudioObjectID(0)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        )
        guard status == noErr else {
            return .failure(.message("获取默认输出设备失败: \(describeStatus(status))"))
        }

        guard deviceID != AudioObjectID(kAudioObjectUnknown) else {
            return .failure(.message("系统未返回可用输出设备"))
        }

        return .success(deviceID)
    }

    private func describeStatus(_ status: OSStatus) -> String {
        String(format: "OSStatus(%d)", status)
    }
}
