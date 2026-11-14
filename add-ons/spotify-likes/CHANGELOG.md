# Changelog

Newest version first. Every new `version` in addon.json needs an entry here.

## 2.3.2

- Capture the source song URI and position before transferring.
- Restore the captured position on the destination when Spotify restarts the song, and verify progress separately from playback.
- Never seek if the destination changed songs; report unknown position when source progress is unavailable.
- Requires the updated Ledge host's scoped seek endpoint.

## 2.3.1

- Preserve the source playback state before transferring devices.
- Resume a paused destination explicitly by device ID when playback was requested.
- Verify both the destination and playing state; active alone is no longer reported as playback confirmation.
- Requires the updated Ledge host with targeted resume and playback-state broker endpoints.

## 2.3.0

- Add AI tools to list Spotify Connect devices and transfer current playback to a selected device.
- Preserve playing/paused state by default and report whether the destination becomes active.
- Reject unavailable or restricted destinations before transferring.
- Require the host's new spotify-devices grant and reconnecting Spotify for device discovery permission.

## 2.2.0

- Add AI tools to search Spotify songs and play a selected URI on the active device.
- Require LedgeKit 0.17.0 and new host search/playback grants. Reconnect Spotify for playback permission.
- Keep existing heart and Liked Songs behavior.

## 2.1.0

- The heart is now the add-on's own: it describes it as a player action, and Ledge draws it in the notch, menu bar,
  floating and lock screen players.
- Its settings page comes from the add-on, with Ledge's Spotify sign-in on it. Needs a Ledge with LedgeKit 0.7.0.

## 2.0.0

- Never receives a Spotify token. Ledge keeps the sign-in and calls Spotify's Liked Songs endpoints for the add-on
  through its account broker, which allows only those endpoints.
- Runs as one long-lived session instead of starting for every like. Needs a Ledge with LedgeKit 0.6.0.

## 1.0.0

- First release: the heart in Ledge's player adds the playing Spotify track to Liked Songs, or removes it.
