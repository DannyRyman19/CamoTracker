#!/usr/bin/env python3
"""Builds Camo Track's MW3 and MW2 data from the old MW3 Camo Tracker's lists.

The old app (Xamarin, ~/MW3CamoTracker) read four files from
camotracker.djr.li/Data/MW3/: MW3 weapons in Multiplayer and Zombies, and the
MWII weapons carried into MW3, in Multiplayer and Zombies. Each has German
twins (`-de`). Camo Track has them as two games, writing into
MW4CamoTracker/Resources/:

    mw3_weapons.json      MW3's 60 guns
    mw3_multiplayer.json  base camos, Gilded > Forged > Priceless > Interstellar
    mw3_zombies.json      base camos, Golden Enigma > Zircon Scale > Serpentinite > Borealis
    mw2_weapons.json      the 77 MWII guns
    mw2_multiplayer.json  base camos, Gold > Platinum > Polyatomic > Orion
    mw2_zombies.json      base camos, Golden Ivory > Spinel Husk > Arachnida > Bioluminescent

then `publish_data.py --game mw3` and `--game mw2` copy them to Data/CT/.

Weapon ids: each game's launch weapons first (MW3's 36, MWII's 51, so
`baseWeaponCount` marks them), then its season weapons.
Camo itemIds are each weapon's camo order (0...), its four Mastery
challenges 100-103 and its four Prestige camos 200-203, the same places the
old app kept them in, so its exported file imports by position.

Unlock rules, from the game (and the old app's counts):
  MW3 MP   Gilded: the weapon's camos. Forged: Gilded on every launch weapon
           in its class. Priceless: Forged on 36 weapons. Interstellar:
           Priceless on 36.
  MW3 ZM   Golden Enigma, Zircon Scale, Serpentinite: each the one before on
           the weapon. Borealis: Serpentinite on 36.
  MWII MP  Gold: the weapon's camos. Platinum: Gold on every launch weapon in
           its class. Polyatomic: Platinum on 51. Orion: Polyatomic on 51.
  MWII ZM  Golden Ivory, Spinel Husk, Arachnida: each on the weapon.
           Bioluminescent: Arachnida on 51.

Run: /usr/bin/python3 MW4CamoTracker/Tools/games/convert_mw3.py
"""
import difflib
import json
import re
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[3]
SRC = ROOT / "Data" / "MW3"
RES = ROOT / "MW4CamoTracker" / "Resources"
SITE = "https://camotracker.djr.li/"
CAMO_DIR = ROOT / "Images" / "Camos" / "MW3Tracker"
VERSION = "1.0.0"

# Each game's modes, from the old app's lists
GAMES = {
    "mw3": {"multiplayer": "Updated_MultiplayerWeapons", "zombies": "Updated_ZombiesWeapons"},
    "mw2": {"multiplayer": "Updated_MW2MultiplayerWeapons", "zombies": "Updated_MW2ZombiesWeapons"},
}
# GameType in the old files: 0 MW3 launch, 1 MW3 season, 3 MWII launch, 4 MWII season
LAUNCH = {0, 3}

CATEGORY_NAMES = {
    "Assault Rifles": ("Assault Rifles", "Sturmgewehre"),
    "Battle Rifles": ("Battle Rifles", "Kampfgewehre"),
    "SMGS": ("SMGs", "MPs"),
    "Shotguns": ("Shotguns", "Schrotflinten"),
    "LMGS": ("LMGs", "LMGs"),
    "Marksman Rifles": ("Marksman Rifles", "Präzisionsgewehre"),
    "Sniper Rifles": ("Sniper Rifles", "Scharfschützengewehre"),
    "Pistols": ("Pistols", "Pistolen"),
    "Handguns": ("Handguns", "Pistolen"),
    "Launchers": ("Launchers", "Werfer"),
    "Melee": ("Melee", "Nahkampf"),
}

# The old lists' casing, made the game's. Only case changes: the import
# from the old app matches weapons by name, case-blind.
NAMES = {
    "WSP swarm": "WSP Swarm", "HOLGER 556": "Holger 556", "FJX HORUS": "FJX Horus",
    "LONGBOW": "Longbow", "STORMENDER": "Stormender", "Iso 45": "ISO 45", "Bas-P": "BAS-P",
    "FTAC RECON": "FTAC Recon", "TR-76 GEIST": "TR-76 Geist", "9MM Daemon": "9mm Daemon",
    "Pila": "PILA", "Rapp H": "RAPP H", "Raal MG": "RAAL MG", "Ram-7": "RAM-7",
}

