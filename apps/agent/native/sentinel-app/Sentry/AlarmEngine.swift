//
//  AlarmEngine.swift
//  Sentry
//
//  Created by 秋星桥 on 5/24/25.
//

import CoreAudioKit

enum AlarmEngine {
    static func defaultDevice() -> AudioDeviceID? {
        var deviceID: AudioDeviceID = kAudioObjectUnknown
        var address = AudioObjectPropertyAddress()
        address.mSelector = kAudioHardwarePropertyDefaultOutputDevice
        address.mScope = kAudioObjectPropertyScopeGlobal
        address.mElement = kAudioObjectPropertyElementMain

        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let error = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID)
        guard error == noErr else {
            print("[*] error getting default audio device: \(error)")
            return nil
        }
        return deviceID
    }

    static func defaultSpeakerDevice() -> AudioDeviceID {
        var aopa = AudioObjectPropertyAddress()
        aopa.mSelector = kAudioHardwarePropertyDevices
        aopa.mScope = kAudioObjectPropertyScopeGlobal
        aopa.mElement = kAudioObjectPropertyElementMain

        var propSize: UInt32 = 0
        var error = AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &aopa, 0, nil, &propSize)

        guard error == noErr else { return kAudioObjectUnknown }

        let deviceCount = Int(propSize) / MemoryLayout<AudioDeviceID>.size
        let audioDevices = UnsafeMutablePointer<AudioDeviceID>.allocate(capacity: deviceCount)
        defer { audioDevices.deallocate() }

        error = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &aopa, 0, nil, &propSize, audioDevices)
        guard error == noErr else { return kAudioObjectUnknown }

        for i in 0 ..< deviceCount {
            let deviceID = audioDevices[i]

            aopa.mSelector = kAudioDevicePropertyTransportType
            aopa.mScope = kAudioObjectPropertyScopeGlobal

            var size = UInt32(MemoryLayout<UInt32>.size)
            var transportType: UInt32 = 0

            error = AudioObjectGetPropertyData(deviceID, &aopa, 0, nil, &size, &transportType)

            guard error == noErr else { continue }
            guard transportType == kAudioDeviceTransportTypeBuiltIn else { continue }

            return deviceID
        }

        return kAudioObjectUnknown
    }

    static func readSystemVolume() -> Float? {
        var volume: Float32 = -1
        var size = UInt32(MemoryLayout.size(ofValue: volume))
        var address = AudioObjectPropertyAddress()
        address.mSelector = AudioObjectPropertySelector(kAudioHardwareServiceDeviceProperty_VirtualMainVolume)
        address.mScope = AudioObjectPropertyScope(kAudioDevicePropertyScopeOutput)
        address.mElement = AudioObjectPropertyElement(kAudioObjectPropertyElementMain)
        AudioObjectGetPropertyData(defaultSpeakerDevice(), &address, 0, nil, &size, &volume)
        guard volume >= 0, volume <= 1 else { return nil }
        return volume
    }

    static func setSystemVolume(_ volume: Float) {
        if volume > 0 {
            var muteVal = 0
            var address = AudioObjectPropertyAddress()
            address.mSelector = AudioObjectPropertySelector(kAudioDevicePropertyMute)
            let size = UInt32(MemoryLayout.size(ofValue: muteVal))
            address.mScope = AudioObjectPropertyScope(kAudioDevicePropertyScopeOutput)
            address.mElement = AudioObjectPropertyElement(kAudioObjectPropertyElementMain)
            AudioObjectSetPropertyData(defaultSpeakerDevice(), &address, 0, nil, size, &muteVal)
        }
        var volume = volume

        #if DEBUG
            if volume > 0.25 { volume = 0.25 }
        #endif

        let size = UInt32(MemoryLayout.size(ofValue: volume))
        var address = AudioObjectPropertyAddress()
        address.mScope = AudioObjectPropertyScope(kAudioDevicePropertyScopeOutput)
        address.mElement = AudioObjectPropertyElement(kAudioObjectPropertyElementMain)
        address.mSelector = AudioObjectPropertySelector(kAudioHardwareServiceDeviceProperty_VirtualMainVolume)
        AudioObjectSetPropertyData(defaultSpeakerDevice(), &address, 0, nil, size, &volume)
    }

    static func setOutputDevice() {}
}
