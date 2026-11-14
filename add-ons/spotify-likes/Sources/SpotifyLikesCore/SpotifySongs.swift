import Foundation
import LedgeKit

/// Catalog search and explicit track playback through the credential-free host broker.
/// Search never starts playback. Playback targets the user's active Spotify device.
public struct SpotifySongs: Sendable {
    public typealias Requester = @Sendable (String, String, [String: String], JSONValue?) async throws -> HostResponse
    private let request: Requester

    public init(request: @escaping Requester = { method, path, query, body in
        try await LedgeHost.request(provider: "spotify", method: method, path: path, query: query, body: body)
    }) { self.request = request }

    public static let tools: [AddOnTool] = [
        AddOnTool("search_songs", title: "Search Spotify songs",
                  summary: "Searches Spotify's catalog by song title, artist, or both. Returns up to five matches with title, artists, album and URI. Does not play anything. Choose the intended match before calling play_song.",
                  arguments: [.init("query", summary: "Song title and optionally artist, e.g. track:Yellow artist:Coldplay.", kind: .text(maximumLength: 300))]),
        AddOnTool("play_song", title: "Play a Spotify song",
                  summary: "Starts the selected search result on the user's active Spotify device, replacing current playback. Requires Spotify Premium and playback permission. Use only when the user asked to play music.",
                  arguments: [.init("uri", summary: "Exact spotify:track: URI from search_songs.", kind: .text(maximumLength: 64))])
    ]

    public func call(_ call: ToolCall) async throws -> ToolResult {
        guard let tool = Self.tools.first(where: { $0.name == call.tool }) else { throw AddOnError("Unknown Spotify tool.") }
        _ = try tool.check(.object(call.arguments))
        switch call.tool {
        case "search_songs":
            let query = (call.text("query") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty else { throw AddOnError("Enter a song title or artist to search.") }
            let response = try await send("GET", "/v1/search", ["q": query, "type": "track", "limit": "5"])
            guard case .object(let root)? = response.body, case .object(let tracks)? = root["tracks"],
                  case .array(let items)? = tracks["items"] else { throw AddOnError("Spotify returned an invalid search response.") }
            var songs: [JSONValue] = []
            for item in items.prefix(5) {
                guard case .object(let track) = item, case .string(let uri)? = track["uri"], Self.validURI(uri),
                      case .string(let title)? = track["name"], case .array(let artists)? = track["artists"],
                      case .object(let album)? = track["album"], case .string(let albumName)? = album["name"] else {
                    throw AddOnError("Spotify returned an invalid song.")
                }
                let names = artists.prefix(10).compactMap { artist -> JSONValue? in
                    guard case .object(let artist) = artist, case .string(let name)? = artist["name"] else { return nil }
                    return .string(String(name.prefix(300)))
                }
                var song: [String: JSONValue] = ["uri": .string(uri), "title": .string(String(title.prefix(300))),
                    "artists": .array(names), "album": .string(String(albumName.prefix(300)))]
                if case .bool(let playable)? = track["is_playable"] { song["playable"] = .bool(playable) }
                songs.append(.object(song))
            }
            return .json(.object(["songs": .array(songs)]))
        case "play_song":
            guard let uri = call.text("uri"), Self.validURI(uri) else { throw AddOnError("Use a Spotify track URI from search_songs.") }
            _ = try await send("PUT", "/v1/me/player/play", [:], .object(["uris": .array([.string(uri)])]))
            return .text("Spotify accepted the playback request on your active device.")
        default: throw AddOnError("Unknown Spotify tool.")
        }
    }

    private static func validURI(_ uri: String) -> Bool {
        guard uri.hasPrefix("spotify:track:") else { return false }
        let id = uri.dropFirst("spotify:track:".count)
        return id.count == 22 && id.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
    }

    private func send(_ method: String, _ path: String, _ query: [String: String], _ body: JSONValue? = nil) async throws -> HostResponse {
        let response: HostResponse
        do { response = try await request(method, path, query, body) }
        catch let error as LedgeHostError { throw AddOnError(error.message) }
        switch response.status {
        case 200..<300: return response
        case 401: throw AddOnError("Reconnect Spotify in Ledge's Spotify Likes settings.")
        case 403: throw AddOnError("Spotify refused access. Playback requires Premium; reconnect Spotify in Ledge to grant playback permission. Your Spotify developer app must also allow this account.")
        case 404 where path == "/v1/me/player/play": throw AddOnError("No active Spotify device was available. Open Spotify and start playback on your desired device, then try again.")
        case 429: throw AddOnError("Spotify is rate limiting requests. Wait before trying again.")
        default: throw AddOnError("Spotify refused the request (\(response.status)).")
        }
    }
}
