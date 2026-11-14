# Changelog

Newest version first. Every new `version` in addon.json needs an entry here.

## 0.15.0

- Removes AI song search and direct playback tools. Song search and starting playback remain in Apple Music; queue, favorite, shuffle, and playlist controls remain available.

## 0.14.0

- Adds an AI tool to favorite or unfavorite the currently playing song using the same Music current-track action as the player star, including streamed songs not yet in the library.

## 0.13.0

- Reports Play Next as successful when the selected song has already become the current song or Music accepted the command before the queue snapshot updated.
- Includes the resulting current or queued state in the AI tool response to avoid false failure messages.

## 0.12.0

- Removes Ledge's confirmation gate from reversible music controls, including queue, shuffle, favorite, playlist-add and playlist-create actions.
- Treats a completed Play Next command as accepted when MediaRemote's queue snapshot is stale, avoiding a false failure after Music moves the track.

## 0.11.0

- Adds AI tools to control shuffle, list Playing Next, add a library song to play next, move an already queued song to the front, and favorite or unfavorite a library song.
- Queue, shuffle, favorite and playlist changes use exact IDs or values.

## 0.10.0

- Removes catalog playback because opening Apple Music song URLs does not reliably start streamed catalog tracks without a MusicKit-enabled app identity and user authorization.
- Keeps catalog search for metadata and local-library playback, playlist, and player controls.

## 0.9.1

- Builds a direct Apple Music song URL from the catalog track ID instead of opening Apple's album URL with a track query parameter, which could leave Music focused on the album item.
- Recognizes Music's numeric catalog-ID metadata and starts that exact selected item.
- Confirms playback only after the same item remains active, Music reports it playing, and its playback position advances.

## 0.7.0

- Searches Apple's storefront song catalog instead of limiting `search_songs` to tracks already in the local library.
- Plays a selected catalog result by opening its Apple song link in Music and confirming the requested title and artist are playing.
- Keeps local-library search separate as `search_library` for playlist edits; adds `play_library_song` for local-only playback.
- Documents storefront selection and the Music sign-in/availability requirement.

## 0.6.0

- Adds `list_playlist_songs` AI tool: returns up to 50 songs in a playlist with IDs, titles, artists and albums.

## 0.5.0

- Adds AI tools to inspect the playing song, search the local library, play a selected result, list playlists, add a selected library song to a playlist, and create playlists.
- Search and playback are separate; identifiers must come from the matching search/list tools. Playlist changes and creation are marked for confirmation.
- Updates the LedgeKit requirement to 0.17.0 and lists the `ai-tool` surface.

## 0.4.0

- Runs as one long-lived session, like other add-ons. The native module and Ledge's `perl` loader are gone:
  Playing Next is read through `osascript`, which macOS lets use Music's queue, and the library actions are
  AppleScript run by the add-on.
- The star is a player action, Add to Playlist and Playing Next a player extension, and the settings page is the
  add-on's own (LedgeKit 0.8.0). Ledge toggles shuffle and repeat itself now.
- Add to Playlist lists only playlists a song can be added to (not smart playlists), by their persistent id.

## 0.3.1

- First release in the Store, as a developer preview: favorite, add to playlist, shuffle, repeat and Playing Next for Apple Music in Ledge's player.
