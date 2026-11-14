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
- `search_songs` queries Apple's public song-store search endpoint for the selected storefront and returns up
  to ten catalog matches, including songs that are not in the local library. It returns catalog IDs separately from
  Music's persistent library IDs. The storefront defaults to the Mac's region; pass a two-letter `storefront` to
  search another country.
- `play_song` accepts a catalog ID from the most recent `search_songs` call, opens Apple's returned song link
  in Music, and reports success only after Music shows that exact title and artist playing. The person must have
  Music signed in and the selected result available in that storefront.
- `search_library` remains available for songs already in the local library. Use its IDs with
  `add_song_to_playlist`; `list_playlists` and `list_playlist_songs` provide the playlist IDs and contents.
  `create_playlist` makes an empty playlist. Ledge asks before playlist mutations.
- Catalog search uses Apple's public iTunes Search API for metadata and Music store links; playback is handed to the
  Music app. It does not retrieve personalized recommendations or listening history, which require a separate
  MusicKit authorization flow.
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
