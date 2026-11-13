import Foundation
import LedgeKit
import NotesCore

// Notes: notes written in the notch, kept as Markdown files on this Mac.
//
// The add-on shows its notes on a page of its own in the open notch: a list, then a note in Ledge's editor, saved as
// it's written. The notes themselves live in NotesCore's NoteStore, in the folder Ledge gives the add-on.

actor Notes {
    private var store = NoteStore(folder: NoteStore.oldFolder)
    private var notes: [Note] = []
    /// The note on screen, if one is open.
    private var open: String?
    /// A note made with New that hasn't been written in yet. It isn't saved until it has words in it.
    private var draft: String?
    private var problem: String?

    func start() async {
        do {
            store = NoteStore(folder: try await LedgeHost.dataFolder())
            store.moveNotes()
        } catch {
            problem = "Ledge didn't give Notes a folder."
            AddOnSession.log("No data folder: \(error)", level: .error)
        }
        reload()
        AddOnSession.show(settingsPage())
        show()
    }

    // MARK: Events

    /// The page opened: read the folder again, so a note changed in Finder or another editor shows up.
    func visibilityChanged(_ visibility: SurfaceVisibility) {
        guard visibility.isVisible(Surface.notchPage), open == nil else { return }
        reload()
        show()
    }

    func handle(_ event: SurfaceEvent) async {
        if event.surface == Surface.settingsPage {
            if event.control == "reveal" { reveal() }
            if event.control == "trashAll" { trashAll() }
            return
        }
        guard event.surface == Surface.notchPage else { return }
        switch (event.control, event.action) {
        case ("notes", .pressed):
            discardEmptyDraft()
            if let id = event.item, notes.contains(where: { $0.id == id }) { open = id }
        case (PageScreen.backControl, .pressed):
            discardEmptyDraft()
            open = nil
            reload()
        case ("new", .pressed):
            discardEmptyDraft()
            let note = Note(id: Note.newID(), text: "", modified: Date())
            notes.insert(note, at: 0)
            draft = note.id
            open = note.id
        case ("body", .edited(let text)), ("body", .ended(let text)):
            // Saved to the note the editor was showing, which may no longer be the open one.
            guard let id = Note.id(fromScreen: event.screen) else { return }
            write(text, to: id)
        case ("copy", .pressed):
            if let note = current { try? await LedgeHost.copy(note.text) }
            return
        case ("delete", .pressed):
            if let id = open {
                do { try store.trash(id) } catch { AddOnSession.log("Couldn't move a note to the Trash: \(error)", level: .error) }
                notes.removeAll { $0.id == id }
                if draft == id { draft = nil }
            }
            open = nil
        default:
            return
        }
        show()
    }

    private var current: Note? { open.flatMap { id in notes.first { $0.id == id } } }

    private func write(_ text: String, to id: String) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        guard notes[index].text != text else { return }
        notes[index].text = text
        notes[index].modified = Date()
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, draft == id { return }   // an empty new note stays unsaved
        do {
            try store.save(notes[index])
            if draft == id { draft = nil }
            problem = nil
        } catch {
            problem = "Couldn't save this note."
            AddOnSession.log("Save failed: \(error)", level: .error)   // never the note itself
        }
    }

    /// A New note left without a word in it isn't kept.
    private func discardEmptyDraft() {
        guard let id = draft, let note = notes.first(where: { $0.id == id }),
              note.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        notes.removeAll { $0.id == id }
        draft = nil
    }

    private func reload() {
        do {
            let saved = try store.load()
            // Keep an unsaved draft at the top.
            notes = (draft.flatMap { id in notes.first { $0.id == id } }.map { [$0] } ?? []) + saved
            problem = nil
        } catch {
            problem = "Couldn't read the notes folder."
            AddOnSession.log("Load failed: \(error)", level: .error)
        }
    }

    /// Every note into the Trash, after Ledge has asked the user.
    private func trashAll() {
        for note in notes where draft != note.id {
            do { try store.trash(note.id) } catch { AddOnSession.log("Couldn't move a note to the Trash: \(error)", level: .error) }
        }
        notes.removeAll()
        draft = nil
        open = nil
        show()
    }

    private func reveal() {
        try? FileManager.default.createDirectory(at: store.folder, withIntermediateDirectories: true)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = [store.folder.path]
        try? process.run()
    }

    // MARK: What Ledge draws

    private func show() {
        AddOnSession.show(notchPage: NotchPage(title: "Notes", symbol: "note.text", size: .large, screen: screen()))
        // The settings page counts the notes, so it follows every change too. Ledge ignores a page that didn't change.
        AddOnSession.show(settingsPage())
    }

    private func screen() -> PageScreen {
        if let note = current {
            return PageScreen("note-\(note.id)", depth: 1, caption: problem ?? "Edited \(Note.when(note.modified))", back: true,
                              actions: [PageAction("copy", symbol: "doc.on.doc", label: "Copy note"),
                                        PageAction("delete", symbol: "trash", label: "Move to Trash", destructive: true)],
                              content: .editor(id: "body", text: note.text, placeholder: "Start writing",
                                               autofocus: note.text.isEmpty))
        }
        let content: PageNode
        if let problem {
            content = .empty(symbol: "exclamationmark.triangle", title: problem, detail: nil)
        } else if notes.isEmpty {
            content = .empty(symbol: "note.text", title: "No notes yet", detail: "Press the pencil to write one")
        } else {
            content = .list(id: "notes", rows: notes.prefix(Surface.maximumListRows).map {
                ListRow($0.id, title: $0.title, subtitle: $0.preview, detail: Note.when($0.modified))
            })
        }
        return PageScreen("list", title: "Notes", actions: [PageAction("new", symbol: "square.and.pencil", label: "New note")],
                          content: content)
    }

    private func settingsPage() -> SettingsPage {
        SettingsPage([
            SettingsSection("notes", title: "Notes",
                            footer: "Notes are Markdown files Ledge keeps for this add-on. They stay on this Mac, a deleted note goes to the Trash, and removing Notes keeps them unless you choose to delete its data.",
                            rows: [
                                .button("reveal", "Show in Finder"),
                                .button("trashAll", "Move all notes to the Trash", destructive: true,
                                        confirm: .init("Move all \(notes.count) notes to the Trash?",
                                                       message: "You can put them back from the Trash in Finder.",
                                                       confirmTitle: "Move to Trash")),
                            ]),
        ], keywords: ["markdown", "writing", "notes"])
    }
}

let addOn = Notes()
var handlers = AddOnHandlers()
handlers.activate = { await addOn.start() }
handlers.onEvent = { event in await addOn.handle(event) }
handlers.onVisibilityChange = { visibility in await addOn.visibilityChanged(visibility) }
exit(await AddOnSession.run(id: "notes", handlers: handlers))
