import Foundation
import Testing
import LedgeKit
import SpotifyLikesCore

private let uri = "spotify:track:4uLU6hMCjMI75M1A2tKUQC"

@Test func searchesWithoutPlayingAndReturnsSongIdentity() async throws {
    let songs = SpotifySongs { method, path, query, body in
        #expect(method == "GET")
        #expect(path == "/v1/search")
        #expect(query == ["q": "Yellow & Coldplay", "type": "track", "limit": "5"])
        #expect(body == nil)
        return HostResponse(status: 200, body: .object(["tracks": .object(["items": .array([
            .object(["uri": .string(uri), "name": .string("Yellow"), "artists": .array([.object(["name": .string("Coldplay")])]),
                     "album": .object(["name": .string("Parachutes")]), "is_playable": .bool(true)])
        ])])]))
    }
    let result = try await songs.call(ToolCall(tool: "search_songs", arguments: ["query": .string(" Yellow & Coldplay ")]))
    #expect(result == .json(.object(["songs": .array([.object([
        "uri": .string(uri), "title": .string("Yellow"), "artists": .array([.string("Coldplay")]),
        "album": .string("Parachutes"), "playable": .bool(true)
    ])])])))
}

@Test func playsOnlyTheSelectedTrack() async throws {
    let songs = SpotifySongs { method, path, query, body in
        #expect(method == "PUT")
        #expect(path == "/v1/me/player/play")
        #expect(query.isEmpty)
        #expect(body == .object(["uris": .array([.string(uri)])]))
        return HostResponse(status: 204, body: nil)
    }
    #expect(try await songs.call(ToolCall(tool: "play_song", arguments: ["uri": .string(uri)])) == .text("Spotify accepted the playback request on your active device."))
}

@Test func invalidSongRequestsNeverReachTheBroker() async {
    let songs = SpotifySongs { _, _, _, _ in
        Issue.record("Invalid request reached Spotify")
        return HostResponse(status: 204, body: nil)
    }
    for call in [ToolCall(tool: "search_songs", arguments: ["query": .string("  ")]),
                 ToolCall(tool: "play_song", arguments: ["uri": .string("https://example.com")]),
                 ToolCall(tool: "play_song", arguments: ["uri": .string("spotify:album:4uLU6hMCjMI75M1A2tKUQC")]),
                 ToolCall(tool: "play_song"), ToolCall(tool: "unknown")] {
        await #expect(throws: (any Error).self) { try await songs.call(call) }
    }
}

@Test func emptySearchAndMalformedResponseAreDifferent() async throws {
    let empty = SpotifySongs { _, _, _, _ in
        HostResponse(status: 200, body: .object(["tracks": .object(["items": .array([])])]))
    }
    let call = ToolCall(tool: "search_songs", arguments: ["query": .string("missing song")])
    #expect(try await empty.call(call) == .json(.object(["songs": .array([])])))
    let malformed = SpotifySongs { _, _, _, _ in HostResponse(status: 200, body: nil) }
    await #expect(throws: AddOnError.self) { try await malformed.call(call) }
}

@Test func spotifyFailuresDoNotReportPlaybackSuccess() async {
    for status in [401, 403, 404, 429, 500] {
        let songs = SpotifySongs { _, _, _, _ in HostResponse(status: status, body: nil) }
        await #expect(throws: AddOnError.self) {
            try await songs.call(ToolCall(tool: "play_song", arguments: ["uri": .string(uri)]))
        }
    }
    let denied = SpotifySongs { _, _, _, _ in throw LedgeHostError("Playback permission is off.") }
    do {
        _ = try await denied.call(ToolCall(tool: "play_song", arguments: ["uri": .string(uri)]))
        Issue.record("Expected permission refusal")
    } catch let error as AddOnError { #expect(error.message == "Playback permission is off.") }
    catch { Issue.record("Unexpected error") }
}
