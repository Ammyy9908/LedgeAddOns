import Foundation

/// One row in Ledge's launcher panel, as the `launcher` request returns it. Return runs `open` when there is one and
/// copies `copy` otherwise; Copy Answer copies `copy`, or the title.
public struct LauncherResult: Codable, Sendable, Equatable {
    public var id: String
    public var title: String
    public var subtitle: String?
    /// The label on the right, like "Application" or "Calculator".
    public var kind: String
    /// An SF Symbol for the row, when there's no file to take an icon from.
    public var symbol: String?
    /// A file or app whose Finder icon the row shows.
    public var iconPath: String?
    /// A URL Ledge opens: a file, a web page, or a System Settings page.
    public var open: String?
    /// Text Copy Answer puts on the clipboard.
    public var copy: String?
    /// A question for the AI: choosing the row sends it back as a `launcher.ask` request and shows the answer.
    public var ask: String?

    public init(id: String, title: String, subtitle: String? = nil, kind: String, symbol: String? = nil,
                iconPath: String? = nil, open: String? = nil, copy: String? = nil, ask: String? = nil) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.kind = kind
        self.symbol = symbol
        self.iconPath = iconPath
        self.open = open
        self.copy = copy
        self.ask = ask
    }
}

/// What Ledge sends as the person types. `scope` is the category they picked, "apps", "files" or "settings", or nil
/// to search everything. Ledge before 0.1.0 Beta 8 sends none.
public struct LauncherQuery: Codable, Sendable {
    public var query: String
    public var scope: String?
    public init(query: String, scope: String? = nil) {
        self.query = query
        self.scope = scope
    }
}

/// An AI's answer to a `launcher.ask` request.
public struct LauncherAnswer: Codable, Sendable, Equatable {
    public var text: String
    /// Who answered, like "Claude".
    public var from: String
    public init(text: String, from: String) {
        self.text = text
        self.from = from
    }
}
