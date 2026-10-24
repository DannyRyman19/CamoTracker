#!/usr/bin/env python3
"""Converts the BO6 Camo Tracker data (Data/BO6/<Mode>_Camos_v2[_lang].json,
the old app's format) into Camo Tracker's per-game files: bo6_weapons.json
plus one mode file each for multiplayer, zombies and warzone.

    python3 Tools/games/convert_bo6.py ../Data/BO6 Resources

BO6's camo track, per weapon and mode: 9 Military camos (challenges), 2
Specials ("Unique") once every Military camo is done, then the Mastery
camos: the first once the weapon's Specials are done, the second once the
class has the first on as many weapons as it had at launch (7 Assault
Rifles, 6 SMGs...), the third once 33 weapons have the second, and the
fourth (Dark Matter in Multiplayer) once 33 weapons have the third. The
first three map onto Completionist steps, the fourth onto the final camo.
The elimination badges (100, 250, 500 on one count) follow as extras. Text comes in English, German,
Spanish, French and Dutch; "{0}" is the amount and "{1}" the weapon.
"""
import json
import re
import sys
from pathlib import Path

MODES = [("Multiplayer", "multiplayer"), ("Zombies", "zombies"), ("Warzone", "warzone")]
LANGS = ["de", "es", "fr", "nl"]
VERSION = "1.0.0"
BADGES = {"en": "Badges", "de": "Abzeichen", "es": "Insignias", "fr": "Insignes", "nl": "Badges", "it": "Distintivi", "pt": "Insígnias"}
CATEGORY_NAMES = {"Launchers/Specials": "Launchers & Specials"}
# The old files spell a few weapons differently per mode; one name each
WEAPON_NAMES = {"cr-56 amax": "CR-56 AMAX", "dresden 9mm": "Dresden 9mm", "ps-21": "PU-21", "pu-21": "PU-21",
                "gravemark": "Gravemark .357", "gravemark .357": "Gravemark .357", "nuncahku": "Nunchaku"}


def weapon_name(raw):
    return WEAPON_NAMES.get(raw.strip().lower(), raw.strip())


def fill(s, amount, weapon):
    return s.replace("{0}", str(amount)).replace("{1}", weapon).strip()


def unit_of(desc):
    d = desc.lower()
    if re.search(r"\d+ times", d) or " times" in d:
        return "times"
    if "headshot" in d:
        return "headshots"
    if "elimination" in d:
        return "eliminations"
    return "kills"


def load(src, mode, lang=None):
    name = f"{mode}_Camos_v2{'_' + lang if lang else ''}.json"
    p = Path(src) / name
    return json.load(open(p)) if p.exists() else None


def texts(files, path, field, amount=None, weapon=None):
    """The same camo field in every language file, as a LocalizedText."""
    out = {}
    for lang, data in files.items():
        try:
            node = data
            for key in path:
                node = node[key]
            value = node[field]
        except (IndexError, KeyError, TypeError):
            continue
        out[lang] = fill(value, amount, weapon) if amount is not None else value.strip()
    # The Spanish and Dutch files are partly English copies: keep only real translations
    return {lang: v for lang, v in out.items() if lang == "en" or v != out.get("en")}


