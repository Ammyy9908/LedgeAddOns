#!/usr/bin/env python3
"""Builds one add-on into a .ledgeaddon folder you can load in Ledge (Settings, Add-on Store, Load Add-on…).

  python3 scripts/package.py <id> [output folder]

The result is for your own Mac: built for its architecture and ad-hoc signed. The Store's builds come from CI.
"""
import json, pathlib, shutil, subprocess, sys

root = pathlib.Path(__file__).resolve().parents[1]
if len(sys.argv) < 2:
    raise SystemExit(__doc__)
package = root / "add-ons" / sys.argv[1]
manifest = json.loads((package / "addon.json").read_text())
output = pathlib.Path(sys.argv[2]).resolve() if len(sys.argv) > 2 else package / ".build" / "addons"

subprocess.run(["swift", "build", "--package-path", str(package), "-c", "release"], check=True)
bin_dir = pathlib.Path(subprocess.check_output(
    ["swift", "build", "--package-path", str(package), "-c", "release", "--show-bin-path"], text=True).strip())
name = manifest["executable"]
bundle = output / f"{name}.ledgeaddon"
shutil.rmtree(bundle, ignore_errors=True)
(bundle / "Assets").mkdir(parents=True)
shutil.copyfile(bin_dir / name, bundle / name)
(bundle / name).chmod(0o755)
shutil.copyfile(package / "addon.json", bundle / "addon.json")
shutil.copyfile(package / "Assets/Icon.png", bundle / "Assets/Icon.png")
subprocess.run(["codesign", "--force", "--sign", "-", str(bundle / name)], check=True)
print(bundle)
