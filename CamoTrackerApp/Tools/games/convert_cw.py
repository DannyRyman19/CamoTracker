#!/usr/bin/env python3
"""Converts the Cold War Camo Tracker data (Data/1_0_9<Mode>Camos.json, the
old app's format) into Camo Tracker's per-game files: cw_weapons.json plus
one mode file each for multiplayer and zombies.

    python3 Tools/games/convert_cw.py ../Data Resources

Cold War's camo track, per weapon and mode: 7 camo categories of 5 camos,
each category one challenge ("Get eliminations", 300 in all) that earns
its camos along the way and opens at a weapon level; the camos of a
category share one count (`counter`). Then, all automatic: Gold (Golden
Viper in Zombies) once every camo is done, Diamond (Plague Diamond) once 2
weapons in the class have Gold, and Dark Matter (Dark Aether) once every
main class has Diamond (Launchers and Melee don't count). Each category
is its own section, and the Sharpshooter badge sits after them as an extra
that doesn't hold up Gold. The old site hosts no camo pictures.
"""
import json
import re
import sys
from pathlib import Path

VERSION = "1.0.0"
MODES = [("Multiplayer", "multiplayer"), ("Zombies", "zombies")]
CATEGORY_NAMES = {"AssaultRifles": "Assault Rifles", "SubmachineGuns": "SMGs", "TacticalRifles": "Tactical Rifles",
                  "LightMachineGuns": "LMGs", "SniperRifles": "Sniper Rifles"}
# Dark Matter needs Diamond in these classes
DARK_MATTER_CLASSES = ["AssaultRifles", "SubmachineGuns", "TacticalRifles", "LightMachineGuns", "SniperRifles", "Pistols", "Shotguns"]
STEPS = {
    "multiplayer": [("Gold", ["#F5D77A", "#C9A227", "#8A6A12"]), ("Diamond", ["#E8FBFF", "#8FDDF5", "#4BA9D6"]),
                    ("Dark Matter", ["#C77DFF", "#5A189A", "#10002B"])],
    "zombies": [("Golden Viper", ["#F0D36B", "#9DBA3C", "#4E7A1F"]), ("Plague Diamond", ["#D6FFE9", "#6FE0B0", "#2E9C7A"]),
                ("Dark Aether", ["#B88CFF", "#6A2FD1", "#2A0F5C"])],
}


def unit_of(desc):
    d = desc.lower()
    if re.search(r"\b(get|kill) \d", d):
        return "times"
    if "headshot" in d or "critical" in d:
        return "headshots"
    if "elimination" in d:
        return "eliminations"
    return "kills"


def text(desc, amount, sub):
    # The old files carry each camo's own wording ("Get 25 eliminations in Multiplayer.")
    own = (sub.get("CamoDescription") or "").strip()
    if own:
        return own if own.endswith(".") else own + "."
    return f"{desc.strip().rstrip('.')}: {amount}."


def https(url):
    return url.replace("http://", "https://", 1) if url else url


def main(src, out_dir):
    out = Path(out_dir)
    files = {mode: json.load(open(Path(src) / f"1_0_9{old}Camos.json", encoding="utf-8-sig")) for old, mode in MODES}
    first = files["multiplayer"]
    classes = list(first.keys())
    order = []
    for ci, key in enumerate(classes):
        for wi, w in enumerate(first[key]):
            order.append((0 if w["IsDefault"] else 1, ci, wi))
    order.sort()
    ids = {(ci, wi): n for n, (_, ci, wi) in enumerate(order)}
    launch = sum(1 for o in order if o[0] == 0)
    categories = []
    for ci, key in enumerate(classes):
        entries = []
        for wi, w in enumerate(first[key]):
            if w["IsDefault"]:
                unlock = "Unlocked by default." if int(w.get("UnlockLevel") or 1) <= 1 else f"Unlocked at Level {w['UnlockLevel']}."
            else:
                unlock = (w.get("UnlockDescription") or "Season weapon.").strip()
                unlock = unlock if unlock.endswith(".") else unlock + "."
            entries.append({"weaponId": ids[(ci, wi)], "name": {"en": w["WeaponName"].strip()}, "maxLevel": int(w["MaxLevel"]),
                            "unlockRequirement": {"en": unlock}, "imageURL": https(w["WeaponURL"])})
        entries.sort(key=lambda e: e["weaponId"])
        categories.append({"categoryId": ci, "name": {"en": CATEGORY_NAMES.get(key, key)}, "weapons": entries})
    catalog = {"version": VERSION, "baseWeaponCount": launch, "weaponPrestige": [], "prestigeCamos": [], "categories": categories,
               "_note": f"Converted from the Cold War Camo Tracker data by Tools/games/convert_cw.py; ids put the {launch} launch weapons first."}
    (out / "cw_weapons.json").write_text(json.dumps(catalog, ensure_ascii=False, indent=2))

    for old, mode in MODES:
        data = files[mode]
        assert list(data.keys()) == classes
        weapon_camos = []
        for ci, key in enumerate(classes):
            for wi, w in enumerate(data[key]):
                assert w["WeaponName"].strip() == first[key][wi]["WeaponName"].strip(), (w["WeaponName"], first[key][wi]["WeaponName"])
                camos = []
                for group in w["Camos"]:
                    counter = len(camos)
                    desc = group["CategoryDescription"]
                    for sub in group["CategoryCamos"]:
                        amount = int(sub["Amount"])
                        camos.append({"itemId": len(camos), "name": {"en": sub["CamoName"].strip()}, "tier": len(camos) + 1,
                                      "unlockLevel": int(group["CategoryUnlockLevel"]),
                                      "requirement": {"amount": amount, "unit": unit_of(desc), "description": {"en": text(desc, amount, sub)}},
                                      "children": [], "imageURL": None, "counter": counter,
                                      "section": {"en": group["CategoryName"].strip()}})
                # The Sharpshooter badge: headshots (critical kills in Zombies), not a camo
                need = int(w.get("SharpshooterRequired") or 0)
                if need:
                    what = "critical kills" if mode == "zombies" else "headshots"
                    camos.append({"itemId": len(camos), "name": {"en": "Sharpshooter"}, "tier": None, "unlockLevel": None,
                                  "requirement": {"amount": need, "unit": "headshots", "description": {"en": f"Get {need} {what}."}},
                                  "children": [], "imageURL": None, "section": {"en": "Badges"}, "extra": True})
                weapon_camos.append({"weaponId": ids[(ci, wi)], "camos": camos})
        weapon_camos.sort(key=lambda e: e["weaponId"])
        (gold, gc), (diamond, dc), (last, lc) = STEPS[mode]
        steps = [{"name": {"en": gold}, "colors": gc, "unlock": "weapon", "auto": True},
                 {"name": {"en": diamond}, "colors": dc, "unlock": "category", "needed": 2, "auto": True},
                 {"name": {"en": last}, "colors": lc, "unlock": "mode", "classes": [classes.index(c) for c in DARK_MATTER_CLASSES], "auto": True}]
        mode_file = {"version": VERSION, "mode": mode, "weaponCamos": weapon_camos, "objectives": [],
                     "completionist": {"steps": steps, "final": {"enabled": False}},
                     "_note": f"Converted from the Cold War Camo Tracker data (1_0_9{old}Camos) by Tools/games/convert_cw.py."}
        (out / f"cw_{mode}.json").write_text(json.dumps(mode_file, ensure_ascii=False, indent=2))
        print(f"cw {mode}: {len(weapon_camos)} weapons, {len(weapon_camos[0]['camos'])} camos each, then {gold}, {diamond}, {last} ({launch} launch)")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
