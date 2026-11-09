#!/usr/bin/env python3
"""Build reviewed packages. Run without write tokens or signing secrets."""
import hashlib, json, pathlib, re, shutil, subprocess

root = pathlib.Path(__file__).resolve().parents[1]
dist = root / "dist"
dist.mkdir(exist_ok=True)
commit = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=root, text=True).strip()
base = f"https://github.com/Ammyy9908/LedgeAddOns/releases/download/catalog-{commit}/"
entries = []
for package in sorted((root / "add-ons").glob("*")) if (root / "add-ons").exists() else []:
    manifest = json.loads((package / "addon.json").read_text())
    addon_id = manifest["id"]
    assert re.fullmatch(r"[a-z0-9-]{1,64}", addon_id) and package.name == addon_id
    assert re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", manifest["version"])
    assert manifest["protocolVersion"] == 1
    assert manifest["capabilities"] == ["spotify-library"]
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
        ("executable", binary_dir / executable, addon_id + ".binary"),
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
    entries.append({"id": addon_id, "name": manifest["name"], "summary": manifest["summary"],
                    "version": manifest["version"], "architectures": ["arm64", "x86_64"],
                    "files": files})
(dist / "catalog.json").write_text(json.dumps({"schemaVersion": 1, "sourceCommit": commit,
                                             "entries": entries}, indent=2) + "\n")
print(f"Built {len(entries)} catalog entries at {commit}")
