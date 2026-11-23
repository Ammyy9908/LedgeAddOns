# Pomodoro

A focus and break timer in Ledge's notch. Pick Focus or Break, set a length, start it, and keep an eye on the
countdown beside the notch while you work.

## Using it

- **The page**: open Pomodoro in the notch's Add-ons pill. Choose **Focus** or **Break**, drag the minute tape under
  the pointer to set the length (from a minute to eight hours), then **Start Timer**. Focus is orange and Break blue,
  and each remembers its length, so 25 and 5 stay set.
- **Stopwatch**: the stopwatch button starts a count-up with the same pause and stop.
- **While it runs**: pause or resume with the round coloured button, stop with ×. The page reads Focus, Break,
  Stopwatch or Paused beside the time.
- **When a session ends**: the end sound and a "Pomodoro complete" notice. The timer then counts overtime (+00:22),
  and a third button starts the next session (a break after focus, focus after a break).
- **Ambient sound**: the speaker button turns it on and off; pick the sound in Settings. It plays while a session
  counts down, not in overtime.
- **Elsewhere**: the time sits beside the notch with a progress ring, on the lock screen while the Mac is locked, and
  on the Pomodoro widget, which also shows on iPhone in Droplets under Focus, with the same buttons. Set a keyboard
  shortcut under Shortcuts to start, pause and resume without opening anything.

## Settings

- **Start as soon as you open it**: opening the Pomodoro page starts your last timer.
- **Always show the timer in the notch**: off, the timer shows on the page, widget and lock screen only.
- **End sound**: None or one of the macOS sounds (Glass by default), with **Play** to hear it.
- **More options**: **Show seconds in the notch** (off reads 25m).
- **Reminders**: Eye break (every 20 minutes), Drink water (30), Stand up (hourly), and your own reminders, every
  30 minutes. They come during focus sessions and stopwatches, not breaks.
- **Ambient sound**: on or off; one of macOS's Background Sounds (the ones in System Settings › Accessibility ›
  Audio: Rain, Rain on Roof, Ocean, Stream, Fireplace, Night, Quiet Night, Brown, Pink and White Noise, Airplane,
  Babble, Boat, Bus, Steam, Train), with **Play**; the volume; and whether it plays during breaks.

## What it does on your Mac

Pomodoro keeps its lengths, settings and the running session (as its end time) in Ledge's settings for the add-on, so a
timer survives Ledge restarting. Ambient sound is macOS's own Background Sounds, read from the system and played on the current output (generated noise
on a Mac without them); the end sound is
one of the macOS system sounds. It reads nothing else and sends nothing anywhere.

## What it can't do

- The Background Sounds are read from a folder inside macOS that Apple doesn't document, so a future macOS could move
  them; Pomodoro then plays generated noise.
- It can't follow timers set in Apple's Clock app or turn on a macOS Focus.
- The timer can't appear only when you hover over the notch: it shows beside the notch for the whole session, or not
  at all.

## Building

```
swift build -c release
swift test
```
