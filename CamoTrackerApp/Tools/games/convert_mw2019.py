#!/usr/bin/env python3
"""Converts the MW (2019) Camo Tracker data (Data/ModernWarfareCamos.json,
the old app's format) into Camo Tracker's per-game files: mw19_weapons.json
and mw19_multiplayer.json.

    python3 Tools/games/convert_mw2019.py ../Data Resources

MW's camo track, per weapon: 10 camo categories of 10 camos, each category
one challenge ("Get kills", 800 in all) earning its camos along the way, on
a shared count (`counter`); the first camo of each is free. Then, all
automatic: Gold once every camo is done, Platinum once the class's launch
weapons have Gold, Damascus once every class has Platinum. Obsidian (one
more challenge per weapon after Damascus) has no place on the track yet
and is left out. Launch weapons (IsDefault) get the lowest ids.
"""
import json
import re
import sys
from pathlib import Path

VERSION = "1.0.0"
CATEGORY_NAMES = {"AssaultRifles": "Assault Rifles", "SubmachineGuns": "SMGs", "LightMachineGuns": "LMGs",
                  "MarksmanRiflesSniperRifles": "Marksman & Sniper Rifles", "Handguns": "Handguns"}
IMAGES = "https://camotracker.djr.li/Images/Camos/{}.png"


def unit_of(desc):
    d = desc.lower()
    if re.search(r"\d", d):
        return "times"
    if "headshot" in d:
        return "headshots"
    return "kills"


def requirement_text(desc, amount):
    desc = desc.strip().rstrip(".")
    if re.search(r"\d", desc):
        return f"{desc} {amount} times."
    if desc.startswith("Get "):
        return f"Get {amount} {desc[4:]}."
    if desc.startswith("Kill enemies"):
        return f"Kill {amount} enemies{desc[len('Kill enemies'):]}."
    return f"{desc}: {amount}."


def main(src, out_dir):
    out = Path(out_dir)
    data = json.load(open(Path(src) / "ModernWarfareCamos.json", encoding="utf-8-sig"))
    order = sorted((0 if w["UnlockRequirements"]["IsDefault"] else 1, ci, wi)
                   for ci, cat in enumerate(data) for wi, w in enumerate(cat["Weapons"]))
    ids = {(ci, wi): n for n, (_, ci, wi) in enumerate(order)}
    launch = sum(1 for o in order if o[0] == 0)
    categories, launch_per_class, weapon_camos = [], {}, []
    for ci, cat in enumerate(data):
        entries = []
        for wi, w in enumerate(cat["Weapons"]):
            u = w["UnlockRequirements"]
            if u["IsDefault"]:
                launch_per_class[str(ci)] = launch_per_class.get(str(ci), 0) + 1
                lvl = int(u.get("UnlockLevel") or 1)
                unlock = "Unlocked by default." if lvl <= 1 else f"Unlocked at Level {lvl}."
            else:
                unlock = (u.get("ChallengeDescription") or "Season weapon.").strip()
                unlock = unlock if unlock.endswith(".") else unlock + "."
            wid = ids[(ci, wi)]
            entries.append({"weaponId": wid, "name": {"en": w["WeaponName"].strip()}, "maxLevel": int(w["MaxLevel"]),
                            "unlockRequirement": {"en": unlock}, "imageURL": w["WeaponImageURL"]})
            camos = []
            for group in w["Camos"]:
                if group["CategoryName"] == "Obsidian":
                    continue
                counter = len(camos) + 1  # the first camo is free, so the count lives on the second
                desc = group["CategoryDescription"]
                for sub in group["CategoryCamos"]:
                    amount = int(sub["Amount"])
                    camo = {"itemId": len(camos), "name": {"en": sub["CamoName"].strip()}, "tier": len(camos) + 1, "unlockLevel": None,
                            "requirement": {"amount": amount, "unit": unit_of(desc),
                                            "description": {"en": requirement_text(desc, amount) if amount else "Free with the category."}},
                            "children": [], "imageURL": sub["CamoURL"]}
                    if amount:
                        camo["counter"] = counter
                    camos.append(camo)
            weapon_camos.append({"weaponId": wid, "camos": camos})
        entries.sort(key=lambda e: e["weaponId"])
        name = cat["WeaponCategoryName"].strip()
        categories.append({"categoryId": ci, "name": {"en": CATEGORY_NAMES.get(name, name)}, "weapons": entries})
    weapon_camos.sort(key=lambda e: e["weaponId"])
    catalog = {"version": VERSION, "baseWeaponCount": launch, "weaponPrestige": [], "prestigeCamos": [], "categories": categories,
               "_note": f"Converted from the MW Camo Tracker data by Tools/games/convert_mw2019.py; ids put the {launch} launch weapons first."}
    (out / "mw19_weapons.json").write_text(json.dumps(catalog, ensure_ascii=False, indent=2))
    steps = [{"name": {"en": "Gold"}, "imageURL": IMAGES.format("gold"), "unlock": "weapon", "auto": True},
             {"name": {"en": "Platinum"}, "imageURL": IMAGES.format("platinum"), "unlock": "category", "neededByCategory": launch_per_class, "auto": True},
             {"name": {"en": "Damascus"}, "imageURL": IMAGES.format("damascus"), "unlock": "mode", "classes": list(range(len(categories))), "auto": True}]
    mode_file = {"version": VERSION, "mode": "multiplayer", "weaponCamos": weapon_camos, "objectives": [],
                 "completionist": {"steps": steps, "final": {"enabled": False}},
                 "_note": "Converted from the MW Camo Tracker data (ModernWarfareCamos) by Tools/games/convert_mw2019.py. Obsidian left out."}
    (out / "mw19_multiplayer.json").write_text(json.dumps(mode_file, ensure_ascii=False, indent=2))
    print(f"mw19: {len(weapon_camos)} weapons, {len(weapon_camos[0]['camos'])} camos each, {launch} launch {launch_per_class}")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
