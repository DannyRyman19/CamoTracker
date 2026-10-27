"""Builds MW4CamoTracker/Resources/hajin.json from the official Tac Map markers
(markers.json) plus our own write-ups and guide tables below."""
import os, json, re, sys

# python3 Tools/hajin/build_hajin.py [markers.json] [out.json]; defaults build
# the bundled guide from the saved Activision Tac Map markers
_HERE = os.path.dirname(os.path.abspath(__file__))
MARKERS = sys.argv[1] if len(sys.argv) > 1 else os.path.join(_HERE, "markers.json")
OUT = sys.argv[2] if len(sys.argv) > 2 else os.path.join(_HERE, "..", "..", "Resources", "hajin.json")
CROP = (750, 740, 2660)  # x0, y0, side in the 4096 px official map

CATS = [
    # id, name, SF Symbol, hex colour, source categories, shown by default
    ("area", "Areas", "map.fill", "#FFFFFF", ["poiLabel"], True),
    ("place", "Places", "mappin", "#C9D1D9", ["poiLabelSecondary"], True),
    ("fortress", "Fortresses", "building.columns.fill", "#E5484D", ["dmz_fortress_"], True),
    ("compound", "Compounds", "shield.lefthalf.filled", "#F76B15", ["dmz_compound"], True),
    ("lieutenant", "Lieutenant Towers", "binoculars.fill", "#FFC53D", ["dmz_lieutenantHunt"], True),
    ("uav", "UAV Towers", "antenna.radiowaves.left.and.right", "#3DD68C", ["dmz_uavTower"], True),
    ("key", "Key Rooms", "key.fill", "#FFD60A", [], True),
    ("cache", "Ammo & Armor Caches", "shippingbox.fill", "#70B8FF", ["dmz_ammoCache"], False),
    ("clinic", "Clinics", "cross.case.fill", "#FF8DCC", ["dmz_clinic"], False),
    ("fire", "Fire Stations", "flame.fill", "#FF977D", ["dmz_fireStation"], False),
    ("police", "Police Stations", "light.beacon.max.fill", "#9EB1FF", ["dmz_policeStation"], False),
    ("gas", "Gas Stations", "fuelpump.fill", "#B5B3AD", ["dmz_gasStation"], False),
    ("marine", "Marine Gas Stations", "sailboat.fill", "#7CE2FE", ["dmz_marineGasStation"], False),
    # community layers (codex_map.json); the source names are dmzcodex layers
    ("boss", "Boss Spawns", "exclamationmark.shield.fill", "#FF6369", [], True),
    ("exfil", "Exfils", "arrow.up.circle.fill", "#00E5A0", ["exfils"], True),
    ("spawn", "Player Spawns", "figure.walk", "#B197FC", ["player-spawns"], False),
    ("safe", "Safes", "lock.square.fill", "#D4A72C", ["safes"], False),
    ("hidden", "Hidden Caches", "archivebox.fill", "#C08532", ["hidden-caches"], False),
    ("supply", "Lost Supply Drops", "shippingbox.circle.fill", "#86EAD4", ["lost-supply-drops"], False),
    ("loot", "Loot Spots", "bag.fill", "#FFB224", ["loot-rockets", "loot-bags", "dead-corpses", "military-boxes",
                                                    "medicine-cabinets", "pc-cases", "dressers", "refrigerators"], False),
    ("deaddrop", "Dead Drops", "tray.and.arrow.down.fill", "#D19DFF", ["dead-drops"], False),
    ("sam", "SAM Sites", "scope", "#E54D2E", ["sam-sites"], False),
    ("radiation", "Radiation Zones", "exclamationmark.triangle.fill", "#BDEE63", ["radiation-zones"], False),
    ("decon", "Decontamination", "shower.fill", "#99D52A", ["decontamination-stations"], False),
    ("bounty", "Bounty Stations", "dollarsign.circle.fill", "#F1A10D", ["bounty-stations"], False),
    ("phone", "Dynamic Op Phones", "phone.fill", "#8DA4EF", ["dynamic-ops-phone"], False),
    ("vehicle", "Vehicle Sightings", "car.fill", "#D0B3FF", ["vehicle-sightings"], False),
    ("silo", "Silos", "cylinder.fill", "#8E8C99", ["silos"], False),
]
CAT_BLURB = {
    "fortress": "A Fortress: a heavily guarded stronghold with tougher enemies and better loot.",
    "compound": "An enemy Compound: a fortified military position inside a normal building, with a guard force and loot to match.",
    "lieutenant": "Climb a Lieutenant Hunt tower to reveal the nearest Lieutenant boss on your map.",
    "uav": "Activate a UAV Tower to see enemies on your minimap for a while.",
    "cache": "Ammo & Armor Cache: refill ammo and plates. It goes on cooldown after use.",
    "clinic": "Clinics hold medical loot.",
    "fire": "Fire Stations are the place for radiation gear and parachutes, which you need for the Nuclear Reactor and high drops.",
    "police": "Police Stations carry military gear, with a locked Armory inside.",
    "gas": "Gas Station: refuel vehicles here.",
    "marine": "Marine Gas Station: refuel boats here.",
    "key": "A locked room. Find its key in Hajin (keys can drop from Lieutenants) and bring it here; the key's description names its grid square.",
    "boss": "Where this boss is usually reported. Lieutenants aren't in every deployment: buy their intel on the Boss Board, or climb a Lieutenant Tower to find the nearest one.",
    "exfil": "A helicopter exfil site. Only some are active each deployment, so check your Tac Map. Call it in and hold the area until you can board.",
    "spawn": "Where squads start a deployment. Expect another squad nearby at the start.",
    "safe": "A safe to crack for cash and valuables. Opening safes is a DMZ Order objective too.",
    "hidden": "A hidden loot cache, tucked away off the main routes.",
    "supply": "A lost supply drop can land here. It isn't there every deployment; opening one completes the Side Op.",
    "loot": "Lootable spots players have reported: rockets, bags, bodies and containers worth checking.",
    "deaddrop": "A dead-drop container, where mission and Order items are handed in.",
    "sam": "Hack and defend a SAM site to turn its missiles on enemy aircraft, Deathstalker included.",
    "radiation": "Radiation reported here. Bring a gas mask and radiation gear, and check your Tac Map for the current spread.",
    "decon": "Decontaminates an Irradiated Container.",
    "bounty": "Check operator bounties or pay off your own here ($5,000).",
    "phone": "Pick up the field phone here to start a Dynamic Operation.",
    "vehicle": "Vehicles players have seen here. They move, get taken or get destroyed, so nothing is guaranteed.",
    "silo": "A missile silo.",
}
# Community-reported spots, from dmzcodex.com/map (fetch_codex_map.py)
CODEX = json.load(open(os.path.join(_HERE, "codex_map.json")))
THREAT = {  # level 1 low .. 5 extreme
    "Imjin Farmland": 1, "Cheongun Village": 1, "Mirae General Hospital": 1, "Songdo Wharf": 1,
    "Cheonwang Peak Array": 2, "Wolves Stadium": 2, "Hajin River Heights": 2, "NuriGO East": 2,
    "14th Political Prison": 3, "Heavenly Luck Casino": 3, "NuriGO West": 3, "Haneul Nuclear Reactor": 3,
    "The Grid": 4, "The Citadel": 4, "Chang-san Air Base": 4, "Admin Complex No. 2": 5,
}
# Our own short write-ups (facts from the official Tac Map and launch guides).
NOTES = {
    "14th Political Prison": "A walled prison on a cleared plateau in the North Korean wilderness. Watchtowers on every corner, barracks on the east side and the main gate to the south. The Citadel Fortress sits inside the yard.",
    "Chang-san Air Base": "A North Korean air base cut into a granite hillside, with an underground bunker bigger than the base above it. Cliffs guard the east side; the woods to the south are the usual way in. The outside is Critical, the bunker Extreme. Lieutenant Bale holds the Tank Depot in the bunker.",
    "Deadtown": "An empty farming town taken over by the army, with toxic rivers to the northwest and east and sewers running under the main buildings. Light resistance and street fights; the two Re-Education Centers hold the better targets.",
    "Imjin Farmland": "Flat rice fields, waterways and rail lines on the southwest border, with the Rice Mill Fortress in the middle. Long sightlines and little cover, so move carefully or use a vehicle.",
    "Cheongun Village": "A gambling town on the Hajin River with border crossings into Russia to the east and west. Expressway No. 1 runs along its south edge. The Heavenly Luck Casino Fortress dominates it.",
    "Haneul Nuclear Reactor": "A radioactive cloud hangs over the whole site and gets worse inside the reactor. Bring radiation gear and a gas mask; Radiation Blockers help. Fire Stations are where to find the gear.",
    "Mirae General Hospital": "Hajin's main hospital, next to a train station with The Grid and the mall to the east. Triage tents and barracks outside, close-quarters fights through the wards inside. Snipers like the woods of Mujin Pass to the south. Also a Fortress.",
    "NuriGo Mall": "A shopping district under the city's towers: police station, clinic, City Hall, a monorail stop and car parks. Three round structures in the main courtyard lead down to a huge dark underground mall (bring NVGs), which is the NuriGO Mall Fortress. Lieutenant Jang-ui camps here. West is High threat, East Medium.",
    "Cheonwang Peak Array": "Hajin's biggest telecom array on a flat summit, now an enemy base. Boulder trails to the west, gentler woods north toward Mujin Pass. The roof has a helipad and long views.",
    "The Grid": "The walled, razor-wired heart of Hajin City: barricaded streets, watchtowers and roaming patrols. Includes Donpyeong Gate, Hanex Bank, the DBN TV tower (the tallest building in Hajin) and the red-roofed Nenshin Tech Complex, which is Extreme threat.",
    "Songdo Wharf": "A quieter waterfront between the reactor and the river, with working train and monorail lines. The La Grande Vie tower is the tallest building nearby; a market, pier, lighthouse and Oamsik Turtle Island are on the coast.",
    "Wolves Stadium": "A ruined baseball stadium with a collapsed apartment tower beside it, an open-air theatre to the north and a police station and bank in the streets around. The edge with The Grid to the north is the dangerous part.",
    "Hajin River Heights": "Battered apartments and narrow shopping streets south of the stadium, rising toward the river's south fork. One apartment block is Compound Echo; Jinseo Park Towers and South Island's comms tower are further south.",
    "The Citadel": "A Y-shaped Fortress inside the prison yard: gantries, cell blocks and a furnace, with high-value targets throughout. Easy to get cut off, so learn the layout. Critical threat.",
    "Heavenly Luck Casino": "A multi-floor casino with an underground car park. No power, so the gambling halls are dark mazes: bring NVGs. High threat.",
    "Admin Complex No. 2": "The command Fortress at Chang-san Air Base. Extreme threat.",
    "Re-Education Center": "Two central buildings in Deadtown where enemy numbers build up. The town around them has a Clinic and a Gas Station at each end.",
    "Rice Mill": "A Fortress on high ground over the farmland. Use the warehouses as cover on the way in, watch for enemy vehicles in the open, and switch to close-range weapons inside.",
    "NuriGO Mall": "The underground mall beneath the NuriGO courtyard: a sprawling, unlit shopping level. Bring NVGs. The Warden's key opens a sealed door down here.",
    "Hanrim Village": "Lieutenant Gorani, a ghillie-suited sniper, hunts from the woods above this village.",
}

