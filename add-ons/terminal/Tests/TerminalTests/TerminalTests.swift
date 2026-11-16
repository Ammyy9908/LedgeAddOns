import Foundation
import LedgeKit
import Testing
@testable import TerminalCore

private func pick(_ value: String) -> SurfaceEvent {
    SurfaceEvent(surface: Surface.settingsPage, control: "start-in", action: .picked(value))
}

@Test func choosingWhereShellsStart() {
    var settings = TerminalSettings()
    let changed = settings.handle(pick("desktop"))
    #expect(changed && settings.startIn == .desktop)
    let again = settings.handle(pick("desktop"))
    let unknown = settings.handle(pick("nowhere"))
    let other = settings.handle(SurfaceEvent(surface: Surface.settingsPage, control: "other", action: .picked("home")))
    #expect(!again && !unknown && !other)
}

@Test func theStartFolderFallsBackToHome() {
    let all: (String) -> Bool = { _ in true }
    #expect(StartFolder.home.folder(home: "/Users/a", last: nil, exists: all) == "/Users/a")
    #expect(StartFolder.desktop.folder(home: "/Users/a", last: nil, exists: all) == "/Users/a/Desktop")
    #expect(StartFolder.last.folder(home: "/Users/a", last: "/Users/a/Code", exists: all) == "/Users/a/Code")
    #expect(StartFolder.last.folder(home: "/Users/a", last: nil, exists: all) == "/Users/a")
    #expect(StartFolder.last.folder(home: "/Users/a", last: "relative", exists: all) == "/Users/a")
    #expect(StartFolder.documents.folder(home: "/Users/a", last: nil, exists: { $0 == "/Users/a" }) == "/Users/a")
}

/// Ledge refuses a settings page over its limits and draws nothing.
@Test(arguments: StartFolder.allCases)
func theSettingsPageIsOneLedgeDraws(startIn: StartFolder) throws {
    try TerminalSettings(startIn: startIn, lastFolder: "/tmp").settingsPage(shell: "/bin/zsh").validate()
}

@Test func settingsKeepNothingTyped() throws {
    let data = try JSONEncoder().encode(TerminalSettings(startIn: .last, lastFolder: "/Users/a/Code"))
    let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    #expect(Set(object?.keys.map { $0 } ?? []) == ["startIn", "lastFolder"])
}
