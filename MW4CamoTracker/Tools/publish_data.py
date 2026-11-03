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
    python3 MW4CamoTracker/Tools/publish_data.py --allow-removed op-old-op   # a tick key dropped on purpose

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

It also refuses a file the app's JSONDecoder would reject (the Codable models
are mirrored below), a Hajin guide link to an id that isn't there, a
published Prestige camo moved from its place, and a published mode's
`trackFrom` changed (--allow-trackfrom-change if meant). A saved tick key the
new file drops (a Hajin row's `check`, an objective) is a loud warning;
--allow-removed KEY[,KEY...] (or `all`) says it's meant.

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
import math
import re
import shutil
import subprocess
import sys
import urllib.error
import urllib.request
from collections import Counter
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


# What the app's Codable models decode, as data, so a file that would fail
# JSONDecoder on a phone is caught here instead. Swift's synthesized
# Decodable: a key is required unless its type is optional (`T?`), and then
# it may be missing or null; Int takes whole numbers only, Double any number,
# Bool only true/false; keys the model doesn't name are ignored. Mirror any
# change to Models.swift, HajinModels.swift (HajinGuide) or DataService.swift
# (Manifest) here.
STR, INT, DOUBLE, BOOL = "a string", "an Int", "a number", "true or false"


def opt(kind):
    return ("optional", kind)


def array(kind):
    return ("array", kind)


def dictionary(kind):
    return ("dictionary", kind)


TEXT = dictionary(STR)                          # LocalizedText
GUIDE_TEXT = ("either", STR, TEXT)              # GuideText: plain English or per language

REQUIREMENT = {"amount": INT, "unit": STR, "description": TEXT}
CHALLENGE_ITEM = {
    "itemId": INT, "name": TEXT, "imageURL": opt(STR), "tier": opt(INT), "unlockLevel": opt(INT),
    "requirement": opt(REQUIREMENT), "group": opt(STR), "section": opt(TEXT), "extra": opt(BOOL),
    "counter": opt(INT),
}
CHALLENGE_ITEM["children"] = array(CHALLENGE_ITEM)
STEP = {
    "name": opt(TEXT), "colors": opt(array(STR)), "imageURL": opt(STR), "requirement": opt(REQUIREMENT),
    "byCategory": opt(dictionary(REQUIREMENT)), "byWeapon": opt(dictionary(REQUIREMENT)), "unlock": opt(STR),
    "needed": opt(INT), "neededByCategory": opt(dictionary(INT)),
}
TIER = {
    "kind": opt(STR), "name": opt(TEXT), "weaponsNeeded": opt(INT), "colors": opt(array(STR)), "imageURL": opt(STR),
    "requirement": opt(REQUIREMENT), "byCategory": opt(dictionary(REQUIREMENT)),
    "byWeapon": opt(dictionary(REQUIREMENT)), "unlock": opt(STR), "needed": opt(INT),
}
MODE_FILE = {
    "version": STR,
    "mode": STR,
    "weaponCamos": array({"weaponId": INT, "camos": array(CHALLENGE_ITEM)}),
    "objectives": array({"categoryId": INT, "name": TEXT, "items": array(CHALLENGE_ITEM)}),
    "mastery": opt({"unlock": opt(STR), "tier1": opt(TIER), "tier2": opt(TIER), "tier3": opt(TIER)}),
    "completionist": opt({
        "steps": opt(array(STEP)),
        "final": opt({"enabled": opt(BOOL), "name": opt(TEXT), "colors": opt(array(STR)), "imageURL": opt(STR),
                      "harmonicBreaksNeeded": opt(INT)}),
    }),
    "trackFrom": opt(STR),
    "specialsAfterMilitary": opt(BOOL),
    "hidden": opt(BOOL),
}
WEAPON_CATALOG = {
    "version": STR,
    "baseWeaponCount": opt(INT),
    "weaponPrestige": opt(array({"name": TEXT, "maxLevel": opt(INT)})),
    "prestigeCamos": opt(array({
        "name": TEXT, "stage": opt(INT), "level": opt(INT), "afterWeaponMaxLevel": opt(BOOL), "imageURL": opt(STR),
        "colors": opt(array(STR)), "weaponsNeeded": opt(INT),
        "byWeapon": opt(dictionary({"name": opt(TEXT), "imageURL": opt(STR), "level": opt(INT),
                                    "colors": opt(array(STR))})),
    })),
    "categories": array({
        "categoryId": INT, "name": TEXT,
        "weapons": array({"weaponId": INT, "name": TEXT, "imageURL": opt(STR), "maxLevel": INT,
                          "unlockRequirement": opt(TEXT)}),
    }),
}
COST = {"item": STR, "qty": INT}
HAJIN_GUIDE = {
    "version": STR,
    "updated": opt(STR),
    "map": {"image": STR, "credit": opt(STR)},
    "threatLevels": array(GUIDE_TEXT),
    "categories": array({"id": STR, "name": GUIDE_TEXT, "symbol": STR, "color": STR, "visible": BOOL,
                         "blurb": opt(GUIDE_TEXT)}),
    "markers": array({
        "id": STR, "cat": STR, "name": GUIDE_TEXT, "x": DOUBLE, "y": DOUBLE, "threat": opt(INT),
        "note": opt(GUIDE_TEXT), "parts": opt(array({"name": GUIDE_TEXT, "threat": opt(INT)})), "symbol": opt(STR),
    }),
    "guide": array({
        "id": STR, "title": GUIDE_TEXT, "symbol": STR, "intro": opt(GUIDE_TEXT),
        "rows": array({
            "title": GUIDE_TEXT, "value": opt(GUIDE_TEXT), "subtitle": opt(GUIDE_TEXT), "level": opt(INT),
            "image": opt(STR), "group": opt(GUIDE_TEXT), "item": opt(STR), "links": opt(array(STR)),
            "weapon": opt(INT), "check": opt(STR), "place": opt(GUIDE_TEXT), "objectives": opt(array(GUIDE_TEXT)),
            "cash": opt(INT), "rewards": opt(array(GUIDE_TEXT)), "prints": opt(array(COST)),
            "extracts": opt(array(COST)), "tips": opt(array(GUIDE_TEXT)), "pageReward": opt(GUIDE_TEXT),
        }),
    }),
    "items": opt(array({
        "id": STR, "name": GUIDE_TEXT, "kind": STR, "rarity": opt(STR), "image": opt(STR), "symbol": opt(STR),
        "unlock": opt(GUIDE_TEXT), "cost": opt(array(COST)), "cash": opt(INT), "effect": opt(GUIDE_TEXT),
        "value": opt(INT), "note": opt(GUIDE_TEXT), "found": opt(GUIDE_TEXT), "foundPlaces": opt(array(STR)),
        "grid": opt(STR), "marker": opt(STR), "family": opt(STR), "tier": opt(INT), "blueprint": opt(BOOL),
    })),
    "traitTrees": opt(array({"id": STR, "name": GUIDE_TEXT, "color": STR, "shape": STR,
                             "rows": array(array(opt(STR))), "emblem": opt(STR)})),
    "traits": opt(array({"id": STR, "name": opt(GUIDE_TEXT), "tree": opt(STR), "effect": opt(GUIDE_TEXT),
                         "icon": opt(STR)})),
}
ENTRY = {"version": STR, "path": STR}
MANIFEST = {
    "catalog": ENTRY,
    "modes": dictionary(ENTRY),
    "notification": opt({"title": opt(TEXT), "body": opt(TEXT), "silent": opt(BOOL)}),
    "guides": opt(dictionary(ENTRY)),
}
# Past this many, a file's decode problems are counted, not listed: one
# missing key on every camo would otherwise print thousands of lines.
DECODE_LIMIT = 10


def described(value):
    if value is None:
        return "null"
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, dict):
        return "an object"
    if isinstance(value, list):
        return "an array"
    return json.dumps(value, ensure_ascii=False)


