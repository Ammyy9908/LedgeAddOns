# Quick Translate

Select text in another app and translate it in a card beside the selection. The card shows the language direction,
an **On this Mac** badge, the result, **Copy** (⌘C), **Replace** (Return) and **Close** (Escape).

## Requirements

- macOS 15 or later and a Ledge implementing LedgeKit API 0.24.0. **Ledge Beta 10 cannot run this add-on.**
- Allow **Ledge** in System Settings → Privacy & Security → Accessibility.
- Apple Translation must support the language pair. macOS may ask to download language files the first time.

## Set up

Turn the add-on on in Ledge, open its settings, choose a target and second language, then assign keys to
**Translate selected text** in the shortcut control. Select text in another app and press those keys.
If the selected text is already in the target language, it translates into the second language.
**Translate button beside selections** is off by default; turn it on to get a small button after mouse selections.

Review the translation before choosing Replace. Ledge rechecks the original app, field, selection range and text.
If the selection changed, the field is read-only, or macOS refuses the edit, it copies the result instead.
Password fields, secure input and selections over 4,000 characters are excluded. Clicking outside dismisses the card.
Long results scroll while Copy and Replace remain visible.

## Privacy and limits

Ledge reads only the selection used for translation. With the optional button off, no mouse-selection monitoring
runs. With it on, mouse selections are checked after a click; there is no clipboard polling or text logging.
Language preferences are saved through Ledge. Selected and translated text are not saved, sent to the add-on,
or sent to an AI or online translation provider. Ledge owns the card, Accessibility handle and Apple Translation session.
Language model downloads are handled by macOS. Unsupported pairs show an explanation; there is no AI fallback.
The add-on doesn't depend on Launcher. Removing or disabling it clears its host configuration and closes its card.

`Store/Translate.png` is a labeled illustrative preview, rendered by the real host with sample Spanish/English text.

## Verify

```sh
swift test
ledgekit build
ledgekit check --report /tmp/quick-translate-check.json
ledgekit check --deny all --report /tmp/quick-translate-denied.json
ledgekit shots --out /tmp/quick-translate-shots
ledgekit lint
ledgekit validate --submit
```
