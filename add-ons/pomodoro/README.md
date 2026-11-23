# Pomodoro

A focus and break timer in Ledge's notch. Pick Focus or Break, set a length, start it, and keep an eye on the
countdown beside the notch while you work.

## Using it

- **The page**: open Pomodoro in the notch's Add-ons pill. Choose **Focus** or **Break**, set the length with the
  slider (from a minute to eight hours, finer at the short end) or the − and + buttons, then **Start timer**. Focus and
  Break each remember their length, so 25 and 5 stay set.
- **While it runs**: pause or resume with the orange button, stop with ×. The page reads Focus, Break or Paused beside
  the time.
- **Focus title**: the pencil button opens a line to say what you're working on. It shows under the timer and on the
  widget.
- **Ambient sound**: the speaker button cycles Off, Brown noise and Pink noise. It plays only while a timer runs.
- **When a session ends**: a chime and a notice, then the page offers the next session (Start break or Start focus).
  Turn on **Move on automatically** to go straight into it.
- **Elsewhere**: the countdown sits beside the notch with a progress ring, on the lock screen while the Mac is
  locked, and on the Pomodoro widget, which also shows on iPhone in Droplets under Focus, with the same buttons.
  Set a keyboard shortcut under Shortcuts to start, pause and resume without opening anything.

## Settings

- **Start instantly**: opening the Pomodoro page starts your last timer.
- **Move on automatically**: start the break when focus ends, and focus when the break ends.
- **Ambient sound**: Off, Brown noise or Pink noise.
- **Chime when a session ends** and **Show a notice when a session ends**.

## What it does on your Mac

Pomodoro keeps its lengths, title and the running session (as its end time) in Ledge's settings for the add-on, so a
timer survives Ledge restarting. Ambient noise is generated on the Mac and played on the current output; the chime is
the macOS Glass sound. It reads nothing else and sends nothing anywhere.

## What it can't do

- No stopwatch, and no fireplace or other recorded sounds: only generated brown and pink noise.
- It can't follow timers set in Apple's Clock app.
- The length is set with a slider, not a scrolling tape.

## Building

```
swift build -c release
swift test
```
