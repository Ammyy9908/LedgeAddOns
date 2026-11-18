import AppKit
import AudioControlCore
import CoreAudio

/// An app playing sound, with every Core Audio process that carries it, helpers included.
struct AudioApp {
    let id: String
    let name: String
    let icon: NSImage?
    var processes: [AudioObjectID]
    var playing: Bool
}

enum AudioApps {
    /// The row for macOS's own alert and interface sounds.
    static let systemSounds = "system-sounds"

    /// Every app with a sound process, keyed by bundle id, and macOS's own sounds as ``systemSounds`` when asked.
    /// Ledge itself is left out: its sounds aren't an app's.
    static func current(includingSystemSounds: Bool) -> [String: AudioApp] {
        let running = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
        let byPID = Dictionary(running.map { ($0.processIdentifier, $0) }, uniquingKeysWith: { first, _ in first })
        let ids = running.compactMap(\.bundleIdentifier)
        var apps: [String: AudioApp] = [:]
        for object in objects() {
            let bundle = string(kAudioProcessPropertyBundleID, of: object) ?? ""
            if bundle == Mixer.systemSoundsProcess {
                guard includingSystemSounds else { continue }
                let icon = NSWorkspace.shared.icon(forFile: "/System/Applications/System Settings.app")
                apps[systemSounds, default: AudioApp(id: systemSounds, name: "System sounds", icon: icon, processes: [], playing: false)]
                    .processes.append(object)
                if flag(kAudioProcessPropertyIsRunningOutput, of: object) { apps[systemSounds]?.playing = true }
                continue
            }
            let owner = byPID[pid(of: object)] ?? Mixer.owner(of: bundle, among: ids).flatMap { id in
                running.first { $0.bundleIdentifier == id }
            }
            guard let owner, let id = owner.bundleIdentifier, !id.hasPrefix("app.ledge") else { continue }
            let playing = flag(kAudioProcessPropertyIsRunningOutput, of: object)
            apps[id, default: AudioApp(id: id, name: owner.localizedName ?? id, icon: owner.icon, processes: [], playing: false)]
                .processes.append(object)
            if playing { apps[id]?.playing = true }
        }
        return apps
    }

    /// The UID of the output the Mac plays to now.
    static func defaultOutput() -> String? {
        var device = AudioObjectID(0)
        guard get(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultOutputDevice, &device), device != 0
        else { return nil }
        return string(kAudioDevicePropertyDeviceUID, of: device)
    }

    private static func objects() -> [AudioObjectID] {
        var address = address(kAudioHardwarePropertyProcessObjectList)
        let system = AudioObjectID(kAudioObjectSystemObject)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var list = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &list) == noErr else { return [] }
        return list
    }

    private static func pid(of object: AudioObjectID) -> pid_t {
        var value: pid_t = 0
        return get(object, kAudioProcessPropertyPID, &value) ? value : 0
    }

    private static func flag(_ selector: AudioObjectPropertySelector, of object: AudioObjectID) -> Bool {
        var value: UInt32 = 0
        return get(object, selector, &value) && value != 0
    }

    private static func string(_ selector: AudioObjectPropertySelector, of object: AudioObjectID) -> String? {
        var value: Unmanaged<CFString>?
        return get(object, selector, &value) ? value?.takeRetainedValue() as String? : nil
    }

    private static func get<Value: BitwiseCopyable>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, _ value: inout Value) -> Bool {
        var address = address(selector)
        var size = UInt32(MemoryLayout<Value>.size)
        return AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr
    }

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                   mElement: kAudioObjectPropertyElementMain)
    }
}

extension NSImage {
    /// The icon as a small PNG for a widget row: 36 pixels, sharp at 18 points on a Retina screen.
    var widgetPNG: Data? {
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 36, pixelsHigh: 36, bitsPerSample: 8,
                                            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                            bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        draw(in: NSRect(x: 0, y: 0, width: 36, height: 36))
        NSGraphicsContext.restoreGraphicsState()
        return bitmap.representation(using: .png, properties: [:])
    }
}
