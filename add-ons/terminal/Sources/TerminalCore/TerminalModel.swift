import Foundation
import LedgeKit

/// Where a new shell starts.
public enum StartFolder: String, CaseIterable, Codable, Sendable {
    case home, desktop, documents, last

    public var title: String {
        switch self {
        case .home: "Home"
        case .desktop: "Desktop"
        case .documents: "Documents"
        case .last: "Where the last one was"
        }
    }

    /// The folder for a new shell: the chosen one, or home when it doesn't exist.
    public func folder(home: String, last: String?, exists: (String) -> Bool) -> String {
        let wanted: String? = switch self {
        case .home: home
        case .desktop: home + "/Desktop"
        case .documents: home + "/Documents"
        case .last: last
        }
        guard let wanted, wanted.hasPrefix("/"), exists(wanted) else { return home }
        return wanted
    }
}

/// What Terminal keeps: where shells start, and the folder the last one was in. Nothing the person typed.
public struct TerminalSettings: Codable, Sendable, Equatable {
    public var startIn: StartFolder
    public var lastFolder: String?

    public init(startIn: StartFolder = .home, lastFolder: String? = nil) {
        self.startIn = startIn
        self.lastFolder = lastFolder
    }

    public static let key = "settings"

    /// Applies a change on the settings page. Returns true when something changed.
    public mutating func handle(_ event: SurfaceEvent) -> Bool {
        guard event.control == "start-in", case .picked(let value) = event.action, let folder = StartFolder(rawValue: value),
              folder != startIn else { return false }
        startIn = folder
        return true
    }

    /// The add-on's page in Ledge's Settings.
    public func settingsPage(shell: String) -> SettingsPage {
        SettingsPage([
            SettingsSection("shell", title: "Terminal",
                            footer: "Your login shell runs as you, with your access to everything on this Mac, like one in Terminal. What you type goes only to the shell: Terminal doesn't keep it. Turning Terminal off ends the shell.",
                            rows: [
                                .picker("start-in", "Start in", options: StartFolder.allCases.map { .init($0.rawValue, $0.title) }, selected: startIn.rawValue),
                                .value("shell", "Shell", shell),
                                .button("restart", "Restart the shell", destructive: true,
                                        confirm: .init("Restart the shell?", message: "Programs running in it end.", confirmTitle: "Restart")),
                            ]),
        ], keywords: ["shell", "zsh", "command line", "console"])
    }
}
