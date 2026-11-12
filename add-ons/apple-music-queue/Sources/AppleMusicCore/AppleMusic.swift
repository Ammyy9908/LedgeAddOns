import Foundation
import LedgeKit

/// Apple Music in Ledge's players: the favourite star (a player action), Add to Playlist in the ••• menu and
/// Playing Next (a player extension), each of which the user can turn off on the add-on's page.
public struct AppleMusic: Sendable {
    public static let music = "com.apple.Music"

    /// Runs one `osascript` program: its language ("AppleScript" or "JavaScript"), its text and its arguments.
    /// Returns what it printed. Tests pass their own.
    public typealias Runner = @Sendable (_ language: String, _ script: String, _ arguments: [String]) async throws -> String

    /// Where the add-on keeps its three switches. Ledge's stored settings by default.
    public struct Settings: Sendable {
        public var load: @Sendable () async -> Choices?
        public var save: @Sendable (Choices) async -> Void
        public init(load: @escaping @Sendable () async -> Choices?, save: @escaping @Sendable (Choices) async -> Void) {
            self.load = load
            self.save = save
        }
        public static let ledge = Settings(
            load: { try? await LedgeHost.value(Choices.self, forKey: "choices") },
            save: { try? await LedgeHost.set($0, forKey: "choices") })
    }

    public struct Choices: Codable, Sendable, Equatable {
        public var queue = true
        public var favorites = true
        public var playlists = true
        public init() {}
    }

    private let run: Runner
    private let settings: Settings

    public init(run: @escaping Runner = Osascript.run, settings: Settings = .ledge) {
        self.run = run
        self.settings = settings
    }

    public static let star = PlayerAction("favorite", label: "Favorite", symbol: "star", selectedSymbol: "star.fill", sources: [music])
    public static let playlistMenu = PlayerMenu("playlists", title: "Add to Playlist", symbol: "text.badge.plus")

    public static func page(_ choices: Choices) -> SettingsPage {
        SettingsPage([
            SettingsSection("controls", title: "In Ledge’s players",
                            footer: "Playing Next appears on the left of the player. The star sits beside ••• in the expanded player, and Add to Playlist is in the ••• menu. macOS asks once to let Ledge control Music.",
                            rows: [
                                .toggle("queue", "Playing Next", detail: "Music’s own queue. Uses a private macOS interface, so it may stop working after an update.", isOn: choices.queue),
                                .toggle("favorites", "Favorite", isOn: choices.favorites),
                                .toggle("playlists", "Add to Playlist", isOn: choices.playlists)
                            ])
        ])
    }

    /// What the add-on shows for the user's choices.
    static func surfaces(_ choices: Choices) -> (actions: [PlayerAction], player: PlayerExtension?) {
        let player = choices.queue || choices.playlists
            ? PlayerExtension(sources: [music], menu: choices.playlists ? playlistMenu : nil, queue: choices.queue) : nil
        return (choices.favorites ? [star] : [], player)
    }

    public func handlers() -> AddOnHandlers {
        let state = State()
        let show: @Sendable (Choices) -> Void = { choices in
            let surfaces = Self.surfaces(choices)
            AddOnSession.show(Self.page(choices))
            AddOnSession.show(playerActions: surfaces.actions)
            AddOnSession.show(player: surfaces.player)
        }
        var handlers = AddOnHandlers()
        handlers.activate = { [settings] in
            let choices = await settings.load() ?? Choices()
            await state.set(choices)
            show(choices)
        }
        handlers.onEvent = { [settings] event in
            guard event.surface == Surface.settingsPage, case .toggled(let on) = event.action else { return }
            var choices = await state.choices
            switch event.control {
            case "queue": choices.queue = on
            case "favorites": choices.favorites = on
            case "playlists": choices.playlists = on
            default: return
            }
            await state.set(choices)
            await settings.save(choices)
            show(choices)
        }
        handlers.onPlayerAction = { request in
            guard request.action == Self.star.id, request.track.source == Self.music, await state.choices.favorites else { return nil }
            return try await favorite(set: request.set)
        }
        handlers.onPlayerMenu = { request in
            guard request.menu == Self.playlistMenu.id, request.track.source == Self.music, await state.choices.playlists else { return [] }
            if let id = request.choose {
                try await addToPlaylist(id)
                return []
            }
            return try await playlists()
        }
        handlers.onPlayerQueue = { request in
            guard request.track.source == Self.music, await state.choices.queue else { throw AddOnError("Playing Next is turned off.") }
            return try await queue(playNext: request.playNext)
        }
        return handlers
    }