# The four completionist camos per list, with what opens each
TRACKS = {
    ("mw3", "multiplayer"): dict(
        unlocks=["weapon", "category", "mode"], needed=36, final="Interstellar", final_de="Interstellar",
        final_image="interstellar.png"),
    ("mw3", "zombies"): dict(
        unlocks=["weapon", "weapon", "weapon"], needed=None, final="Borealis", final_de="Borealis",
        final_image="borealis.png", final_needed=36),
    ("mw2", "multiplayer"): dict(
        unlocks=["weapon", "category", "mode"], needed=51, final="Orion", final_de="Orion",
        final_image="orion.png"),
    ("mw2", "zombies"): dict(
        unlocks=["weapon", "weapon", "weapon"], needed=None, final="Bioluminescent", final_de="Biolumineszenz",
        final_image="bioluminescent.png", final_needed=51),
}

# Name shimmer per completionist camo, picked by eye from the camo art (the
# pictures are guns wearing them, so averaging them reads grey)
PALETTES = {
    "Gilded": ["#D4AF37", "#F6E7A1", "#8A6A12"], "Forged": ["#D2602A", "#F5A35E", "#3A2A24"],
    "Priceless": ["#3FA3E0", "#DDF1FF", "#1B5C9A"], "Interstellar": ["#8A6CFF", "#CBBEFF", "#241A5C"],
    "Golden Enigma": ["#D9B44A", "#FFF1B8", "#7A5A10"], "Zircon Scale": ["#C9353A", "#FF8F86", "#5D1D20"],
    "Serpentinite": ["#5A9A3E", "#BEDD84", "#1A2E15"], "Borealis": ["#3FD0B0", "#B08CFF", "#22305A"],
    "Gold": ["#D4AF37", "#F6E7A1", "#8A6A12"], "Platinum": ["#C7D1DB", "#F4F8FB", "#7C8790"],
    "Polyatomic": ["#8A5BE0", "#E39BFF", "#2C1A5E"], "Orion": ["#C24A86", "#F2A6D0", "#3A1430"],
    "Golden Ivory": ["#E6D3A3", "#FFF8E6", "#9A8455"], "Spinel Husk": ["#C0395F", "#F28BA8", "#4A1023"],
    "Arachnida": ["#8C99A6", "#D3DCE3", "#2A3036"], "Bioluminescent": ["#2FD4E0", "#9BF6FF", "#0E3A4A"],
}

SECTIONS = {
    # The weapon page names its extras tab after the first section: kills
    # with each mastery camo read as badges, as BO6's do
    "mastery": {"en": "Badges", "de": "Abzeichen", "es": "Insignias", "fr": "Insignes",
                "nl": "Badges", "it": "Distintivi", "pt": "Insígnias"},
    "prestige": {"en": "Prestige", "de": "Prestige", "es": "Prestigio", "fr": "Prestige",
                 "it": "Prestigio", "nl": "Prestige", "pt": "Prestígio"},
}


def load(name):
    return json.loads((SRC / f"{name}.json").read_text(encoding="utf-8-sig"))


def unit(text):
    t = text.lower()
    if "xp" in t:
        return "xp"
    if "{0} times" in t:
        return "times"
    if "headshot" in t:
        return "headshots"
    return "kills"


def text(template, amount):
    return template.replace("{0}", f"{amount:,}" if amount >= 10000 else str(amount)).strip()


def requirement(en, de, amount):
    desc = {"en": text(en, amount)}
    if de:
        desc["de"] = text(de, amount)
    return {"amount": amount, "unit": unit(en), "description": desc}


AVAILABLE = sorted(p.name for p in CAMO_DIR.glob("*.png"))


def camo_image(url):
    """The camo picture's URL when the site has it, else its closest name
    there (a few of the old links had typos), else none."""
    if not url:
        return None
    name = url.rsplit("/", 1)[-1]
    if (CAMO_DIR / name).exists():
        return url
    close = difflib.get_close_matches(name, AVAILABLE, n=1, cutoff=0.85)
    return f"{SITE}Images/Camos/MW3Tracker/{close[0]}" if close else None


