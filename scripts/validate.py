#!/usr/bin/env python3
"""Checks every add-on folder against the rules in CONTRIBUTING.md and decides what publishing does with it.

Run it before opening a pull request: `python3 scripts/validate.py`. CI runs the same checks, and
`scripts/build.py` uses the plan it returns. Nothing here builds, signs or uploads anything.

The plan, per add-on:
  build   a new add-on, or its version went up: build it from source
  reuse   same version as the Store and its build inputs are unchanged: republish the published files as they are
  retired listed in retired.json: left out of the catalog
"""
import json, os, pathlib, re, subprocess, sys, urllib.error, urllib.request

ROOT = pathlib.Path(__file__).resolve().parents[1]
CATALOG_URL = "https://github.com/Ammyy9908/LedgeAddOns/releases/latest/download/catalog.json"

# What an add-on folder may hold at its top level. Anything else is refused by name.
ALLOWED_TOP = {"addon.json", "listing.json", "Package.swift", "Package.resolved", "README.md", "CHANGELOG.md",
               "LICENSE", "NOTICE.md", ".gitignore", "Sources", "Tests", "Assets", "Store"}
REQUIRED = ["addon.json", "Package.swift", "README.md", "CHANGELOG.md", "Assets/Icon.png"]
# Never part of a submission, at any depth.
REFUSED_PARTS = {".build", ".swiftpm", ".DS_Store", ".mcp.json", ".cursor", "AGENTS.md", "CLAUDE.md", "__pycache__"}
REFUSED_SUFFIXES = {".ledgeaddon", ".binary", ".dylib", ".a", ".o", ".zip"}
# Store media have their own limits (see LISTING.md); every other file stays small.
LIMITS = {".mp4": 32 * 1024 * 1024, ".png": 8 * 1024 * 1024}
DEFAULT_LIMIT = 4 * 1024 * 1024
# Changing these changes what gets built, so it needs a new version. README, CHANGELOG, listing.json, Store/
# and Tests/ can change without one.
BUILD_INPUTS = ["Sources", "Package.swift", "Package.resolved", "addon.json", "Assets"]
# Add-ons listed before listing.json existed.
NO_LISTING_YET = {"spotify-likes"}
CHANGELOG_HEADING = re.compile(r"^## \[?(\d+\.\d+\.\d+)\]?", re.MULTILINE)


def version_key(text):
    return tuple(int(part) for part in text.split("."))


def git(*args):
    return subprocess.run(["git", *args], cwd=ROOT, capture_output=True, text=True)


def tracked_files(folder):
    # Tracked files plus new ones not yet added, leaving out what .gitignore covers.
    out = git("ls-files", "-z", "--cached", "--others", "--exclude-standard", "--", str(folder.relative_to(ROOT)))
    return [ROOT / path for path in out.stdout.split("\0") if path and (ROOT / path).exists()]


def published_catalog():
    """The catalog the Store serves now, or None before the first release or with LEDGE_OFFLINE=1."""
    if os.environ.get("LEDGE_OFFLINE") == "1":
        return None
    override = os.environ.get("LEDGE_PUBLISHED_CATALOG")
    try:
        if override:
            return json.loads(pathlib.Path(override).read_text())
        with urllib.request.urlopen(CATALOG_URL, timeout=30) as response:
            return json.loads(response.read())
    except urllib.error.HTTPError as error:
        if error.code == 404:
            return None
        raise


def retired_ids():
    path = ROOT / "retired.json"
    if not path.exists():
        return {}
    data = json.loads(path.read_text())
    return {item["id"]: item.get("reason", "") for item in data.get("retired", [])}


NAME = re.compile(r"[a-z0-9][a-z0-9-]{0,63}")
RELEASE_VERSION = re.compile(r"\d+\.\d+\.\d+")
CATEGORIES = {"AI", "Productivity", "Media", "Capture", "Files", "System"}