    // MARK: Music

    /// Reads the star, or sets it. Nil when Music has no playing song to ask about.
    func favorite(set: Bool?) async throws -> Bool? {
        let output = try await music(set.map { _ in Scripts.setFavorite } ?? Scripts.readFavorite, set.map { [$0 ? "true" : "false"] } ?? [])
        switch output.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "true": return true
        case "false": return false
        default: return nil
        }
    }

    func playlists() async throws -> [PlayerMenu.Item] {
        let output = try await music(Scripts.playlists, [])
        return Self.parsePlaylists(output)
    }

    func addToPlaylist(_ id: String) async throws {
        guard Self.isPersistentID(id) else { throw AddOnError("That isn’t one of your playlists.") }
        _ = try await music(Scripts.addToPlaylist, [id])
    }

    func queue(playNext: String?) async throws -> [PlayerQueueEntry] {
        if let playNext, playNext.isEmpty || playNext.count > 1024 { throw AddOnError("That song isn’t in Playing Next.") }
        let output = try await run("JavaScript", Scripts.queue, playNext.map { [$0] } ?? [])
        return try Self.parseQueue(output)
    }

    /// Runs an AppleScript for Music, turning macOS's refusals into reasons people can act on.
    private func music(_ script: String, _ arguments: [String]) async throws -> String {
        do {
            return try await run("AppleScript", script, arguments)
        } catch let error as Osascript.Failure {
            if error.output.contains("-1743") {
                throw AddOnError("Allow Ledge to control Music in System Settings › Privacy & Security › Automation.")
            }
            if error.output.contains("-600") { throw AddOnError("Music isn’t open.") }
            throw AddOnError("Music didn’t answer.")
        }
    }

    // MARK: Parsing

    static func parsePlaylists(_ output: String) -> [PlayerMenu.Item] {
        output.split(separator: "\n").prefix(Surface.maximumMenuItems).compactMap { line in
            let parts = line.split(separator: "\t", maxSplits: 1).map(String.init)
            guard parts.count == 2, isPersistentID(parts[0]), !parts[1].isEmpty, parts[1].count <= 512 else { return nil }
            return PlayerMenu.Item(parts[0], title: parts[1])
        }
    }

    static func parseQueue(_ output: String) throws -> [PlayerQueueEntry] {
        struct Answer: Decodable {
            let status: String
            let message: String?
            let entries: [PlayerQueueEntry]?
        }
        guard let answer = try? JSONDecoder().decode(Answer.self, from: Data(output.utf8)) else {
            throw AddOnError("Music’s queue answered in a way this add-on doesn’t understand.")
        }
        guard answer.status == "available", let entries = answer.entries else {
            throw AddOnError(String((answer.message ?? "Playing Next isn’t available.").prefix(512)))
        }
        // Drop what Ledge would refuse rather than lose the whole list.
        return entries.prefix(12).filter { (try? PlayerQueueEntry.validate([$0])) != nil }
    }

    /// Music's persistent ids are 16 hexadecimal digits.
    static func isPersistentID(_ text: String) -> Bool {
        text.count == 16 && text.allSatisfy { $0.isHexDigit }
    }
}

/// The user's choices, as the session last saw them.
private actor State {
    private(set) var choices = AppleMusic.Choices()
    func set(_ choices: AppleMusic.Choices) { self.choices = choices }
}

/// Runs `/usr/bin/osascript` with a fixed program and arguments, with a deadline and an output limit.
public enum Osascript {
    public struct Failure: Error {
        /// What it wrote to its error output, for the error code.
        public let output: String
    }

    public static let run: AppleMusic.Runner = { language, script, arguments in
        try await Task.detached { try runNow(language: language, script: script, arguments: arguments) }.value
    }

    private static func runNow(language: String, script: String, arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-l", language, "-e", script] + arguments
        let output = Pipe(), errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        process.standardInput = FileHandle.nullDevice
        try process.run()
        let deadline = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 8, execute: deadline)
        let data = (try? output.fileHandleForReading.read(upToCount: 262_145)) ?? Data()
        let failure = (try? errors.fileHandleForReading.read(upToCount: 4096)) ?? Data()
        process.waitUntilExit()
        deadline.cancel()
        guard process.terminationStatus == 0, data.count <= 262_144 else {
            throw Failure(output: String(decoding: failure, as: UTF8.self))
        }
        return String(decoding: data, as: UTF8.self)
    }
}
