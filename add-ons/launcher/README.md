# Launcher

A search bar for the Mac in Ledge. Press the launcher shortcut (⌥Space unless it's changed on the add-on's page in
Settings) and type:

- an app, like `safari` or `vsc` for Visual Studio Code
- a page of System Settings, like `wifi`, `displays` or `battery`
- a file or folder in the home folder, from Spotlight's index
- a sum, `1,250 * 1.2`, `80 + 15%`, `sqrt 2`, or a tip, `18% tip on 62.50`
- a conversion, `10 km in miles`, `212 f to c`, `2 gb in mb`
- a time, `time in tokyo`, `3pm london in nyc`, `9:30 in delhi`

Return opens the selected row, or copies an answer; ⌘C copies any row. The last row searches the web. Everything is
found on this Mac and nothing is sent anywhere unless that web row is picked.

## How Ledge asks

The manifest declares the `launcher` surface. Ledge owns the panel, its shortcut and what Return does; as the person
types it sends the add-on a `launcher` request, `{"query": "…"}`, and shows the rows that come back:

```json
[{"id": "app:/Applications/Safari.app", "title": "Safari", "kind": "Application",
  "iconPath": "/Applications/Safari.app", "open": "file:///Applications/Safari.app"}]
```

Each row may carry a `subtitle`, an SF Symbol name in `symbol` or a file whose icon to show in `iconPath`, a URL to
`open` and text to `copy`. Ledge only opens `file`, `http`, `https` and `x-apple.systempreferences` URLs.

The answers, matching and ranking live in `LauncherCore` and are tested with `swift test`.
