# Pomodoro

A focus and break timer in Ledge's notch. Pick Focus or Break, set a length, start it, and keep an eye on the
countdown beside the notch while you work.

## Using it

- **The page**: open Pomodoro in the notch's Add-ons pill. Choose **Focus** or **Break**, set the length with the
  slider (from a minute to eight hours, finer at the short end) or the − and + buttons, then **Start timer**. Focus and
  Break each remember their length, so 25 and 5 stay set.
- **Stopwatch**: the stopwatch button starts a count-up with the same pause and stop.
- **While it runs**: pause or resume with the orange button, stop with ×. The page reads Focus, Break, Stopwatch or
  Paused beside the time.
- **When a session ends**: the end sound and a "Pomodoro complete" notice. The timer then counts overtime (+00:22),
  and a third button starts the next session (a break after focus, focus after a break). Turn on **Move on
  automatically** to go straight into it.
- **Focus title**: the pencil button opens a line to say what you're working on. It shows under the timer and on the
  widget.
- **Ambient sound**: the speaker button turns it on and off; pick the sound in Settings. It plays while a session
  counts down, not in overtime.
- **Elsewhere**: the time sits beside the notch with a progress ring, on the lock screen while the Mac is locked, and
  on the Pomodoro widget, which also shows on iPhone in Droplets under Focus, with the same buttons. Set a keyboard
  shortcut under Shortcuts to start, pause and resume without opening anything.

## Settings

- **Start as soon as you open it**: opening the Pomodoro page starts your last timer.
- **End sound**: None or one of the macOS sounds (Glass by default), with **Play** to hear it.
- **Show a notice when a session ends**.
- **More options**: **Show seconds beside the notch** (off reads 25m), and **Move on automatically**.
- **Ambient sound**: on or off, Brown, Pink or White noise, the volume, and whether it plays during breaks.

## What it does on your Mac

Pomodoro keeps its lengths, title and the running session (as its end time) in Ledge's settings for the add-on, so a
timer survives Ledge restarting. Ambient noise is generated on the Mac and played on the current output; the end sound is
one of the macOS system sounds. It reads nothing else and sends nothing anywhere.

## What it can't do

- No rain, fireplace or other recorded sounds: only generated brown, pink and white noise.
- No reminders, and it can't turn on a macOS Focus.
- It can't follow timers set in Apple's Clock app.
- The length is set with a slider, not a scrolling tape, and Break uses the same accent colour as Focus.

## Building

```
swift build -c release
swift test
```
