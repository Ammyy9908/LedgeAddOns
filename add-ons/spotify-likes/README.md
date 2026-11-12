# Spotify Likes for Ledge

A self-contained Swift add-on using [LedgeKit 0.1.0](https://github.com/Ammyy9908/LedgeKit).
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
user-library-modify for library access. Keep secrets out of addon.json and source.
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
allows only the library's contains, save and remove endpoints for `spotify-library`; anything else is refused.

This package executes trusted native code with user privileges, without a sandbox. It needs Ledge with LedgeKit
0.6.0; version 1.0 received a short-lived token instead and still works on older Ledge builds. Automated tests use a
stand-in for Ledge and don't establish a live Spotify sign-in.
