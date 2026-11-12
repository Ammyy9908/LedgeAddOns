# Changelog

Newest version first. Every new `version` in addon.json needs an entry here.

## 2.0.0

- Never receives a Spotify token. Ledge keeps the sign-in and calls Spotify's Liked Songs endpoints for the add-on
  through its account broker, which allows only those endpoints.
- Runs as one long-lived session instead of starting for every like. Needs a Ledge with LedgeKit 0.6.0.

## 1.0.0

- First release: the heart in Ledge's player adds the playing Spotify track to Liked Songs, or removes it.
