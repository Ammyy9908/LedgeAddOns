import AppKit
import AudioToolbox

/// Each agent's own app icon, read from the app installed on this Mac, as a small PNG for the notch. Nil when the app
/// isn't installed; then the add-on uses its own picture.
enum AgentIcons {
    nonisolated(unsafe) private static var cache: [String: Data?] = [:]

    static func png(_ app: String) -> Data? {
        if let cached = cache[app] { return cached }
        let paths = ["/Applications/\(app).app", NSHomeDirectory() + "/Applications/\(app).app"]
        let data = paths.first(where: FileManager.default.fileExists).flatMap { path -> Data? in
            let side = 64
            guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8,
                                                samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                                bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
            NSWorkspace.shared.icon(forFile: path).draw(in: NSRect(x: 0, y: 0, width: side, height: side))
            NSGraphicsContext.restoreGraphicsState()
            return bitmap.representation(using: .png, properties: [:])
        }
        cache[app] = data
        return data
    }
}

/// The sound played when an agent finishes: one of macOS's own alert sounds.
enum FinishSound {
    static let names = ["Glass", "Ping", "Pop", "Purr", "Hero", "Submarine", "Funk", "Tink"]

    static func play(_ name: String) {
        guard names.contains(name) else { return }
        var sound: SystemSoundID = 0
        let url = URL(fileURLWithPath: "/System/Library/Sounds/\(name).aiff") as CFURL
        guard AudioServicesCreateSystemSoundID(url, &sound) == noErr else { return }
        AudioServicesPlaySystemSoundWithCompletion(sound) { AudioServicesDisposeSystemSoundID(sound) }
    }
}
