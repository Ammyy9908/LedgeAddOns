# Agents

What your [Claude Code](https://code.claude.com) sessions are doing, in the notch, and their permission prompts
answered from it.

## Connecting

In Ledge's Settings, Add-ons, Agents, press **Connect**. Ledge adds its hooks to `~/.claude/settings.json` and keeps
everything else in the file; the file as it was is saved beside it as `settings.json.ledge-backup`. Sessions you
start after connecting show up. **Disconnect**, or removing the add-on, takes the hooks out again.

Each hook pipes Claude Code's event to a socket in the add-on's folder with `nc`. When Ledge isn't running the hook
does nothing, so Claude Code works as before.

## What it shows

- Beside the notch: the latest session's folder and step, like "ledge · Editing Notch.swift", a tick for a few
  seconds when it finishes, and a hand when it's waiting for permission.
- On the add-on's page in the notch: every session, with its step and the lines its edits added and removed.

## Approvals

When Claude Code wants permission for a tool, the notch asks, naming the command or file. **Allow** and **Deny**
answer Claude Code. With no answer in 45 seconds, Claude Code asks as usual. Turn this off in the add-on's settings
to always answer in Claude Code. Questions Claude Code asks you and plan approvals stay in Claude Code.

## What it asks for

- `agent-hooks`: it adds hooks to Claude Code's settings and receives each prompt, tool call and stop of your
  sessions, including commands and file paths. They stay on this Mac.
- `questions`, to ask you about permission prompts in the notch.
