# Changelog

Newest version first. Every new `version` in addon.json needs an entry here.

## 0.4.0

- Copy says so: "Copied" in the note's header when it worked, and "Copying is off in Ledge" when copying is turned off
  for Notes, instead of nothing happening.
- Built with LedgeKit 0.15.2. It still runs in every Ledge with LedgeKit 0.13.0 or later.

## 0.3.0

- First release in the Store.
- A page of its own in the open notch: the list of notes, newest first, and a note in Ledge's Markdown editor, saved
  as you type.
- Notes are Markdown files in the folder Ledge gives the add-on, kept through updates. Notes written with 0.2 move
  there once.
- The list reads the folder again whenever the page opens, so a note changed in another editor shows up.
- Settings: Show in Finder, and Move all notes to the Trash, which asks first. Settings search finds it by
  "markdown" and "writing".
- Needs a Ledge with LedgeKit 0.13.0.
