import Foundation
import Testing
@testable import NotesCore

// MARK: What the list shows

@Test func aNoteIsTitledByItsFirstLineWithoutMarkdown() {
    #expect(Note(id: "a", text: "# Launch **day**\nBeta 2", modified: .now).title == "Launch day")
    #expect(Note(id: "a", text: "", modified: .now).title == "New note")
    #expect(Note(id: "a", text: "\n\n  \n", modified: .now).title == "New note")
}

@Test func thePreviewIsTheNextLineWithWordsWithoutListMarks() {
    let note = Note(id: "a", text: "Groceries\n\n- [ ] Oat _milk_\n- eggs", modified: .now)
    #expect(note.preview == "Oat milk")
    #expect(Note(id: "a", text: "Only a title", modified: .now).preview == nil)
    #expect(Note(id: "a", text: "Title\n2. `code` and ~~gone~~", modified: .now).preview == "code and gone")
}

@Test func blankNotesAreOnlySpace() {
    #expect(Note(id: "a", text: " \n\t", modified: .now).isBlank)
    #expect(!Note(id: "a", text: "x", modified: .now).isBlank)
}

@Test func screensNameTheirNote() {
    #expect(Note.id(fromScreen: "note-b1c065d4") == "b1c065d4")
    #expect(Note.id(fromScreen: "list") == nil)
    #expect(Note.id(fromScreen: "note-") == nil)
    #expect(Note.id(fromScreen: nil) == nil)
    let id = Note.newID()
    #expect(id.count == 8 && id == id.lowercased())
}

@Test func datesReadTheWayANotesListDoesThem() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
    let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 13, hour: 12)))
    #expect(Note.when(now.addingTimeInterval(-20), now: now, calendar: calendar) == "Now")
    #expect(Note.when(now.addingTimeInterval(-26 * 3600), now: now, calendar: calendar) == "Yesterday")
    #expect(Note.when(now.addingTimeInterval(-30 * 86400), now: now, calendar: calendar) != "Yesterday")
}

// MARK: The folder

private func scratch() throws -> URL {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("notes-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder
}

@Test func savedNotesLoadBackNewestFirst() throws {
    let folder = try scratch()
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = NoteStore(folder: folder.appendingPathComponent("Files"))
    try store.save(Note(id: "older", text: "Older", modified: .now))
    try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -3600)], ofItemAtPath: store.url(for: "older").path)
    try store.save(Note(id: "newer", text: "Newer\nline", modified: .now))
    let notes = try store.load()
    #expect(notes.map(\.id) == ["newer", "older"])
    #expect(notes.first?.text == "Newer\nline")
}

@Test func onlyMarkdownFilesAreNotes() throws {
    let folder = try scratch()
    defer { try? FileManager.default.removeItem(at: folder) }
    try Data("x".utf8).write(to: folder.appendingPathComponent("photo.png"))
    try Data("# Kept".utf8).write(to: folder.appendingPathComponent("kept.md"))
    #expect(try NoteStore(folder: folder).load().map(\.id) == ["kept"])
}

@Test func oldNotesMoveOnceAndTheOldFolderGoes() throws {
    let root = try scratch()
    defer { try? FileManager.default.removeItem(at: root) }
    let old = root.appendingPathComponent("Ledge Notes", isDirectory: true)
    try FileManager.default.createDirectory(at: old, withIntermediateDirectories: true)
    try Data("# Moved".utf8).write(to: old.appendingPathComponent("a.md"))
    try Data("# Old copy".utf8).write(to: old.appendingPathComponent("b.md"))
    let store = NoteStore(folder: root.appendingPathComponent("Files"))
    try store.save(Note(id: "b", text: "# Newer copy", modified: .now))

    #expect(store.moveNotes(from: old) == 1)
    #expect(try store.load().first { $0.id == "b" }?.text == "# Newer copy")   // a note already here wins
    #expect(FileManager.default.fileExists(atPath: old.path))                   // b.md is still there, so the folder stays
    #expect(store.moveNotes(from: root.appendingPathComponent("nowhere")) == 0)
}

@Test func searchFindsNotesWithEveryWordInAnyCase() {
    let notes = [Note(id: "a", text: "# Shopping\nOat milk, bread", modified: Date()),
                 Note(id: "b", text: "Milk the cow", modified: Date()),
                 Note(id: "c", text: "Ideas", modified: Date())]
    #expect(Note.search(notes, for: "MILK").map(\.id) == ["a", "b"])
    #expect(Note.search(notes, for: "oat milk").map(\.id) == ["a"])
    #expect(Note.search(notes, for: "").map(\.id) == ["a", "b", "c"])
    #expect(Note.search(notes, for: "", limit: 1).map(\.id) == ["a"])
}
