# Apple Music Controls — developer preview

Apple Music in Ledge's players: the favourite star, Add to Playlist in the ••• menu, and Music's own Playing Next,
with a song moved to play next when it's clicked. Each can be turned off on the add-on's settings page.

Test with `swift test --package-path add-ons/apple-music-queue`.

## How it works

The add-on is an ordinary session (LedgeKit 0.8.0): the star is a player action, the menu and Playing Next a player
extension. It runs fixed `osascript` programs (`Sources/AppleMusicCore/Scripts.swift`); anything that varies, such
as a playlist or song id, is passed as an argument, never written into a script.

- Favourites and playlists are AppleScript. macOS asks once to let Ledge control Music.
- Playing Next uses MediaRemote's `MRNowPlayingController`, a private interface macOS answers only for its own
  programs (others get error 3). `osascript` is one, so the queue program is JavaScript for Automation run by it.
  It asks for 20 items, checks that Music is the source, finds the playing song by the id in the same answer and
  returns up to 12 after it. It never falls back to playlist order. Play Next sends command 130 only when Music
  lists it as enabled and the song is still upcoming, and returns the queue once Music confirms the move.

Versions up to 0.3.1 loaded a native module into `/usr/bin/perl` instead, an approach informed by
ungive/mediaremote-adapter (BSD-3-Clause, https://github.com/ungive/mediaremote-adapter); no upstream code was used.

## Limits

Private interfaces can change with macOS updates; Playing Next then says it isn't available rather than guessing.
Tooling in a sandbox gets error 35 even while Music plays; test in the ordinary logged-in session, as Ledge runs.
