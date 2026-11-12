# Changelog

Newest version first. Every new `version` in addon.json needs an entry here.

## 0.4.0

- Runs as one long-lived session, like other add-ons. The native module and Ledge's `perl` loader are gone:
  Playing Next is read through `osascript`, which macOS lets use Music's queue, and the library actions are
  AppleScript run by the add-on.
- The star is a player action, Add to Playlist and Playing Next a player extension, and the settings page is the
  add-on's own (LedgeKit 0.8.0). Ledge toggles shuffle and repeat itself now.
- Add to Playlist lists only playlists a song can be added to (not smart playlists), by their persistent id.

## 0.3.1

- First release in the Store, as a developer preview: favorite, add to playlist, shuffle, repeat and Playing Next for Apple Music in Ledge's player.
