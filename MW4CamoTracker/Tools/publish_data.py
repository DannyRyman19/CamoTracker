#!/usr/bin/env python3
"""
publish_data.py - copy the bundled JSON into Data/MW4/ and regenerate the
manifest the app reads, so new weapons and camos reach installed apps without
an App Store update. The full workflow is in MW4CamoTracker/CONTENT.md.

    python3 MW4CamoTracker/Tools/publish_data.py                 # built-in notification
    python3 MW4CamoTracker/Tools/publish_data.py --silent        # no notification
    python3 MW4CamoTracker/Tools/publish_data.py \\
        --title "Season 1 is live" --body "New weapons and camos to track."
    python3 MW4CamoTracker/Tools/publish_data.py --dry-run       # check only

DataService fetches Data/MW4/manifest.json first and only downloads a file
whose `version` differs from the one it has, so the manifest is generated from
each file's own `version` field rather than typed by hand: a manifest version
that disagrees with the file it points at either re-downloads forever or never
updates at all.

Bump the `version` inside the source JSON when you change it, then run this.
It refuses to publish a file whose content changed but whose version did not,
because installed apps would never fetch it.

What the notification says is decided here, per publish, and written into the
manifest's `notification` block:

  (nothing)            the app's built-in "New Content Available" wording
  --title / --body     your own words. Plain text is English; for more
                       languages pass JSON: --title '{"en": "...", "de": "..."}'
                       Languages you leave out fall back to English.
  --silent             the data goes out and nobody is notified (a fix)

The block is regenerated every time, so a message never carries over to the
next publish by accident.

jsDelivr caches a branch-pinned path (@master) for around 12 hours, so purge
https://purge.jsdelivr.net/gh/DannyRyman19/CamoTracker@master/Data/MW4/manifest.json
(and each changed file, same URL shape) if you need it live sooner. Nothing is
live until the commit is pushed to master.
"""
import argparse
import json
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]          # the CamoTracker repo
RES = ROOT / "MW4CamoTracker" / "Resources"
OUT = ROOT / "Data" / "MW4"
MODES = ["multiplayer", "warzone", "dmz"]
LANGS = ["en", "fr", "es", "de", "nl"]


def load(path):
    return json.loads(path.read_text(encoding="utf-8"))


def version_of(path):
    v = load(path).get("version")
    if not v:
        raise SystemExit(f"{path.name} has no top-level \"version\"")
    return v


def localized(value, flag):
    """Plain text is English; a JSON object is one string per language."""
    value = value.strip()
    if value.startswith("{"):
        try:
            texts = json.loads(value)
        except json.JSONDecodeError as error:
            raise SystemExit(f"{flag}: not valid JSON ({error})")
        if not isinstance(texts, dict) or not all(isinstance(v, str) and v.strip() for v in texts.values()):
            raise SystemExit(f"{flag}: expected an object of non-empty strings, one per language")
        unknown = sorted(set(texts) - set(LANGS))
        if unknown:
            raise SystemExit(f"{flag}: unknown language(s) {', '.join(unknown)} (the app ships {', '.join(LANGS)})")
        if "en" not in texts:
            raise SystemExit(f"{flag}: include \"en\"; it is what every other language falls back to")
        return texts
    if not value:
        raise SystemExit(f"{flag}: empty")
    return {"en": value}


