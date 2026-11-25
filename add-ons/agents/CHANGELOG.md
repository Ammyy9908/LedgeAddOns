# Changelog

Newest version first. Every new `version` in addon.json needs an entry here.

## 0.3.0

- A Home widget lists your latest sessions and what each is doing. It also shows on your iPhone, under At a glance in
  Add-ons, and opens the Agents page there.

## 0.2.0

- While a session works or waits for your approval, opening the notch shows it in Home's place, and the closed notch
  shows it over the song playing, which moves beside it. Turn this off in Ledge's Settings, Live Activities. Needs a
  Ledge with LedgeKit 0.27.
- Shows Codex sessions too, read from Codex's session logs with nothing to connect: the commands they run, the
  files they edit and the lines changed, each session marked Claude or Codex. Turn it off in the add-on's settings.
- Sessions (orange) and Usage (green), before the blue gear, switch the page between the session card and a ring for Claude Code and
  one for Codex, each with the agent's own app icon: how much is left of the limit closest to running out, and when
  it resets. Sessions again lists every session.
- Follows Cursor's agent sessions too, from its transcripts, with nothing to connect. Turn it off in the settings.
- With nothing running, the page shows the coding agents installed on this Mac in a row.
- The card shows what you asked and what the agent last said, beside its last three steps. Its status has a
  coloured dot, its steps an orange tick or arrow, and the command it runs sits in a box.
- Press a usage ring for that agent's plan and each limit with its reset time and what is left. Cursor has a ring
  too, dotted, since it doesn't report its limits on this Mac.
- Preview alerts, in the settings, shows the running-low and back-to-full alerts. An alert has the notch to itself
  for its few seconds.
- New settings: keep the agent's pill up while it runs, which the notch shows when music is also playing, a sound
  when an agent finishes, show what is left or used, which limit the rings show, a warning when a limit runs low
  (at 75 to 95% used) and a note when it's back to full. Codex's comes from its session logs. Claude Code tells only a status line, so
  connecting adds one that shows nothing, where you have none; reconnect to get it if you connected with 0.1.0.
- A gear in the page's header opens the add-on's settings, to connect Claude Code or turn approvals in the notch on
  or off.

## 0.1.0

- Shows what your Claude Code sessions are doing: the current step of the latest one beside the notch, and every
  session with its step and the lines its edits added and removed on a page in the notch.
- Asks in the notch when Claude Code wants permission for a tool, so you can allow or deny it there.
- Connect and Disconnect in Settings add and remove Ledge's hooks in `~/.claude/settings.json`.
