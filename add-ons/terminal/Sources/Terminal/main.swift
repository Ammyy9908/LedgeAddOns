import Foundation
import LedgeKit
import TerminalCore

// Terminal: the person's login shell on the notch's Terminal page. The shell runs here, on a pseudo-terminal, as the
// person; Ledge draws its screen and sends what they type, which goes to the shell and nowhere else.

actor Settings {
    private(set) var value = TerminalSettings()

    func load() async {
        value = (try? await LedgeHost.value(TerminalSettings.self, forKey: TerminalSettings.key)) ?? TerminalSettings()
        show()
    }

    /// A change on the settings page. True when the shell should restart.
    func handle(_ event: SurfaceEvent) async -> Bool {
        if event.control == "restart", case .pressed = event.action { return true }
        guard value.handle(event) else { return false }
        await save()
        show()
        return false
    }

    /// The folder the shell is in, kept for "Where the last one was".
    func remember(_ folder: String) async {
        guard value.lastFolder != folder else { return }
        value.lastFolder = folder
        await save()
    }

    private func save() async {
        do { try await LedgeHost.set(value, forKey: TerminalSettings.key) } catch {
            AddOnSession.log("Couldn't save the settings.", level: .error)
        }
    }

    private func show() {
        AddOnSession.show(value.settingsPage(shell: AddOnTerminal.loginShell))
    }
}

let settings = Settings()
let terminal = AddOnTerminal()
var handlers = AddOnHandlers()
handlers.activate = { await settings.load() }
handlers.onEvent = { event in
    guard event.surface == Surface.settingsPage else { return }
    if await settings.handle(event) {
        // The next key starts a new shell, as when one ends.
        terminal.stop()
    }
}
terminal.connect(&handlers) { terminal, size in
    let chosen = await settings.value
    let folder = chosen.startIn.folder(home: NSHomeDirectory(), last: chosen.lastFolder) {
        var directory: ObjCBool = false
        return FileManager.default.fileExists(atPath: $0, isDirectory: &directory) && directory.boolValue
    }
    try terminal.start(size: size, directory: folder)
}
// Remember the shell's folder when the person turns Terminal off, for "Where the last one was".
let deactivate = handlers.deactivate
handlers.deactivate = {
    if let folder = terminal.folder { await settings.remember(folder) }
    await deactivate()
}
exit(await AddOnSession.run(id: "terminal", handlers: handlers))
