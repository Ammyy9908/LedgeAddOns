import Foundation
import LedgeKit

/// The skin tone the person picks: emoji that come in tones show in it.
public enum SkinTone: String, CaseIterable, Codable, Sendable {
    case none, light, mediumLight, mediumDark, medium, dark

    public var title: String {
        switch self {
        case .none: "Default"
        case .light: "Light"
        case .mediumLight: "Medium light"
        case .medium: "Medium"
        case .mediumDark: "Medium dark"
        case .dark: "Dark"
        }
    }

    /// How Unicode's names say it, as in "waving hand: light skin tone".
    var suffix: String? {
        switch self {
        case .none: nil
        case .light: "light skin tone"
        case .mediumLight: "medium-light skin tone"
        case .medium: "medium skin tone"
        case .mediumDark: "medium-dark skin tone"
        case .dark: "dark skin tone"
        }
    }
}

/// One emoji as the picker shows it: in each skin tone it comes in.
public struct Emoji: Sendable, Equatable {
    public let id: String
    public let name: String
    public let group: String
    public let subgroup: String
    public let base: String
    /// The emoji in each tone, when it comes in tones.
    public let tones: [SkinTone: String]

    public func text(in tone: SkinTone) -> String { tones[tone] ?? base }
}

/// Every emoji, from Unicode's list, in Unicode's order and groups.
public struct EmojiCatalog: Sendable {
    public let emoji: [Emoji]
    /// Unicode's groups in order, without the skin tone components.
    public let groups: [String]

    /// The Unicode emoji version this macOS can draw: newer ones show as empty boxes, so they're left out.
    public static func supportedVersion(macOS major: Int, minor: Int) -> Double {
        switch (major, minor) {
        case (..<14, _): 14.0
        case (14, ..<4): 15.0
        case (14, _): 15.1
        case (15, ..<4): 15.1
        case (15, _), (26, ..<4): 16.0
        default: 17.0
        }
    }

    public init(table: String = EmojiData.table, upTo version: Double) {
        var bases: [String: (group: String, subgroup: String, text: String)] = [:]
        var order: [String] = []
        var tones: [String: [SkinTone: String]] = [:]
        var groups: [String] = []
        for line in table.split(separator: "\n") {
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard fields.count == 5, let since = Double(fields[2]), since <= version else { continue }
            let (group, subgroup, text, name) = (fields[0], fields[1], fields[3], fields[4])
            if let colon = name.range(of: ": "), let tone = SkinTone.allCases.first(where: { $0.suffix == String(name[colon.upperBound...]) }) {
                // A tone of an emoji listed before it, like "waving hand: light skin tone". Mixed tones are left out.
                tones[String(name[..<colon.lowerBound]), default: [:]][tone] = text
                continue
            }
            if name.contains("skin tone") { continue }
            guard bases[name] == nil else { continue }
            bases[name] = (group, subgroup, text)
            order.append(name)
            if !groups.contains(group) { groups.append(group) }
        }
        emoji = order.compactMap { name in
            guard let base = bases[name] else { return nil }
            let id = base.text.unicodeScalars.filter { $0.value != 0xFE0F }.map { String($0.value, radix: 16) }.joined(separator: "-")
            return Emoji(id: id, name: name, group: base.group, subgroup: base.subgroup, base: base.text, tones: tones[name] ?? [:])
        }
        self.groups = groups
    }
}

/// What Emoji keeps: the skin tone, and the emoji picked most recently. Nothing about where they went.
public struct EmojiSettings: Codable, Sendable, Equatable {
    public var tone: SkinTone
    /// Emoji ids, most recent first.
    public var recents: [String]

    public static let key = "settings"
    public static let maximumRecents = 24

    public init(tone: SkinTone = .none, recents: [String] = []) {
        self.tone = tone
        self.recents = recents
    }

    /// Puts a picked emoji first in Recents.
    public mutating func picked(_ id: String) {
        recents.removeAll { $0 == id }
        recents.insert(id, at: 0)
        recents = Array(recents.prefix(Self.maximumRecents))
    }

    /// Applies a change on the settings page. Returns true when something changed.
    public mutating func handle(_ event: SurfaceEvent) -> Bool {
        switch (event.control, event.action) {
        case ("skin-tone", .picked(let value)):
            guard let tone = SkinTone(rawValue: value), tone != self.tone else { return false }
            self.tone = tone
            return true
        case ("clear-recents", .pressed):
            guard !recents.isEmpty else { return false }
            recents = []
            return true
        default:
            return false
        }
    }

    public func settingsPage() -> SettingsPage {
        SettingsPage([
            SettingsSection("emoji", title: "Emoji",
                            footer: "Open the picker with the shortcut you choose below, search by name, and choose with Return or a click. Emoji keeps your skin tone and the last \(Self.maximumRecents) you picked, on this Mac, and nothing about where they went.",
                            rows: [
                                .picker("skin-tone", "Skin tone", options: SkinTone.allCases.map { .init($0.rawValue, $0.title) }, selected: tone.rawValue),
                                .button("clear-recents", "Clear Recents", detail: recents.isEmpty ? "None yet" : "\(recents.count) emoji",
                                        destructive: true, confirm: .init("Clear Recents?", message: "The emoji you picked lately are forgotten.", confirmTitle: "Clear")),
                            ]),
        ], keywords: ["emoji", "skin tone", "smiley", "picker"])
    }

    /// The picker: Recents first, then Unicode's groups, each emoji in the chosen tone.
    public func picker(from catalog: EmojiCatalog) -> Picker {
        let byID = Dictionary(catalog.emoji.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        func item(_ emoji: Emoji) -> PickerItem {
            // Its subgroup's words find it too: "heart" finds "red heart", "animal-mammal" finds "dog".
            let words = emoji.subgroup.split(separator: "-").map(String.init) + emoji.group.lowercased().split { !$0.isLetter }.map(String.init)
            var keywords: [String] = []
            for word in words where !keywords.contains(word) && word.count > 1 && !emoji.name.lowercased().contains(word) { keywords.append(word) }
            return PickerItem(emoji.id, text: emoji.text(in: tone), label: emoji.name, keywords: Array(keywords.prefix(12)))
        }
        var sections = [Picker.Section("recents", title: "Recents", symbol: "clock", items: recents.compactMap { byID[$0] }.map(item))]
        for group in catalog.groups {
            sections.append(.init(Self.id(group), title: group, symbol: Self.symbol(group),
                                  items: catalog.emoji.filter { $0.group == group }.map(item)))
        }
        return Picker(title: "Emoji", placeholder: "Search emoji", style: .glyphs, sections: sections)
    }

    static func id(_ group: String) -> String {
        group.lowercased().split { !$0.isLetter }.joined(separator: "-")
    }

    static func symbol(_ group: String) -> String {
        switch group {
        case "Smileys & Emotion": "face.smiling"
        case "People & Body": "hand.raised"
        case "Animals & Nature": "leaf"
        case "Food & Drink": "fork.knife"
        case "Travel & Places": "car"
        case "Activities": "soccerball"
        case "Objects": "lightbulb"
        case "Symbols": "heart"
        case "Flags": "flag"
        default: "circle.grid.3x3"
        }
    }
}
