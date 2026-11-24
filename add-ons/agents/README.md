# Agents

What your [Claude Code](https://code.claude.com), Codex and Cursor sessions are doing, in the notch, and Claude Code's
permission prompts answered from it.

## Connecting

In Ledge's Settings, Add-ons, Agents, press **Connect**. Ledge adds its hooks to `~/.claude/settings.json` and keeps
everything else in the file; the file as it was is saved beside it as `settings.json.ledge-backup`. Sessions you
start after connecting show up. **Disconnect**, or removing the add-on, takes the hooks out again.

Each hook pipes Claude Code's event to a socket in the add-on's folder with `nc`. When Ledge isn't running the hook
does nothing, so Claude Code works as before.

## Codex

Codex needs no connecting: the add-on reads Codex's session logs in `~/.codex/sessions` as they're written, for
sessions active in the last half hour, and shows them like Claude Code's, with the commands they run and the files
they edit. It changes nothing in Codex. Turn it off with **Codex** in the add-on's settings. Codex's
questions and approvals stay in Codex.

## What it shows

- On Home: while a session works or waits for your approval, opening the notch shows it in Home's place, and the
  closed notch shows it over the song playing. Ledge's Settings, Live Activities, Add-ons can lead Home turns it off.
- Beside the notch: the latest session's folder and step, like "ledge · Editing Notch.swift", a tick for a few
  seconds when it finishes, and a hand when it's waiting for permission.
- On the add-on's page in the notch: every session, with its step and the lines its edits added and removed.

## Approvals

When Claude Code wants permission for a tool, the notch asks, naming the command or file. **Allow** and **Deny**
answer Claude Code. With no answer in 45 seconds, Claude Code asks as usual. Turn this off in the add-on's settings
to always answer in Claude Code. Questions Claude Code asks you and plan approvals stay in Claude Code.

## Cursor

Cursor needs no connecting either: the add-on reads the agent transcripts Cursor writes in `~/.cursor/projects` for
Agent mode, with what you asked, the tools it uses and what it says. Turn it off with **Cursor** in the settings.
Antigravity and OpenCode show in the row of agents when they're installed, but Ledge doesn't follow their sessions
yet.

## Usage

**Usage**, the gauge in the page's header, shows a ring for each agent: how much is left of the limit closest to
running out, green, then orange under 25% and red under 10%, and when it resets. Codex writes its plan's limits into
its session logs. Claude Code tells them only to a status line, and only on a Pro or Max plan, so connecting adds a
status line that shows nothing and passes them to Ledge, unless you already have a status line, which stays as it
is. Disconnecting takes Ledge's status line out too.

Press a ring for that agent's limits in full: its plan, then each limit with when it resets, how much is left and a
bar. Cursor gets a dotted ring: it keeps its limits in your account online, and Ledge doesn't sign in to it.

## Settings

- **Answer agents from the notch**: Claude Code's permission prompts, answered in the notch.
- **Keep agent status in the notch**: off, the pill shows for a moment as a turn starts, then goes.
- **When music is also playing, show**: Agents, which takes the notch from the song and opens on the agent, or Music.
- **Sound when an agent finishes**: one of macOS's alert sounds, or none.
- **Usage**: show what is left or what is used; which limit the rings show; warn once per window when a limit
  crosses 75, 80, 90 or 95% used; and say when a limit that ran low is back to full. Preview alerts shows each
  alert in the notch once, to see what it looks like.

## What it asks for

- `agent-hooks`: it adds hooks to Claude Code's settings and receives each prompt, tool call and stop of your
  sessions, including commands and file paths, and reads the same from Codex's session logs, and a status line that
  passes on how much of your plan is used. They stay on this Mac.
- `questions`, to ask you about permission prompts in the notch.