def main(src, out_dir):
    out = Path(out_dir)
    files_by_mode = {}
    for old, _ in MODES:
        files = {"en": load(src, old)}
        for lang in LANGS:
            data = load(src, old, lang)
            if data:
                files[lang] = data
        files_by_mode[old] = files

    # One weapon list across the modes, in category order, keyed by name
    categories, weapons, ids = [], [], {}
    for old, _ in MODES:
        for ci, cat in enumerate(files_by_mode[old]["en"]):
            while len(categories) <= ci:
                categories.append({"categoryId": len(categories), "name": None, "weapons": []})
            if categories[ci]["name"] is None:
                name = cat["WeaponCategoryName"].strip()
                categories[ci]["name"] = {"en": CATEGORY_NAMES.get(name, name)}
            for w in cat["Weapons"]:
                key = (ci, weapon_name(w["WeaponName"]))
                if key in ids:
                    continue
                ids[key] = None
                weapons.append((ci, w))
    # Ids in roster order, class by class, so each class's own weapons stay together
    weapons.sort(key=lambda x: x[0])
    for wid, (ci, w) in enumerate(weapons):
        ids[(ci, weapon_name(w["WeaponName"]))] = wid
        unlock = str(w["UnlockRequirement"]).strip()
        categories[ci]["weapons"].append({
            "weaponId": wid,
            "name": {"en": weapon_name(w["WeaponName"])},
            "maxLevel": int(w["MaxLevel"]),
            "unlockRequirement": {"en": unlock if unlock.endswith(".") else unlock + "."},
            "imageURL": w["WeaponImageURL"],
        })

    catalog = {
        "version": VERSION,
        "baseWeaponCount": len(weapons),
        "weaponPrestige": [],
        "prestigeCamos": [],
        "categories": categories,
        "_note": "Converted from the BO6 Camo Tracker data by Tools/games/convert_bo6.py.",
    }
    (out / "bo6_weapons.json").write_text(json.dumps(catalog, ensure_ascii=False, indent=2))

    for old, mode in MODES:
        files = files_by_mode[old]
        en = files["en"]
        weapon_camos = []
        steps = [{"byWeapon": {}, "unlock": "weapon"},
                 {"byWeapon": {}, "unlock": "category", "neededByCategory": {}},
                 {"byWeapon": {}, "unlock": "mode", "needed": 33}]
        final = {}
        for ci, cat in enumerate(en):
            for wi, w in enumerate(cat["Weapons"]):
                name = weapon_name(w["WeaponName"])
                wid = ids[(ci, name)]
                if any(e["weaponId"] == wid for e in weapon_camos):
                    continue  # listed twice under two spellings: keep the first
                camos = []
                groups = [("MilitaryCamos", "military"), ("UniqueCamos", "special")]
                for grp, group in groups:
                    for i, c in enumerate(w.get(grp, [])):
                        amount = int(c["AmountRequired"] or 1)
                        path = [ci, "Weapons", wi, grp, i]
                        desc = texts(files, path, "CategoryRequirement", amount, name)
                        camos.append({"itemId": len(camos), "name": texts(files, path, "CamoName") or {"en": c["CamoName"]},
                                      "tier": len(camos) + 1, "unlockLevel": None,
                                      "requirement": {"amount": amount, "unit": unit_of(desc["en"]), "description": desc},
                                      "children": [], "imageURL": c["CamoURL"], "group": group})
                # The elimination badges: one count, earned at 100, 250 and 500
                badges = [c for c in w["MasteryCamos"] if c["CamoName"].startswith("Badge") or c["CamoName"] == "Mastery"]
                counter, total = len(camos), 0
                for c in badges:
                    total += int(c["AmountRequired"] or 0)
                    path = [ci, "Weapons", wi, "MasteryCamos", w["MasteryCamos"].index(c)]
                    desc = texts(files, path, "CategoryRequirement", total, name)
                    camos.append({"itemId": len(camos), "name": texts(files, path, "CamoName") or {"en": c["CamoName"]},
                                  "tier": None, "unlockLevel": None,
                                  "requirement": {"amount": total, "unit": "eliminations", "description": desc},
                                  "children": [], "imageURL": c["CamoURL"] or None, "counter": counter,
                                  "section": BADGES, "extra": True})
                weapon_camos.append({"weaponId": wid, "camos": camos})
                mastery = [c for c in w["MasteryCamos"] if not c["CamoName"].startswith("Badge") and c["CamoName"] != "Mastery"]
                for i, c in enumerate(mastery[:3]):
                    amount = int(c["AmountRequired"] or 1)
                    path = [ci, "Weapons", wi, "MasteryCamos", w["MasteryCamos"].index(c)]
                    desc = texts(files, path, "CategoryRequirement", amount, name)
                    steps[i]["byWeapon"][str(wid)] = {"amount": amount, "unit": unit_of(desc["en"]), "description": desc}
                    if "name" not in steps[i]:
                        steps[i]["name"] = texts(files, path, "CamoName")
                        steps[i]["imageURL"] = c["CamoURL"]
                    if i == 1:
                        m = re.search(r"for (\d+) ", c["UnlockRequirement"])
                        if m:
                            steps[1]["neededByCategory"][str(ci)] = int(m.group(1))
                if len(mastery) > 3 and not final:
                    c = mastery[3]
                    path = [ci, "Weapons", wi, "MasteryCamos", w["MasteryCamos"].index(c)]
                    final = {"name": texts(files, path, "CamoName"), "imageURL": c["CamoURL"], "harmonicBreaksNeeded": 33}
        mode_file = {
            "version": VERSION,
            "mode": mode,
            "specialsAfterMilitary": True,
            "weaponCamos": weapon_camos,
            "objectives": [],
            "completionist": {"steps": steps, "final": final or {"enabled": False}},
            "_note": f"Converted from the BO6 Camo Tracker data ({old}_Camos_v2) by Tools/games/convert_bo6.py.",
        }
        (out / f"bo6_{mode}.json").write_text(json.dumps(mode_file, ensure_ascii=False, indent=2))
        print(f"{mode}: {len(weapon_camos)} weapons, steps {[s.get('name', {}).get('en') for s in steps]}, "
              f"final {final.get('name', {}).get('en')}, class counts {steps[1]['neededByCategory']}, languages {sorted(files)}")
    print(f"catalog: {len(weapons)} weapons")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
