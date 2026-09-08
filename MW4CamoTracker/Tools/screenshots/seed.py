#!/usr/bin/env python3
"""Write a believable in-progress save into the simulator's app defaults.

    seed.py <path-to-com.DannyRyman.MW4CamoTracker.plist>

Empty rings and 0/20 everywhere make for dead marketing shots, so this fills in
a save that looks like a few weeks of play:

  * Multiplayer -- every weapon Gold, Mercurial Drift (tier1) earned on all of
                   them and Polyatomic Reforged (tier2) on the Assault Rifles,
                   so the Mastery track shows real movement.
  * Warzone     -- a mid-grind, roughly two thirds of the way.
  * DMZ         -- early, with a few objectives ticked.
  * Levels      -- four weapons maxed, the rest scattered.

Everything is derived from the shipped JSON rather than hardcoded, because the
modes genuinely differ: Multiplayer has 4 camos per weapon at 10/25/50/75,
Warzone has 3 at 1/3/10, and DMZ has no weapon camos at all, only objectives.
Assuming a uniform shape here silently seeds keys nothing reads.

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

MAXED = {1, 3, 5, 13}          # M4, Kastov 762, ISO Nightshade, KG-7 Vulcan
PINNED_WEAPON = 3              # Kastov 762, so the Pinned card is populated

HERE = os.path.dirname(os.path.abspath(__file__))
RES = os.path.join(HERE, "..", "..", "Resources")


def load(name):
    with open(os.path.join(RES, name), encoding="utf-8") as fh:
        return json.load(fh)


def camo_key(mode, weapon_id, camo_id):
    return f"camo|{mode}|{weapon_id}|{camo_id}"


def wmastery_key(mode, weapon_id, tier):
    return f"wmastery|{mode}|{weapon_id}|{tier}"


def objective_key(mode, category_id, item_id):
    return f"obj|{mode}|{category_id}|{item_id}"


def build():
    rng = random.Random(20260908)  # stable output, so shots are reproducible
    amounts, completed = {}, []

    catalog = load("weapons.json")
    weapons = {w["weaponId"]: w for c in catalog["categories"] for w in c["weapons"]}
    assault_rifles = [w["weaponId"] for w in catalog["categories"][0]["weapons"]]

    def apply(mode, weapon_id, camos, done_count):
        """Complete `done_count` of this weapon's camos, part-fill the next."""
        for index, camo in enumerate(camos):
            required = (camo.get("requirement") or {}).get("amount", 1)
            key = camo_key(mode, weapon_id, camo["itemId"])
            if index < done_count:
                amounts[key] = required
                completed.append(key)
            elif index == done_count and required > 1:
                amounts[key] = rng.randint(1, max(1, required - 1))

    def mastery(mode, weapon_id, tier):
        key = wmastery_key(mode, weapon_id, tier)
        amounts[key] = TIER1_AMOUNT if tier == 1 else TIER2_AMOUNT
        completed.append(key)

    # How far into each mode's camo list to go, per weapon.
    plans = {
        "multiplayer": lambda n: n,                                  # all Gold
        "warzone": lambda n: rng.choice([n - 1, n - 1, n, n - 2]),   # mid-grind
        "dmz": lambda n: rng.choice([0, 1, 1, 2]),                   # early
    }

    for mode, depth in plans.items():
        data = load(f"{mode}.json")
        for entry in data.get("weaponCamos", []):
            weapon_id, camos = entry["weaponId"], entry["camos"]
            apply(mode, weapon_id, camos, max(0, min(len(camos), depth(len(camos)))))

        # Objectives (DMZ is the only mode carrying any today).
        for category in data.get("objectives", []):
            for item in category["items"][: rng.randint(1, len(category["items"]))]:
                required = (item.get("requirement") or {}).get("amount", 1)
                key = objective_key(mode, category["categoryId"], item["itemId"])
                amounts[key] = required
                completed.append(key)

    # Mastery: Multiplayer fully tier1 and its ARs tier2; Warzone part-way.
    for weapon_id in weapons:
        mastery("multiplayer", weapon_id, 1)
    for weapon_id in assault_rifles:
        mastery("multiplayer", weapon_id, 2)
    for weapon_id in assault_rifles[:4]:
        mastery("warzone", weapon_id, 1)

    levels = {}
    for weapon_id in sorted(weapons):
        max_level = weapons[weapon_id]["maxLevel"]
        levels[str(weapon_id)] = max_level if weapon_id in MAXED else rng.randint(4, max_level - 6)

    return {"weaponLevels": levels, "amounts": amounts, "completed": completed}


def main():
    if len(sys.argv) < 2:
        sys.exit("usage: seed.py <plist path>")
    path = sys.argv[1]
    try:
        with open(path, "rb") as fh:
            defaults = plistlib.load(fh)
    except (FileNotFoundError, plistlib.InvalidFileException):
        defaults = {}

    store = build()
    defaults[STORE_KEY] = json.dumps(store, separators=(",", ":")).encode()
    defaults[PINNED_KEY] = PINNED_WEAPON
    defaults["mw4_has_onboarded"] = True
    defaults["mw4_image_cache_token"] = 1

    with open(path, "wb") as fh:
        plistlib.dump(defaults, fh, fmt=plistlib.FMT_BINARY)

    per_mode = {}
    for key in store["completed"]:
        per_mode[key.split("|")[1]] = per_mode.get(key.split("|")[1], 0) + 1
    print(f"    seeded {len(store['completed'])} completed keys "
          f"({', '.join(f'{m} {n}' for m, n in sorted(per_mode.items()))}), "
          f"{len(store['weaponLevels'])} weapon levels")


if __name__ == "__main__":
    main()
