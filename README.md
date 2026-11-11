# Ledge Add-on Store

The Add-on Store for Ledge, as a repository. Every add-on in the Store lives here, one folder each under
[`add-ons/`](add-ons/). Merging a change publishes it: CI builds the add-on for arm64 and x86_64, writes its
catalog entry, and every Mac running Ledge sees it the next time the Store opens.

Listed today: Spotify Likes, Notifications (developer preview) and Apple Music Controls (developer preview). Any
add-on can be submitted. Capabilities are open: an add-on may name one Ledge doesn't support yet, and Ledge keeps
it off until it does. Each catalog entry says which Ledge, LedgeKit and macOS it needs, so the Store can mark an
add-on your Ledge can't run before you install it.

- **Build an add-on**: [LedgeKit](https://github.com/Ammyy9908/LedgeKit).
- **Publish yours**: read [CONTRIBUTING.md](CONTRIBUTING.md) and [LISTING.md](LISTING.md), then open a pull request.

## How it works

```
add-ons/<id>/        your add-on: Package.swift, addon.json, listing.json, Sources/, Tests/, Assets/, Store/
   CHANGELOG.md      what changed, newest version first
   README.md         what it does, how to set it up
retired.json         add-ons taken off the Store
scripts/validate.py  the checks CI runs; run it before opening a pull request
scripts/package.py   builds one add-on into a .ledgeaddon to load in Ledge
scripts/build.py     builds the catalog
```

1. You add or change an add-on and open a pull request.
2. CI validates it: the folder, the manifest, the version, the changelog entry, the listing. It builds and tests
   with read-only permissions and no release secrets.
3. A maintainer reads the source and its permissions and merges. An add-on is native code running on people's
   Macs, so every merge is a review.
4. A fresh build of `main` builds every add-on whose version is newer than the Store's, republishes the others
   from the files already published (checked against their hashes), and a separate job releases the files and
   `catalog.json`.
5. Ledge reads the latest catalog when the Store opens and verifies every file against its SHA-256 before
   installing it.

Versions only move forward. A published build never changes: to change what ships, raise `version` in
`addon.json`, add the entry to `CHANGELOG.md` and open another pull request.

## Retiring an add-on

Publishing is automatic; taking an add-on off the Store is a maintainer's decision. Add its id to
[`retired.json`](retired.json) with a reason:

```json
{ "retired": [{ "id": "my-addon", "reason": "Replaced by …" }] }
```

The next release leaves it out of the catalog, so the Store stops offering it. Macs that already have it keep it:
the Store can't remove code from people's computers. A retired add-on isn't republished by a version bump; take it
out of `retired.json` to restore it.

## Release contract

Catalog endpoint:
https://github.com/Ammyy9908/LedgeAddOns/releases/latest/download/catalog.json

Every catalog carries its source commit, and every file is referenced by a URL under that commit's release and
by its hash. Pull request builds can't publish. A failed build doesn't replace the last release.

Builds are ad-hoc signed development executables, not notarized releases. Installing asks people to trust native
code. TLS and hashes protect transport and file integrity; they aren't an independent publisher signature. Public
production distribution needs Developer ID signing, notarization and the host security milestones. Native
add-ons aren't sandboxed.

Repository owners must protect `main` and review workflow and script changes as carefully as add-on source. Never
run unreviewed pull request code with signing or publishing secrets.

## Licence

This repository is source-available, not open source: see [LICENSE](LICENSE). Read every line of it, build and
test add-ons with it, and fork it to open a pull request. It doesn't give the right to redistribute the
repository, or the collection of add-ons it holds, as part of another product or store. An add-on may carry its
own licence in its folder; publishing here doesn't transfer its ownership.
