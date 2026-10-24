#!/usr/bin/env python3
"""Converts the BO2 Camo Tracker data (Data/BO2/Multiplayer_Camos.json and
Multiplayer_Challenges.json, the old app's format) into Camo Tracker's
per-game files: bo2_weapons.json and bo2_multiplayer.json.

    python3 Tools/games/convert_bo2.py ../Data/BO2 Resources

BO2's camo track, per weapon: 14 camos, each its own challenge, in order.
Then two automatic camos, so the game sets `completionistSteps` 2: Gold once
all 14 are done, Diamond once every weapon in the class has Gold. The
challenge list (33 categories) becomes the mode's objectives. Reticles are
left out.
"""
import json
import re
import sys
from pathlib import Path

VERSION = "1.0.0"


def unit_of(desc):
    d = desc.lower()
    if "headshot" in d:
        return "headshots"
    if "medal" in d:
        return "medals"
    return "kills"


def sentence(s):
    s = s.strip()
    return s if s.endswith(".") or s.endswith("!") else s + "."


def main(src, out_dir):
    out = Path(out_dir)
    data = json.load(open(Path(src) / "Multiplayer_Camos.json", encoding="utf-8-sig"))
    challenges = json.load(open(Path(src) / "Multiplayer_Challenges.json", encoding="utf-8-sig"))
    categories, weapon_camos, wid = [], [], 0
    for ci, cat in enumerate(data):
        entries = []
        for w in cat["Weapons"]:
            entries.append({"weaponId": wid, "name": {"en": w["WeaponName"].strip()}, "maxLevel": int(w["MaxLevel"]),
                            "unlockRequirement": {"en": sentence(w["UnlockRequirement"])}, "imageURL": w["WeaponImageURL"]})
            camos = []
            for i, c in enumerate(w["Camos"]):
                amount = int(c["AmountRequired"])
                desc = c["CategoryRequirement"].replace("{0}", str(amount)).strip()
                camos.append({"itemId": i, "name": {"en": c["CamoName"].strip()}, "tier": i + 1, "unlockLevel": None,
                              "requirement": {"amount": amount, "unit": unit_of(desc), "description": {"en": sentence(desc)}},
                              "children": [], "imageURL": c["CamoImageURL"]})
            weapon_camos.append({"weaponId": wid, "camos": camos})
            wid += 1
        categories.append({"categoryId": ci, "name": {"en": cat["WeaponCategoryName"].strip()}, "weapons": entries})
    catalog = {"version": VERSION, "baseWeaponCount": wid, "weaponPrestige": [], "prestigeCamos": [], "categories": categories,
               "_note": "Converted from the BO2 Camo Tracker data by Tools/games/convert_bo2.py."}
    (out / "bo2_weapons.json").write_text(json.dumps(catalog, ensure_ascii=False, indent=2))

    mastery = data[0]["Weapons"][0]["MasteryCamos"]
    steps = [{"name": {"en": mastery[0]["CamoName"]}, "imageURL": mastery[0]["CamoImageURL"], "unlock": "weapon", "auto": True},
             {"name": {"en": mastery[1]["CamoName"]}, "imageURL": mastery[1]["CamoImageURL"], "unlock": "category", "auto": True}]
    objectives = []
    for cat in challenges:
        items = []
        for ch in cat["Challenges"]:
            amount = int(ch["AmountRequired"] or 1)
            items.append({"itemId": int(ch["ChallengeID"]), "name": {"en": ch["ChallengeName"].strip()}, "imageURL": None, "tier": None,
                          "unlockLevel": None,
                          "requirement": {"amount": amount, "unit": "times", "description": {"en": sentence(ch["ChallengeDescription"])}}
                          if amount > 1 else None, "children": []})
        objectives.append({"categoryId": int(cat["CategoryID"]), "name": {"en": cat["CategoryName"].strip()}, "items": items})
    mode_file = {"version": VERSION, "mode": "multiplayer", "weaponCamos": weapon_camos, "objectives": objectives,
                 "completionist": {"steps": steps, "final": {"enabled": False}},
                 "_note": "Converted from the BO2 Camo Tracker data by Tools/games/convert_bo2.py."}
    (out / "bo2_multiplayer.json").write_text(json.dumps(mode_file, ensure_ascii=False, indent=2))
    print(f"bo2: {wid} weapons, {len(weapon_camos[0]['camos'])} camos each, {[s['name']['en'] for s in steps]}, "
          f"{len(objectives)} challenge categories ({sum(len(o['items']) for o in objectives)} challenges)")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
