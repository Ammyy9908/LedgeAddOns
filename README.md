# Ledge Add-on Store

Public source submissions and release catalog for Ledge. Supported integrations are Spotify Likes and Notifications (developer preview). Other capability types require corresponding host
support before a listing can be accepted.

## Developer workflow

1. Clone and test the SDK:
   `git clone https://github.com/Ammyy9908/LedgeKit.git`,
   then `cd LedgeKit && swift test`.
2. Fork this repository and clone your fork.
3. Create a branch. Add a self-contained Swift package under `add-ons/<id>/`.
   Pin LedgeKit to a release using its HTTPS URL. Include addon.json, Sources,
   Tests, README, Assets/Icon.png and listing.json with preview media (see LISTING.md). Never submit credentials or build outputs.
4. Run `swift test --package-path add-ons/<id>` and
   `python3 scripts/build.py`. Load the resulting local package in Ledge.
5. Open a PR against main. Describe permissions, behavior, tests, dependencies and
   asset ownership. CI builds with read-only permissions and no release secrets.
6. A maintainer reviews source and permissions and merges the PR.
7. A fresh main-branch job rebuilds the reviewed commit for arm64 and x86_64.
   A separate publish job releases those artifacts and catalog.json.
8. Users open Add-on Store and refresh. The updated Ledge host lists catalog
   entries and verifies downloaded files against their SHA-256 before installation.

## Release contract

Catalog endpoint:
https://github.com/Ammyy9908/LedgeAddOns/releases/latest/download/catalog.json

Every catalog carries its source commit. Every file is referenced by a unique
commit-derived release URL and hash. PR builds cannot publish. Failed builds do
not replace the last release. Reverting a submission and publishing a new release
removes its listing; it does not remotely uninstall code from user computers.

Artifacts are ad-hoc signed development executables, not notarized releases.
Installation explicitly asks users to trust native code. TLS and hashes provide
transport/artifact integrity, not an independent publisher signature. Public
production distribution requires Developer ID/notarization and the host security
milestones. No claim is made that native add-ons are sandboxed.

Repository owners must protect main and review workflow/script changes as well
as source changes. Never run unreviewed PR code with signing or publication secrets.
