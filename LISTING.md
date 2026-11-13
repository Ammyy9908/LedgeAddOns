# Store listings

New submissions include `listing.json` beside `addon.json`. Package permissions
remain in `addon.json`; store presentation belongs here:

```json
{
  "developer": "Your display name",
  "category": "System",
  "availability": "Free · macOS 14 or later",
  "description": "Describe actual behavior, setup and limitations.",
  "feedbackURL": "https://github.com/your-account/your-addon/issues/new",
  "screenshots": ["Store/Screenshot.png"],
  "motionDemo": "Store/Demo.mp4"
}
```

Include 1–8 PNG screenshots (8 MB each maximum, up to 4096 pixels per side) and,
optionally, an MP4 motion demo (32 MB maximum). Use real product captures or clearly labeled
demos without private account content. The publisher converts local paths into
release URLs and SHA-256 hashes. The host verifies media before displaying it;
videos require user playback. Feedback opens the developer’s HTTPS destination
and never submits a message automatically.

`installs` is reserved for a future verified-installation service. Authors cannot
supply this metric. Until that service exists, the Store displays “Not available”.
Downloads must not be represented as installations. Existing listings without
this metadata continue to load and show explicit missing-preview states.