def decodes(value, kind, path, found):
    """Appends (path, what's wrong) for every place `value` fails to decode
    as `kind`, the way JSONDecoder would fail on it."""
    if isinstance(kind, tuple) and kind[0] == "optional":
        if value is None:
            return
        kind = kind[1]
    if value is None:
        found.append((path, "null, but the app needs a value"))
    elif isinstance(kind, dict):
        if not isinstance(value, dict):
            found.append((path, f"expected an object, got {described(value)}"))
            return
        for key, sub in kind.items():
            where = f"{path}.{key}" if path else key
            if key in value:
                decodes(value[key], sub, where, found)
            elif not (isinstance(sub, tuple) and sub[0] == "optional"):
                found.append((where, "missing"))
    elif kind[0] == "array":
        if not isinstance(value, list):
            found.append((path, f"expected an array, got {described(value)}"))
            return
        for index, element in enumerate(value):
            decodes(element, kind[1], f"{path}[{index}]", found)
    elif kind[0] == "dictionary":
        if not isinstance(value, dict):
            found.append((path, f"expected an object, got {described(value)}"))
            return
        for key, element in value.items():
            decodes(element, kind[1], f"{path}[{json.dumps(key, ensure_ascii=False)}]", found)
    elif kind[0] == "either":
        # GuideText: a string, or failing that an object of strings
        if not isinstance(value, str) and not (isinstance(value, dict) and all(isinstance(v, str) for v in value.values())):
            found.append((path, f"expected a string or an object of strings, got {described(value)}"))
    elif kind == STR:
        if not isinstance(value, str):
            found.append((path, f"expected {kind}, got {described(value)}"))
    elif kind == INT:
        # JSONDecoder takes 3.0 as 3, not 1.5, "3" or true
        whole = isinstance(value, int) or (isinstance(value, float) and value.is_integer())
        if isinstance(value, bool) or not whole or not -2**63 <= value < 2**63:
            found.append((path, f"expected {kind}, got {described(value)}"))
    elif kind == DOUBLE:
        if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value):
            found.append((path, f"expected {kind}, got {described(value)}"))
    elif kind == BOOL:
        if not isinstance(value, bool):
            found.append((path, f"expected {kind}, got {described(value)}"))


