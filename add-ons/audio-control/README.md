# Audio Control

A volume slider for each app that's playing sound, on its own page in Ledge's notch (the Add-ons tab) and as a
widget you can put on Home. Each app is a row that fills to its level; drag or scroll on it.

## How it works

macOS has one volume for everything. For an app you turn below full, Audio Control asks Core Audio for a
process tap on that app (macOS 14.2 or later): macOS stops sending the app's sound straight to your speakers
and hands it to the add-on, which plays it on the same output at the level you set. Past the line at 100% the
slider boosts the app, up to 200%. At 100% there's no tap, and the app plays as usual. Nothing is recorded or written anywhere, and nothing leaves the Mac.

The first time an app is turned down, macOS may ask to let Ledge capture system audio.

## Settings

- **Remember volumes**: an app keeps its level the next time it plays.
- **Show paused apps**: apps with sound open but silent right now keep their row.
- **Include system sounds**: a row for macOS's alerts and interface sounds.
- **Volume curve**: Natural sounds even across the slider; Linear moves the level evenly.
- **Allow boost above 100%**: sliders go to 200%, with loud peaks held at full scale.
- **Reset all volumes**: every app back to 100%.
- **Output per app**: send an app to its own speakers or headphones. It plays on the Mac's output while that device
  isn't connected.
- **Preferred devices**: when one of up to three outputs connects, the Mac switches to the best one connected.
  An output you choose yourself stays until another of them connects.
- **Microphones**: mute every microphone, including ones that connect while muted, from Settings or the microphone
  button on the page, or a keyboard shortcut you choose under Shortcuts (⌃⌥M, ⌥⌘M or ⌃⌥⌘M). Turning Audio Control
  off unmutes them.

## Building

```
swift build -c release
swift test
```
