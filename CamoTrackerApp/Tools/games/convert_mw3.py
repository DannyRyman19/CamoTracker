#!/usr/bin/env python3
"""Converts the MW3 Camo Tracker data (Data/MW3/Updated_*.json, the old
app's format) into two Camo Tracker games:

- MW3 (mw3_*): Multiplayer and Zombies, MW3's own weapons
- MWII (mw2_*): Multiplayer and Zombies, the MWII weapons, which kept
  MWII's camo grind in MW3 (the most complete MWII roster we have)

    python3 Tools/games/convert_mw3.py ../Data/MW3 Resources

Per weapon and mode: 4 base camos (a challenge each, opening at a weapon
level), then 3 Completionist camos and a final one, as the old app rules
them: the first once the weapon's base camos are done, the second once the
class's launch weapons all have the first, the third once as many weapons
as there were at launch have the second (MW3 36, MWII 51), and the final
once that many have the third. Launch weapons get the lowest ids, so the
app's launch roster matches. English and German.
"""
import json
import sys
from pathlib import Path

VERSION = "1.0.0"
# GameType in the old app: 0 MW3 launch, 1 MW3 seasonal, 3 MWII launch, 4 MWII seasonal
GAMES = {
    "mw3": {"launch": 0, "modes": [("multiplayer", "Updated_MultiplayerWeapons"), ("zombies", "Updated_ZombiesWeapons")],
            "finals": {"multiplayer": "Interstellar", "zombies": "Borealis"}},
    "mw2": {"launch": 3, "modes": [("multiplayer", "Updated_MW2MultiplayerWeapons"), ("zombies", "Updated_MW2ZombiesWeapons")],
            "finals": {"multiplayer": "Orion", "zombies": "Bioluminescent"}},
}
CATEGORY_NAMES = {"SMGS": "SMGs", "LMGS": "LMGs"}
FINAL_IMAGES = "https://camotracker.djr.li/Images/Camos/MW3Tracker/{}.png"


def load(src, name):
    p = Path(src) / f"{name}.json"
    return json.load(open(p, encoding="utf-8-sig")) if p.exists() else None


def fill(s, amount):
    return s.replace("{0}", str(amount)).strip()


def unit_of(desc):
    d = desc.lower()
    if " times" in d:
        return "times"
    if "headshot" in d:
        return "headshots"
    return "kills"


def title(s):
    # "Rancid venom" -> "Rancid Venom"; "M4" and "of" stay as they are
    return " ".join(w[0].upper() + w[1:] if w.isalpha() and w.islower() and w not in ("of", "the") else w for w in s.split())


def localized(en, de):
    return {"en": en, **({"de": de} if de and de != en else {})}


