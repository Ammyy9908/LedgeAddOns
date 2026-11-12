import Foundation
import LedgeKit
import SpotifyLikesCore

// A long-lived session. Ledge's player sends `read` and `write`; the library asks Ledge's account broker, which
// holds the Spotify sign-in. No token ever reaches this program.
@main
struct SpotifyLikesMain {
    static func main() async {
        exit(await AddOnSession.run(id: "spotify-likes", handlers: SpotifyLibrary().handlers()))
    }
}
