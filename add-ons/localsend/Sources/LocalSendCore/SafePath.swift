import Foundation

/// Where a received file goes. The sender picks its name, so the name is never trusted: a folder sent from LocalSend
/// arrives as "Trip/Day 1/photo.jpg", and a hostile sender could send "../../.zshrc".
public enum SafePath {
    /// The name's parts as safe file names: no "..", no ".", no empty parts, no slashes or colons, no control
    /// characters, no leading dots that would hide a file. Never empty.
    public static func components(of name: String) -> [String] {
        let parts = name.replacingOccurrences(of: "\\", with: "/").split(separator: "/").compactMap { part -> String? in
            var clean = String(part.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) })
                .replacingOccurrences(of: ":", with: "-")
                .trimmingCharacters(in: .whitespaces)
            while clean.hasPrefix(".") { clean.removeFirst() }
            guard !clean.isEmpty else { return nil }
            // A file system name is at most 255 bytes; keep the extension when shortening.
            while clean.utf8.count > 255 {
                let ext = (clean as NSString).pathExtension
                let stem = (clean as NSString).deletingPathExtension
                clean = ext.isEmpty || ext.utf8.count > 16 ? String(clean.dropLast()) : String(stem.dropLast()) + "." + ext
            }
            return clean
        }
        return parts.isEmpty ? ["Received file"] : Array(parts.suffix(8))
    }

    /// A new file's place inside `folder`: its folders as sent, and a name that's free, adding " (1)", " (2)"… before
    /// the extension as the Finder does. Always inside `folder`.
    public static func destination(for name: String, in folder: URL, exists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }) -> URL {
        let parts = components(of: name)
        var directory = folder
        for part in parts.dropLast() { directory.appendPathComponent(part, isDirectory: true) }
        let file = parts.last!
        let stem = (file as NSString).deletingPathExtension
        let ext = (file as NSString).pathExtension
        var candidate = directory.appendingPathComponent(file)
        var n = 1
        while exists(candidate) {
            candidate = directory.appendingPathComponent(ext.isEmpty ? "\(stem) (\(n))" : "\(stem) (\(n)).\(ext)")
            n += 1
        }
        precondition(candidate.standardizedFileURL.path.hasPrefix(folder.standardizedFileURL.path + "/"))
        return candidate
    }

    /// The first part of where it went, relative to the folder: the file, or the top folder a sent folder made. That's
    /// what goes on the shelf.
    public static func topItem(of file: URL, in folder: URL) -> URL {
        let base = folder.standardizedFileURL.pathComponents
        let parts = file.standardizedFileURL.pathComponents
        guard parts.count > base.count, Array(parts.prefix(base.count)) == base else { return file }
        return folder.appendingPathComponent(parts[base.count])
    }
}
