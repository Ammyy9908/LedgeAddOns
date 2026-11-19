import Foundation

/// Something the launcher can find by name: an app or a System Settings page.
public struct Entry: Sendable, Equatable {
    public var result: LauncherResult
    /// More words that find it, like "wifi" for Wi‑Fi.
    public var keywords: [String]

    public init(_ result: LauncherResult, keywords: [String] = []) {
        self.result = result
        self.keywords = keywords
    }
}

public enum Launcher {
    /// The rows for `query` from what's known now: answers first, then apps and settings by how well they match.
    /// Files and the web search come after these, from the add-on.
    public static func search(_ query: String, apps: [Entry], settings: [Entry], now: Date = Date(), here: TimeZone = .current) -> [LauncherResult] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        let found = (apps.map { ($0, 1) } + settings.map { ($0, 0) })
            .compactMap { entry, bonus in score(entry.result.title, keywords: entry.keywords, query: query).map { (entry.result, $0 * 2 + bonus) } }
            .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0.title.count < $1.0.title.count }
        return answers(query, now: now, here: here) + found.prefix(8).map(\.0)
    }

    /// A sum, a conversion or a time, when `query` asks for one.
    public static func answers(_ query: String, now: Date = Date(), here: TimeZone = .current) -> [LauncherResult] {
        if let percent = percentOf(query) { return [percent] }
        if let conversion = Units.convert(query) {
            let shown = NumberText.shown(conversion.result)
            return [LauncherResult(id: "answer", title: "\(shown) \(conversion.to)",
                                   subtitle: "\(NumberText.shown(conversion.value)) \(conversion.from) = \(shown) \(conversion.to)",
                                   kind: "Conversion", symbol: "arrow.left.arrow.right", copy: NumberText.copied(conversion.result))]
        }
        if let time = TimeZones.answer(query, now: now, here: here) {
            return [LauncherResult(id: "answer", title: time.time, subtitle: time.detail, kind: "Time Zone", symbol: "globe", copy: time.time)]
        }
        if Calculator.looksLikeMath(query), let value = Calculator.evaluate(query) {
            return [LauncherResult(id: "answer", title: NumberText.shown(value), subtitle: "= \(query)", kind: "Calculator",
                                   symbol: "plus.forwardslash.minus", copy: NumberText.copied(value))]
        }
        return []
    }

    /// "15% of 80", "15% tip on 80", "18 percent tip on 62.50".
    static func percentOf(_ query: String) -> LauncherResult? {
        guard let match = query.lowercased().firstMatch(#"^\s*([\d.]+)\s*(?:%|percent)\s*(tip\s+)?(?:of|on)\s+(.+?)\s*$"#),
              let rate = Double(match[1]), let base = Calculator.evaluate(match[3]) else { return nil }
        let amount = base * rate / 100
        if match[2].isEmpty {
            return LauncherResult(id: "answer", title: NumberText.shown(amount), subtitle: "\(match[1])% of \(NumberText.shown(base))",
                                  kind: "Calculator", symbol: "percent", copy: NumberText.copied(amount))
        }
        let total = base + amount
        return LauncherResult(id: "answer", title: NumberText.shown(amount),
                              subtitle: "\(match[1])% tip on \(NumberText.shown(base)) · total \(NumberText.shown(total))",
                              kind: "Tip", symbol: "percent", copy: NumberText.copied(amount))
    }

    /// How well `query` names something, higher is better, nil when it doesn't. Case and accents don't matter.
    public static func score(_ name: String, keywords: [String] = [], query: String) -> Int? {
        let name = fold(name)
        let query = fold(query)
        guard !query.isEmpty else { return nil }
        if name == query { return 100 }
        if name.hasPrefix(query) { return 90 }
        let words = name.split { !$0.isLetter && !$0.isNumber }.map(String.init)
        let parts = query.split(separator: " ").map(String.init)
        if parts.allSatisfy({ part in words.contains { $0.hasPrefix(part) } }) { return 70 }
        // "vsc" for Visual Studio Code.
        if !query.contains(" "), query.count >= 2, String(words.compactMap(\.first)).hasPrefix(query) { return 60 }
        if keywords.contains(where: { fold($0).hasPrefix(query) }) { return 50 }
        if query.count >= 3, name.contains(query) { return 30 }
        return nil
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .replacingOccurrences(of: "\u{2011}", with: "-")
            .trimmingCharacters(in: .whitespaces)
    }

    /// The last row: the query, searched on the web.
    public static func webSearch(_ query: String) -> LauncherResult? {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, var components = URLComponents(string: "https://www.google.com/search") else { return nil }
        components.queryItems = [URLQueryItem(name: "q", value: query)]
        guard let url = components.url else { return nil }
        return LauncherResult(id: "web", title: "Search the web for “\(query)”", subtitle: "Google", kind: "Web Search",
                              symbol: "magnifyingglass", open: url.absoluteString)
    }
}
