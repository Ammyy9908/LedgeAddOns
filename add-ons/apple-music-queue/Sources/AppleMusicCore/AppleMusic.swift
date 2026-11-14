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


    /// AI tools exposed by Ledge to connected assistants. Search returns local-library IDs; mutations require a
    /// separate call using those IDs so the assistant can present the exact selection first.
    public static let tools: [AddOnTool] = [
        AddOnTool("now_playing", title: "Get the Apple Music song playing now",
                  summary: "Returns the current Apple Music song, album, artist, favorite state, player state and position. It does not change playback."),
        AddOnTool("search_songs", title: "Search the Apple Music library",
                  summary: "Searches songs in the user's local Apple Music library and returns up to ten matches with stable IDs. It does not play anything. Choose a result before calling play_song.",
                  arguments: [.init("query", summary: "A song title, artist or album to search for.", kind: .text(maximumLength: 300))]),
        AddOnTool("play_song", title: "Play an Apple Music library song",
                  summary: "Starts the selected library song and replaces current playback. Use only after search_songs and when the user asked to play music.",
                  arguments: [.init("track_id", summary: "Exact persistent ID from search_songs.", kind: .text(maximumLength: 16))]),
        AddOnTool("list_playlists", title: "List Apple Music playlists",
                  summary: "Lists the user's editable, non-smart playlists with IDs and names. It does not change the library."),
        AddOnTool("list_playlist_songs", title: "List songs in an Apple Music playlist",
                  summary: "Returns up to 50 songs in a playlist with their IDs, titles, artists and albums. Use an ID returned by list_playlists.",
                  arguments: [.init("playlist_id", summary: "Exact persistent ID from list_playlists.", kind: .text(maximumLength: 16))]),
        AddOnTool("add_song_to_playlist", title: "Add a song to an Apple Music playlist",
                  summary: "Adds one selected library song to one selected playlist. Use IDs returned by search_songs and list_playlists; make the intended song and playlist clear before calling.",
                  arguments: [.init("track_id", summary: "Exact persistent ID from search_songs.", kind: .text(maximumLength: 16)),
                              .init("playlist_id", summary: "Exact persistent ID from list_playlists.", kind: .text(maximumLength: 16))], destructive: true),
        AddOnTool("create_playlist", title: "Create an Apple Music playlist",
                  summary: "Creates an empty playlist in the user's Apple Music library. Ask before creating it and use the requested name.",
                  arguments: [.init("name", summary: "The new playlist's name.", kind: .text(maximumLength: 100))], destructive: true)
    ]

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
            AddOnSession.show(tools: Self.tools)
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
        handlers.onTool = { [self] call in try await tool(call) }
        return handlers
    }

    private func tool(_ call: ToolCall) async throws -> ToolResult {
        guard let definition = Self.tools.first(where: { $0.name == call.tool }) else {
            throw AddOnError("Unknown Apple Music tool.")
        }
        _ = try definition.check(.object(call.arguments))
        switch call.tool {
        case "now_playing":
            let output = try await music(Scripts.nowPlaying, [])
            let fields = output.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "\t")
            guard fields.count == 7, Self.isPersistentID(fields[0]) else {
                throw AddOnError("Apple Music doesn't have a song playing now.")
            }
            return .json(.object([
                "id": .string(fields[0]), "title": .string(String(fields[1].prefix(512))),
                "artist": .string(String(fields[2].prefix(512))), "album": .string(String(fields[3].prefix(512))),
                "favorite": .bool(fields[4].lowercased() == "true"), "state": .string(String(fields[5].prefix(32))),
                "position_seconds": Double(fields[6]).map { .number($0) } ?? .null
            ]))
        case "search_songs":
            guard let query = call.text("query")?.trimmingCharacters(in: .whitespacesAndNewlines), !query.isEmpty else {
                throw AddOnError("Enter a song title, artist or album to search.")
            }
            let output = try await music(Scripts.searchLibrary, [String(query.prefix(300))])
            let songs = output.split(separator: "\n").prefix(10).compactMap { line -> JSONValue? in
                let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
                guard fields.count == 4, Self.isPersistentID(fields[0]) else { return nil }
                return .object(["id": .string(fields[0]), "title": .string(String(fields[1].prefix(512))),
                                "artist": .string(String(fields[2].prefix(512))), "album": .string(String(fields[3].prefix(512)))])
            }
            return .json(.object(["songs": .array(songs)]))
        case "play_song":
            guard let id = call.text("track_id"), Self.isPersistentID(id) else {
                throw AddOnError("Use a song ID returned by search_songs.")
            }
            let fields = try await music(Scripts.playSong, [id]).trimmingCharacters(in: .whitespacesAndNewlines)
                .components(separatedBy: "\t")
            guard fields.count == 3 else { throw AddOnError("Music didn't confirm the selected song.") }
            return .json(.object(["id": .string(fields[0]), "title": .string(fields[1]), "artist": .string(fields[2]),
                                  "accepted": .bool(true)]))
        case "list_playlists":
            let rows = Self.parsePlaylists(try await music(Scripts.playlists, []))
            return .json(.object(["playlists": .array(rows.map { .object(["id": .string($0.id), "name": .string($0.title)]) })]))
        case "list_playlist_songs":
            guard let playlistID = call.text("playlist_id"), Self.isPersistentID(playlistID) else {
                throw AddOnError("Use a playlist ID from list_playlists.")
            }
            let output = try await music(Scripts.listPlaylistSongs, [playlistID])
            let songs = output.split(separator: "\n").prefix(50).compactMap { line -> JSONValue? in
                let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
                guard fields.count == 4, Self.isPersistentID(fields[0]) else { return nil }
                return .object(["id": .string(fields[0]), "title": .string(String(fields[1].prefix(512))),
                                "artist": .string(String(fields[2].prefix(512))), "album": .string(String(fields[3].prefix(512)))])
            }
            return .json(.object(["songs": .array(songs)]))
        case "add_song_to_playlist":
            guard let trackID = call.text("track_id"), Self.isPersistentID(trackID),
                  let playlistID = call.text("playlist_id"), Self.isPersistentID(playlistID) else {
                throw AddOnError("Use a song ID from search_songs and a playlist ID from list_playlists.")
            }
            _ = try await music(Scripts.addSongToPlaylist, [trackID, playlistID])
            return .text("Apple Music added the selected song to the selected playlist.")
        case "create_playlist":
            guard let name = call.text("name")?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !name.isEmpty, name.count <= 100 else {
                throw AddOnError("Enter a playlist name up to 100 characters.")
            }
            let fields = try await music(Scripts.createPlaylist, [name]).trimmingCharacters(in: .whitespacesAndNewlines)
                .components(separatedBy: "\t")
            guard fields.count == 2, Self.isPersistentID(fields[0]) else {
                throw AddOnError("Music didn't confirm the new playlist.")
            }
            return .json(.object(["id": .string(fields[0]), "name": .string(fields[1])]))
        default:
            throw AddOnError("Unknown Apple Music tool.")
        }
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
