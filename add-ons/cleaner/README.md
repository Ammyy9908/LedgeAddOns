# Cleaner

Uninstall apps together with what they leave behind, and clear out data your Mac can rebuild, from Cleaner's page in
the notch's Add-ons tab. Everything goes to the Trash, so nothing is gone until you empty it.

## Uninstall an app

Press **Uninstall an app** and choose one, drop an app on that row, or choose **Send with Cleaner, Uninstall…** on a
shelf item. Cleaner lists the app and every file it left in `~/Library`, each with its size and place:

- Files named after the app's identifier (`com.maker.app`, `com.maker.app.plist`, `com.maker.app.helper.plist`) start
  checked. Ones that only share the app's name, and the maker's shared group containers, start unchecked.
- If another copy of the app is on this Mac, nothing starts checked, because that copy still uses those files.
- Other apps' sandboxes (`Containers`, `Group Containers`) are found by name and never opened, so macOS asks nothing.
- If the app is open, Cleaner asks it to quit first.

Tap a row to check or uncheck it, then press **Move to Trash**. **Put Back** on the main screen returns the last move.

## Clean up storage

Sizes app caches, logs, Xcode build data (DerivedData), device support files, and developer caches (simulator, npm,
Gradle, `~/.cache`). Caches, logs and Xcode build data start checked. Emptying the Trash is what frees the space.

## Scheduled cleaning

In Settings, **Clean automatically**, weekly or monthly, moves app caches and logs nobody used in three days to the
Trash, leaving the caches of apps that are open alone.

## What it never touches

macOS's own apps and anything in `/System`, Ledge, Apple's caches, and anything outside your Library and the developer
cache folders above, such as Desktop, Documents, Downloads, Pictures or iCloud Drive. Files apps leave in the shared
`/Library` need your password, so Cleaner leaves them for now.
