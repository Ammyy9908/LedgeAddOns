import CoreAudio
import Foundation

/// A sound device: speakers, headphones, a microphone, or one device that's several of those.
struct AudioDevice: Equatable {
    let object: AudioObjectID
    let uid: String
    let name: String
    let output: Bool
    let input: Bool
}

enum Devices {
    /// Every device on this Mac, Ledge's own private ones left out.
    static func all() -> [AudioDevice] {
        let system = AudioObjectID(kAudioObjectSystemObject)
        var address = address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var objects = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &objects) == noErr else { return [] }
        return objects.compactMap { object in
            guard let uid = string(kAudioDevicePropertyDeviceUID, of: object),
                  let name = string(kAudioObjectPropertyName, of: object), !name.hasPrefix("Ledge") else { return nil }
            let device = AudioDevice(object: object, uid: uid, name: name,
                                     output: hasStreams(object, kAudioObjectPropertyScopeOutput),
                                     input: hasStreams(object, kAudioObjectPropertyScopeInput))
            return device.output || device.input ? device : nil
        }
    }

    static func defaultOutput() -> AudioObjectID? {
        var device = AudioObjectID(0)
        var address = address(kAudioHardwarePropertyDefaultOutputDevice)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr,
              device != 0 else { return nil }
        return device
    }

    /// Makes `device` the Mac's output, as choosing it in Control Center does.
    static func setDefaultOutput(_ device: AudioObjectID) {
        var value = device
        var address = address(kAudioHardwarePropertyDefaultOutputDevice)
        AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil,
                                   UInt32(MemoryLayout<AudioObjectID>.size), &value)
    }

    /// Mutes or unmutes a microphone. False when the device has no mute of its own to set.
    // shortcut: uses the device's main mute only; a microphone with per-channel mutes alone isn't muted.
    @discardableResult
    static func setMuted(_ muted: Bool, _ device: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute, mScope: kAudioObjectPropertyScopeInput,
                                                 mElement: kAudioObjectPropertyElementMain)
        var settable: DarwinBoolean = false
        guard AudioObjectHasProperty(device, &address),
              AudioObjectIsPropertySettable(device, &address, &settable) == noErr, settable.boolValue else { return false }
        var value: UInt32 = muted ? 1 : 0
        return AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value) == noErr
    }

    private static func hasStreams(_ object: AudioObjectID, _ scope: AudioObjectPropertyScope) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams, mScope: scope,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(object, &address, 0, nil, &size) == noErr && size > 0
    }

    private static func string(_ selector: AudioObjectPropertySelector, of object: AudioObjectID) -> String? {
        var address = address(selector)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value?.takeRetainedValue() as String?
    }

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                   mElement: kAudioObjectPropertyElementMain)
    }
}
