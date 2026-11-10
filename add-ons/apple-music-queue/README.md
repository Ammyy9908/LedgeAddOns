# Apple Music Controls — developer preview

Install from the Add-on Store. The updated host routes the player's favorite,
playlist, shuffle, repeat and Playing Next requests to this package when Apple
Music is active. Remove it from the Store's Installed view.

Test with `swift test --package-path add-ons/apple-music-queue`. The catalog build
(`python3 scripts/build.py`) ships the `QueueBridge` dynamic library
(`libQueueBridge.dylib`) under the manifest's executable name, `AppleMusicQueue`.
The executable target is a direct-request diagnostic and is not published.

## Runtime

Version 0.3.0 packages a signed native dynamic module as `AppleMusicQueue`.
This is an adapter-specific runtime: the host invokes `/usr/bin/perl` with a fixed
DynaLoader script and passes the module's absolute path as a separate argument.
The module exports `LedgeQueueMain`, validates one stdin request, writes JSON and
exits. It does not return through the Perl XS ABI. It is not directly executable
and requires the updated Ledge host; this is not a generic LedgeKit runtime format.
The standalone Swift executable remains a direct-request diagnostic only.

The approach was informed by ungive/mediaremote-adapter (BSD-3-Clause):
https://github.com/ungive/mediaremote-adapter
No upstream source files are bundled. Ledge uses its own bounded loader and queue
request. Native add-on code runs with user access and is not sandboxed.

The module configures MRNowPlayingController to request a queue range of 20 items,
verifies the source is com.apple.Music, and matches the current content-item ID
from the same response. It returns only following items, capped at 12. It never
substitutes playlist order. Metadata isCurrentPlaying was false for every item in
the live response, so it is deliberately not used to locate the current song.

## Validation and limits

On the development Mac, direct requests returned MediaRemote error 3. The
interpreter-loaded module returned a real Apple Music queue, verified on
2026-11-10 with 11 items including the current song; subsequent reads reflected
playback advancing. The packaged module returned 10 upcoming titles/artists.
Sandboxed tooling returned error 35 despite playback being active; testing must
use the ordinary logged-in desktop session, as the Ledge app does.

This remains private-API integration. Shuffle, explicit Play Next edits, repeat,
AutoPlay transitions and other macOS versions need further live verification.
Catalog publication is separate from local installation.

## Protocol

One JSON request on stdin (at most 4096 bytes, closed after writing):
`{"protocolVersion":1,"action":"readQueue"}`

Response: `protocolVersion`, `status` (`available` or `unavailable`), `message`,
and `entries` containing `title` and `artist`. At most 12 entries are returned.
The host bounds output to 64 KiB and terminates requests after seven seconds.
The module stops waiting after five seconds. Exceptions and missing selectors
produce an unavailable response. No tokens or artwork are sent.

This provider-specific preview uses LedgeKit 0.2.0 packaging conventions. Its
queue protocol and module loader are not public SDK contracts.

### Play Next
The normal player offers a trailing Play Next button for upcoming entries. The adapter validates the stable queue item ID against a fresh Apple Music response and moves it after the current song using native queue reordering. It confirms the new order before reporting success. The first upcoming item is already next and has no reorder action. Unsupported or stale requests fail without falling back to a different song.


## Controls and migration

Version 0.3.0 retains the package ID `apple-music-queue` and executable name so existing queue installations can be upgraded. It adds the host capability `apple-music-controls`. Legacy queue-only packages still work, but do not unlock favorites or playlists.

The installed package owns Apple Music scripting for `readFavorite`, `setFavorite` (boolean `value`), `playlists`, and `addToPlaylist` (playlist `name`). Responses use the same envelope; controls return boolean `value`, and playlist discovery returns `playlists`. Automation permission is required. Queue reads/reordering remain in the native MediaRemote adapter.

Settings → Add-ons → Apple Music Controls independently enables queue, favorites and playlist actions. Removing the package disables those features. Generic playback, seeking and output selection remain in Ledge. These are host-specific capabilities, not yet generic LedgeKit SDK contracts.

The settings currently offer feature toggles; configurable button slots, quality badges and Discord presence are not implemented.
