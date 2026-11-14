import Foundation
import LedgeKit

/// Liked Songs through Ledge's account broker. This add-on never sees a token: it asks Ledge to call one of the
/// library endpoints Ledge allows for `spotify-library`, and Ledge adds the user's credentials itself.
public struct SpotifyLibrary: Sendable {
    /// Sends a request through Ledge: method, path and query in, status and body out.
    public typealias Requester = @Sendable (_ method: String, _ path: String, _ query: [String: String]) async throws -> HostResponse
    private let requester: Requester

    public init(requester: @escaping Requester = { method, path, query in
        try await LedgeHost.request(provider: "spotify", method: method, path: path, query: query)
    }) {
        self.requester = requester
    }

    public struct LikeRequest: Codable, Sendable {
        public let trackID: String
        public let liked: Bool?
        public init(trackID: String, liked: Bool? = nil) {
            self.trackID = trackID
            self.liked = liked
        }
    }

    /// Whether the track is in Liked Songs.
    public func isLiked(_ trackID: String) async throws -> Bool {
        let response = try await send("GET", "/v1/me/library/contains", trackID: trackID)
        guard case .array(let values)? = response.body, values.count == 1, case .bool(let liked) = values[0] else {
            throw AddOnError("Spotify answered in a way this add-on doesn't understand.")
        }
        return liked
    }

    /// Adds the track to Liked Songs, or removes it. Returns the new state.
    public func setLiked(_ liked: Bool, trackID: String) async throws -> Bool {
        _ = try await send(liked ? "PUT" : "DELETE", "/v1/me/library", trackID: trackID)
        return liked
    }

    /// The heart in Ledge's players while Spotify plays.
    public static let heart = PlayerAction("like", label: "Like", symbol: "heart", selectedSymbol: "heart.fill",
                                           sources: ["com.spotify.client"])

    /// The add-on's settings page: Ledge's Spotify sign-in, which stays in Ledge, and what the heart does.
    public static let page = SettingsPage([
        SettingsSection("account", title: "Spotify Account",
                        footer: "Signed in, the heart in Ledge’s players adds Spotify songs to Liked Songs or takes them out. Ledge keeps the sign-in in your Keychain; this add-on never sees it.",
                        rows: [.account("spotify", "Spotify", provider: "spotify")])
    ])

    /// The session's handlers: the heart as a player action, plus `read` and `write` for Ledge builds from before
    /// player actions.
    public func handlers() -> AddOnHandlers {
        var handlers = AddOnHandlers()
        handlers.activate = {
            AddOnSession.show(tools: SpotifySongs.tools)
            AddOnSession.show(Self.page)
            AddOnSession.show(playerActions: [Self.heart])
        }
        handlers.onTool = { try await SpotifySongs().call($0) }
        handlers.onPlayerAction = { request in
            guard request.action == Self.heart.id, request.track.source == "com.spotify.client" else { return nil }
            // Local files and ads have no track id; there's nothing to like.
            guard let trackID = request.track.id else { return nil }
            if let liked = request.set { return try await setLiked(liked, trackID: trackID) }
            return try await isLiked(trackID)
        }
        handlers.on("read") { (request: LikeRequest) in try await isLiked(request.trackID) }
        handlers.on("write") { (request: LikeRequest) in
            guard let liked = request.liked else { throw AddOnError("Say whether to like or unlike the song.") }
            return try await setLiked(liked, trackID: request.trackID)
        }
        return handlers
    }

    private func send(_ method: String, _ path: String, trackID: String) async throws -> HostResponse {
        guard !trackID.isEmpty, trackID.count <= 128, trackID.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else {
            throw AddOnError("That isn't a Spotify track.")
        }
        let response: HostResponse
        do {
            response = try await requester(method, path, ["uris": "spotify:track:" + trackID])
        } catch let error as LedgeHostError {
            // Ledge's reasons are written for people ("Spotify isn't connected…"), so pass them on.
            throw AddOnError(error.message)
        }
        guard (200..<300).contains(response.status) else { throw AddOnError("Spotify refused the request (\(response.status)).") }
        return response
    }
}
