import Foundation
import Testing
@testable import CleanerCore

private func home() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("cleaner-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func make(_ path: String, in home: URL, bytes: Int = 10) throws {
    let url = home.appendingPathComponent(path)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(count: bytes).write(to: url)
}

private let app = App(url: URL(fileURLWithPath: "/nonexistent/Some Editor.app"), name: "Some Editor", bundleID: "com.maker.editor")

@Test func identifierMatchesStartCheckedAndNameMatchesDont() throws {
    let home = try home()
    defer { try? FileManager.default.removeItem(at: home) }
    for path in ["Library/Preferences/com.maker.editor.plist", "Library/Caches/com.maker.editor/a",
                 "Library/LaunchAgents/com.maker.editor.helper.plist", "Library/Application Support/Some Editor/b",
                 "Library/Application Support/com.maker.editorial/c", "Library/Caches/com.other.app/d",
                 "Library/Group Containers/TEAM123.com.maker.editor/e", "Library/Containers/com.maker.editor/f"] {
        try make(path, in: home)
    }
    let found = Leftovers.find(for: app, home: home)
    let byName = Dictionary(uniqueKeysWithValues: found.dropFirst().map { ($0.url.deletingLastPathComponent().lastPathComponent + "/" + $0.url.lastPathComponent, $0) })
    #expect(found.first?.url == app.url)
    #expect(byName["Preferences/com.maker.editor.plist"]?.checked == true)
    #expect(byName["LaunchAgents/com.maker.editor.helper.plist"]?.checked == true)
    #expect(byName["Application Support/Some Editor"]?.checked == false)
    #expect(byName["Group Containers/TEAM123.com.maker.editor"]?.checked == false)
    // Another app whose id merely starts the same, and other apps' files, aren't touched.
    #expect(byName["Application Support/com.maker.editorial"] == nil)
    #expect(byName["Caches/com.other.app"] == nil)
    // Sandboxes are listed without being opened to size them.
    #expect(byName["Containers/com.maker.editor"]?.size == nil)
    #expect(byName["Caches/com.maker.editor"]?.size != nil)
}

@Test func anotherCopyLeavesEverythingUnchecked() throws {
    let home = try home()
    defer { try? FileManager.default.removeItem(at: home) }
    try make("Library/Preferences/com.maker.editor.plist", in: home)
    #expect(Leftovers.find(for: app, home: home, anotherCopy: true).dropFirst().allSatisfy { !$0.checked })
}

@Test func shortNamesAndProtectedAppsAreLeftAlone() {
    let go = App(url: URL(fileURLWithPath: "/Applications/Go.app"), name: "Go", bundleID: "com.example.go")
    #expect(Leftovers.match("Go", app: go, place: "Application Support") == nil)
    #expect(App(url: URL(fileURLWithPath: "/Applications/Safari.app"), name: "Safari", bundleID: "com.apple.Safari").isProtected)
    #expect(App(url: URL(fileURLWithPath: "/Applications/Ledge.app"), name: "Ledge", bundleID: "app.ledge.macos").isProtected)
    #expect(!app.isProtected)
}

@Test func storageSkipsApplesCachesAndScheduledCleaningSkipsFreshAndOpenApps() throws {
    let home = try home()
    defer { try? FileManager.default.removeItem(at: home) }
    for path in ["Library/Caches/com.apple.Safari/a", "Library/Caches/com.maker.editor/a", "Library/Caches/com.busy.app/a",
                 "Library/Caches/com.fresh.app/a", "Library/Logs/old.log"] {
        try make(path, in: home)
    }
    let caches = Storage.scan(home: home).first { $0.id == "caches" }
    #expect(caches?.items.map(\.lastPathComponent) == ["com.busy.app", "com.fresh.app", "com.maker.editor"])
    let old = Date().addingTimeInterval(-10 * 86_400)
    for path in ["Library/Caches/com.maker.editor", "Library/Caches/com.maker.editor/a", "Library/Caches/com.busy.app",
                 "Library/Caches/com.busy.app/a", "Library/Logs/old.log"] {
        try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: home.appendingPathComponent(path).path)
    }
    let stale = Storage.stale(home: home, running: ["com.busy.app"]).map(\.lastPathComponent)
    #expect(stale == ["com.maker.editor", "old.log"])
}

@Test func putBackReturnsWhatWasTrashed() throws {
    let home = try home()
    defer { try? FileManager.default.removeItem(at: home) }
    try make("Library/Caches/com.maker.editor/a", in: home)
    let url = home.appendingPathComponent("Library/Caches/com.maker.editor")
    let result = Trash.move([url])
    #expect(result.moved.count == 1 && !FileManager.default.fileExists(atPath: url.path))
    #expect(Trash.putBack(result.moved) == 1)
    #expect(FileManager.default.fileExists(atPath: url.appendingPathComponent("a").path))
}
