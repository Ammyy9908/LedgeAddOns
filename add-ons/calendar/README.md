# Calendar

Your next meetings in the notch, with Join.

- **Widget:** your next events today with their times. The next one counts down, with **Join** when it has a meeting
  link. With nothing left today, tomorrow's first event.
- **Beside the notch:** from Remind me before (5, 10 or 15 minutes, or off) ahead of an event until 5 minutes after
  it starts, "Design review in 8 min", then "now". Clicking it opens the page.
- **Page:** the next event with Join, then the rest of today and tomorrow. Clicking one opens Calendar.

## Setting up

Calendar reads the calendars in the Mac's Calendar app, with EventKit. macOS counts an add-on as part of Ledge, so
Ledge holds the permission: in Ledge's Settings, open Calendar under Add-ons and choose **Allow…** beside
`calendars`, then allow Calendars when macOS asks. Once granted it's listed on Ledge's Permissions page.

## What it can't do

- It only reads events: it can't create, change or answer them.
- Join knows Zoom, Google Meet, Microsoft Teams, Webex and FaceTime links (https only). Other links aren't offered.
- All-day and declined events are left out.
- It needs a Ledge that supports the `calendars` capability.

Nothing leaves your Mac. Event titles and links are never logged.
