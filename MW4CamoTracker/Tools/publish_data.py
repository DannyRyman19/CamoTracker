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
    python3 MW4CamoTracker/Tools/publish_data.py --game bo6      # another game

Every game in Resources/games.json publishes to its own `path` (BO6 to
Data/CT/BO6/) from its own bundled files (`bo6_weapons.json`...), with the
prefix dropped there. MW4, with no prefix, is the default.

DataService fetches Data/MW4/manifest.json first and only downloads a file
whose `version` is numerically higher than the one it has (DataService.isNewer:
dotted numbers compared one by one, "0.9.12" > "0.9.9"), so the manifest is
generated from each file's own `version` field rather than typed by hand: a
manifest version that disagrees with the file it points at either re-downloads
forever or never updates at all.

Bump the `version` inside the source JSON when you change it, then run this.
It refuses to publish a file whose content changed but whose version did not,
a version that isn't plain dotted numbers ("0.9.11a"), and a changed file
whose version isn't higher than the live one, because installed apps would
never fetch it. "Live" is what the app reads: the file on jsDelivr, and the
same file on origin/master (newer while jsDelivr still caches the old one).
When jsDelivr can't be reached it says so and uses origin/master alone, as of
the last `git fetch`.

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
import re
import shutil
import subprocess
import sys
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]          # the CamoTracker repo
RES = ROOT / "MW4CamoTracker" / "Resources"
OUT = ROOT / "Data" / "MW4"
MODES = ["multiplayer", "warzone", "dmz"]
# Reference guides: listed under the manifest's own "guides" block (old app
# versions read every "modes" entry as a camo file). A guide change never
# posts a notification; the app picks it up quietly.
GUIDES = ["hajin"]
# Bundled files are `<PREFIX><name>.json`; MW4's have none
PREFIX = ""
# Where installed apps fetch from: Game.dataURL in Games.swift, plus OUT's
# path in the repo
CDN = "https://cdn.jsdelivr.net/gh/DannyRyman19/CamoTracker@master/"


def use_game(game_id):
    """Point OUT, MODES, GUIDES and PREFIX at a game from games.json."""
    global OUT, MODES, GUIDES, PREFIX
    games = {g["id"]: g for g in load(RES / "games.json")}
    if game_id not in games:
        raise SystemExit(f"--game: no game {game_id!r} (games.json has {', '.join(games)})")
    game = games[game_id]
    OUT = ROOT / game["path"]
    MODES = [m["id"] for m in game["modes"]]
    PREFIX = game["seedPrefix"]
    if game_id != "mw4":
        GUIDES = []


def src(name):
    return RES / f"{PREFIX}{name}.json"
LANGS = ["en", "fr", "es", "de", "it", "nl"]


def load(path):
    return json.loads(path.read_text(encoding="utf-8"))


def version_of(path):
    v = load(path).get("version")
    if not v:
        raise SystemExit(f"{path.name} has no top-level \"version\"")
    return v


def swift_int(part):
    """Swift's `Int(part) ?? 0`: an optional sign and digits, in range."""
    if not re.fullmatch(r"[+-]?[0-9]+", part):
        return 0
    value = int(part)
    return value if -2**63 <= value < 2**63 else 0


def is_newer(version, known):
    """DataService.isNewer, exactly: whether an installed app holding `known`
    downloads `version`. Change one, change both."""
    if known is None:
        return True
    # Swift's split(separator:) drops empty parts
    a = [swift_int(p) for p in version.split(".") if p]
    b = [swift_int(p) for p in known.split(".") if p]
    for i in range(max(len(a), len(b))):
        x = a[i] if i < len(a) else 0
        y = b[i] if i < len(b) else 0
        if x != y:
            return x > y
    return False


def plain_version(version):
    """Dotted numbers only: what is_newer reads the way it looks."""
    return isinstance(version, str) and re.fullmatch(r"[0-9]+(\.[0-9]+)*", version) is not None


def fetch_cdn(name):
    """The live file from jsDelivr, as the app gets it: (data, None), (None,
    None) when it isn't published, or (None, reason) when it can't be read."""
    url = CDN + f"{OUT.relative_to(ROOT).as_posix()}/{name}.json"
    try:
        with urllib.request.urlopen(urllib.request.Request(url, headers={"Cache-Control": "no-cache"}), timeout=20) as response:
            return json.loads(response.read().decode("utf-8")), None
    except urllib.error.HTTPError as error:
        if error.code == 404:
            return None, None
        return None, f"HTTP {error.code}"
    except (urllib.error.URLError, TimeoutError, OSError, ValueError) as error:
        return None, str(getattr(error, "reason", error))


