# Spotify Likes for Ledge

A self-contained Swift add-on using [LedgeKit 0.1.0](https://github.com/Ammyy9908/LedgeKit).
The heart in Ledge adds or removes the playing Spotify track from Liked Songs.
It does not download music.

## Build this add-on

Requires macOS 14+, Swift 6, and SSH access to the private LedgeKit repository.
Run from this folder, even if you copy it outside the Ledge checkout:

```sh
swift test
zsh Scripts/package.sh
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
- Sources/SpotifyLikes contains the small SDK worker entry point.
- Sources/SpotifyLikesCore contains Spotify request validation and library behavior.
- Tests/SpotifyLikesTests exercises read, like, unlike, invalid input and failures.
- Scripts/package.sh builds an installable folder without the parent repository.

LedgeKit reads one JSON request from stdin, calls SpotifyLibrary, and writes one
response to stdout. SpotifyLibrary uses an injectable HTTP transport so tests run
without tokens or live account changes. Exceptions are redacted by the SDK worker.

## Spotify API

The implementation follows Spotify's library endpoints:
[check](https://developer.spotify.com/documentation/web-api/reference/check-library-contains),
[save](https://developer.spotify.com/documentation/web-api/reference/save-library-items),
and [remove](https://developer.spotify.com/documentation/web-api/reference/remove-library-items).
It sends a track URI in the uris query parameter. Reads require exactly one boolean
response. Failed requests never report a successful like.

## Current limits

Ledge's current host explicitly recognizes the spotify-likes ID and SpotifyLikes
executable. Keep these names until generic add-on registration ships. The host
owns settings and heart rendering; this SDK version cannot register arbitrary UI.

This package executes trusted native code with user privileges, without a sandbox.
Ledge supplies a short-lived access token through stdin. Store publishing,
notarized distribution and automatic updates remain future work. Automated tests
do not establish successful live OAuth or account mutation.
