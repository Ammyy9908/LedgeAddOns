## Add-on
Name, id, version, and what it does:

## Capabilities and data
Every capability, network destination and credential it uses, and what it stores:

## Checklist
- [ ] `python3 scripts/validate.py` passes
- [ ] Tests pass (`swift test --package-path add-ons/<id>`)
- [ ] Loaded and tried in Ledge (`python3 scripts/package.py <id>`, then Load Add-on…)
- [ ] `version` raised in `addon.json` and a matching `CHANGELOG.md` entry added (new add-ons: first entry)
- [ ] LedgeKit pinned to a published release
- [ ] No credentials, build products or private content in the folder or Store media
- [ ] I have the rights to the icon, screenshots and demo
- [ ] Failure and removal behaviour checked

## What was tested
What you verified, and what you couldn't:
