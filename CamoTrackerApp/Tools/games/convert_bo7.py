#!/usr/bin/env python3
"""Converts the BO7 Camo Tracker data (Data/BO7/weapons.json, the old app's
format) into Camo Tracker's per-game files: bo7_weapons.json plus one mode
file per mode (campaign, multiplayer, zombies, warzone).

    python3 Tools/games/convert_bo7.py ../Data/BO7/weapons.json Resources

BO7's camo track, per weapon and mode: 9 Military camos (each a challenge,
not a weapon level), 3 Specials once every Military camo is done, then 3
Mastery camos: the first once the weapon's Specials are done, the second
once 6 weapons in the class have the first, the third once 30 weapons have
the second. They map onto Camo Tracker's Completionist steps (per-weapon
challenges, "weapon"/"category"/"mode" gates with counts) with no final
camo. Prestige: Prestige 1, Prestige 2, then Prestige Master to level 250.
"""
import json
import re
import sys
from pathlib import Path

MODES = [("Campaign", "campaign"), ("Multiplayer", "multiplayer"), ("Zombies", "zombies"), ("Warzone", "warzone")]
VERSION = "1.0.0"


def text(s):
    return {"en": s.strip()}


CATEGORY_NAMES = {"SMGS": "SMGs", "LMGS": "LMGs", "LAUNCHERS/SPECIALS": "Launchers & Specials"}


def title(s):
    # "SHATTERED GOLD" -> "Shattered Gold", "M15 MOD 0" stays as it is
    words = s.strip().split()
    return " ".join(w.capitalize() if w.isalpha() and len(w) > 1 else w for w in words)


def unit_of(desc):
    d = desc.lower()
    if re.search(r"\d+ times", d) or " times." in d:
        return "times"
    if "headshot" in d:
        return "headshots"
    if "elimination" in d:
        return "eliminations"
    return "kills"


def requirement(camo):
    return {"amount": int(camo["AmountRequired"] or 1), "unit": unit_of(camo["CategoryRequirement"]),
            "description": text(camo["CategoryRequirement"])}


def main(src, out_dir):
    data = json.load(open(src))
    out = Path(out_dir)
    weapons, categories = [], []
    for cat in data["weapons"]:
        entries = []
        for w in cat["Weapons"]:
            # In order across the roster: ids below baseWeaponCount are the
            # launch weapons, which the class and roster gates count
            wid = len(weapons)
            unlock = w["UnlockRequirement"].strip()
            entries.append({
                "weaponId": wid,
                "name": text(w["WeaponName"]),
                "maxLevel": int(w["MaxLevel"]),
                "unlockRequirement": text(unlock if unlock.endswith(".") else unlock + "."),
                "imageURL": w["WeaponImageURL"],
            })
            weapons.append((wid, w))
        categories.append({"categoryId": int(cat["WeaponCategoryID"]), "name": text(CATEGORY_NAMES.get(cat["WeaponCategoryName"].strip(), title(cat["WeaponCategoryName"]))),
                           "weapons": entries})

    first = weapons[0][1]
    prestige_camos = []
    for i, c in enumerate(first["PrestigeCamos"]):
        camo = {"name": text(title(c["CamoName"])), "imageURL": c["CamoImageURL"]}
        m = re.search(r"Prestige (\d)\b", c["CategoryRequirement"])
        lvl = re.search(r"Level (\d+)", c["CategoryRequirement"])
        if m and not lvl:
            camo["stage"] = int(m.group(1))
        elif lvl:
            camo["stage"] = 3
            camo["level"] = int(lvl.group(1))
        prestige_camos.append(camo)

    catalog = {
        "version": VERSION,
        "baseWeaponCount": len(weapons),
        "weaponPrestige": [
            {"name": text("Prestige 1"), "maxLevel": None},
            {"name": text("Prestige 2"), "maxLevel": None},
            {"name": text("Prestige Master"), "maxLevel": 250},
        ],
        "prestigeCamos": prestige_camos,
        "categories": categories,
        "_note": "Converted from the BO7 Camo Tracker data by Tools/games/convert_bo7.py. Weapon ids run in roster order (the old app numbered weapons within each category).",
    }
    (out / "bo7_weapons.json").write_text(json.dumps(catalog, ensure_ascii=False, indent=2))

    for old, mode in MODES:
        weapon_camos = []
        steps = [{"byWeapon": {}}, {"byWeapon": {}, "unlock": "category", "needed": 6},
                 {"byWeapon": {}, "unlock": "mode", "needed": 30}]
        steps[0]["unlock"] = "weapon"
        for wid, w in weapons:
            block = w[old]
            camos = []
            for i, c in enumerate(block["MilitaryCamos"]):
                camos.append({"itemId": i, "name": text(title(c["CamoName"])), "tier": i + 1, "unlockLevel": None,
                              "requirement": requirement(c), "children": [], "imageURL": c["CamoImageURL"],
                              "group": "military"})
            base = len(camos)
            for i, c in enumerate(block["SpecialCamos"]):
                camos.append({"itemId": base + i, "name": text(title(c["CamoName"])), "tier": base + i + 1,
                              "unlockLevel": None, "requirement": requirement(c), "children": [],
                              "imageURL": c["CamoImageURL"], "group": "special"})
            weapon_camos.append({"weaponId": wid, "camos": camos})
            for i, c in enumerate(block["MasteryCamos"][:3]):
                steps[i]["byWeapon"][str(wid)] = requirement(c)
        mastery = first[old]["MasteryCamos"][:3]
        for i, c in enumerate(mastery):
            steps[i]["name"] = text(title(c["CamoName"]))
            steps[i]["imageURL"] = c["CamoImageURL"]
        mode_file = {
            "version": VERSION,
            "mode": mode,
            "specialsAfterMilitary": True,
            "weaponCamos": weapon_camos,
            "objectives": [],
            "completionist": {"steps": steps, "final": {"enabled": False}},
            "_note": f"Converted from the BO7 Camo Tracker data ({old}) by Tools/games/convert_bo7.py.",
        }
        (out / f"bo7_{mode}.json").write_text(json.dumps(mode_file, ensure_ascii=False, indent=2))
    print(f"{len(weapons)} weapons, {len(prestige_camos)} prestige camos, modes: {', '.join(m for _, m in MODES)}")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
