# Launcher

A search bar for the Mac in Ledge. Press the launcher shortcut (⌥Space unless it's changed on the add-on's page in
Settings) and type:

- an app, like `safari` or `vsc` for Visual Studio Code
- a page of System Settings, like `wifi`, `displays` or `battery`
- a file or folder in the home folder, from Spotlight's index
- a sum, `1,250 * 1.2`, `80 + 15%`, `sqrt 2`, or a tip, `18% tip on 62.50`
- a conversion, `10 km in miles`, `212 f to c`, `2 gb in mb`
- a time, `time in tokyo`, `now in sydney`, `3pm london in nyc`, `3pm in nyc` (your 3pm there), `3pm est` (theirs here)

- a question for an AI: with your own key set up, an **Ask** row sends it and shows the answer in the launcher

Return opens the selected row, or copies an answer; ⌘C copies any row. The last row searches the web. Everything is
found on this Mac and nothing is sent anywhere unless that web row is picked.

## Store preview

`Store/Demo.mp4` is a silent recording of Launcher categories, file previews and
an Ask AI answer. `listing.json` publishes it alongside the screenshot.

## How Ledge asks

The manifest declares the `launcher` surface. Ledge owns the panel, its shortcut and what Return does; as the person
types it sends the add-on a `launcher` request, `{"query": "…"}`, and shows the rows that come back:

```json
[{"id": "app:/Applications/Safari.app", "title": "Safari", "kind": "Application",
  "iconPath": "/Applications/Safari.app", "open": "file:///Applications/Safari.app"}]
```

Each row may carry a `subtitle`, an SF Symbol name in `symbol` or a file whose icon to show in `iconPath`, a URL to
`open` and text to `copy`. Ledge only opens `file`, `http`, `https` and `x-apple.systempreferences` URLs.

A row with `ask` is a question for the AI: choosing it sends `launcher.ask` (`{"query": "…"}`) and Ledge shows the
answer, `{"text": "…", "from": "Claude"}`, in the panel. A failure is an `AddOnError` whose message Ledge shows as it is.

## Ask AI, with your own key

On the Launcher's page in Settings, pick who answers (Claude, ChatGPT, Gemini, or any server with OpenAI's chat
completions API, such as OpenRouter, Groq or a local Ollama), paste your API key and, if you like, a model. Each
service is one `Assistant` value, so adding another is a new value, not new code, when it speaks one of the three
API shapes.

- The key is saved in your login Keychain (service `app.ledge.launcher.ai`), never in settings, never logged and
  never sent back to Ledge; the field clears once it's saved. Remove Key deletes it.
- It goes only to the service you chose, over https (plain http only to this Mac), and only when you choose an Ask
  row. Typing never asks the AI.
- Error replies are turned into short messages; their bodies, which can echo the request, are never shown or logged.
- Defaults: Claude `claude-opus-5-5` at low effort, ChatGPT `gpt-5-mini`, Gemini `gemini-flash-latest`.

The answers, matching, ranking and the AI requests live in `LauncherCore` and are tested with `swift test`, without
the network.
