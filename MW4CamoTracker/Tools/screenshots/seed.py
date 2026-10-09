#!/usr/bin/env python3
"""Write a believable in-progress save into the simulator's app defaults.

    seed.py [--preview] <path-to-com.DannyRyman.MW4CamoTracker.plist>

Empty rings and 0/20 everywhere make for dead marketing shots, so this fills in
a save that looks like a few weeks of play:

  * Base camos  -- every weapon Gold. MW4 has one Camo Track per weapon,
                   shared by every mode, so this shows in all three tabs.
  * Multiplayer -- Mercurial Drift (tier1) on every weapon and Polyatomic
                   Reforged (tier2) on the Assault Rifles, so the Mastery
                   track shows real movement.
  * Warzone     -- Parallax (tier1) on four Assault Rifles.
  * DMZ         -- Chiral (tier1) on two weapons, a few objectives ticked.
  * Levels      -- four weapons maxed, the rest scattered but high enough to
                   have opened every base camo (each camo's `unlockLevel`).

Camos and levels are derived from the shipped weapons.json rather than
hardcoded, so a data change can't silently seed keys nothing reads.

`--preview` is the same save with one change for the preview video
(Tools/preview): weapon PREVIEW_WEAPON's base track is left one camo short,
with the camo before it part-filled, and it gets no Mastery, so the `grind`
take (filmed on the PREVIEW_MODE tab) can fill that bar and tick the last camo
on camera and earn the real Gold celebration.

Run with /usr/bin/python3. Homebrew's python currently fails to import plistlib
(pyexpat links against a libexpat that lacks a symbol it wants).

Key formats and the store shape must match TrackerViewModel.swift. Two traps:
  * the weapon mastery prefix is `wmastery|`, not `mastery|`
  * `weaponLevels: [Int: Int]` encodes as a JSON *object with stringified keys*
    ({"1": 68}). Swift's Codable special-cases String and Int dictionary keys;
    only other key types get flattened to a [k, v, k, v, ...] array. Emitting
    the array form decodes to nil, which fails the whole ProgressStore and
    silently leaves the app on an empty save.
"""
import json
import os
import plistlib
import random
import sys

STORE_KEY = "mw4_progress_v2"
PINNED_KEY = "mw4_pinned_weapon_v1"

# MasteryRequirement in Theme.swift.
TIER1_AMOUNT = 3
TIER2_AMOUNT = 5

PREVIEW_WEAPON = 3             # Kastov 762, also the pinned weapon
PREVIEW_MODE = "warzone"

MAXED = {1, 3, 5, 13}          # M4, Kastov 762, ISO Nightshade, KG-7 Vulcan
PINNED_WEAPON = 3              # Kastov 762, so the Pinned card is populated

HERE = os.path.dirname(os.path.abspath(__file__))
RES = os.path.join(HERE, "..", "..", "Resources")


def load(name):
    with open(os.path.join(RES, name), encoding="utf-8") as fh:
        return json.load(fh)


def camo_key(weapon_id, camo_id):
    return f"camo|{weapon_id}|{camo_id}"   # no mode: the track is shared


def wmastery_key(mode, weapon_id, tier):
    return f"wmastery|{mode}|{weapon_id}|{tier}"


def objective_key(mode, category_id, item_id):
    return f"obj|{mode}|{category_id}|{item_id}"


def build(preview=False):
    rng = random.Random(20260908)  # stable output, so shots are reproducible
    amounts, completed = {}, []

    catalog = load("weapons.json")
    weapons = {w["weaponId"]: w for c in catalog["categories"] for w in c["weapons"]}
    assault_rifles = [w["weaponId"] for w in catalog["categories"][0]["weapons"]]

    def mastery(mode, weapon_id, tier):
        if preview and weapon_id == PREVIEW_WEAPON:
            return  # not Gold yet in the preview save, so no Mastery either
        key = wmastery_key(mode, weapon_id, tier)
        amounts[key] = TIER1_AMOUNT if tier == 1 else TIER2_AMOUNT
        completed.append(key)

    # Base track: every weapon Gold, except the preview weapon in --preview,
    # which stops one camo short with the camo before it part-filled.
    for weapon_id, weapon in weapons.items():
        camos = weapon.get("camos") or []
        for index, camo in enumerate(camos):
            required = (camo.get("requirement") or {}).get("amount", 1)
            key = camo_key(weapon_id, camo["itemId"])
            if not (preview and weapon_id == PREVIEW_WEAPON) or index < len(camos) - 2:
                amounts[key] = required
                completed.append(key)
            elif index == len(camos) - 2:
                amounts[key] = max(1, required - 3)

    # Objectives (DMZ is the only mode carrying any today).
    for mode in ("multiplayer", "warzone", "dmz"):
        for category in load(f"{mode}.json").get("objectives", []):
            for item in category["items"][: rng.randint(1, len(category["items"]))]:
                required = (item.get("requirement") or {}).get("amount", 1)
                key = objective_key(mode, category["categoryId"], item["itemId"])
                amounts[key] = required
                completed.append(key)

    for weapon_id in weapons:
        mastery("multiplayer", weapon_id, 1)
    for weapon_id in assault_rifles:
        mastery("multiplayer", weapon_id, 2)
    for weapon_id in assault_rifles[:4]:
        mastery("warzone", weapon_id, 1)
    for weapon_id in assault_rifles[:2]:
        mastery("dmz", weapon_id, 1)

    levels = {}
    for weapon_id in sorted(weapons):
        weapon = weapons[weapon_id]
        max_level = weapon["maxLevel"]
        # Gold needs every base camo open, so never below the highest gate.
        floor = max([c.get("unlockLevel") or 0 for c in weapon.get("camos") or []] + [4])
        levels[str(weapon_id)] = max_level if weapon_id in MAXED else rng.randint(floor, max(floor, max_level - 6))

    return {"weaponLevels": levels, "amounts": amounts, "completed": completed}


def main():
    args = [a for a in sys.argv[1:] if a != "--preview"]
    preview = "--preview" in sys.argv
    if not args:
        sys.exit("usage: seed.py [--preview] <plist path>")
    path = args[0]
    try:
        with open(path, "rb") as fh:
            defaults = plistlib.load(fh)
    except (FileNotFoundError, plistlib.InvalidFileException):
        defaults = {}

    store = build(preview=preview)
    defaults[STORE_KEY] = json.dumps(store, separators=(",", ":")).encode()
    defaults[PINNED_KEY] = PINNED_WEAPON
    defaults["mw4_has_onboarded"] = True
    defaults["mw4_image_cache_token"] = 1

    with open(path, "wb") as fh:
        plistlib.dump(defaults, fh, fmt=plistlib.FMT_BINARY)

    per_mode = {}
    for key in store["completed"]:
        bucket = "base camos" if key.startswith("camo|") else key.split("|")[1]
        per_mode[bucket] = per_mode.get(bucket, 0) + 1
    print(f"    seeded {len(store['completed'])} completed keys "
          f"({', '.join(f'{m} {n}' for m, n in sorted(per_mode.items()))}), "
          f"{len(store['weaponLevels'])} weapon levels")


if __name__ == "__main__":
    main()
