import Foundation
import LedgeKit
import AppleMusicCore

// A long-lived session: the star, Add to Playlist and Playing Next in Ledge's players while Apple Music plays.
exit(await AddOnSession.run(id: "apple-music-queue", handlers: AppleMusic().handlers()))
