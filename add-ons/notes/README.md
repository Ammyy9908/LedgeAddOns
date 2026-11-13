# Notes

Write notes in the notch. Notes adds a page to the open notch, after Shelf, Clipboard and Widgets: a list of your
notes, newest first, and Ledge's Markdown editor for the one you open. Headings, bold, italic, lists and checklists
are styled as you type, a click on `[ ]` ticks it, and the note is saved a moment after you stop typing and again
when you leave it.

## Where the notes are

Each note is a plain Markdown file in the folder Ledge keeps for the add-on
(`~/Library/Application Support/Ledge/AddOnData/notes/Files`). Open them in any editor; the list picks up changes
whenever the page opens. **Show in Finder** on the add-on's settings page opens the folder.

- A deleted note goes to the Trash, so it can be put back.
- **Move all notes to the Trash** asks first.
- Removing the add-on keeps your notes, unless you tick "Also delete its settings and saved data".
- Notes 0.2 kept notes in `Application Support/Ledge Notes`; 0.3 moves them into the add-on's folder once.

## What it asks for

- `clipboard-write`, for **Copy note**.
- The `notch-page` and `settings-page` surfaces.

It reads nothing outside its folder, sends nothing off the Mac, and logs failures without note text.

## What it doesn't do

No sync, no search inside notes, no attachments, and no access to Apple Notes.

## Building

```sh
swift test --package-path add-ons/notes
python3 scripts/package.py notes
```

Needs a Ledge with LedgeKit 0.13.0 and macOS 14 or later. Screenshots in `Store/` show sample notes.
