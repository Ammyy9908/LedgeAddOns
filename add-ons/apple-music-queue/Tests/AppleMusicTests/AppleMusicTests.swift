import Foundation
import Testing
import LedgeKit
@testable import AppleMusicCore

private actor Calls {
    var all: [String] = []
    func add(_ call: String) { all.append(call) }
}

private let song = PlayerTrack(source: AppleMusic.music, title: "Song")

@Test func queueAnswersParseAndRefusalsBecomeReasons() throws {
    let entries = try AppleMusic.parseQueue(#"{"status":"available","currentID":"1","entries":[{"id":"2","title":"Next","artist":"A","storeID":"123"},{"title":"Cover","artist":"B","artworkURL":"https://example.com/a.jpg"},{"title":"Bad art","artist":"C","artworkURL":"http://example.com/a.jpg"}]}"#)
    #expect(entries.map(\.title) == ["Next", "Cover"])
    #expect(entries[0].storeID == "123")
    #expect(throws: AddOnError.self) { try AppleMusic.parseQueue(#"{"status":"unavailable","message":"Apple Music isn’t the app playing right now.","entries":[]}"#) }
    #expect(throws: AddOnError.self) { try AppleMusic.parseQueue("not json") }
}

@Test func playlistsKeepOnlyWellFormedLines() {
    let items = AppleMusic.parsePlaylists("0123456789ABCDEF\tRoad Trip\nnot-an-id\tOops\nFEDCBA9876543210\tFocus\n")
    #expect(items == [PlayerMenu.Item("0123456789ABCDEF", title: "Road Trip"), PlayerMenu.Item("FEDCBA9876543210", title: "Focus")])
}

@Test func handlersRouteTheStarMenuAndQueueToMusic() async throws {
    let calls = Calls()
    let music = AppleMusic(run: { language, script, arguments in
        await calls.add("\(language) \(arguments)")
        if language == "JavaScript" { return #"{"status":"available","entries":[{"id":"2","title":"Next","artist":"A"}]}"# }
        if script == Scripts.playlists { return "0123456789ABCDEF\tRoad Trip" }
        if script == Scripts.addToPlaylist { return "true" }
        return arguments.first ?? "false"
    }, settings: .init(load: { nil }, save: { _ in }))
    let handlers = music.handlers()
    #expect(try await handlers.onPlayerAction(PlayerActionRequest(action: "favorite", track: song)) == false)
    #expect(try await handlers.onPlayerAction(PlayerActionRequest(action: "favorite", track: song, set: true)) == true)
    #expect(try await handlers.onPlayerAction(PlayerActionRequest(action: "favorite", track: PlayerTrack(source: "com.spotify.client", title: "x"))) == nil)
    #expect(try await handlers.onPlayerMenu(PlayerMenuRequest(menu: "playlists", track: song)).map(\.title) == ["Road Trip"])
    #expect(try await handlers.onPlayerMenu(PlayerMenuRequest(menu: "playlists", track: song, choose: "0123456789ABCDEF")) == [])
    await #expect(throws: AddOnError.self) { _ = try await handlers.onPlayerMenu(PlayerMenuRequest(menu: "playlists", track: song, choose: "\" & do shell script \"x")) }
    #expect(try await handlers.onPlayerQueue(PlayerQueueRequest(track: song, playNext: "2")).map(\.title) == ["Next"])
    #expect(await calls.all == ["AppleScript []", "AppleScript [\"true\"]", "AppleScript []", "AppleScript [\"0123456789ABCDEF\"]", "JavaScript [\"2\"]"])
}

@Test func automationRefusalsExplainWhatToDo() async {
    let refused = AppleMusic(run: { _, _, _ in throw Osascript.Failure(output: "execution error: Not authorized to send Apple events to Music. (-1743)") },
                             settings: .init(load: { nil }, save: { _ in }))
    do {
        _ = try await refused.favorite(set: nil)
        Issue.record("Expected a refusal")
    } catch let error as AddOnError {
        #expect(error.message.contains("Automation"))
    } catch { Issue.record("Unexpected \(error)") }
}

@Test func choicesDecideWhatShows() throws {
    var choices = AppleMusic.Choices()
    #expect(AppleMusic.surfaces(choices).actions == [AppleMusic.star])
    #expect(AppleMusic.surfaces(choices).player == PlayerExtension(sources: [AppleMusic.music], menu: AppleMusic.playlistMenu, queue: true))
    choices.queue = false; choices.playlists = false; choices.favorites = false
    #expect(AppleMusic.surfaces(choices).actions.isEmpty)
    #expect(AppleMusic.surfaces(choices).player == nil)
    try AppleMusic.page(choices).validate()
    try AppleMusic.surfaces(AppleMusic.Choices()).player?.validate()
}