def convert(src, out, gid, spec):
    first = load(src, spec["modes"][0][1])
    # Weapon ids: launch weapons first across every class, then seasonal ones
    order = []
    for ci, cat in enumerate(first):
        for wi, w in enumerate(cat["Weapons"]):
            order.append((0 if w["GameType"] == spec["launch"] else 1, ci, wi, w))
    order.sort(key=lambda x: (x[0], x[1], x[2]))
    ids = {(ci, wi): n for n, (_, ci, wi, _) in enumerate(order)}
    launch = sum(1 for o in order if o[0] == 0)
    launch_per_class = {}
    categories = []
    for ci, cat in enumerate(first):
        name = cat["WeaponCategoryName"].strip()
        entries = []
        for wi, w in enumerate(cat["Weapons"]):
            unlock = w["UnlockRequirement"].strip()
            entries.append({"weaponId": ids[(ci, wi)], "name": {"en": w["WeaponName"].strip()}, "maxLevel": int(w["MaxLevel"]),
                            "unlockRequirement": {"en": unlock if unlock.endswith(".") else unlock + "."},
                            "imageURL": w["WeaponImageURL"]})
            if w["GameType"] == spec["launch"]:
                launch_per_class[str(ci)] = launch_per_class.get(str(ci), 0) + 1
        entries.sort(key=lambda e: e["weaponId"])
        categories.append({"categoryId": ci, "name": {"en": CATEGORY_NAMES.get(name, name)}, "weapons": entries})
    catalog = {"version": VERSION, "baseWeaponCount": launch, "weaponPrestige": [], "prestigeCamos": [],
               "categories": categories,
               "_note": f"Converted from the MW3 Camo Tracker data by Tools/games/convert_mw3.py; ids put the {launch} launch weapons first."}
    (out / f"{gid}_weapons.json").write_text(json.dumps(catalog, ensure_ascii=False, indent=2))

    for mode, name in spec["modes"]:
        en, de = load(src, name), load(src, name + "-de")
        weapon_camos = []
        steps = [{"byWeapon": {}, "unlock": "weapon"},
                 {"byWeapon": {}, "unlock": "category", "neededByCategory": launch_per_class},
                 {"byWeapon": {}, "unlock": "mode", "needed": launch}]
        for ci, cat in enumerate(en):
            for wi, w in enumerate(cat["Weapons"]):
                wid = ids[(ci, wi)]
                dw = None
                try:
                    dw = de[ci]["Weapons"][wi] if de else None
                except (IndexError, KeyError):
                    pass
                camos = []
                for i, c in enumerate(w["Camos"]):
                    dc = dw["Camos"][i] if dw and i < len(dw["Camos"]) else None
                    amount = int(c["AmountRequired"])
                    camos.append({"itemId": i, "name": localized(title(c["CamoName"]), dc and dc["CamoName"].strip()),
                                  "tier": i + 1, "unlockLevel": int(c["UnlockLevel"]),
                                  "requirement": {"amount": amount, "unit": unit_of(c["CategoryRequirement"]),
                                                  "description": localized(fill(c["CategoryRequirement"], amount),
                                                                           dc and fill(dc["CategoryRequirement"], amount))},
                                  "children": [], "imageURL": c["CamoURL"], "group": "military"})
                # The per-weapon extras: kills with each Completionist camo,
                # and the Prestige camos earned with weapon XP
                for key, section in (("MasteryChallenges", {"en": "Mastery", "de": "Meisterschaft"}),
                                     ("PrestigeChallenges", {"en": "Prestige", "de": "Prestige"})):
                    for i, c in enumerate(w.get(key) or []):
                        dc = (dw.get(key) or [])[i] if dw and i < len(dw.get(key) or []) else None
                        amount = int(c["AmountRequired"])
                        desc_en = fill(c["CategoryRequirement"], amount).replace("weapon xp", "weapon XP")
                        desc_de = dc and fill(dc["CategoryRequirement"], amount)
                        camos.append({"itemId": len(camos), "name": localized(title(c["ChallengeName"].replace("Engima", "Enigma")),
                                                                              dc and title(dc["ChallengeName"].replace("Engima", "Enigma"))),
                                      "tier": None, "unlockLevel": None,
                                      "requirement": {"amount": amount, "unit": "xp" if "xp" in desc_en.lower() else "kills",
                                                      "description": localized(desc_en if desc_en.endswith(".") else desc_en + ".",
                                                                               desc_de and (desc_de if desc_de.endswith(".") else desc_de + "."))},
                                      "children": [], "imageURL": None, "section": section, "extra": True})
                weapon_camos.append({"weaponId": wid, "camos": camos})
                for i, c in enumerate(w["CompletionistCamos"][:3]):
                    dc = dw["CompletionistCamos"][i] if dw and i < len(dw.get("CompletionistCamos", [])) else None
                    amount = int(c["AmountRequired"])
                    steps[i]["byWeapon"][str(wid)] = {
                        "amount": amount, "unit": unit_of(c["CategoryRequirement"]),
                        "description": localized(fill(c["CategoryRequirement"], amount), dc and fill(dc["CategoryRequirement"], amount))}
                    if "name" not in steps[i]:
                        steps[i]["name"] = localized(title(c["CamoName"]), dc and dc["CamoName"].strip())
                        steps[i]["imageURL"] = c["CamoURL"]
        final_name = spec["finals"][mode]
        mode_file = {"version": VERSION, "mode": mode, "weaponCamos": weapon_camos, "objectives": [],
                     "completionist": {"steps": steps, "final": {"name": {"en": final_name}, "harmonicBreaksNeeded": launch,
                                                                 "imageURL": FINAL_IMAGES.format(final_name.lower())}},
                     "_note": f"Converted from the MW3 Camo Tracker data ({name}) by Tools/games/convert_mw3.py."}
        (out / f"{gid}_{mode}.json").write_text(json.dumps(mode_file, ensure_ascii=False, indent=2))
        print(f"{gid} {mode}: {len(weapon_camos)} weapons, {[s['name']['en'] for s in steps]} then {final_name} ({launch}), "
              f"class counts {launch_per_class}, German {'yes' if de else 'no'}")


def main(src, out_dir):
    out = Path(out_dir)
    for gid, spec in GAMES.items():
        convert(src, out, gid, spec)


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
