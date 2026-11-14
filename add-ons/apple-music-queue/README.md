# Apple Music Controls — developer preview

Apple Music in Ledge's players: the favourite star, Add to Playlist in the ••• menu, and Music's own Playing Next,
with a song moved to play next when it's clicked. It also exposes Apple Music library tools to AI apps that the
person has enabled in Ledge. Player controls can be turned off on the add-on's settings page.

Test with `swift test --package-path add-ons/apple-music-queue`.

## How it works

The add-on is an ordinary session (LedgeKit 0.17.0): the star is a player action, the menu and Playing Next a player
extension, and AI tools expose read-only lookup plus explicit playback and playlist operations. It runs fixed
`osascript` programs (`Sources/AppleMusicCore/Scripts.swift`); anything that varies, such as a playlist, song id,
search text or playlist name, is passed as an argument, never written into a script.

- Favourites and playlists are AppleScript. macOS asks once to let Ledge control Music.
- `now_playing` reads the current song and player state. `search_songs` searches only the local Music library and
  returns up to ten matches. `play_song` accepts an exact ID from that search, and does not search or play in one
  step.
- `list_playlists` returns editable, non-smart playlists. `add_song_to_playlist` accepts IDs returned by the
  search and playlist tools. `create_playlist` creates an empty playlist. Ledge marks both playlist mutations for
  approval before the add-on runs them.
- The AI tools do not search the Apple Music catalog, retrieve personalized recommendations or query listening
  history. Those require a separate MusicKit authorization flow; this add-on uses local AppleScript Automation.
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