# Key rooms inside a known building, pinned beside that building's marker
# (community-reported 2026-10-20, dmzhub.gg). Rooms we can't place stay
# in the Keys table only.
KEY_ROOMS = [
    ("k-vault-armory", "Vault Armory", "Heavenly Luck Casino", "dmz_fortress_heavenlyLuckCasino", "Epic key, grid F4. Opens the small armory in the casino's underground car park."),
    ("k-imjin-mill", "Imjin Mill Foreman's Office", "Rice Mill", "dmz_fortress_riceMill", "Rare key, grid D8. Opens the foreman's office on the first floor of the Rice Mill."),
    ("k-citadel-south", "The Citadel South Wing", "The Citadel", "dmz_fortress_theCitadel", "Uncommon key. Opens the South Wing of the Citadel inside the prison."),
    ("k-reeducation-annex", "Re-Education Center Annex", "Re-Education Center", "dmz_fortress_reEducationCenter", "Epic key, grid B7. Opens the annex on the ground floor of the Re-Education Center in Deadtown."),
    ("k-iskra", "Iskra's Control Room", "Cheonwang Peak Array", "poiLabel", "Legendary key, grid F7. Opens the control room on the upper floor of the broadcast building."),
    ("k-counting-room", "Counting Room Vault", "Heavenly Luck Casino", "dmz_fortress_heavenlyLuckCasino", "Epic key, grid F4. Opens the counting-room vault on the casino's main floor; players report a backpack inside.", (-34, -26)),
    ("k-reactor-drc", "Reactor DRC Locker", "Haneul Nuclear Reactor", "poiLabel", "Ultra key, grid H4. Opens the DRC Weapons Locker in Reactor 02's irradiated pool. Bring radiation gear.", (30, 30)),
    ("k-exec-auction", "Executive Arms Auction", "DBN Headquarters", "poiLabelSecondary", "Epic key, grid G6. Opens the arms auction room at the top of DBN Headquarters, the tallest building in The Grid.", (30, -26)),
    ("k-mirae-electrical", "Mirae Electrical Room", "Mirae General Hospital", "dmz_fortress_miraeGeneralHospital", "Rare key, grid F5. Opens the electrical room in the hospital's northwestern basement car park.", (-34, -26)),
    ("k-reactor-02", "Reactor 02 Control Room", "Haneul Nuclear Reactor", "poiLabel", "Rare key, grid H4. Opens the control room inside the Reactor 02 building.", (-34, 30)),
    ("k-doctor-office", "The Doctor's Command Office", "Mirae General Hospital", "dmz_fortress_miraeGeneralHospital", "Legendary key, grid F5. Opens a converted conference room in the hospital's upper-floor offices, behind wooden double doors.", (34, -26)),
    ("k-gas-electrical", "Gas Station Electrical Room", "Construction Zone", "poiLabelSecondary", "Rare key, grid H6. Opens the gas station's electrical room: a grey metal door beside a noticeboard.", (30, 26)),
    ("k-shopping-drc", "Shopping DRC Locker", "NuriGO Mall", "dmz_fortress_nurigoMall", "Ultra key, grid H5. Reported to open the DRC Locker in the DRC Labs under the mall, in the secured lower car park.", (34, 26)),
    ("k-mechanics-shack", "Mechanic's Shack", "Cheongun Village", "poiLabel", "Rare key, grid F5. Opens the standalone shack south of the clinic.", (-30, 30)),
    ("k-militia-depot", "Militia Arms Depot", "Hajin River Heights", "poiLabel", "Rare key, grid G7. Opens the lower-floor armory in Gangbyeon Apartment B.", (30, 30)),
    ("k-airbase-drc", "Air Base DRC Weapons Locker", "Admin Complex No. 2", "dmz_fortress_adminComplexNo2", "Ultra key, grid B6. Opens the DRC Weapons Locker in the secure armory deep in the Chang-san Air Base bunker."),
]

