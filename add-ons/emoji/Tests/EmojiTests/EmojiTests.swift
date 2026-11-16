import Foundation
import LedgeKit
import Testing
@testable import EmojiCore

private let catalog = EmojiCatalog(upTo: 17.0)

@Test func theCatalogHasEveryGroupButComponents() {
    #expect(catalog.groups.first == "Smileys & Emotion")
    #expect(!catalog.groups.contains("Component"))
    #expect(catalog.emoji.count > 1800)
    #expect(Set(catalog.emoji.map(\.id)).count == catalog.emoji.count)
}

@Test func skinTonesApplyToEmojiThatHaveThem() throws {
    let wave = try #require(catalog.emoji.first { $0.name == "waving hand" })
    #expect(wave.text(in: .none) == "👋")
    #expect(wave.text(in: .dark) == "👋🏿")
    let grin = try #require(catalog.emoji.first { $0.name == "grinning face" })
    #expect(grin.text(in: .dark) == "😀")
    #expect(!catalog.emoji.contains { $0.name.contains("skin tone") })
}

@Test func olderMacsGetOnlyEmojiTheyDraw() {
    let older = EmojiCatalog(upTo: EmojiCatalog.supportedVersion(macOS: 14, minor: 0))
    #expect(older.emoji.count < catalog.emoji.count)
    #expect(EmojiCatalog.supportedVersion(macOS: 14, minor: 4) == 15.1)
    #expect(EmojiCatalog.supportedVersion(macOS: 27, minor: 0) == 17.0)
}

@Test func searchFindsByNameAndSubgroup() throws {
    let picker = EmojiSettings().picker(from: catalog)
    let all = picker.sections.flatMap(\.items)
    #expect(all.contains { $0.label == "red heart" && $0.matches("heart") })
    #expect(all.contains { $0.label == "dog face" && $0.matches("mammal") })
    #expect(all.filter { $0.matches("thumbs up") }.map(\.text) == ["👍"])
}

@Test func recentsComeFirstAndStayShort() {
    var settings = EmojiSettings()
    for id in ["1f600", "2764", "1f600"] { settings.picked(id) }
    #expect(settings.recents == ["1f600", "2764"])
    for index in 0..<30 { settings.picked("x\(index)") }
    #expect(settings.recents.count == EmojiSettings.maximumRecents)
    let picker = EmojiSettings(recents: ["2764", "nope"]).picker(from: catalog)
    #expect(picker.sections.first?.items.map(\.text) == ["❤️"])
}

@Test(arguments: SkinTone.allCases)
func thePickerAndSettingsAreOnesLedgeDraws(tone: SkinTone) throws {
    let settings = EmojiSettings(tone: tone, recents: ["1f44b"])
    try settings.picker(from: catalog).validate()
    try settings.settingsPage().validate()
    // Small enough to send in one message.
    #expect(try JSONEncoder().encode(settings.picker(from: catalog)).count < SessionProtocol.maximumMessageBytes)
}

@Test func settingsChangeOnlyWhenSomethingDoes() {
    var settings = EmojiSettings()
    let tone = settings.handle(SurfaceEvent(surface: Surface.settingsPage, control: "skin-tone", action: .picked("medium")))
    let same = settings.handle(SurfaceEvent(surface: Surface.settingsPage, control: "skin-tone", action: .picked("medium")))
    let empty = settings.handle(SurfaceEvent(surface: Surface.settingsPage, control: "clear-recents", action: .pressed))
    #expect(tone && !same && !empty && settings.tone == .medium)
}
