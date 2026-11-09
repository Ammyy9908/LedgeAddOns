# Notifications

First-party developer-preview add-on, using LedgeKit 0.2.0. Requires the updated
Ledge host with `notification-banners` support and macOS 14 or later. Banner
Accessibility behavior is OS-dependent; successful delivery has been manually
verified on the developer's Mac, not every supported macOS release.

The host owns explicit Accessibility consent, visible-banner observation,
lock/session suspension, and expanded notch rendering. The worker only formats
one bounded JSON request; it receives no Spotify credentials. Body text is omitted
when previews are off. Native-code execution is not sandboxing.

Install from the Store, open Add-ons → Notifications, allow Accessibility and
enable mirroring. Keep native macOS banners enabled. Message previews are off by
default. There are no sample/test controls in the shipped settings page.

No notification history, database access, cloud forwarding, native-banner
suppression or inline replies. Private text is never logged or persisted by this
worker. Store PNG/MP4 assets are labeled illustrative previews using fixture text.
The icon uses Apple's system bell symbol. All preview artwork is generated for
this project; it contains no desktop screenshots, accounts or personal messages.

Validation: `swift test --package-path add-ons/notifications` and the repository
catalog build. The latter produces an ad-hoc-signed universal executable.
