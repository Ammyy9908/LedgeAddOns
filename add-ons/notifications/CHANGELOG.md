# Changelog

Newest version first. Every new `version` in addon.json needs an entry here.

## 0.3.0

- Its settings page comes from the add-on. Mirroring follows the add-on's own switch, and "Show message text" is
  the add-on's choice: Ledge passes the text and the add-on drops it unless you turned it on. Off by default.
- Needs a Ledge with LedgeKit 0.7.0.

## 0.2.0

- Runs as one long-lived session while mirroring is on, instead of starting a program for every banner. Needs a Ledge build with session support (LedgeKit 0.3.0).

## 0.1.0

- First release, as a developer preview: mirrors visible macOS notification banners in the notch after Accessibility and mirroring are turned on.