def check(problems, warnings):
    """Things that would break installed apps or lose players' progress."""
    catalog = load(RES / "weapons.json")
    weapon_ids = [w["weaponId"] for c in catalog["categories"] for w in c["weapons"]]
    category_ids = [c["categoryId"] for c in catalog["categories"]]
    for name, ids in (("weaponId", weapon_ids), ("categoryId", category_ids)):
        dupes = sorted({i for i in ids if ids.count(i) > 1})
        if dupes:
            problems.append(f"weapons.json: duplicate {name} {dupes}")
    for c in catalog["categories"]:
        for w in c["weapons"]:
            missing = [l for l in LANGS if not (w.get("name") or {}).get(l)]
            if missing:
                warnings.append(f"weapons.json: weapon {w['weaponId']} has no name in {', '.join(missing)}")
            if not w.get("imageURL"):
                warnings.append(f"weapons.json: weapon {w['weaponId']} ({w['name'].get('en')}) has no imageURL")

    # Progress is stored against these ids. One that disappears from a
    # published file strands whatever players had logged on it.
    published_catalog = OUT / "weapons.json"
    if published_catalog.exists():
        before = {w["weaponId"] for c in load(published_catalog)["categories"] for w in c["weapons"]}
        gone = sorted(before - set(weapon_ids))
        if gone:
            problems.append(f"weapons.json: weaponId {gone} is published but missing now; ids must never be removed or renumbered")

    for mode in MODES:
        data = load(RES / f"{mode}.json")
        if data.get("mode") != mode:
            problems.append(f"{mode}.json: \"mode\" is {data.get('mode')!r}")
        seen = [e["weaponId"] for e in data["weaponCamos"]]
        unknown = sorted(set(seen) - set(weapon_ids))
        if unknown:
            problems.append(f"{mode}.json: camos for weaponId {unknown}, which weapons.json does not have")
        without = sorted(set(weapon_ids) - set(seen))
        if without:
            warnings.append(f"{mode}.json: no camos for weaponId {without} (the weapon shows \"no camo data\" in this mode)")
        for entry in data["weaponCamos"]:
            item_ids = [c["itemId"] for c in entry["camos"]]
            if len(item_ids) != len(set(item_ids)):
                problems.append(f"{mode}.json: weapon {entry['weaponId']} has duplicate camo itemIds")
        published = OUT / f"{mode}.json"
        if published.exists():
            before = {e["weaponId"]: {c["itemId"] for c in e["camos"]} for e in load(published)["weaponCamos"]}
            now = {e["weaponId"]: {c["itemId"] for c in e["camos"]} for e in data["weaponCamos"]}
            for weapon_id, items in before.items():
                gone = sorted(items - now.get(weapon_id, set()))
                if gone:
                    problems.append(f"{mode}.json: weapon {weapon_id} lost camo itemId {gone}; ids must never be removed or renumbered")


def main():
    ap = argparse.ArgumentParser(description="Publish the MW4 data and its manifest.")
    ap.add_argument("--title", help="notification title: plain text (English) or a JSON object per language")
    ap.add_argument("--body", help="notification body, same forms as --title")
    ap.add_argument("--silent", action="store_true", help="publish without notifying anyone")
    ap.add_argument("--dry-run", action="store_true", help="check and report; write nothing")
    args = ap.parse_args()
    if args.silent and (args.title or args.body):
        raise SystemExit("--silent and --title/--body contradict each other")

    files = ["weapons"] + MODES
    problems, warnings, changed = [], [], []
    for name in files:
        src, dst = RES / f"{name}.json", OUT / f"{name}.json"
        try:
            new = load(src)
        except json.JSONDecodeError as error:
            raise SystemExit(f"{src.name} is not valid JSON: {error}")
        if not new.get("version"):
            problems.append(f"{src.name}: no top-level \"version\"")
            continue
        if not dst.exists():
            changed.append((name, None, new["version"]))
            continue
        old = load(dst)
        if old == new:
            continue
        if old.get("version") == new["version"]:
            problems.append(f"{src.name}: the content changed but \"version\" is still {new['version']}; bump it or installed apps never fetch the change")
        else:
            changed.append((name, old.get("version"), new["version"]))
    check(problems, warnings)

    for line in warnings:
        print(f"warning: {line}")
    if problems:
        for line in problems:
            print(f"error: {line}", file=sys.stderr)
        raise SystemExit(1)

    notification = None
    if args.silent:
        notification = {"silent": True}
    elif args.title or args.body:
        notification = {}
        if args.title:
            notification["title"] = localized(args.title, "--title")
        if args.body:
            notification["body"] = localized(args.body, "--body")

    manifest = {"catalog": {"version": version_of(RES / "weapons.json"), "path": "weapons.json"}, "modes": {}}
    for mode in MODES:
        manifest["modes"][mode] = {"version": version_of(RES / f"{mode}.json"), "path": f"{mode}.json"}
    if notification:
        manifest["notification"] = notification

    if changed:
        print("changed:")
        for name, old, new in changed:
            print(f"  {name:12} {old or 'new'} -> {new}")
    else:
        print("no data changed: installed apps will fetch nothing and notify nobody")
    if not changed:
        said = "n/a"
    elif args.silent:
        said = "none (silent)"
    elif notification:
        said = "custom: " + json.dumps(notification, ensure_ascii=False)
    else:
        said = "the app's built-in wording"
    print(f"notification: {said}")

    if args.dry_run:
        print("dry run: nothing written")
        return
    if not changed and not notification and (OUT / "manifest.json").exists():
        # A second run after a publish must not quietly strip the message
        # (or the silence) the first one wrote. To change it, pass the flags.
        print("manifest left as it is")
        return

    OUT.mkdir(parents=True, exist_ok=True)
    for name in files:
        shutil.copy2(RES / f"{name}.json", OUT / f"{name}.json")
    (OUT / "manifest.json").write_text(
        json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"published -> {OUT}")
    print("next: commit Resources/ and Data/MW4/ together and push to master. It is live once pushed (purge jsDelivr to skip its cache).")


if __name__ == "__main__":
    main()
