import Foundation
import LedgeKit

public struct TranslationPreferences: Codable, Sendable, Equatable {
    public var target: String
    public var secondary: String
    public var selectionButton: Bool
    public init(target: String = "en", secondary: String = "es", selectionButton: Bool = false) {
        self.target = target; self.secondary = secondary; self.selectionButton = selectionButton
    }
}

public struct QuickTranslateModel: Sendable {
    public enum Effect: Sendable, Equatable { case configure, translate }
    public var preferences: TranslationPreferences
    public var problem: String?
    public static let languages: [(String, String)] = [
        ("ar", "Arabic"), ("zh-Hans", "Chinese (Simplified)"), ("zh-Hant", "Chinese (Traditional)"),
        ("nl", "Dutch"), ("en", "English"), ("fr", "French"), ("de", "German"), ("hi", "Hindi"),
        ("id", "Indonesian"), ("it", "Italian"), ("ja", "Japanese"), ("ko", "Korean"), ("pl", "Polish"),
        ("pt", "Portuguese"), ("ru", "Russian"), ("es", "Spanish"), ("th", "Thai"), ("tr", "Turkish"),
        ("uk", "Ukrainian"), ("vi", "Vietnamese")
    ]

    public init(preferences: TranslationPreferences = .init()) {
        let known = Set(Self.languages.map(\.0))
        if known.contains(preferences.target), known.contains(preferences.secondary),
           (try? SelectionTranslation(target: preferences.target, secondary: preferences.secondary).validate()) != nil {
            self.preferences = preferences
        } else { self.preferences = .init() }
    }

    public var options: SelectionTranslation {
        SelectionTranslation(target: preferences.target, secondary: preferences.secondary, selectionButton: preferences.selectionButton)
    }
    public var shortcuts: [AddOnShortcut] { [AddOnShortcut("translate", title: "Translate selected text", key: "T")] }

    public mutating func handle(_ event: SurfaceEvent) -> Effect? {
        switch (event.surface, event.control, event.action) {
        case (Surface.shortcut, "translate", .pressed): return .translate
        case (Surface.settingsPage, "selectionButton", .toggled(let on)):
            preferences.selectionButton = on; problem = nil; return .configure
        case (Surface.settingsPage, let id, .picked(let code)) where id == "target" || id == "secondary":
            guard Self.languages.contains(where: { $0.0 == code }) else { return nil }
            let language = code.split(separator: "-").first
            if id == "target" {
                if language == preferences.secondary.split(separator: "-").first { preferences.secondary = preferences.target }
                preferences.target = code
            } else {
                if language == preferences.target.split(separator: "-").first { preferences.target = preferences.secondary }
                preferences.secondary = code
            }
            problem = nil
            return .configure
        default: return nil
        }
    }

    public func settingsPage() -> SettingsPage {
        let choices = Self.languages.map { SettingsRow.Option($0.0, $0.1) }
        var sections = [
            SettingsSection("languages", title: "Quick Translate", footer: "Source language is detected automatically. If text is already in your target language, it translates into your second language.", rows: [
                .picker("target", "Target language", options: choices, selected: preferences.target),
                .picker("secondary", "Second language", options: choices, selected: preferences.secondary)
            ]),
            SettingsSection("selection", title: "Selected text", footer: "Allow Ledge in System Settings → Privacy & Security → Accessibility. Assign Translate selected text in the Shortcuts section below, select text in another app and press the shortcut.", rows: [
                .toggle("selectionButton", "Translate button beside selections", detail: "Show a small button after selecting text with the mouse", isOn: preferences.selectionButton)
            ]),
            SettingsSection("privacy", title: "On this Mac", footer: "Supported pairs use Apple Translation on macOS 15 or later. Apple may ask to download language files. Unavailable pairs show an explanation; text is never sent to an AI or online translation service.", rows: [
                .note("workflow", "Read the card beside the selection, then choose Copy (⌘C) or Replace (Return). A changed or read-only selection is copied instead. Escape closes the card.")
            ])
        ]
        if let problem { sections.insert(SettingsSection("problem", title: "Couldn't translate", rows: [.note("notice", problem)]), at: 0) }
        return SettingsPage(sections, keywords: ["translate", "translation", "language", "selected text", "Spanish", "English"])
    }
}
