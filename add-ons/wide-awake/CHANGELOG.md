# Changelog

Newest version first. Every new `version` in addon.json needs an entry here.

## 0.2.0

- The page shows when a timer would end as you drag the tape ("until 4:19 PM"), and while it runs.
- AI apps can keep the Mac awake until a time of day: `keep_awake_start` takes `until`, like 18:30 or 6:30 pm.

## 0.1.1

- A timer an AI app starts no longer changes the length and mode you set on the page.
- AI apps read "the screen and the Mac stay awake" rather than "screen and mac stay awake".

## 0.1.0

- A Wide Awake page in the notch: pick Display (screen and Mac) or System (the Mac only), drag the minute tape to
  any length from a minute to a day, and press Stay Awake, or ∞ to stay awake until you stop it.
- While it runs: stop, and +15 to add a quarter of an hour, with the time left in large digits that turn yellow in
  the last 15 minutes and red in the last 5.
- A "Wide Awake is off" notice when a timer runs out.
- The time beside the notch with a progress ring, on the lock screen, and on a Home widget that's also a tile in the
  Ledge iPhone app's Droplets, under Mac controls.
- A keyboard shortcut to start and stop, set under Shortcuts.
- Automatic: stay awake while plugged in, while another display is connected, while a file downloads, while printing,
  while a coding agent runs, or while apps you name are open.
- AI tools for AI apps connected to Ledge: keep_awake_start, keep_awake_stop and keep_awake_status.
- Start as soon as you open it: opening the page starts your last length.
