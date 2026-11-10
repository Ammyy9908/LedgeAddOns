#!/usr/bin/env python3
"""Build reviewed packages. Run without write tokens or signing secrets."""
import hashlib, json, pathlib, re, shutil, subprocess

root = pathlib.Path(__file__).resolve().parents[1]
dist = root / "dist"
dist.mkdir(exist_ok=True)
commit = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=root, text=True).strip()
base = f"https://github.com/Ammyy9908/LedgeAddOns/releases/download/catalog-{commit}/"
entries = []
# Add-ons whose host loads a native module rather than running the executable target.
# Apple Music Controls ships its QueueBridge dynamic library under the manifest's executable name.
packaged_binaries = {"apple-music-queue": "libQueueBridge.dylib"}
for package in sorted((root / "add-ons").glob("*")) if (root / "add-ons").exists() else []:
    manifest = json.loads((package / "addon.json").read_text())
    addon_id = manifest["id"]
    assert re.fullmatch(r"[a-z0-9-]{1,64}", addon_id) and package.name == addon_id
    assert re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", manifest["version"])
    assert manifest["protocolVersion"] == 1
    supported = {"spotify-likes": ["spotify-library"], "notifications": ["notification-banners"],
                 "apple-music-queue": ["apple-music-queue", "apple-music-controls"]}
    assert addon_id in supported and manifest["capabilities"] == supported[addon_id]
    executable = manifest["executable"]
    assert re.fullmatch(r"[A-Za-z0-9_-]+", executable)
    assert manifest["icon"] == "Assets/Icon.png"
    assert all(manifest[k].strip() for k in ["name", "author", "summary", "description"])
    subprocess.run(["swift", "test", "--package-path", str(package)], check=True)
    command = ["swift", "build", "--package-path", str(package), "-c", "release",
               "--arch", "arm64", "--arch", "x86_64"]
    subprocess.run(command, check=True)
    binary_dir = pathlib.Path(subprocess.check_output(command + ["--show-bin-path"], text=True).strip())
    files = {}
    for key, source, name in [
        ("executable", binary_dir / packaged_binaries.get(addon_id, executable), addon_id + ".binary"),
        ("manifest", package / "addon.json", addon_id + ".manifest.json"),
        ("icon", package / "Assets/Icon.png", addon_id + ".icon.png")
    ]:
        destination = dist / name
        shutil.copyfile(source, destination)
        if key == "executable":
            destination.chmod(0o755)
            subprocess.run(["codesign", "--force", "--sign", "-", str(destination)], check=True)
        data = destination.read_bytes()
        assert len(data) <= 32 * 1024 * 1024
        files[key] = {"url": base + name, "sha256": hashlib.sha256(data).hexdigest()}
    listing_path = package / "listing.json"
    assert listing_path.exists() or addon_id == "spotify-likes", "New submissions require listing.json"
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
    entries.append({"id": addon_id, "name": manifest["name"], "summary": manifest["summary"],
                    "version": manifest["version"], "architectures": ["arm64", "x86_64"],
                    "files": files, **({"listing": listing} if listing is not None else {})})
(dist / "catalog.json").write_text(json.dumps({"schemaVersion": 1, "sourceCommit": commit,
                                             "entries": entries}, indent=2) + "\n")
print(f"Built {len(entries)} catalog entries at {commit}")