def check_manifest_v2(manifest, say):
    """The same rules as LedgeKit's AddOnManifest.validate(). Capabilities are open: any well-formed name is
    accepted, and Ledge grants only those it supports, so a new capability doesn't need this repo to change."""
    if not re.fullmatch(r"[A-Za-z0-9_-]+", str(manifest.get("executable", ""))):
        say("executable must be a file name: letters, digits, hyphens and underscores")
    if manifest.get("icon") != "Assets/Icon.png":
        say("icon must be Assets/Icon.png")
    for field in ["capabilities", "surfaces"]:
        names = manifest.get(field, [])
        if not isinstance(names, list) or not all(isinstance(n, str) and NAME.fullmatch(n) for n in names):
            say(f"{field} must be lowercase names: letters, digits and hyphens")
        elif len(set(names)) != len(names):
            say(f"{field} lists a name twice")
    if not isinstance(manifest.get("capabilities"), list):
        say("addon.json needs a capabilities list (it can be empty)")
    for field, value in [("kit.minAPI", (manifest.get("kit") or {}).get("minAPI")), ("minLedge", manifest.get("minLedge"))]:
        if value is not None and not RELEASE_VERSION.fullmatch(str(value)):
            say(f"{field} must look like 1.2.3")
    if "kit" in manifest and "minAPI" not in (manifest["kit"] or {}):
        say("kit needs a minAPI")
    if manifest.get("minMacOS") is not None and not re.fullmatch(r"\d+(\.\d+){0,2}", str(manifest["minMacOS"])):
        say("minMacOS must look like 14 or 14.5")
    if manifest.get("category") is not None and manifest["category"] not in CATEGORIES:
        say(f"category must be one of {', '.join(sorted(CATEGORIES))}")
    if "creator" in manifest and not str((manifest["creator"] or {}).get("name", "")).strip():
        say("creator needs a name")
    keywords = manifest.get("keywords", [])
    if not isinstance(keywords, list) or len(keywords) > 20 or any(len(str(k)) > 40 for k in keywords):
        say("keywords: at most 20, each at most 40 characters")


def requirements(manifest):
    """What a Ledge needs to run the add-on, as the catalog publishes it: Ledge reads this to mark an add-on it
    can't run before anyone installs it."""
    requires = {"protocolVersion": manifest.get("protocolVersion", 1)}
    if (manifest.get("kit") or {}).get("minAPI"):
        requires["kit"] = manifest["kit"]["minAPI"]
    if manifest.get("minLedge"):
        requires["ledge"] = manifest["minLedge"]
    if manifest.get("minMacOS"):
        requires["macOS"] = manifest["minMacOS"]
    return requires


def check_folder(package, problems):
    addon_id = package.name
    say = lambda message: problems.append(f"{addon_id}: {message}")
    files = tracked_files(package)
    if not files:
        say("the folder is empty or entirely ignored by git")
        return None
    for path in files:
        relative = path.relative_to(package)
        if relative.parts[0] not in ALLOWED_TOP:
            say(f"'{relative.parts[0]}' isn't allowed in an add-on folder (see CONTRIBUTING.md)")
        if REFUSED_PARTS.intersection(relative.parts) or path.suffix in REFUSED_SUFFIXES:
            say(f"'{relative}' is a build product or tool file and can't be submitted")
        if path.exists():
            limit = LIMITS.get(path.suffix.lower(), DEFAULT_LIMIT) if relative.parts[0] == "Store" else DEFAULT_LIMIT
            if path.stat().st_size > limit:
                say(f"'{relative}' is larger than {limit // (1024 * 1024)} MB")
    tracked = {path.relative_to(package).as_posix() for path in files}
    for required in REQUIRED:
        if required not in tracked:
            say(f"{required} is missing")
    if not any(name.startswith("Sources/") for name in tracked):
        say("Sources/ is missing")
    if not any(name.startswith("Tests/") for name in tracked):
        say("Tests/ is missing: every add-on ships with tests")
    if "listing.json" not in tracked and addon_id not in NO_LISTING_YET:
        say("listing.json is missing (see LISTING.md)")
    if "addon.json" not in tracked:
        return None

    manifest = json.loads((package / "addon.json").read_text())
    if manifest.get("id") != addon_id:
        say(f"addon.json id '{manifest.get('id')}' must equal the folder name")
    if not re.fullmatch(r"[a-z0-9-]{1,64}", addon_id):
        say("the folder name must be lowercase letters, digits and hyphens")
    version = str(manifest.get("version", ""))
    if not re.fullmatch(r"\d+\.\d+\.\d+", version):
        say(f"version '{version}' must look like 1.2.3")
        return None
    if manifest.get("protocolVersion") not in (1, 2):
        say("protocolVersion must be 1 (one run per request) or 2 (a long-lived session)")
    check_manifest_v2(manifest, say)
    for key in ["name", "author", "summary", "description"]:
        if not str(manifest.get(key, "")).strip():
            say(f"addon.json needs a {key}")

    if (package / "CHANGELOG.md").exists():
        headings = CHANGELOG_HEADING.findall((package / "CHANGELOG.md").read_text())
        if not headings:
            say("CHANGELOG.md has no '## 1.2.3' heading")
        elif headings[0] != version:
            say(f"CHANGELOG.md's newest entry is {headings[0]}, but addon.json says {version}; add a '## {version}' entry at the top")
    return manifest