def decode_problems(file_name, data, schema):
    """Why the app's JSONDecoder would reject `data` (nothing if it wouldn't).
    One failure anywhere loses the whole file on a phone."""
    found = []
    decodes(data, schema, "", found)
    lines = [f"{file_name}: {path + ': ' if path else ''}{what} (the app can't decode this file)"
             for path, what in found[:DECODE_LIMIT]]
    if len(found) > DECODE_LIMIT:
        lines.append(f"{file_name}: ...and {len(found) - DECODE_LIMIT} more places the app can't decode")
    return lines


def english(text):
    """A LocalizedText or GuideText's English, for messages."""
    if isinstance(text, dict):
        return text.get("en")
    return text


def dupes_of(ids):
    counts = Counter(ids)
    return sorted((i for i in counts if counts[i] > 1), key=str)


def check_catalog(problems, warnings, catalog, published):
    """weapons.json, against the published copy (None before the first
    publish)."""
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

    # A Prestige camo's `stage` counts weaponPrestige from 1
    stages = len(catalog.get("weaponPrestige") or [])
    for index, camo in enumerate(catalog.get("prestigeCamos") or []):
        stage = camo.get("stage")
        if stage is not None and not 1 <= stage <= stages:
            problems.append(f"weapons.json: prestigeCamos[{index}] ({english(camo['name'])}) has stage {stage}, "
                            f"but weaponPrestige has {stages} stage(s); it counts from 1")

    if published is None:
        return
    # Progress is stored against these ids. One that disappears from a
    # published file strands whatever players had logged on it.
    before = {w["weaponId"] for c in published["categories"] for w in c["weapons"]}
    gone = sorted(before - set(weapon_ids))
    if gone:
        problems.append(f"weapons.json: weaponId {gone} is published but missing now; ids must never be removed or renumbered")
    # Prestige camo ticks are saved by position (prestigecamo|<weaponId>|<index>),
    # so a published camo has to stay at its index for good.
    now = [english(c.get("name")) for c in catalog.get("prestigeCamos") or []]
    for index, camo in enumerate(published.get("prestigeCamos") or []):
        name = english(camo.get("name"))
        if index >= len(now):
            problems.append(f"weapons.json: prestigeCamos[{index}] ({name}) is published but missing now; "
                            "prestigeCamos order is saved progress: append new ones at the end")
        elif now[index] != name:
            problems.append(f"weapons.json: prestigeCamos[{index}] was {name!r} and is now {now[index]!r}; "
                            "prestigeCamos order is saved progress: append new ones at the end")


