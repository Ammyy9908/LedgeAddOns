# Lyrics

The words of the song that's playing, in Ledge's players and on the lock screen. Press **L** in the notch's player,
or the lyrics button in the menu bar player; with the lock screen player on, they also show under it while the Mac
is locked (Settings, Lock Screen, Lyrics).

Ledge draws the lyrics and keeps them in time with the music; this add-on finds them. They come from
[LRCLIB](https://lrclib.net), a free, open database of lyrics. Timed lyrics scroll line by line; a song that only has
untimed lyrics shows them as plain text. Only the song's title and artist are sent to LRCLIB.

## How Ledge asks

The manifest declares the `lyrics` surface. Ledge sends the add-on that has it a `lyrics` request with the playing
song, `{"title": "…", "artist": "…"}`, and gets back its lines, `[{"time": 12.5, "text": "…"}]`, sorted, where
`time` is when the line starts in seconds, or -1 for untimed lyrics. An empty list means there are none for the
song; an `AddOnError` means they didn't load.