def cat_of(c):
    for cid, _, _, _, srcs, _ in CATS:
        if any(c == s or (s.endswith("_") and c.startswith(s)) for s in srcs): return cid
    raise SystemExit("unknown category " + c)

feats = json.load(open(MARKERS))["features"]
markers, counts = [], {}
for f in feats:
    p = f["properties"]; x, y = f["geometry"]["coordinates"]
    cid = cat_of(p["category"]); counts[cid] = counts.get(cid, 0) + 1
    name = p["name"].strip()
    if cid == "place" and name == "Russian Border Crossing":
        continue  # the East and West entries already cover it
    m = {"id": "m" + p["mapId"], "cat": cid, "name": name,
         "x": round((x - CROP[0]) / CROP[2], 4), "y": round((y - CROP[1]) / CROP[2], 4)}
    t = THREAT.get(name) or THREAT.get(name.replace("NuriGo", "NuriGO"))
    if t and cid in ("area", "fortress"): m["threat"] = t
    note = NOTES.get(name)
    if cid == "fortress" and name == "Mirae General Hospital": note = "The hospital itself is a Fortress: expect close-quarters fights through the wards and lobby."
    if note: m["note"] = note
    markers.append(m)
for entry in KEY_ROOMS:
    kid, kname, near, src, knote = entry[:5]
    dx, dy = entry[5] if len(entry) > 5 else (34, -26)
    f = next(f for f in feats if f["properties"]["name"] == near and f["properties"]["category"] == src)
    x, y = f["geometry"]["coordinates"]
    markers.append({"id": kid, "cat": "key", "name": kname,
                    "x": round((x + dx - CROP[0]) / CROP[2], 4), "y": round((y + dy - CROP[1]) / CROP[2], 4), "note": knote})

# Key doors players have pinned (dmzcodex.com/map): a room we already pin
# moves onto its door, the rest become key rooms of their own
DOOR_ALIASES = {"Rail Depot Storage": "Traindepot Storage Room", "Shopping DRC Weapons Locker": "Shopping DRC Locker",
                "Black Market Weapons Locker": "Blackmarket Weapons Locker", "Key Room": "Locked room"}
def door_name(label):
    name = re.sub(r"(,| -| ·) [A-I]\d(, [A-I]\d)?$", "", label.replace("’", "'"))
    name = re.sub(r" · .*$| (search )?area$", "", name)
    return DOOR_ALIASES.get(name, name)
UNKNOWN_ROOMS = {"Locked room", "Fire Station Storage", "Field Depot", "Mirae General Hospital Ward", "Silo Control Room",
                 "Underground Equipment Storage", "Heavenly Luck Casino Ground Floor", "Rice Mill Bunker"}
by_key_name = {m["name"]: m for m in markers if m["cat"] == "key"}
for p in CODEX["pins"]:
    if p["layer"] not in ("key-rooms", "keypad-doors"): continue
    name, grid = door_name(p["label"]), re.search(r"[A-I]\d", p["label"][-6:])
    rough = " area" in p["label"] or "reported location" in p["label"]
    if p["layer"] == "keypad-doors":
        markers.append({"id": "k-" + p["id"], "cat": "key", "name": "Eundeok Restaurant keypad door", "x": p["x"], "y": p["y"],
                        "note": "A keypad-locked door players have reported around the Eundeok Restaurant, grid B7. The code isn't known yet."})
        continue
    if name in by_key_name and not by_key_name[name].get("moved"):
        m = by_key_name[name]; m["x"], m["y"], m["moved"] = p["x"], p["y"], True
        continue
    at = f", grid {grid.group(0)}." if grid else "."
    note = "A locked room players have reported" + at + " Which key opens it isn't known yet." if name in UNKNOWN_ROOMS else "The door its key opens" + at
    if rough: note += " Roughly here: the exact door isn't pinned yet."
    base = mid = "k-" + re.sub(r"[^a-z0-9]+", "-", name.lower().replace("'", "")).strip("-")
    n = 1
    while any(m["id"] == mid for m in markers): n += 1; mid = f"{base}-{n}"
    markers.append({"id": mid, "cat": "key", "name": name, "x": p["x"], "y": p["y"], "note": note})
    by_key_name.setdefault(name, markers[-1])["moved"] = True
