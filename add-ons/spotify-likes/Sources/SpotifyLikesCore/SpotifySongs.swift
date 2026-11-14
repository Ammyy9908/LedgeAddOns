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
        AddOnTool("list_devices", title: "List Spotify devices",
                  summary: "Lists available Spotify Connect devices, including IDs, names, types and active/restricted status. Open Spotify on a missing device and try again; listing never changes playback."),
        AddOnTool("transfer_playback", title: "Move Spotify playback",
                  summary: "Moves the current playback to one device selected from list_devices. Use only when asked to switch devices; resolve ambiguous names first. Requires Premium. Preserves playing/paused state unless play=true is requested.",
                  arguments: [.init("device_id", summary: "Exact device ID from list_devices.", kind: .text(maximumLength: 256)),
                              .init("play", summary: "True starts playback after transfer; false or omitted preserves the current playing/paused state.", kind: .boolean, required: false)]),
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
        case "list_devices":
            return .json(.object(["devices": .array(try await devices())]))
        case "transfer_playback":
            guard let id = call.text("device_id"), Self.validDeviceID(id) else { throw AddOnError("Choose a device ID from list_devices.") }
            let available = try await devices()
            guard let selected = available.first(where: { device in
                guard case .object(let fields) = device else { return false }
                return fields["id"] == .string(id)
            }), case .object(let fields) = selected else {
                throw AddOnError("That Spotify device is no longer available. Open Spotify on it and list devices again.")
            }
            guard fields["is_restricted"] == .bool(false) else { throw AddOnError("Spotify does not allow playback control on that device.") }
            _ = try await send("PUT", "/v1/me/player", [:], .object([
                "device_ids": .array([.string(id)]), "play": .bool(call.boolean("play") ?? false)
            ]))
            // A 204 is acceptance, not confirmation that the destination is active.
            var confirmed = false
            for attempt in 0..<3 {
                if attempt > 0 { try await Task.sleep(for: .milliseconds(400)) }
                guard let current = try? await devices() else { break }
                confirmed = current.contains { device in
                    guard case .object(let value) = device else { return false }
                    return value["id"] == .string(id) && value["is_active"] == .bool(true)
                }
                if confirmed { break }
            }
            return .json(.object(["device_id": .string(id), "name": fields["name"] ?? .string("Spotify device"),
                                  "accepted": .bool(true), "active_confirmed": .bool(confirmed)]))
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

    private static func validDeviceID(_ id: String) -> Bool {
        !id.isEmpty && id.count <= 256 && id.unicodeScalars.allSatisfy { !CharacterSet.controlCharacters.contains($0) }
    }

    private func devices() async throws -> [JSONValue] {
        let response = try await send("GET", "/v1/me/player/devices", [:])
        guard case .object(let root)? = response.body, case .array(let items)? = root["devices"] else {
            throw AddOnError("Spotify returned an invalid device list.")
        }
        return try items.prefix(100).map { item in
            guard case .object(let fields) = item, case .string(let name)? = fields["name"],
                  case .string(let type)? = fields["type"], case .bool(let active)? = fields["is_active"],
                  case .bool(let restricted)? = fields["is_restricted"] else {
                throw AddOnError("Spotify returned an invalid device.")
            }
            let id: JSONValue
            if case .string(let value)? = fields["id"], Self.validDeviceID(value) { id = .string(value) }
            else { id = .null }
            return .object(["id": id, "name": .string(String(name.prefix(300))), "type": .string(String(type.prefix(100))),
                            "is_active": .bool(active), "is_restricted": .bool(restricted)])
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
        case 403 where path == "/v1/me/player/devices" || path == "/v1/me/player":
            throw AddOnError("Reconnect Spotify in Ledge to grant device access. Transfers require Premium and a controllable Spotify Connect device.")
        case 404 where path == "/v1/me/player": throw AddOnError("That Spotify device is unavailable. Open Spotify on it and list devices again.")
        case 403: throw AddOnError("Spotify refused access. Playback requires Premium; reconnect Spotify in Ledge to grant playback permission. Your Spotify developer app must also allow this account.")
        case 404 where path == "/v1/me/player/play": throw AddOnError("No active Spotify device was available. Open Spotify and start playback on your desired device, then try again.")
        case 429: throw AddOnError("Spotify is rate limiting requests. Wait before trying again.")
        default: throw AddOnError("Spotify refused the request (\(response.status)).")
        }
    }
}