def objective_keys(mode, data):
    """The keys a mode's objective ticks are saved under (obj|<mode>|<categoryId>|<itemId>)."""
    keys = set()

    def walk(category_id, items):
        for item in items:
            keys.add(f"obj|{mode}|{category_id}|{item['itemId']}")
            walk(category_id, item["children"])
    for category in data["objectives"]:
        walk(category["categoryId"], category["items"])
    return keys


def check_mode(problems, warnings, mode, data, weapon_ids, published, modes, files, allow_trackfrom_change=False, notes=None):
    """One mode file, against the catalog's weapon ids, the game's other mode
    files (`files`, by mode) and its own published copy (None before the
    first publish)."""
    if data.get("mode") != mode:
        problems.append(f"{mode}.json: \"mode\" is {data.get('mode')!r}")
    seen = [e["weaponId"] for e in data["weaponCamos"]]
    dupes = dupes_of(seen)
    if dupes:
        # The app reads the first and silently drops the rest
        problems.append(f"{mode}.json: more than one weaponCamos entry for weaponId {dupes}")
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
        # A counter camo reads another camo's count on the same weapon
        for camo in entry["camos"]:
            if camo.get("counter") is not None and camo["counter"] not in item_ids:
                problems.append(f"{mode}.json: weapon {entry['weaponId']} camo {camo['itemId']} has counter {camo['counter']}, "
                                "which isn't an itemId in that weapon's camos")

    # Objectives: a duplicate id shares one saved tick with its twin
    category_ids = [c["categoryId"] for c in data["objectives"]]
    dupes = dupes_of(category_ids)
    if dupes:
        problems.append(f"{mode}.json: duplicate objectives categoryId {dupes}")

    def walk(items, where):
        dupes = dupes_of([i["itemId"] for i in items])
        if dupes:
            problems.append(f"{mode}.json: duplicate itemId {dupes} in {where}")
        for item in items:
            walk(item["children"], f"{where} > item {item['itemId']}'s children")
    for category in data["objectives"]:
        walk(category["items"], f"objectives category {category['categoryId']}")

    # trackFrom decides which mode's camo progress this one reads: the app
    # ignores a name that isn't a loaded mode, itself, or a mode that shares
    # in turn (TrackSharing), so each of those is a typo, not a choice.
    source = data.get("trackFrom")
    if source is not None:
        if source == mode:
            problems.append(f"{mode}.json: \"trackFrom\" names the mode itself")
        elif source not in modes:
            problems.append(f"{mode}.json: \"trackFrom\" is {source!r}, which isn't one of this game's modes ({', '.join(modes)})")
        elif (files.get(source) or {}).get("trackFrom") is not None:
            problems.append(f"{mode}.json: \"trackFrom\" is {source!r}, which itself tracks from "
                            f"{files[source]['trackFrom']!r}; the app doesn't chain them and ignores it")

    if published is None:
        return
    before = {e["weaponId"]: {c["itemId"] for c in e["camos"]} for e in published["weaponCamos"]}
    now = {e["weaponId"]: {c["itemId"] for c in e["camos"]} for e in data["weaponCamos"]}
    for weapon_id, items in before.items():
        gone = sorted(items - now.get(weapon_id, set()))
        if gone:
            problems.append(f"{mode}.json: weapon {weapon_id} lost camo itemId {gone}; ids must never be removed or renumbered")
    was = published.get("trackFrom")
    if was != source:
        if allow_trackfrom_change:
            if notes is not None:
                notes.append(f"{mode}.json: \"trackFrom\" {was!r} -> {source!r}, acknowledged with --allow-trackfrom-change")
        else:
            problems.append(f"{mode}.json: \"trackFrom\" changes from {was!r} to {source!r}; that switches which camo progress "
                            "the mode reads, so players' ticks would be stranded. Pass --allow-trackfrom-change if that is intended")