def colors(image_name, fallback):
    """Three swatches for a camo's name shimmer: its mean colour, a light and
    a dark one, from the picture."""
    path = CAMO_DIR / image_name
    if not path.exists():
        return fallback
    im = Image.open(path).convert("RGB").resize((48, 48))
    px = list(im.getdata())
    px.sort(key=lambda c: sum(c))
    def mean(part):
        n = len(part)
        return tuple(sum(c[i] for c in part) // n for i in range(3))
    mid = mean(px[len(px) // 4: 3 * len(px) // 4])
    light = mean(px[-len(px) // 6:])
    dark = mean(px[: len(px) // 6])
    hexs = lambda c: "#%02X%02X%02X" % c
    return [hexs(mid), hexs(light), hexs(dark)]


def main():
    for game, files in GAMES.items():
        convert(game, files)


def convert(game, files):
    en = {m: load(f) for m, f in files.items()}
    de = {m: load(f + "-de") for m, f in files.items()}
    ref = en["multiplayer"]

    # ── Catalog ─────────────────────────────────────────────────────────
    # (category index, weapon index) -> id: launch weapons first
    order = [(w["GameType"] in LAUNCH, ci, wi) for ci, cat in enumerate(ref) for wi, w in enumerate(cat["Weapons"])]
    ids = {}
    for launch_pass in (True, False):
        for launch, ci, wi in order:
            if launch == launch_pass:
                ids[(ci, wi)] = len(ids)
    base_count = sum(1 for o in order if o[0])

    categories = []
    for ci, cat in enumerate(ref):
        name_en, name_de = CATEGORY_NAMES[cat["WeaponCategoryName"]]
        weapons = []
        for wi, w in enumerate(cat["Weapons"]):
            wde = de["multiplayer"][ci]["Weapons"][wi]
            unlock = {"en": w["UnlockRequirement"]}
            if wde.get("UnlockRequirement"):
                unlock["de"] = wde["UnlockRequirement"]
            entry = {
                "weaponId": ids[(ci, wi)],
                "name": {"en": NAMES.get(w["WeaponName"], w["WeaponName"])},
                "maxLevel": w["MaxLevel"],
                "unlockRequirement": unlock,
                "imageURL": w.get("WeaponImageURL") or None,
            }
            # Season weapons: how they're got, so "Season 5 Battle Pass"
            # or "Get 45 kills" isn't read as an unlock level
            said = w["UnlockRequirement"].strip().replace("Rfile", "Rifle")
            unlock["en"] = said
            if re.search(r"battle ?pass", said, re.I):
                entry["acquiredBy"] = "battlePass"
            elif re.search(r"armou?ry", said, re.I):
                entry["acquiredBy"] = "armory"
            elif said and not re.match(r"unlock(s|ed)? at (player )?level \d+", said, re.I):
                entry["acquiredBy"] = "challenge"
            weapons.append(entry)
        categories.append({"categoryId": ci, "name": {"en": name_en, "de": name_de}, "weapons": weapons})

    write(f"{game}_weapons.json", {
        "version": VERSION,
        "baseWeaponCount": base_count,
        "weaponPrestige": [],
        "prestigeCamos": [],
        "_note": "Converted from the MW3 Camo Tracker data by Tools/games/convert_mw3.py.",
        "categories": categories,
    })

    # ── Mode files ──────────────────────────────────────────────────────
    for mode in files:
        track = TRACKS[(game, mode)]
        lists_en, lists_de = en[mode], de[mode]
        steps_by_weapon = [{}, {}, {}]
        step_names = [None, None, None]
        launch_by_class = {}
        weapon_camos = []
        steps_by_weapon = [{}, {}, {}]
        step_names = [None, None, None]
        launch_by_class = {}
        for ci, cat in enumerate(lists_en):
            for wi, w in enumerate(cat["Weapons"]):
                assert w["WeaponName"].lower() == ref[ci]["Weapons"][wi]["WeaponName"].lower(), (mode, w["WeaponName"])
                wid = ids[(ci, wi)]
                wde = lists_de[ci]["Weapons"][wi]
                class_id = ci
                if w["GameType"] in LAUNCH:
                    launch_by_class[str(class_id)] = launch_by_class.get(str(class_id), 0) + 1
                camos = []
                for k, c in enumerate(w["Camos"]):
                    cde = wde["Camos"][k] if k < len(wde["Camos"]) else {}
                    name = {"en": c["CamoName"]}
                    if cde.get("CamoName") and cde["CamoName"] != c["CamoName"]:
                        name["de"] = cde["CamoName"]
                    camos.append({
                        "itemId": k, "name": name, "tier": k + 1,
                        "unlockLevel": c.get("UnlockLevel") or None,
                        "requirement": requirement(c["CategoryRequirement"], cde.get("CategoryRequirement"), c["AmountRequired"]),
                        "children": [], "imageURL": camo_image(c.get("CamoURL")),
                    })
                # Kills with each completionist camo on: open once the weapon has it
                for k, c in enumerate(w["MasteryChallenges"]):
                    cde = wde["MasteryChallenges"][k] if k < len(wde["MasteryChallenges"]) else {}
                    name = {"en": c["ChallengeName"].replace("Engima", "Enigma")}
                    if cde.get("ChallengeName"):
                        name["de"] = cde["ChallengeName"].replace("Engima", "Enigma")
                    req = requirement(c["CategoryRequirement"].replace("Engima", "Enigma").replace("Zircon Scale Enigma", "Zircon Scale"),
                                      (cde.get("CategoryRequirement") or "").replace("Engima", "Enigma") or None, c["AmountRequired"])
                    camos.append({
                        "itemId": 100 + k, "name": name, "tier": None, "unlockLevel": None, "requirement": req,
                        "children": [], "imageURL": None, "section": SECTIONS["mastery"], "extra": True,
                        "afterCompletionist": k,
                    })
                # Weapon XP past max level, one after another
                for k, c in enumerate(w.get("PrestigeChallenges") or []):
                    cde = (wde.get("PrestigeChallenges") or [{}] * 4)[k] if k < len(wde.get("PrestigeChallenges") or []) else {}
                    image = camo_image(f"{SITE}Images/Camos/MW3Tracker/{slug(c['ChallengeName'])}.png")
                    item = {
                        "itemId": 200 + k, "name": {"en": c["ChallengeName"]}, "tier": None,
                        "unlockLevel": w["MaxLevel"] if k == 0 else None,
                        "requirement": requirement("Earn {0} weapon XP after reaching max level.",
                                                   "Verdiene nach Erreichen der Höchststufe {0} Waffen-EP.", c["AmountRequired"]),
                        "children": [], "imageURL": image, "section": SECTIONS["prestige"], "extra": True,
                    }
                    if k > 0:
                        item["afterItem"] = 200 + k - 1
                    camos.append(item)
                weapon_camos.append({"weaponId": wid, "camos": camos})

                for k, c in enumerate(w["CompletionistCamos"][:3]):
                    cde = wde["CompletionistCamos"][k] if k < len(wde["CompletionistCamos"]) else {}
                    steps_by_weapon[k][str(wid)] = requirement(c["CategoryRequirement"], cde.get("CategoryRequirement"), c["AmountRequired"])
                    if step_names[k] is None:
                        name = {"en": c["CamoName"]}
                        if cde.get("CamoName") and cde["CamoName"] != c["CamoName"]:
                            name["de"] = cde["CamoName"]
                        step_names[k] = (name, c["CamoURL"].rsplit("/", 1)[-1])

        steps = []
        for k in range(3):
            name, image = step_names[k]
            step = {"unlock": track["unlocks"][k], "name": name,
                    "imageURL": f"{SITE}Images/Camos/MW3Tracker/{image}",
                    "colors": PALETTES.get(name["en"]) or colors(image, ["#D4AF37", "#F5E6A8", "#8A6A12"])}
            if track["unlocks"][k] == "category":
                step["neededByCategory"] = launch_by_class
            if track["unlocks"][k] == "mode":
                step["needed"] = track["needed"]
            # The most common challenge as the default, the rest per weapon
            counts = {}
            for r in steps_by_weapon[k].values():
                key = json.dumps(r, sort_keys=True)
                counts[key] = counts.get(key, 0) + 1
            default = json.loads(max(counts, key=counts.get))
            step["requirement"] = default
            own = {wid: r for wid, r in steps_by_weapon[k].items() if json.dumps(r, sort_keys=True) != json.dumps(default, sort_keys=True)}
            if own:
                step["byWeapon"] = own
            steps.append(step)
        final = {
            "name": {"en": track["final"], **({"de": track["final_de"]} if track["final_de"] != track["final"] else {})},
            "imageURL": f"{SITE}Images/Camos/MW3Tracker/{track['final_image']}",
            "colors": PALETTES.get(track["final"]) or colors(track["final_image"], ["#6E9BE8", "#C9DBFF", "#2B3F7A"]),
            "harmonicBreaksNeeded": track.get("final_needed") or track["needed"],
        }
        write(f"{game}_{mode}.json", {
            "version": VERSION, "mode": mode,
            "completionist": {"steps": steps, "final": final},
            "weaponCamos": weapon_camos, "objectives": [],
        })


def slug(name):
    return re.sub(r"[^a-z0-9]+", "-", name.lower().replace("'", "")).strip("-")


def write(name, data):
    (RES / name).write_text(json.dumps(data, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    print("wrote", name)


if __name__ == "__main__":
    main()
