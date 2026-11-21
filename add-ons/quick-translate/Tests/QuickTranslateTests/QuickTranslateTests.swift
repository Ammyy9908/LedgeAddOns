import LedgeKit
import Testing
@testable import QuickTranslateCore

@Test func selectionButtonIsOffUntilChosen() throws {
    let model = QuickTranslateModel()
    #expect(!model.preferences.selectionButton)
    try model.options.validate()
    try model.settingsPage().validate()
    try AddOnShortcut.validate(model.shortcuts)
}

@Test func pickingTheOtherLanguageSwapsRatherThanCreatingAnInvalidPair() throws {
    var model = QuickTranslateModel()
    #expect(model.handle(.init(surface: Surface.settingsPage, control: "target", action: .picked("es"))) == .configure)
    #expect(model.preferences.target == "es")
    #expect(model.preferences.secondary == "en")
    try model.options.validate()
    #expect(model.handle(.init(surface: Surface.settingsPage, control: "target", action: .picked("file:///private"))) == nil)
}

@Test func onlyTheDeclaredShortcutStartsTranslation() {
    var model = QuickTranslateModel()
    #expect(model.handle(.init(surface: Surface.shortcut, control: "translate", action: .pressed)) == .translate)
    #expect(model.handle(.init(surface: Surface.settingsPage, control: "translate", action: .pressed)) == nil)
    #expect(model.handle(.init(surface: Surface.shortcut, control: "unknown", action: .pressed)) == nil)
}

@Test func storedInvalidLanguagesAreResetAndProblemsFitTheSurface() throws {
    var model = QuickTranslateModel(preferences: .init(target: "en", secondary: "en"))
    try model.options.validate()
    model.problem = "Translation isn't allowed. Open Quick Translate settings."
    try model.settingsPage().validate()
}

@Test func languageVariantsStillProduceTwoDifferentLanguages() throws {
    var model = QuickTranslateModel(preferences: .init(target: "en", secondary: "zh-Hant"))
    _ = model.handle(.init(surface: Surface.settingsPage, control: "target", action: .picked("zh-Hans")))
    try model.options.validate()
    #expect(model.preferences.secondary == "en")
}
