# Wide Awake

Keeps your Mac from sleeping, from Ledge's notch: for a while, until you stop it, or by itself while something
needs the Mac awake.

## Using it

- **The page**: open Wide Awake in the notch's Add-ons pill. Choose **Display** (the screen and the Mac stay awake)
  or **System** (the Mac stays awake, the screen can dim and turn off), drag the minute tape to a length from a
  minute to a day, then **Stay Awake**. The **∞** button keeps it awake until you stop it.
- **While it runs**: × stops it, **+15** adds 15 minutes. The time left turns yellow in the last 15 minutes and red
  in the last 5. When a timer runs out you get a "Wide Awake is off" notice and the Mac sleeps as usual again.
- **Elsewhere**: the time sits beside the notch with a progress ring, on the lock screen, and on the Wide Awake
  widget, which also shows on iPhone in Droplets under Mac controls. Set a keyboard shortcut under Shortcuts to
  start and stop without opening anything.
- **AI apps**: an AI app connected to Ledge can call `keep_awake_start` (minutes, mode), `keep_awake_stop` and
  `keep_awake_status`.

## Settings

- **Start as soon as you open it**: opening the page starts your last length.
- **Mode**: Display or System, for the page and for Automatic.
- **Colours as time runs out**: off keeps the time orange.
- **Show on the lock screen**.
- **Automatic**: stay awake while plugged in, while another display is connected, while a file downloads (a
  `.download`, `.crdownload` or `.part` file in Downloads), while printing, while a coding agent runs (Claude Code,
  Codex, Gemini CLI, Aider and others), or while the apps you name are open. Each is off until you turn it on, and
  Wide Awake looks every 15 seconds.

## What it does on your Mac

Wide Awake holds a macOS power assertion (the same kind a video player uses) while it keeps the Mac awake, and
releases it when it stops. macOS releases it on its own if Wide Awake or Ledge quits, so the Mac never stays
sleepless by mistake. It can't keep a Mac awake with the lid closed. For Automatic it reads only what the triggers
you turned on need: the power source, the connected displays, the names of files in Downloads, the print queue
(`lpstat`), the names of running programs (`ps`) and the open apps. It keeps its settings and a running timer (as its
end time) in Ledge's settings for the add-on, and sends nothing anywhere.