for m in markers: m.pop("moved", None)

# Community layers: exfils, spawns, loot spots... one marker per pin
CODEX_CATS = {"exfil", "spawn", "safe", "hidden", "supply", "loot", "deaddrop", "sam", "radiation", "decon", "bounty", "phone", "vehicle", "silo"}
LAYER_CAT = {src: c[0] for c in CATS if c[0] in CODEX_CATS for src in c[4]}
for p in CODEX["pins"]:
    cid = LAYER_CAT.get(p["layer"])
    if not cid: continue
    name = re.sub(r" · ([A-I]\d)(, [A-I]\d)?$", r", \1\2", p["label"]).replace("’", "'")
    markers.append({"id": "c-" + p["id"], "cat": cid, "name": name, "x": p["x"], "y": p["y"]})
    counts[cid] = counts.get(cid, 0) + 1

# Where each boss is usually reported (dmzcodex.com/bosses, the official
# blog and the guide's boss notes): next to that place's marker
BOSS_SPAWNS = [
    ("Bale", "Admin Complex No. 2", "Lieutenant. Holds the Tank Depot in the Chang-san Air Base bunker (the Paid Intel Side Op). Some players report him at the Re-Education Center in Deadtown instead."),
    ("Gorani", "Hanrim Village", "Lieutenant. A ghillie-suited sniper with an escort in the woods above Hanrim Village; also reported around Mujin Pass. Watch for decoys."),
    ("Jang-ui", "NuriGO Mall", "Lieutenant. Camps in the NuriGO Mall shopping district; also reported in the upper server halls of the Netshin Tech Complex."),
    ("The Doctor", "Mirae General Hospital", "Lieutenant. Mirae General Hospital. Sometimes drops The Doctor's Command Office key."),
    ("Jin-Tae", "Heavenly Luck Casino", "Lieutenant. The casino gaming floor and the staff offices behind it."),
    ("Scavenger", "Cheongun Village", "Lieutenant. Reported around Cheongun Village, including a car park on South Island, and in an Imjin Farmland warehouse."),
    ("Iskra", "Cheonwang Peak Array", "Lieutenant. Up the stairs toward the Data Farm in the broadcast building. Her Control Room is upstairs too."),
    ("Roze", "DBN Headquarters", "Lieutenant. Reported on the DBN Headquarters rooftop and in a dark parking garage, with a scoped rifle."),
    ("The Chemist", "Haneul Nuclear Reactor", "Lieutenant. A blue-and-white warehouse beside the reactor's tanks; the yellow-suited Chemist waits near the rear bay. Bring radiation gear."),
    ("The Warden", "14th Political Prison", "Lieutenant. The prison mess hall, carrying a riot shield. His key opens a sealed door under NuriGO Mall."),
    ("Colossus", "The Citadel", "Commander. Roams and shows on your Tac Map: reported around the Citadel, the North Korean wilderness and the Air Base bunker."),
    ("Deathstalker", "DBN Headquarters", "Commander. A huge drone that roams over The Grid and NuriGO Mall and shows on your Tac Map. A captured SAM site can shoot it down."),
]
_anchor = {}
for m in markers:
    if m["cat"] in ("area", "place", "fortress"): _anchor.setdefault(m["name"], m)
_used = {}
for boss, near, note in BOSS_SPAWNS:
    a = _anchor[near]; n = _used[near] = _used.get(near, 0) + 1
    markers.append({"id": "b-" + re.sub(r"[^a-z0-9]+", "-", boss.lower()).strip("-"), "cat": "boss", "name": boss,
                    "x": round(a["x"] + 0.014 * n, 4), "y": round(a["y"] - 0.012, 4), "note": note})

def rows(items): return [dict(zip(("title", "value", "subtitle"), r)) if isinstance(r, tuple) else r for r in items]