def guide_keys(guide):
    """Every key a player's Hajin progress is saved under (HajinStore): row
    ticks, FOB upgrades, blueprints found, Gunsmith manuals, and item ids
    (stash counts `stash:<id>` and tracked recipes `track:<id>`)."""
    keys = set()
    for section in guide["guide"]:
        for row in section["rows"]:
            if row.get("check"):
                keys.add(row["check"])
            # HajinStore.manualRows: starter weapons have no manual
            if section["id"] == "gunsmith" and row.get("weapon") is not None \
                    and not (english(row.get("subtitle")) or "").startswith("Starter"):
                keys.add(f"manual-{row['weapon']}")
    for item in guide.get("items") or []:
        keys.add(item["id"])
        if item["kind"] == "FOB Upgrade":
            keys.add(f"upgrade-{item['id']}")
        if item.get("blueprint") is True:
            keys.add(f"blueprint-{item['id']}")
    return keys


def check_guide(problems, warnings, guide, file_name="hajin.json"):
    """The Hajin guide's own references. A duplicate id makes two entries
    one (the app finds the first), and a link to an id that isn't there
    goes nowhere."""
    lists = [("categories", guide["categories"]), ("markers", guide["markers"]), ("guide sections", guide["guide"]),
             ("items", guide.get("items") or []), ("traitTrees", guide.get("traitTrees") or []),
             ("traits", guide.get("traits") or [])]
    for what, entries in lists:
        dupes = dupes_of([e["id"] for e in entries])
        if dupes:
            problems.append(f"{file_name}: duplicate {what} id {dupes}")
    categories = {c["id"] for c in guide["categories"]}
    markers = {m["id"] for m in guide["markers"]}
    items = {i["id"] for i in guide.get("items") or []}
    traits = {t["id"] for t in guide.get("traits") or []}

    for marker in guide["markers"]:
        if marker["cat"] not in categories:
            problems.append(f"{file_name}: marker {marker['id']} has cat {marker['cat']!r}, which isn't a category (the map can't show it)")
    for item in guide.get("items") or []:
        for cost in item.get("cost") or []:
            if cost["item"] not in items:
                problems.append(f"{file_name}: item {item['id']} costs {cost['item']!r}, which isn't an item")
        # Soft: the item still shows, just without that place on the map
        for place in item.get("foundPlaces") or []:
            if place not in markers:
                warnings.append(f"{file_name}: item {item['id']} foundPlaces {place!r}, which isn't a marker")
        if item.get("marker") and item["marker"] not in markers:
            warnings.append(f"{file_name}: item {item['id']} has marker {item['marker']!r}, which isn't a marker")

    checks = []
    for section in guide["guide"]:
        for index, row in enumerate(section["rows"]):
            where = f"{section['id']} row {index} ({english(row['title'])})"
            named = ([row["item"]] if row.get("item") else []) + list(row.get("links") or []) \
                + [c["item"] for c in (row.get("prints") or []) + (row.get("extracts") or [])]
            for item in named:
                if item not in items:
                    problems.append(f"{file_name}: {where} links item {item!r}, which isn't an item")
            if row.get("check"):
                checks.append(row["check"])
    dupes = dupes_of(checks)
    if dupes:
        problems.append(f"{file_name}: rows share check key {dupes}; ticking one would tick the other")

    for tree in guide.get("traitTrees") or []:
        named = [t for row in tree["rows"] for t in row if t is not None] + ([tree["emblem"]] if tree.get("emblem") else [])
        for trait in named:
            if trait not in traits:
                warnings.append(f"{file_name}: trait tree {tree['id']} names trait {trait!r}, which isn't in traits")


def removed_keys(warnings, notes, file_name, before, now, allowed):
    """Keys players' ticks are saved under that the new file no longer has.
    Not an error (a guide can drop a retired op on purpose), but loud unless
    --allow-removed names them. Returns the keys removed."""
    gone = sorted(before - now)
    if not gone:
        return []
    quiet = gone if "all" in allowed else [k for k in gone if k in allowed]
    loud = [k for k in gone if k not in quiet]
    if quiet:
        notes.append(f"{file_name}: {len(quiet)} saved tick key(s) removed, acknowledged with --allow-removed: {', '.join(quiet)}")
    if loud:
        warnings.append("\n".join([
            f"WARNING: {file_name} drops {len(loud)} saved tick key(s) that the published copy has:",
            *(f"    {key}" for key in loud),
            "  Players' ticks on them are stranded: they stay saved but nothing shows them any more.",
            "  If a key was renamed, put the old one back. If the removal is intended, acknowledge it with",
            f"  --allow-removed {','.join(loud)}",
        ]))
    return gone


