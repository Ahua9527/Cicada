import CoreAudio
import Foundation

final class NativeAudioController: NativeAudioControlling {
    func toggleSystemMute() -> Result<Bool, NativeCommandError> {
        switch getMuted() {
        case let .failure(error):
            return .failure(error)
        case let .success(isMuted):
            let target = !isMuted
            switch setMuted(target) {
            case let .failure(error):
                return .failure(error)
            case .success:
                return .success(target)
            }
        }
    }

    func setMuted(_ muted: Bool) -> Result<Void, NativeCommandError> {
        withMuteProperty { deviceID, address in
            var raw: UInt32 = muted ? 1 : 0
            let status = AudioObjectSetPropertyData(
                deviceID,
                &address,
                0,
                nil,
                UInt32(MemoryLayout<UInt32>.size),
                &raw
            )
            guard status == noErr else {
                return .failure(.message("写入静音状态失败: \(describeStatus(status))"))
            }
            return .success(())
        }
    }

    func currentVolume() -> Result<Float, NativeCommandError> {
        withVolumeProperty { deviceID, address in
            var volume: Float = 0
            var size = UInt32(MemoryLayout<Float>.size)
            let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &volume)
            guard status == noErr else {
                return .failure(.message("读取音量失败: \(describeStatus(status))"))
            }
            return .success(volume)
        }
    }

    func setVolume(_ level: Float) -> Result<Float, NativeCommandError> {
        let clamped = max(0, min(1, level))
        let result: Result<Void, NativeCommandError> = withVolumeProperty { deviceID, address in
            var volume = clamped
            let status = AudioObjectSetPropertyData(
                deviceID,
                &address,
                0,
                nil,
                UInt32(MemoryLayout<Float>.size),
                &volume
            )
            guard status == noErr else {
                return .failure(.message("写入音量失败: \(describeStatus(status))"))
            }
            return .success(())
        }
        return result.map { clamped }
    }

    func adjustVolume(by delta: Float) -> Result<Float, NativeCommandError> {
        switch currentVolume() {
        case let .failure(error):
            return .failure(error)
        case let .success(current):
            return setVolume(current + delta)
        }
    }

    private func getMuted() -> Result<Bool, NativeCommandError> {
        withMuteProperty { deviceID, address in
            var raw: UInt32 = 0
            var size = UInt32(MemoryLayout<UInt32>.size)
            let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &raw)
            guard status == noErr else {
                return .failure(.message("读取静音状态失败: \(describeStatus(status))"))
            }
            return .success(raw != 0)
        }
    }

    private func withMuteProperty<T>(
        _ body: (AudioObjectID, inout AudioObjectPropertyAddress) -> Result<T, NativeCommandError>
    ) -> Result<T, NativeCommandError> {
        withDeviceProperty(selector: kAudioDevicePropertyMute, label: "静音", body)
    }

    private func withVolumeProperty<T>(
        _ body: (AudioObjectID, inout AudioObjectPropertyAddress) -> Result<T, NativeCommandError>
    ) -> Result<T, NativeCommandError> {
        withDeviceProperty(selector: kAudioDevicePropertyVolumeScalar, label: "音量", body)
    }

    private func withDeviceProperty<T>(
        selector: AudioObjectPropertySelector,
        label: String,
        _ body: (AudioObjectID, inout AudioObjectPropertyAddress) -> Result<T, NativeCommandError>
    ) -> Result<T, NativeCommandError> {
        switch defaultOutputDevice() {
        case let .failure(error):
            return .failure(error)
        case let .success(deviceID):
            var address = AudioObjectPropertyAddress(
                mSelector: selector,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain
            )
            guard AudioObjectHasProperty(deviceID, &address) else {
                return .failure(.message("当前输出设备不支持\(label)控制"))
            }
            return body(deviceID, &address)
        }
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
