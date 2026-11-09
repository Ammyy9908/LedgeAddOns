import LedgeKit
import SpotifyLikesCore

@main
struct SpotifyLikesMain {
    static func main() async {
        let library = SpotifyLibrary()
        await AddOnWorker.run { request in
            try await library.handle(request)
        }
    }
}
