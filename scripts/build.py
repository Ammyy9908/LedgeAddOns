#!/usr/bin/env python3
"""Build reviewed packages. Run without write tokens or signing secrets.

Only add-ons whose version went up (or that are new) are built from source. An add-on at the same version as
the Store is republished from the files already published, checked against their hashes, so a published build
never changes. Ledge accepts only files under the catalog's own release, which is why those files are copied
into this release rather than linked to the old one.
"""
import hashlib, json, pathlib, re, shutil, subprocess, sys, time, urllib.error, urllib.request

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import validate  # noqa: E402

root = validate.ROOT
dist = root / "dist"
shutil.rmtree(dist, ignore_errors=True)
dist.mkdir()
commit = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=root, text=True).strip()
base = f"https://github.com/Ammyy9908/LedgeAddOns/releases/download/catalog-{commit}/"
decisions, published = validate.plan()
published_entries = {entry["id"]: entry for entry in (published or {}).get("entries", [])}
entries = []
# Apple Music Controls ships its QueueBridge dynamic library under the manifest's executable name.


def record(destination):
    data = destination.read_bytes()
    assert len(data) <= 32 * 1024 * 1024
    return {"url": base + destination.name, "sha256": hashlib.sha256(data).hexdigest()}


def fetch_published(asset, destination):
    """Copies a published file into this release, refusing it if its bytes don't match the published hash."""
    # GitHub redirects release downloads to short-lived signed links, which can expire on a slow connection
    # ("jwt:expired"). Each attempt asks GitHub for a fresh link.
    for attempt in range(4):
        try:
            with urllib.request.urlopen(asset["url"], timeout=120) as response:
                data = response.read(32 * 1024 * 1024 + 1)
            break
        except (urllib.error.URLError, TimeoutError) as error:
            if attempt == 3:
                raise
            print(f"Retrying {asset['url']}: {error}", file=sys.stderr)
            time.sleep(2 ** attempt)
    assert hashlib.sha256(data).hexdigest() == asset["sha256"], f"{asset['url']} doesn't match its published hash"
    destination.write_bytes(data)


for addon_id, decision in decisions.items():
    if decision == "retired":
        continue
    package = root / "add-ons" / addon_id
    manifest = json.loads((package / "addon.json").read_text())
    # 1: one program run per request. 2: a long-lived session (LedgeKit 0.3.0 and later).
    assert manifest["protocolVersion"] in (1, 2), f"{addon_id}: unsupported protocolVersion"
    executable = manifest["executable"]
    assert re.fullmatch(r"[A-Za-z0-9_-]+", executable)
    assert manifest["icon"] == "Assets/Icon.png"
    files = {}
    names = {"executable": addon_id + ".binary", "manifest": addon_id + ".manifest.json", "icon": addon_id + ".icon.png"}
    if decision == "reuse":
        for key, name in names.items():
            fetch_published(published_entries[addon_id]["files"][key], dist / name)
            files[key] = record(dist / name)
    else:
        subprocess.run(["swift", "test", "--package-path", str(package)], check=True)
        command = ["swift", "build", "--package-path", str(package), "-c", "release",
                   "--arch", "arm64", "--arch", "x86_64"]
        subprocess.run(command, check=True)
        binary_dir = pathlib.Path(subprocess.check_output(command + ["--show-bin-path"], text=True).strip())
        sources = {"executable": binary_dir / executable,
                   "manifest": package / "addon.json", "icon": package / "Assets/Icon.png"}
        for key, name in names.items():
            destination = dist / name
            shutil.copyfile(sources[key], destination)
            if key == "executable":
                destination.chmod(0o755)
                subprocess.run(["codesign", "--force", "--sign", "-", str(destination)], check=True)
            files[key] = record(destination)
    # Store listings can change without a new version, so they always come from the folder as it is now.
    listing_path = package / "listing.json"
    listing = json.loads(listing_path.read_text()) if listing_path.exists() else None
    if listing is not None:
        from urllib.parse import urlparse
        for field, limit in [("developer", 120), ("category", 60), ("availability", 120), ("description", 10000)]:
            assert isinstance(listing[field], str) and 0 < len(listing[field]) <= limit
        feedback = urlparse(listing["feedbackURL"])
        assert feedback.scheme == "https" and feedback.hostname and not feedback.username and not feedback.password
        assert "installs" not in listing, "Install counts are service-owned, never developer supplied"

        def publish_media(relative, suffix, limit):
            source = (package / relative).resolve()
            assert source.is_relative_to(package.resolve()) and source.is_file()
            assert source.suffix.lower() == suffix
            data = source.read_bytes()
            assert 0 < len(data) <= limit
            name = addon_id + ".preview-" + hashlib.sha256(data).hexdigest()[:16] + suffix
            shutil.copyfile(source, dist / name)
            return {"url": base + name, "sha256": hashlib.sha256(data).hexdigest()}
        assert 1 <= len(listing["screenshots"]) <= 8, "At least one screenshot is required"
        listing["screenshots"] = [publish_media(path, ".png", 8 * 1024 * 1024) for path in listing["screenshots"]]
        listing["motionDemo"] = publish_media(listing["motionDemo"], ".mp4", 32 * 1024 * 1024)
    # Capabilities are open: validate.py checked the names, and Ledge grants only those it supports.
    entries.append({"id": addon_id, "name": manifest["name"], "summary": manifest["summary"],
                    "version": manifest["version"], "architectures": ["arm64", "x86_64"],
                    "requires": validate.requirements(manifest),
                    "files": files, **({"listing": listing} if listing is not None else {})})
(dist / "catalog.json").write_text(json.dumps({"schemaVersion": 1, "sourceCommit": commit,
                                             "entries": entries}, indent=2) + "\n")
built = sum(1 for d in decisions.values() if d == "build")
print(f"Built {built} and republished {len(entries) - built} catalog entries at {commit}")
