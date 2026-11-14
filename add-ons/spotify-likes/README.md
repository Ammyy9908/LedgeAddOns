# Spotify Likes for Ledge

A self-contained Swift add-on using [LedgeKit 0.17.0](https://github.com/Ammyy9908/LedgeKit).
The heart in Ledge adds or removes the playing Spotify track from Liked Songs.
It does not download music.

## Build this add-on

Requires macOS 14+, Swift 6, and internet access to the public LedgeKit repository.
Run from the repository root:

```sh
swift test --package-path add-ons/spotify-likes
python3 scripts/package.py spotify-likes
```

Output: `.build/addons/SpotifyLikes.ledgeaddon`. The binary targets your Mac's
architecture and is ad-hoc signed for local development.

## Install and connect

1. Open Ledge → Settings → Add-on Store → Load Add-on.
2. Choose the generated SpotifyLikes.ledgeaddon folder and approve local execution.
3. Open Add-ons → Spotify Likes.
4. Configure your Spotify Client ID and register the exact Redirect URI shown by
   Ledge in your Spotify developer app. Connect your account in the browser.
5. Play a Spotify track. Use the heart in Ledge to like or unlike it.

Ledge owns OAuth and Keychain storage. It requests user-library-read and
user-library-modify for library access, plus user-modify-playback-state for playback. Keep secrets out of addon.json and source.
Installing this package updates the existing spotify-likes add-on, if present.

## Project structure

- Package.swift pins the remote SDK. No Ledge application source is imported.
- addon.json defines identity, descriptions, capability, executable and icon.
- Assets/Icon.png supplies the package logo.
- Sources/SpotifyLikes starts the session (`AddOnSession.run`).
- Sources/SpotifyLikesCore contains Spotify request validation and library behavior.
- Tests/SpotifyLikesTests exercises read, like, unlike, invalid input and failures.
- The repository's scripts/package.py builds an installable folder from it.

Since 2.0 the add-on runs as a long-lived session. Ledge's player sends `read` and `write`; SpotifyLibrary asks
Ledge's account broker to call Spotify (`LedgeHost.request`), and Ledge adds the user's credentials itself. The
add-on never receives a token. SpotifyLibrary takes the request function as a parameter, so tests run without an
account. Errors other than Ledge's own reasons reach Ledge as a generic failure.

## Spotify API

The implementation follows Spotify's library endpoints:
[check](https://developer.spotify.com/documentation/web-api/reference/check-library-contains),
[save](https://developer.spotify.com/documentation/web-api/reference/save-library-items),
and [remove](https://developer.spotify.com/documentation/web-api/reference/remove-library-items).
It sends a track URI in the uris query parameter. Reads require exactly one boolean
response. Failed requests never report a successful like.

## Current limits

Ledge's Spotify Likes adapter owns the settings page, the Spotify sign-in and the heart in the player. The broker
allows library endpoints for `spotify-library`. The updated host additionally allows catalog search with `spotify-search` and single-track playback with `spotify-playback`; older hosts refuse these new requests.

This package executes trusted native code with user privileges, without a sandbox. It needs Ledge with LedgeKit
0.17.0 and the search/playback host update for these tools; version 1.0 received a short-lived token instead and still works on older Ledge builds. Automated tests use a
stand-in for Ledge and don't establish a live Spotify sign-in.

## Search and play from AI apps (2.2.0)

Update Ledge and load the updated add-on, approving its new search/playback capabilities.
Reconnect Spotify from the add-on settings to grant playback permission, then enable
Spotify Likes under Settings → AI apps for your approved agent.

- `spotify-likes__search_songs(query)` returns up to five catalog songs with title,
  artists, album and track URI. Empty matches return an empty songs array; search never plays music.
- `spotify-likes__play_song(uri)` plays the selected track on your **active Spotify device**,
  which can be a phone or speaker rather than this Mac. It replaces current playback.

For example: “Search Spotify for Yellow by Coldplay and play the matching song.”
The agent should resolve ambiguous matches before calling play_song. Playback needs
Spotify Premium and an active device: open Spotify and start playback there first.
Errors explain expired sign-in, missing access, unavailable devices and rate limits;
an accepted API request is not a confirmation that audio is audible.

API references: [Search](https://developer.spotify.com/documentation/web-api/reference/search)
and [Start playback](https://developer.spotify.com/documentation/web-api/reference/start-a-users-playback).


## Device switching (2.3.0)

- `list_devices()` returns Spotify Connect device IDs, names, types, active status,
  and restrictions. A null ID cannot be used for transfer. Some devices may not be
  visible until Spotify is opened on them.
- `transfer_playback(device_id, play?)` moves the current playback to one listed
  device. Omit `play` (or use false) to preserve playing/paused state; true starts
  playback. It refreshes the device list before transferring and rejects absent
  or restricted destinations. It returns `accepted` separately from
  `active_confirmed`; API acceptance alone does not prove audio is audible.

The updated host must recognize and approve the separate `spotify-devices`
capability. Existing playback grants do not automatically permit device access.
Load this package and approve that capability in Ledge, then reconnect Spotify
in the add-on settings to grant `user-read-playback-state` alongside the existing
`user-modify-playback-state`. Transfers require Spotify Premium. Use exact IDs
from a fresh list, and ask which device when names are ambiguous.

Examples: “List my Spotify devices” and “Move my Spotify playback to my iPhone.”

References: [Available devices](https://developer.spotify.com/documentation/web-api/reference/get-a-users-available-devices)
and [Transfer playback](https://developer.spotify.com/documentation/web-api/reference/transfer-a-users-playback).


### Transfer playback verification (2.3.1)

Transfer now reads the source playing state before moving devices. If the selected
destination becomes active but remains paused when playback was requested, the
add-on sends one explicit resume request with that destination's device_id. It
then checks Spotify's playback state, returning playing, requested_playing, and
playback_confirmed separately from active_confirmed. Unconfirmed playback must
not be described as playing. This requires the updated Ledge host; existing device
and playback grants and OAuth scopes are reused.


### Preserve position (2.3.2)

The source track URI and progress_ms are captured before transfer. After playback
is resumed on the destination, a device-targeted seek restores the saved position
if the same song restarted. Progress is checked within a 2.5-second tolerance;
position_confirmed is separate from playback_confirmed and source_position_ms
records the captured point. Missing source metadata returns an unknown position
confirmation; a changed song is never sought using the previous song's progress.
Requires the updated host's seek endpoint, using the existing device/playback grants.