def check(problems, warnings, notes=None, allow_removed=(), allow_trackfrom_change=False):
    """Things that would break installed apps or lose players' progress."""
    notes = [] if notes is None else notes
    allowed = set(allow_removed)

    def published(name):
        path = OUT / f"{name}.json"
        return load(path) if path.exists() else None

    catalog = load(src("weapons"))
    files = {mode: load(src(mode)) for mode in MODES}
    guides = {g: load(src(g)) for g in GUIDES}
    # Everything below reads the files the way the app does, so a file the
    # app couldn't decode at all is reported on its own first.
    decoding = decode_problems("weapons.json", catalog, WEAPON_CATALOG)
    for mode, data in files.items():
        decoding += decode_problems(f"{mode}.json", data, MODE_FILE)
    for name, data in guides.items():
        decoding += decode_problems(f"{name}.json", data, HAJIN_GUIDE)
    if decoding:
        problems.extend(decoding)
        return

    check_catalog(problems, warnings, catalog, published("weapons"))
    weapon_ids = [w["weaponId"] for c in catalog["categories"] for w in c["weapons"]]
    removed = []
    for mode, data in files.items():
        before = published(mode)
        check_mode(problems, warnings, mode, data, weapon_ids, before, MODES, files, allow_trackfrom_change, notes)
        if before is not None and not decode_problems(f"{mode}.json", before, MODE_FILE):
            removed += removed_keys(warnings, notes, f"{mode}.json", objective_keys(mode, before), objective_keys(mode, data), allowed)
    for name, data in guides.items():
        check_guide(problems, warnings, data, f"{name}.json")
        before = published(name)
        if before is not None and not decode_problems(f"{name}.json", before, HAJIN_GUIDE):
            removed += removed_keys(warnings, notes, f"{name}.json", guide_keys(before), guide_keys(data), allowed)
    unused = sorted(allowed - set(removed) - {"all"})
    if unused:
        warnings.append(f"--allow-removed {','.join(unused)}: no published key by that name is being removed (a typo?)")


def main():
    ap = argparse.ArgumentParser(description="Publish the MW4 data and its manifest.")
    ap.add_argument("--title", help="notification title: plain text (English) or a JSON object per language")
    ap.add_argument("--body", help="notification body, same forms as --title")
    ap.add_argument("--silent", action="store_true", help="publish without notifying anyone")
    ap.add_argument("--dry-run", action="store_true", help="check and report; write nothing")
    ap.add_argument("--game", default="mw4", help="which game in Resources/games.json (default mw4)")
    ap.add_argument("--allow-removed", action="append", default=[], metavar="KEY[,KEY...]",
                    help="saved tick keys this publish removes on purpose (or 'all'): a note instead of the warning")
    ap.add_argument("--allow-trackfrom-change", action="store_true",
                    help="let a published mode file's \"trackFrom\" change, stranding progress read through the old one")
    args = ap.parse_args()
    use_game(args.game)
    if args.silent and (args.title or args.body):
        raise SystemExit("--silent and --title/--body contradict each other")

    files = ["weapons"] + MODES + GUIDES
    problems, warnings, notes, changed = [], [], [], []
    allow_removed = [key.strip() for value in args.allow_removed for key in value.split(",") if key.strip()]
    for name in files:
        source, dst = src(name), OUT / f"{name}.json"
        try:
            new = load(source)
        except json.JSONDecodeError as error:
            raise SystemExit(f"{source.name} is not valid JSON: {error}")
        if not isinstance(new, dict) or not new.get("version"):
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
    check(problems, warnings, notes, allow_removed, args.allow_trackfrom_change)
    check_live(files, problems)

    for line in warnings:
        # A multi-line block (saved ticks removed) stands apart so it's seen
        print(f"\n{line}\n" if "\n" in line else f"warning: {line}")
    for line in notes:
        print(f"note: {line}")
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
    broken = decode_problems("manifest.json", manifest, MANIFEST)
    if broken:
        raise SystemExit("\n".join(f"error: {line}" for line in broken))

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