LEVELS = [
 (2, "3D Printer station; recipes: 1-Plate Armor Vest, 2-Plate Armor Vest, Bandage, Medkit, Small Backpack, Medium Backpack"),
 (3, "Sedative Inhaler recipe"), (4, "Reece operator skin; Tacticals print upgrade; Smoke Grenade and Concussion Grenade recipes"),
 (5, "Vendor station"), (6, "Rigid Synthetics x2; Basic Armor Kit"), (7, "Lethals print upgrade; Frag Grenade and Throwing Knife recipes"),
 (8, "Restock Kit"), (9, "Coffey operator skin; Snapshot Grenade recipe"), (10, "Gunsmith station"),
 (11, "Reactive Metals x2; Basic Triage Kit"), (12, "Field Upgrades print upgrade; Ammo Box and Spotter Scope recipes"),
 (13, "UAV (Epic Fire Support)"), (14, "Armor Box recipe"), (15, "Simone operator skin; +1 Operator slot"),
 (16, "Explosives Equipment Kit"), (17, "Shock Stick recipe"), (18, "Vendor upgrade: more items for sale"),
 (19, "Hector operator skin; Recon Equipment Kit"), (20, "Dog Tag Case station"), (21, "Basic Armor Kit"),
 (22, "+18 Stash slots"), (23, "Semtex recipe"), (24, "Restock Kit"), (25, "5% Gunsmith discount"),
 (26, "Gas Mask recipe"), (27, "Triage Kit (Epic)"), (28, "Fire Support print upgrade; Care Package recipe"),
 (29, "Detonators x2"), (30, "10% Bounty payout"), (31, "UAV recipe"), (32, "Vendor upgrade"), (33, "Electronics x2"),
 (34, "Large Backpack (Epic)"), (35, "+6 Weapon Stash slots"), (36, "Molotov Cocktail recipe"), (37, "3-Plate Armor Vest (Epic)"),
 (38, "Control Unit x2"), (39, "Biomaterials x2"), (40, "Station upgrade (players report a 25% Bounty payout)"), (41, "Thermite recipe"), (42, "Trap Equipment Kit"),
 (43, "Structural Alloy x2 (Rare)"), (44, "CPU x2 (Rare)"), (45, "+18 Stash slots"), (46, "Recon Equipment Kit"),
 (47, "Nitro Compounds x2 (Rare)"), (48, "Self-Revive Kit recipe"), (49, "Binding Catalyst x2 (Rare)"), (50, "50% Bounty payout"),
 (51, "Stock Rod x2 (Rare)"), (52, "Inflatable Decoy recipe"), (53, "High-Tenacity Fibers x2 (Rare)"), (54, "Epic consumable"),
 (55, "Disposable Parachute recipe"), (56, "Printed Circuit Board x2 (Rare)"), (57, "Nylon Cloth x2 (Rare)"),
 (58, "Care Package (Rare Fire Support)"), (59, "Combat Drone (Epic Fire Support)"), (60, "+6 Weapon Stash slots"),
 (61, "Medium Weapon Backpack (Epic)"), (62, "Door Breacher Charge (Ultra consumable)"), (63, "2-Plate Helmet Armor Vest (Epic)"),
 (64, "Revive Pistol (Field Upgrade)"), (65, "UAV (Epic Fire Support)"), (66, "Crossfire (Fire Support)"), (67, "Defibrillator"),
 (68, "Durable Gas Mask (Epic)"), (69, "Parachute (Legendary)"), (70, "+18 Stash slots; 100% Bounty payout; Advanced SERE Kit (Legendary)"),
]
NC = "Cost not confirmed yet"
RECIPES = [
 ("Bandage", "Lv 2", "15 Synthetics, 15 Chemicals"), ("Medkit", "Lv 2", "30 Chemicals, 1 Binding Catalyst, 5 Biomaterials"),
 ("1-Plate Armor Vest", "Lv 2", "25 Synthetics, 25 Metals"), ("2-Plate Armor Vest", "Lv 2", "50 Synthetics, 5 Reactive Metals"),
 ("Small Backpack", "Lv 2", "25 Synthetics, 25 Metals"), ("Medium Backpack", "Lv 2", "50 Synthetics, 5 Rigid Synthetics. Adds Secure Slots"),
 ("Energy Drink", "Any", "10 Chemicals, 10 Metals. Unlimited stamina for a while"),
 ("Door Breacher Charge", "Any", "1 Stock Rod"), ("Bomb Glider", "Any", "1 Stock Rod"),
 ("Pain Killers", None, "15 Electronics, 15 Chemicals"), ("Radiation Blockers", None, "15 Electronics, 15 Chemicals"),
 ("Small Secure Backpack", None, "50 Metals, 10 Rigid Synthetics, 3 Structural Alloy. Three Secure Slots"),
 ("Secure Scavenger Backpack", None, "2 Military Composites, 4 Nylon Laminate, 10 Reactive Metals"),
 ("Tempered Armor Vest", None, "2 Military Composites, 4 Ballistic Fabric, 10 Rigid Synthetics"),
 ("Recon Drone", "Order", "Reward from the Counterfeit DMZ Order. " + NC),
 ("Sedative Inhaler", "Lv 3", "15 Synthetics, 15 Chemicals"), ("Smoke Grenade", "Lv 4", NC), ("Concussion Grenade", "Lv 4", NC),
 ("Frag Grenade", "Lv 7", NC), ("Throwing Knife", "Lv 7", NC), ("Snapshot Grenade", "Lv 9", NC),
 ("Ammo Box", "Lv 12", NC), ("Spotter Scope", "Lv 12", NC), ("Armor Box", "Lv 14", "1 Reactive Metals (rest not confirmed)"),
 ("Shock Stick", "Lv 17", NC), ("Semtex", "Lv 23", NC), ("Gas Mask", "Lv 26", NC), ("Care Package", "Lv 28", NC),
 ("UAV", "Lv 31", NC), ("Molotov Cocktail", "Lv 36", NC), ("Thermite", "Lv 41", NC), ("Self-Revive Kit", "Lv 48", "5 Biomaterials, 3 Binding Catalyst"),
 ("Inflatable Decoy", "Lv 52", NC), ("Disposable Parachute", "Lv 55", "1 Rigid Synthetics (rest not confirmed)"),
]
guide = [
 {"id": "levels", "title": "Level unlocks", "symbol": "chart.bar.fill",
  "intro": "What each DMZ level gives you, up to level 70.",
  "rows": [{"title": f"Level {l}", "subtitle": u, "level": l} for l, u in LEVELS]},
 {"id": "recipes", "title": "Crafting recipes", "symbol": "printer.fill",
  "intro": "Made at the 3D Printer in your FOB before you deploy. Recipes unlock by level, from DMZ Orders, or by extracting with a looted recipe, which adds it to the printer and pays $5,000. More costs get added as they're confirmed.",
  "rows": rows(RECIPES)},
 {"id": "resources", "title": "Resources & ingredients", "symbol": "cube.fill",
  "intro": "Loot breaks down by itself into four resources, which take no backpack space. Ingredients stay whole, take a slot and must be extracted.",
  "rows": rows([
   ("Synthetics", "Resource", None), ("Electronics", "Resource", None), ("Chemicals", "Resource", None), ("Metals", "Resource", None),
   ("Biomaterials", "Uncommon", "Medkit, Self-Revive Kit. Level 39 gives 2"), ("Rigid Synthetics", "Uncommon", "Medium Backpack, Disposable Parachute, Small Secure Backpack, Tempered Armor Vest. Sells for $200. Level 6 gives 2"),
   ("Reactive Metals", "Uncommon", "Industrial areas and toolboxes. 2-Plate Armor Vest, Armor Box, Secure Scavenger Backpack. Sells for $400. Level 11 gives 2"), ("Binding Catalyst", "Rare", "Medkit, Self-Revive Kit. Level 49 gives 2"),
   ("Stock Rod", "Rare", "Door Breacher Charge, Bomb Glider. Sells for $500. Level 51 gives 2"), ("Detonators", None, "Level 29 gives 2"),
   ("Control Unit", "Uncommon", "Level 38 gives 2"), ("Structural Alloy", "Rare", "Small Secure Backpack. Level 43 gives 2"), ("CPU", "Rare", "Level 44 gives 2"),
   ("Nitro Compounds", "Rare", "Level 47 gives 2"), ("High-Tenacity Fibers", "Rare", "Level 53 gives 2"),
   ("Printed Circuit Board", "Rare", "Level 56 gives 2"), ("Nylon Cloth", "Rare", "Level 57 gives 2"),
   ("Electronic Sensors", "Uncommon", "Stash upgrade (+18 slots). Sells for $800"),
   ("Ballistic Flight Logs", "Uncommon", "Sells for $1,000"),
   ("Nylon Laminate", "Epic", "Military holdings and upmarket civilian buildings. Secure Scavenger Backpack"),
   ("Ballistic Fabric", "Epic", "Tempered Armor Vest"), ("Power Regulator", "Epic", None),
   ("Military Composites", "Legendary", "Secure Scavenger Backpack, Tempered Armor Vest"),
   ("Commanders", None, "Kill one and extract to get valuable ingredients"),
  ])},
 {"id": "stations", "title": "FOB stations", "symbol": "house.fill",
  "rows": rows([
   ("3D Printer", "Lv 2", "Crafts gear and upgrades your FOB: Bank and Stash size, MIA rescue discounts, rarer ingredients. Print upgrades: Tacticals (4), Lethals (7), Field Upgrades (12), Fire Support (28)"),
   ("Vendor", "Lv 5", "Sells weapons and items for DMZ Cash. Stock rotates daily; upgrades at 18 and 32 add more"),
   ("Gunsmith", "Lv 10", "Extract a weapon's Manual once, then buy that gun here whenever you like. Base M4 about $5,000, assault rifles $4,750, SMGs $2,850, each attachment slot $1,000. 5% off from level 25"),
   ("Dog Tag Case", "Lv 20", "Stores and shows off the dog tags you've extracted"),
   ("Boss Board", "2nd Order", "Lieutenant intel costs DMZ Cash and lasts one deployment. Commander intel is free"),
   ("Stash", None, "Starts at 40 items and 12 weapons, shared by your operators. +18 at levels 22, 45 and 70; +6 weapons at 35 and 60"),
   ("Bank", None, "Holds your DMZ Cash; cash you extract goes here. Has a cap that FOB upgrades raise"),
   ("Firing Range", None, "Targets from under 10 m to over 100 m"),
  ])},
 {"id": "bosses", "title": "Bosses", "symbol": "scope",
  "intro": "Lieutenants drop lots of cash, a Dog Tag (picking it up shows your position), sometimes a Key and rarely their weapon. Commanders roam the map; the first kill of each pays cash, and extracting after a kill gives ingredients.",
  "rows": rows([
   ("Gorani", "Lieutenant", "Ghillie-suited sniper in the woods above Hanrim Village. Pays $10,000"),
   ("Bale", "Lieutenant", "Tank Depot in the Chang-san Air Base bunker. Bale's Dog Tag (Legendary) marks you for nearby squads until you extract"),
   ("Jang-ui", "Lieutenant", "Camp in the NuriGO Mall shopping district"),
   ("The Doctor", "Lieutenant", "Drops The Doctor's Dog Tag (Legendary), and sometimes The Doctor's Command Office key. Pays $10,000"),
   ("Jin-Tae", "Lieutenant", "The target in Operation Critical Extraction. Drops Jin-Tae's Dog Tag (Legendary) and Radiation Blockers. Pays $10,000"),
   ("Scavenger", "Lieutenant", "Drops the Scavenger's Dog Tag (Legendary). Pays $10,000"),
   ("Iskra", "Lieutenant", "Her Control Room is in the broadcast building at Cheonwang Peak Array. Drops Iskra's Dog Tag (Legendary). Pays $10,000"),
   ("Roze", "Lieutenant", "Drops Roze's Dog Tag (Legendary)"),
   ("The Chemist", "Lieutenant", "Based around the Haneul Nuclear Reactor. The Chemist's Secure Armory key opens a bunker by the reactor boathouse. Pays $10,000"),
   ("The Warden", "Lieutenant", "Northern hills. Drops a key to a sealed door under NuriGO Mall"),
   ("Colossus", "Commander", "A seven-foot armored soldier with a minigun"),
   ("Deathstalker", "Commander", "A huge autonomous drone with twin machine-gun turrets. A captured SAM site can shoot it"),
   ("NK Battle Tank", "Commander", "Roams Hajin"),
  ])},
 {"id": "keys", "title": "Keys", "symbol": "key.fill",
  "intro": "Keys open locked loot rooms; Lieutenants can drop them. Each key's description names its Tac Map grid square. Locations reported by players, more as they're found.",
  "rows": rows([
   ("Counting Room Vault", "F4", "Epic. The counting-room vault on the Heavenly Luck Casino's main floor, Cheongun Village. Players report a backpack inside"),
   ("Reactor DRC Locker", "H4", "Ultra. The DRC Weapons Locker in Reactor 02's irradiated pool, Haneul Nuclear Reactor. Bring radiation gear. Reported as a reward from Operation Fallen Ember"),
   ("Executive Arms Auction", "G6", "Epic. The arms auction room at the top of DBN Headquarters, The Grid"),
   ("Mirae Electrical Room", "F5", "Rare. The electrical room in the northwestern basement car park, Mirae General Hospital"),
   ("Police Weapon Depository", "G7", "Epic. The auxiliary police armory north of the police station, Wolves Stadium"),
   ("Shop Records Room", "F7", "Rare. The records room above the Goh24 supermarket south of the clinic, Wolves Stadium"),
   ("Reactor 02 Control Room", "H4", "Rare. The control room inside the Reactor 02 building, Haneul Nuclear Reactor"),
   ("The Doctor's Command Office", "F5", "Legendary. A converted conference room in the upper-floor offices of Mirae General Hospital, behind wooden double doors. The Doctor sometimes drops it"),
   ("Gun Store Weapons Locker", None, "Rare. Opens the three locked cabinets in a gun store basement. Comes in the Explosives and Trap Equipment Kits (DMZ levels 16 and 42)"),
   ("Gas Station Electrical Room", "H6", "Rare. The gas station's electrical room at the Construction Zone, a grey metal door beside a noticeboard"),
   ("Shopping DRC Locker", "H5", "Ultra. Reported to open the DRC Locker in the DRC Labs under NuriGO Mall, in the secured lower car park"),
   ("Mechanic's Shack", "F5", "Rare. The standalone shack south of the clinic, Cheongun Village"),
   ("Militia Arms Depot", "G7", "Rare. The lower-floor armory in Gangbyeon Apartment B, Hajin River Heights. Players have found it in a duffel bag in the Citadel East Wing"),
   ("Blackmarket Weapons Locker", None, "Rare. Comes in DMZ level reward kits. Where its door is isn't known yet"),
   ("Underground Propaganda Store Room", None, "Rare. Where its door is isn't known yet"),
   ("Air Base DRC Weapons Locker", "B6", "Ultra. The DRC Weapons Locker in the secure armory deep in the Chang-san Air Base bunker"),
   ("Vault Armory", "F4", "Epic. The small armory in the Heavenly Luck Casino's underground car park, Cheongun Village"),
   ("Imjin Mill Foreman's Office", "D8", "Rare. First floor of the Rice Mill, Imjin Farmland"),
   ("Haksan School Armory", "B7", "Rare. Makeshift armory upstairs in the school northeast of the Re-Education Center, Deadtown"),
   ("Re-Education Center Annex", "B7", "Epic. The annex on the Re-Education Center's ground floor, Deadtown"),
   ("Iskra's Control Room", "F7", "Legendary. Upper floor of the broadcast building, Cheonwang Peak Array"),
   ("Netshin IT Room", "G6", "Epic. The high-security server room on the upper floors of the Netshin Tech Complex, The Grid"),
   ("Traindepot Storage Room", "E5", "Rare. Basement of the train station by the fire station, Cheongun Village"),
   ("The Chemist's Secure Armory", "I4", "Legendary. A secured bunker by the Haneul Nuclear Reactor boathouse"),
   ("The Citadel South Wing", None, "Uncommon. The Citadel's South Wing, 14th Political Prison"),
   ("Bank Branch Vault Access", None, "Rare. The cash vaults of South Korean bank branches"),
   ("Hanex Guard Station", "G6", "Epic. The guard station on an upper floor near the Hanex Bank vault, The Grid"),
   ("Lucera Suite 703 Bedroom", "H7", "Epic. The upper-floor executive suite in Hotel Lucera, The Grid"),
   ("Jang-ui's Converted Power Room", "H6", "Legendary. The enclosed generator room on the bottom floor of NuriGO Mall, next to the Robo Dog agility course"),
   ("Old Barber Shop", "I7", "Rare. The barber shop next to the crab shack on the south side of Songdo Wharf"),
   ("Hazard Storehouse", "I7", "Rare. The material storage warehouse south of the cooling towers, Haneul Nuclear Reactor"),
   ("Coin Mining Den", "G6", "Rare. The e-coin mining lab in an upper apartment east of the westernmost gas station, NuriGO West: a grey office door beside a red fire alarm. Reported as a reward from Operation Shopping Hacks"),
   ("Supreme Leader's Bunker Access Card", "B6", "Legendary. The Supreme Leader's Bunker deep in the Chang-san Air Base bunker; Bale cloned its credentials onto a new card. Reported as a reward from Operation Iron Citadel"),
   ("Roze's High-Rise Armory", "G6", "Legendary. The upstairs offices of the Netshin Tech Complex, The Grid. Reported as a reward from Operation Grid Assault"),
   ("Hoesik Supply Room", None, "Epic. Reported to open a key-marked building around the rice mill, Imjin Farmland. The exact door isn't known yet"),
   ("Mill Explosives Lab", None, "Uncommon. The Explosives Lab in the Rice Mill, Imjin Farmland. Its grid square isn't on the key yet"),
   ("Prison Encampment Storage", "C3", "Rare. The ordnance storage on the southeast side of the prison camp, 14th Political Prison"),
   ("Utility Maintenance Storage", "H4", "Rare. The maintenance room under the transformer area next to Reactor 01, Haneul Nuclear Reactor"),
   ("Gangbyeon Apartment B", "G7", "Uncommon. Opens Gangbyeon Apartment B in the Hajin River Heights compound"),
   ("Police Station Armory", None, "Uncommon. Reported to open any Police Station armory: West Cheongun Village, north NuriGO Mall, Revolution Dam and south Pyonghwa Village. Whether it is the same key as the Police Station Key isn't known yet"),
   ("Police Station Key", None, "Comes in the Recon Equipment Kit (DMZ level 19). Where its door is isn't known yet"),
   ("Air Base Access Card - Multi Use", "B5", "Epic. Opens doors around Chang-san Air Base, and can be used more than once"),
   ("Weapons Mod Workshop", "B5", "Rare. The weapons workshop on the second floor of the military repair garage, directly west of the clinic, Chang-san Air Base"),
   ("Commandant Office", "B5", "Epic. The commandant's office on the second floor of Admin Complex No. 2, Chang-san Air Base"),
   # dmzcodex.com/keys (2026-10-27)
   ("Haejeok Radio Station", "D6", "Rare. The broadcast room in the white transmitter building under Imjin Suburb's red radio mast"),
   ("Hanwoori Art Records Room", None, "Rare. The ground-floor records room of the Hanwoori Design Complex, The Grid"),
   ("Jin-Tae's Private Lounge", "F4", "The upper-floor lounge of the Heavenly Luck Casino: take the lobby elevator to the penthouse. Reported as a drop from Jin-Tae"),
   ("Gorani's Scout Overlook", "D8", "The Scout Overlook, reached from the Rice Mill roof, Imjin Farmland. Gorani sometimes drops it"),
   ("The Citadel Main Control Room", None, "Uncommon. The Citadel's main control room. Players find it after the East Wing's four-core K9 terminal sequence"),
   ("The Citadel Secondary Control Room", "B3", "Uncommon. The Citadel's secondary control room and its security station. Players find it after the South Wing controls"),
   ("South Block Armory", None, "Legendary. An armory in the Citadel. Players have found the key on the main control room's counter"),
  ])},
 {"id": "valuables", "title": "Valuables", "symbol": "diamond.fill",
  "intro": "Gem-icon loot: sell it for DMZ Cash or put it toward FOB upgrades.",
  "rows": rows([
   ("Gold Bar", "$25,000", "Ultra. Also a reward from Silent Ledger"), ("Gold Skull", "$25,000", "Ultra"),
   ("Sanctioned Assassination List", "$10,000", "Legendary"), ("Foreign Intelligence Targets", "$5,000", "Epic. Five are needed for MIA Recovery Discount III"),
   ("Cash Bag", "$1,500", "Rare. Carried out of the casino vault in Operation Silent Ledger, which is reported to hold twelve optional bags worth about $1,500 each"),
   ("Cipher Code Ledger", "$5,000", "Epic"), ("W.M.D Manifest", "$5,000", "Epic"),
   ("Parachute", "$5,000", "Legendary"), ("Revive Pistol", "$2,500", "Legendary"), ("Fulton Drop Marker", "$2,500", "Ultra"),
   ("Encrypted Archive", "$2,000", "Rare. Found in the Heavenly Luck Casino storage and counting rooms, and the Mirae Electrical Room"), ("Medkit", "$2,000", "Epic"), ("Keys", "$100", "Every key sells for $100"),
  ])},
 {"id": "threat", "title": "Threat levels", "symbol": "exclamationmark.triangle.fill",
  "rows": rows([
   ("Low", None, "Imjin Farmland, Cheongun Village, Mirae General Hospital, Songdo Wharf"),
   ("Medium", None, "Cheonwang Peak Array, Wolves Stadium, Hajin River Heights, NuriGO East"),
   ("High", None, "14th Political Prison, Heavenly Luck Casino, NuriGO West, Haneul Nuclear Reactor"),
   ("Critical", None, "The Grid, The Citadel, Chang-san Air Base (outside)"),
   ("Extreme", None, "Chang-san Air Base bunker, Nenshin Tech Complex"),
  ])},
 {"id": "infil", "title": "Infil", "symbol": "airplane",
  "rows": rows([
   ("On foot", "Free", "Random spot"), ("Polaris Dagor A1", "$5,000", "Random spot"),
   ("LTV", "$25,000", "Random spot. Unlocked by Operation Iron Citadel"),
   ("Helicopter", "$50,000", "Flown in from the FOB. Unlocked by Operation Grid Assault"),
   ("Cargo Plane", "$100,000", "Pick your exact drop point. Unlocked by Operation Fallen Ember"),
  ])},
 {"id": "ops", "title": "Missions & payouts", "symbol": "target",
  "rows": rows([
   ("Dynamic Operations", "$10-20K", "Paid into your Bank per op, plus a Supply Drop that improves with each success"),
   ("Critical Extraction", "$25,000", "Mirae General Hospital. Get General Kang out alive. Also rewards a Defibrillator"),
   ("Silent Ledger", "$25,000", "Cheongun Village. Also a Gold Bar and a Polaris Dagor"),
   ("Shopping Hacks", "$25,000", "NuriGO Mall. Also Night Vision Goggles"),
   ("Robbery", None, "Extract $5,000 in cash value"),
   ("Story Missions", "Weekly", "Finish a random one three times a week for the weekly rewards"),
   ("Reduce Bounty", "$5,000", "At a Bounty Station. Four kills make you Wanted"),
  ])},
 {"id": "rules", "title": "Exfil & death", "symbol": "figure.run",
  "rows": rows([
   ("Exfil", None, "Green smoke marks the helicopter exfils. Call it in and hold the area until it lands. A Fulton balloon or a Flare also gets you out; flares are loud and visible from far away"),
   ("Only extracted loot counts", None, "Anything outside your Secure Slots is lost if you don't make it out. Dog tags and bosses' guns only count once extracted"),
   ("Recipes and Manuals", "$5,000", "Used up when you extract with them: the recipe goes to your printer, the Manual to the Gunsmith"),
   ("Dying", None, "Your gear stays in Hajin. A squadmate can rescue you as MIA; the rescue costs more the more Traits you have. Traits are kept"),
   ("Failed exfil", None, "You still get the XP"),
   ("Radiation", None, "The Reactor needs radiation gear and a gas mask. Radiation Blockers help in irradiated areas"),
  ])},
 {"id": "prestige", "title": "Operator Prestige", "symbol": "star.fill",
  "intro": "An operator can Prestige once it has 18 Trait Points (spent or not) and isn't MIA. You pay the cash and hand in the gear below, equipped on the operator, and all of it is used up along with every trait you picked. In return the operator gets a random permanent trait. It can hold up to three, and from Prestige 4 you're offered a new one to swap in or turn down. Move anything you want to keep into your Stash first; Secure Slots don't protect it.",
  "rows": rows([
   ("Prestige 1", "$200,000", "Hand in 2 weapons with 3 attachment slots (Rare or better), a Rare or better plate carrier and backpack, and 4 Rare or better ingredients"),
   ("Prestige 2", "$300,000", "Hand in 2 weapons with 4 attachment slots, an Epic plate carrier and backpack, and 4 Epic ingredients"),
   ("Prestige 3 and later", "$500,000", "Hand in 2 weapons with 4 attachment slots, a Legendary plate carrier and backpack, and 4 Legendary ingredients"),
   ("If Prestige won't go through", None, "Activision is looking into a Prestige bug. Its workaround is to equip Rare weapons with three attachment slots that have never had four or more attachments; just removing an attachment doesn't count"),
  ])},
]
for s in guide:
    for r in s["rows"]:
        for k in [k for k, v in r.items() if v is None]: del r[k]

