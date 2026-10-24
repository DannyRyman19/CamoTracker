#!/usr/bin/env python3
"""Converts the Vanguard Camo Tracker data (Data/<Mode>VanguardCamos.json,
the old app's format) into Camo Tracker's per-game files: vg_weapons.json
plus one mode file each for multiplayer and zombies.

    python3 Tools/games/convert_vanguard.py ../Data Resources

Vanguard's camo track, per weapon and mode: 10 camo categories, each one
challenge ("Get Eliminations", 400 in all) that earns its camos along the
way (one at 40, 80, 120...) and opens at a weapon level. The camos of a
category share one count (`counter`). Then Gold once every camo is done,
Diamond once the class's launch weapons have Gold, and Atomic (Dark Aether
in Zombies) once every launch weapon has Gold: all three automatic, as in
the old app. Launch weapons (IsDefault) get the lowest ids.
"""
import json
import re
import sys
from pathlib import Path

VERSION = "1.0.0"
MODES = [("Multiplayer", "multiplayer"), ("Zombies", "zombies")]
CATEGORY_NAMES = {"AssaultRifles": "Assault Rifles", "SubmachineGuns": "SMGs", "LightMachineGuns": "LMGs",
                  "MarksmanRifles": "Marksman Rifles", "SniperRifles": "Sniper Rifles"}
STEPS = {
    "multiplayer": [("Gold", ["#F5D77A", "#C9A227", "#8A6A12"]), ("Diamond", ["#E8FBFF", "#8FDDF5", "#4BA9D6"]),
                    ("Atomic", ["#FF5C8A", "#B84DFF", "#4D7BFF"])],
    "zombies": [("Golden Viper", ["#F0D36B", "#9DBA3C", "#4E7A1F"]), ("Plague Diamond", ["#D6FFE9", "#6FE0B0", "#2E9C7A"]),
                ("Dark Aether", ["#B88CFF", "#6A2FD1", "#2A0F5C"])],
}


def requirement_text(desc, amount):
    desc = desc.strip().rstrip(".")
    if re.match(r"Get \d", desc):
        return f"{desc} {amount} times."
    if desc.startswith("Get "):
        return f"Get {amount} {desc[4:]}."
    return f"{desc}: {amount}."


def unit_of(desc):
    d = desc.lower()
    if re.match(r"get \d", d):
        return "times"
    if "headshot" in d or "critical" in d:
        return "headshots"
    if "elimination" in d:
        return "eliminations"
    return "kills"


def main(src, out_dir):
    out = Path(out_dir)
    files = {mode: json.load(open(Path(src) / f"{old}VanguardCamos.json", encoding="utf-8-sig")) for old, mode in MODES}
    first = files["multiplayer"]
    order = []
    for ci, cat in enumerate(first):
        for wi, w in enumerate(cat["Weapons"]):
            order.append((0 if w["UnlockRequirements"]["IsDefault"] else 1, ci, wi))
    order.sort()
    ids = {(ci, wi): n for n, (_, ci, wi) in enumerate(order)}
    launch = sum(1 for o in order if o[0] == 0)
    launch_per_class, categories = {}, []
    for ci, cat in enumerate(first):
        entries = []
        for wi, w in enumerate(cat["Weapons"]):
            u = w["UnlockRequirements"]
            if u["IsDefault"]:
                launch_per_class[str(ci)] = launch_per_class.get(str(ci), 0) + 1
            unlock = "Unlocked by default." if int(u.get("UnlockLevel") or 1) <= 1 and u["IsDefault"] else \
                (f"Unlocked at Level {u['UnlockLevel']}." if u["IsDefault"] else (u.get("ChallengeDescription") or "Season weapon.").strip())
            if not unlock.endswith("."):
                unlock += "."
            entries.append({"weaponId": ids[(ci, wi)], "name": {"en": w["WeaponName"].strip()}, "maxLevel": int(w["MaxLevel"]),
                            "unlockRequirement": {"en": unlock}, "imageURL": w["WeaponImageURL"]})
        entries.sort(key=lambda e: e["weaponId"])
        name = cat["WeaponCategoryName"].strip()
        categories.append({"categoryId": ci, "name": {"en": CATEGORY_NAMES.get(name, name)}, "weapons": entries})
    catalog = {"version": VERSION, "baseWeaponCount": launch, "weaponPrestige": [], "prestigeCamos": [], "categories": categories,
               "_note": f"Converted from the Vanguard Camo Tracker data by Tools/games/convert_vanguard.py; ids put the {launch} launch weapons first."}
    (out / "vg_weapons.json").write_text(json.dumps(catalog, ensure_ascii=False, indent=2))

    for old, mode in MODES:
        weapon_camos = []
        for ci, cat in enumerate(files[mode]):
            for wi, w in enumerate(cat["Weapons"]):
                camos = []
                for group in w["Camos"]:
                    counter = len(camos)
                    desc = group["CategoryDescription"]
                    for sub in group["CategoryCamos"]:
                        amount = int(sub["Amount"])
                        camos.append({"itemId": len(camos), "name": {"en": sub["CamoName"].strip()}, "tier": len(camos) + 1,
                                      "unlockLevel": int(group["CategoryUnlockLevel"]),
                                      "requirement": {"amount": amount, "unit": unit_of(desc), "description": {"en": requirement_text(desc, amount)}},
                                      "children": [], "imageURL": sub["CamoURL"], "counter": counter,
                                      "section": {"en": group["CategoryName"].strip()}})
                weapon_camos.append({"weaponId": ids[(ci, wi)], "camos": camos})
        weapon_camos.sort(key=lambda e: e["weaponId"])
        (gold, gc), (diamond, dc), (last, lc) = STEPS[mode]
        steps = [{"name": {"en": gold}, "colors": gc, "unlock": "weapon", "auto": True},
                 {"name": {"en": diamond}, "colors": dc, "unlock": "category", "neededByCategory": launch_per_class, "auto": True},
                 # Atomic is Gold on every launch weapon, which is Diamond across every class
                 {"name": {"en": last}, "colors": lc, "unlock": "mode", "needed": launch, "auto": True}]
        mode_file = {"version": VERSION, "mode": mode, "weaponCamos": weapon_camos, "objectives": [],
                     "completionist": {"steps": steps, "final": {"enabled": False}},
                     "_note": f"Converted from the Vanguard Camo Tracker data ({old}VanguardCamos) by Tools/games/convert_vanguard.py."}
        (out / f"vg_{mode}.json").write_text(json.dumps(mode_file, ensure_ascii=False, indent=2))
        print(f"vg {mode}: {len(weapon_camos)} weapons, {len(weapon_camos[0]['camos'])} camos each, then {gold}, {diamond}, {last} ({launch} launch, {launch_per_class})")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