def fetch_origin(name):
    """The file on origin/master as of the last fetch: (data, None), (None,
    None) when it isn't there, or (None, reason)."""
    path = f"{OUT.relative_to(ROOT).as_posix()}/{name}.json"
    run = subprocess.run(["git", "-C", str(ROOT), "show", f"origin/master:{path}"], capture_output=True, text=True)
    if run.returncode != 0:
        if "does not exist" in run.stderr or "exists on disk, but not in" in run.stderr:
            return None, None
        return None, run.stderr.strip() or "git show failed"
    try:
        return json.loads(run.stdout), None
    except json.JSONDecodeError as error:
        return None, f"not valid JSON ({error})"


def live_problems(file_name, new, live, where):
    """Why `new` can't replace a live copy (None if nothing is live): a file
    that differs from it must carry a higher version, or no app fetches it."""
    if live is None or live == new:
        return []
    old = live.get("version")
    if old is None or is_newer(new["version"], old):
        return []
    return [f"{file_name}: \"version\" {new['version']} is not higher than the live {old} ({where}); "
            "installed apps only fetch a higher number, so bump it past the live one"]


def check_live(files, problems):
    """Compares every file with what is live (see the top of this file)."""
    cdn_failed = []
    for name in files:
        new = load(src(name))
        if not new.get("version"):
            continue
        copies = []
        live, failed = fetch_cdn(name)
        if failed:
            cdn_failed.append(f"{name}.json ({failed})")
        else:
            copies.append((live, "jsDelivr"))
        origin, failed = fetch_origin(name)
        if failed:
            problems.append(f"{name}.json: can't read origin/master's copy to compare versions: {failed}")
        elif origin != live:
            copies.append((origin, "origin/master"))
        for copy, where in copies:
            problems.extend(live_problems(src(name).name, new, copy, where))
    if cdn_failed:
        print(f"warning: couldn't fetch the live copy from jsDelivr for {', '.join(cdn_failed)}; "
              "compared versions with origin/master as of the last git fetch instead")
    else:
        print("versions compared with the live copies (jsDelivr and origin/master)")


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
    catalog = load(src("weapons"))
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
        data = load(src(mode))
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
    ap.add_argument("--game", default="mw4", help="which game in Resources/games.json (default mw4)")
    args = ap.parse_args()
    use_game(args.game)
    if args.silent and (args.title or args.body):
        raise SystemExit("--silent and --title/--body contradict each other")

    files = ["weapons"] + MODES + GUIDES
    problems, warnings, changed = [], [], []
    for name in files:
        source, dst = src(name), OUT / f"{name}.json"
        try:
            new = load(source)
        except json.JSONDecodeError as error:
            raise SystemExit(f"{source.name} is not valid JSON: {error}")
        if not new.get("version"):
            problems.append(f"{source.name}: no top-level \"version\"")
            continue
        if not plain_version(new["version"]):
            problems.append(f"{source.name}: \"version\" {new['version']!r} must be dotted numbers like 0.9.12; "
                            "the app reads any other part as 0, so it would never fetch this file")
        if not dst.exists():
            changed.append((name, None, new["version"]))
            continue
        old = load(dst)
        if old == new:
            continue
        if old.get("version") == new["version"]:
            problems.append(f"{source.name}: the content changed but \"version\" is still {new['version']}; bump it or installed apps never fetch the change")
        else:
            changed.append((name, old.get("version"), new["version"]))
    check(problems, warnings)
    check_live(files, problems)

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

    manifest = {"catalog": {"version": version_of(src("weapons")), "path": "weapons.json"}, "modes": {}}
    for mode in MODES:
        manifest["modes"][mode] = {"version": version_of(src(mode)), "path": f"{mode}.json"}
    if GUIDES:
        manifest["guides"] = {g: {"version": version_of(src(g)), "path": f"{g}.json"} for g in GUIDES}
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
        shutil.copy2(src(name), OUT / f"{name}.json")
    (OUT / "manifest.json").write_text(
        json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"published -> {OUT}")
    print(f"next: commit Resources/ and {OUT.relative_to(ROOT)}/ together and push to master. It is live once pushed (purge jsDelivr to skip its cache).")


if __name__ == "__main__":
    main()
