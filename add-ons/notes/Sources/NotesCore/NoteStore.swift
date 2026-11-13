import Foundation

// Notes keeps each note as one Markdown file in the folder Ledge gives the add-on, named by the note's id. A note's
// title is its first line and its date is the file's, so the files stay plain Markdown anyone can open.

/// One note: its id, its Markdown and when it last changed.
public struct Note: Sendable, Equatable {
    public let id: String
    public var text: String
    public var modified: Date

    public init(id: String, text: String, modified: Date) {
        self.id = id
        self.text = text
        self.modified = modified
    }

    /// The first line, without heading marks or Markdown, or "New note" while it's empty.
    public var title: String {
        let first = text.split(separator: "\n", omittingEmptySubsequences: true).first.map(String.init) ?? ""
        let plain = Self.words(first.trimmingCharacters(in: CharacterSet(charactersIn: "#").union(.whitespaces)))
        return plain.isEmpty ? "New note" : String(plain.prefix(80))
    }

    /// The next line with words in it, for under the title in the list.
    public var preview: String? {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true).dropFirst()
        guard let line = lines.first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) else { return nil }
        // Drop list and checkbox marks so the preview reads as words.
        let plain = line.replacingOccurrences(of: #"^\s*([-*+] (\[[ xX]\] )?|\d+\. |> |#+ )"#, with: "", options: .regularExpression)
        return String(Self.words(plain).prefix(120))
    }

    /// True while there's nothing in it but space.
    public var isBlank: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// Markdown's marks taken off, so a list shows the words: **bold**, _italic_, `code` and ~~struck~~ read plainly.
    public static func words(_ line: String) -> String {
        line.replacingOccurrences(of: #"(\*\*|__|~~|`)"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?<![\w*_])[*_](?=\S)(.+?)(?<=\S)[*_](?![\w*_])"#, with: "$1", options: .regularExpression)
    }

    /// A short id for a new note, which is also its file name.
    public static func newID() -> String {
        String(UUID().uuidString.prefix(8)).lowercased()
    }

    /// The note a screen shows, from its id ("note-<id>").
    public static func id(fromScreen screen: String?) -> String? {
        guard let screen, screen.hasPrefix("note-"), screen.count > 5 else { return nil }
        return String(screen.dropFirst(5))
    }

    /// "Now", "12:41", "Yesterday", "Tue" or "3 Nov", the way a notes list dates its notes.
    public static func when(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        if now.timeIntervalSince(date) < 60 { return "Now" }
        if calendar.isDate(date, inSameDayAs: now) { return date.formatted(date: .omitted, time: .shortened) }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return "Yesterday"
        }
        if let days = calendar.dateComponents([.day], from: date, to: now).day, days < 7 {
            return date.formatted(.dateTime.weekday(.abbreviated))
        }
        return date.formatted(.dateTime.day().month(.abbreviated))
    }
}

/// The notes folder. Files are written whole and atomically, so a note is never half saved.
public struct NoteStore: Sendable {
    public let folder: URL

    public init(folder: URL) {
        self.folder = folder
    }

    /// Notes 0.2 kept its notes here, before Ledge gave each add-on a folder of its own.
    public static let oldFolder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Ledge Notes", isDirectory: true)

    /// Moves notes from an older folder into this one, once, skipping any already here, and removes the old folder
    /// when nothing is left in it. Returns how many moved.
    @discardableResult
    public func moveNotes(from old: URL = NoteStore.oldFolder) -> Int {
        let manager = FileManager.default
        guard let files = try? manager.contentsOfDirectory(at: old, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        else { return 0 }
        try? manager.createDirectory(at: folder, withIntermediateDirectories: true)
        var moved = 0
        for file in files where file.pathExtension == "md" {
            let target = folder.appendingPathComponent(file.lastPathComponent)
            guard !manager.fileExists(atPath: target.path) else { continue }
            if (try? manager.moveItem(at: file, to: target)) != nil { moved += 1 }
        }
        if (try? manager.contentsOfDirectory(atPath: old.path).filter { !$0.hasPrefix(".") }.isEmpty) == true {
            try? manager.removeItem(at: old)
        }
        return moved
    }

    public func url(for id: String) -> URL { folder.appendingPathComponent(id).appendingPathExtension("md") }

    /// Every note, newest first.
    public func load() throws -> [Note] {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey],
                                                                 options: [.skipsHiddenFiles])
        return files.filter { $0.pathExtension == "md" }.compactMap { file in
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { return nil }
            let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return Note(id: file.deletingPathExtension().lastPathComponent, text: text, modified: modified)
        }.sorted { $0.modified > $1.modified }
    }

    public func save(_ note: Note) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(note.text.utf8).write(to: url(for: note.id), options: .atomic)
    }

    /// Into the Trash, so a note deleted by mistake can still be put back.
    public func trash(_ id: String) throws {
        let file = url(for: id)
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        try FileManager.default.trashItem(at: file, resultingItemURL: nil)
    }
}
