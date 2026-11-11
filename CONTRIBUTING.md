# Contributing an add-on

Everything CI checks is written down here, so a pull request is never sent back for a rule you couldn't have
known. `python3 scripts/validate.py` runs the same checks on your machine.

## Before you start

- Build against [LedgeKit](https://github.com/Ammyy9908/LedgeKit), pinned to a release by its HTTPS URL.
- An add-on is native code that Ledge runs on people's Macs. A maintainer reads every line before it merges.
- Capabilities are open. Name the ones you use in `addon.json`; Ledge grants those it supports and keeps the
  rest off. Today it supports `spotify-library`, `notification-banners`, `apple-music-queue` and
  `apple-music-controls`. If you need something new, open an **Add-on idea** issue, so support can be planned.
- Say what your add-on needs with the optional manifest v2 fields: `kit.minAPI` (the LedgeKit API level, such as
  `0.4.0`), `minLedge`, `minMacOS`, plus `category`, `creator`, `source` and `keywords`. The Store build copies the
  requirements into the catalog, so Ledge can tell people before they install.

## The short version

```sh
git clone https://github.com/<you>/LedgeAddOns.git && cd LedgeAddOns
git switch -c add-my-addon
# add add-ons/my-addon/ (see below)
swift test --package-path add-ons/my-addon
python3 scripts/package.py my-addon     # builds a .ledgeaddon; load it in Ledge → Add-on Store → ⋯ → Load Add-on…
python3 scripts/validate.py             # the checks CI runs
```

Then open a pull request against `main` and fill in the template.

## What an add-on folder holds

```
add-ons/<id>/
  addon.json        identity, version, capabilities, executable, icon; `id` must equal the folder name
  listing.json      the Store listing: developer, category, description, feedback link, media (see LISTING.md)
  Package.swift     a self-contained Swift package; LedgeKit is its only dependency
  Package.resolved  optional: the resolved LedgeKit version
  Sources/          the add-on
  Tests/            its tests; required
  Assets/Icon.png   the icon
  Store/            screenshots (PNG) and the motion demo (MP4) that listing.json names
  CHANGELOG.md      newest version first
  README.md         what it does, how to set it up, what it can't do
  LICENSE           optional: the add-on's own licence (see "Licence")
  NOTICE.md         optional: third-party notices
  .gitignore        optional
```

Nothing else at the top of the folder: scripts, tools, notes and other folders are refused by name. Build products
(`.build/`, `.swiftpm/`, `*.ledgeaddon`, binaries), editor and agent files (`.DS_Store`, `.cursor/`, `.mcp.json`,
`AGENTS.md`, `CLAUDE.md`) are refused at any depth. Files are limited to 4 MB, except Store media: 8 MB per PNG and
32 MB for the MP4. Only files git tracks are checked, so ignored build folders don't matter.

## Versions

Versions only move forward, and a published build never changes.

- A **new add-on** is built and published when it merges.
- **Raising `version`** in `addon.json` publishes a new build. Add a `## <version>` entry at the top of
  `CHANGELOG.md` saying what changed; CI refuses a version without one.
- **Changing what gets built** (`Sources/`, `Package.swift`, `Package.resolved`, `addon.json`, `Assets/`) without
  raising the version is refused.
- **Store text and media** (`listing.json`, `Store/`), `README.md`, `CHANGELOG.md` and `Tests/` can change without a
  new version. The next release carries the new listing with the same build.
- A lower version than the Store's is refused.

Every release republishes unchanged add-ons from the files already in the Store, checked against their published
hashes, so merging someone else's change never rebuilds yours.

## Ownership

`author` in `addon.json` and `developer` in `listing.json` say who made an add-on, and
[`.github/CODEOWNERS`](.github/CODEOWNERS) lists the GitHub account behind each folder. Changes to an add-on you
don't own are welcome; its owner is asked before they merge.

## Licence

The repository is source-available under [LICENSE](LICENSE). An add-on can carry its own licence as `LICENSE` in its
folder; without one, the repository licence applies to it. Publishing here doesn't transfer ownership of an add-on.

## After merging

A fresh build of `main` runs the same checks with no secrets, then a separate job publishes the catalog as a GitHub
release. Ledge reads the latest catalog when the Store opens, and verifies every file against its SHA-256 before
installing it. Builds are ad-hoc signed developer previews, not notarized releases.