def build_inputs_changed(package, commit):
    """Whether anything that goes into the build changed since `commit`, the commit the Store was published from."""
    if git("cat-file", "-e", f"{commit}^{{commit}}").returncode != 0:
        raise SystemExit(f"The published commit {commit} isn't in this checkout. Fetch full history (git fetch --unshallow) and run again.")
    paths = [str((package / name).relative_to(ROOT)) for name in BUILD_INPUTS]
    return git("diff", "--quiet", commit, "--", *paths).returncode != 0


def plan(verbose=True):
    """Checks every add-on and returns ({id: "build" | "reuse" | "retired"}, published catalog or None)."""
    problems = []
    retired = retired_ids()
    catalog = published_catalog()
    published = {entry["id"]: entry for entry in (catalog or {}).get("entries", [])}
    decisions = {}
    folders = sorted(path for path in (ROOT / "add-ons").glob("*") if path.is_dir())
    for package in folders:
        addon_id = package.name
        if addon_id in retired:
            decisions[addon_id] = "retired"
            continue
        manifest = check_folder(package, problems)
        if manifest is None or not re.fullmatch(r"\d+\.\d+\.\d+", str(manifest.get("version", ""))):
            continue
        version = manifest["version"]
        current = published.get(addon_id)
        if current is None:
            decisions[addon_id] = "build"
        elif version_key(version) < version_key(current["version"]):
            problems.append(f"{addon_id}: version {version} is lower than the published {current['version']}; versions only move forward")
        elif version_key(version) > version_key(current["version"]):
            decisions[addon_id] = "build"
        elif build_inputs_changed(package, catalog["sourceCommit"]):
            problems.append(f"{addon_id}: Sources, Package files, addon.json or Assets changed since {current['version']} was published; "
                            f"raise version in addon.json and add a CHANGELOG.md entry")
        else:
            decisions[addon_id] = "reuse"
    for addon_id in retired:
        if not (ROOT / "add-ons" / addon_id).is_dir():
            problems.append(f"retired.json lists '{addon_id}', which has no folder")
    if problems:
        print("Validation failed:\n  " + "\n  ".join(problems), file=sys.stderr)
        raise SystemExit(1)
    if verbose:
        source = f"published catalog {catalog['sourceCommit'][:10]}" if catalog else "no published catalog (offline or first release)"
        print(f"Checked {len(folders)} add-ons against {source}:")
        for addon_id, decision in decisions.items():
            note = f" ({retired[addon_id]})" if decision == "retired" and retired[addon_id] else ""
            print(f"  {addon_id}: {decision}{note}")
    return decisions, catalog


if __name__ == "__main__":
    plan()
