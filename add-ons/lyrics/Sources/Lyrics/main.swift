import Foundation
import LedgeKit
import LyricsCore

// Lyrics: answers Ledge's `lyrics` request for the playing song, which Ledge shows in the notch's player, the menu
// bar player and on the lock screen. Ledge draws them and keeps them in time; this add-on only finds them.

var handlers = AddOnHandlers()
handlers.on("lyrics") { (request: LyricsRequest) async throws -> [LyricLine] in
    do {
        return try await LRCLib.lines(title: request.title, artist: request.artist)
    } catch {
        throw AddOnError("Lyrics didn’t load. Check your connection.")
    }
}
exit(await AddOnSession.run(id: "lyrics", handlers: handlers))
