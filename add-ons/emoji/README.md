# Emoji for Ledge

Every emoji in a floating picker, opened by a shortcut from any app.

## Setting it up

Install Emoji from Ledge's Add-on Store and allow it to insert text. In its page in Ledge's Settings, pick a
shortcut, where the picker opens, and whether choosing types the emoji in or copies it. Typing it in needs
Accessibility for Ledge; without it, choosing copies the emoji.

## Using it

Press the shortcut, type a name like "heart" or "thumbs", move with the arrow keys or Tab between groups, and press
Return. The emoji goes where you were typing, and your clipboard is left as it was. Esc or a click elsewhere closes it.

## What it asks for

- The `insert-text` capability: Ledge types the emoji you pick into the app you're in.
- The `picker` surface: Ledge draws the panel and searches it.
- The `settings-page` surface: your skin tone and Recents.

## What it keeps

Your skin tone and the last 24 emoji you picked, on this Mac. Nothing about where they went, and nothing you type.

## What it doesn't do

It doesn't open from typing a word like `:heart`, so nothing reads what you type. It leaves out emoji newer than your
version of macOS can show. macOS's own emoji viewer stays on ⌃⌘Space.

## Build it

```sh
swift test --package-path add-ons/emoji
python3 scripts/package.py emoji
```

The emoji list comes from Unicode's emoji-test.txt; see NOTICE.md.
