# Changelog

Newest version first. Every new `version` in addon.json needs an entry here.

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
