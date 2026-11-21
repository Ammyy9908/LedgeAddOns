# Developer Tools

Seven local tools in Ledge’s notch: Base64, JSON, hashes, UUID v4, JWT decoding, URL components and QR codes. Requires Ledge beta 12 or later (LedgeKit API 0.24.0), on macOS 14 or later. No companion app or account is needed.

## Use

Install and turn on the add-on, then choose **Open tools** in its settings or widget. Optionally assign the **Open developer tools** keyboard shortcut in Ledge. Choose a quick tab or **All tools**, type or paste input, then press the operation button. Copy writes the result to your clipboard; Full result opens an editable, scrollable result. Changing input or mode discards the previous result. Clear empties the workspace.

QR codes have a four-module white quiet zone. **Preview** shows a larger image; **To shelf** exports a PNG that can be dragged from Ledge’s shelf. Copy text copies the original content, not the image.

## Processing and limits

- Base64 accepts UTF-8 text, including Unicode. Decoding allows whitespace but rejects malformed or binary output.
- JSON supports fragments, preserves key order and original number precision, and limits nesting to 64 levels.
- Hashes: SHA-256, SHA-512, SHA-1 and MD5. SHA-1 and MD5 are legacy checksums, not secure password or signature algorithms.
- UUIDs are random version 4 identifiers.
- JWT decodes the header and payload of three-part tokens. **It does not verify signatures or validate authentication claims.** Encrypted tokens are unsupported.
- URL encoding treats input as a component, not a whole URL or form body. Decoding leaves `+` as a literal plus sign.
- QR uses native Core Image, with medium error correction. Input is limited to 1,800 UTF-8 bytes.
- Other inputs are limited to 8 KB; output is limited to 40 KB.

## Privacy and permissions

Input and results are kept in memory and are never logged, saved or uploaded. The add-on makes no network requests, reads no files and launches no processes. Turning it off discards its workspace.

`clipboard-write` is used only for an explicit Copy press. `notch-control` opens the workspace from settings, the widget or a configured shortcut. `shelf-add` is used only for To shelf. QR export writes a temporary PNG with a random filename to the add-on’s host-provided data folder, asks Ledge to copy it to the shelf, then removes the temporary file. A failed cleanup can leave that PNG in the data folder. Permission denial leaves the tools usable and displays a short explanation.

The notch input and full-result editor use Ledge’s native Markdown editor. They have a formatting toolbar; use plain text for encoded input and JSON.

## Build and verify

```sh
swift test
ledgekit build
ledgekit check --report /tmp/developer-tools-check.json
ledgekit check --deny all --report /tmp/developer-tools-denied.json
ledgekit shots --out /tmp/developer-tools-shots
ledgekit lint
ledgekit validate --submit
```

All surfaces and processing live in DeveloperToolsCore. The executable only manages the session and explicit host effects. Tests cover Unicode, malformed input, known hashes, precise JSON numbers, size limits, navigation, stale-result prevention and decoding generated QR images with Vision.
