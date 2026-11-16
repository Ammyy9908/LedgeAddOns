# Terminal for Ledge

Your login shell on a Terminal page in the notch, with full-screen programs like vim, top and ssh.

## Setting it up

Install Terminal from Ledge's Add-on Store and allow it to run programs. A Terminal page appears in the tab pill
under the open notch. Pick a shortcut in Ledge's Settings, General, Terminal to open it from anywhere, and the app
its open button hands the shell's folder to.

## What it asks for

- The `terminal` capability: it runs your login shell as you, with your access to everything on this Mac, like a
  shell in Terminal.
- The `terminal` surface: Ledge draws the shell's screen and sends what you type. Ledge never runs a program itself.
- The `settings-page` surface: where shells start, and a button to restart the shell.

## What it keeps

Where shells start, and the folder the last one was in, through Ledge's settings for the add-on. Nothing you type:
it goes to the shell and nowhere else. Programs in the shell can copy to your clipboard but can't read it.

## What it doesn't do

One shell at a time, with no tabs or split panes. It doesn't keep history beyond what your shell keeps. Turning
Terminal off ends the shell and what runs in it.

## Build it

```sh
swift test --package-path add-ons/terminal
python3 scripts/package.py terminal
```