import importlib.util, os
_spec = importlib.util.spec_from_file_location("video_data", os.path.join(os.path.dirname(os.path.abspath(__file__)), "video_data.py"))
_vd = importlib.util.module_from_spec(_spec); _spec.loader.exec_module(_vd)
_vd.apply(guide, rows)
items = _vd.build_items(guide, markers)
_w = json.load(open(os.path.join(os.path.dirname(os.path.abspath(OUT)), "weapons.json")))
_weapons = {(w["name"] if isinstance(w["name"], str) else w["name"]["en"]): w["weaponId"] for c in _w["categories"] for w in c["weapons"]}
items = _vd.link_rows(guide, items, _weapons)
trees, traits = _vd.build_traits(guide)
_vd.group_bosses(guide)
_vd.check_upgrades(guide)
_vd.sweep_oct20(guide, markers, items)
_vd.structured_ops(guide)
_vd.relink(guide, items, {'bosses', 'kits'})
_vd.polish(guide, items)
_vd.tier_upgrades(guide, items)
_vd.new_pictures(items)
_vd.sell_values(items)
_vd.key_pictures(items)
_vd.fob_pictures(items)
_vd.key_sources(items, markers, CODEX["keys"])

cats = [{"id": c[0], "name": c[1], "symbol": c[2], "color": c[3], "visible": c[5], **({"blurb": CAT_BLURB[c[0]]} if c[0] in CAT_BLURB else {})} for c in CATS]
data = {"version": "0.9.32", "updated": "2026-10-27",
        "map": {"image": "hajin_map", "credit": "Map: Activision Hajin DMZ Tac Map"},
        "threatLevels": ["Low", "Medium", "High", "Critical", "Extreme"],
        "categories": cats, "markers": markers, "guide": guide, "items": items, "traitTrees": trees, "traits": traits}
json.dump(data, open(OUT, "w"), ensure_ascii=False, indent=1)
print(len(markers), "markers", counts, sum(len(s["rows"]) for s in guide), "guide rows")
