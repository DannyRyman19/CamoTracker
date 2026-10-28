"""Data read off the in-game 3D Printer, Gunsmith, Vendor and Traits screens
(video Call of Duty_20261020203519.webm, 2026-10-20). Applied by build_hajin.py."""
import json
IMG_BASE = "https://camotracker.djr.li/Images/DMZ/"

def _imgs():
    try:
        m = json.load(open(__file__.rsplit("/", 1)[0] + "/imgmap.json"))
        return {k.lower(): IMG_BASE + v["slug"] + ".png?v=1" for k, v in m.items()}
    except FileNotFoundError:
        return {}

NC = "Cost not confirmed yet"
F = "Find"
# (group, name, unlock, rarity, cost, what it does)
RECIPES = [
 ("Consumables", "Bandage", "Lv 2", "Uncommon", "15 Synthetics, 15 Chemicals", "Restores max health for a while after you're hurt"),
 ("Consumables", "Medkit", "Lv 2", "Epic", "30 Chemicals, 1 Binding Catalyst, 5 Biomaterials", "Repairs your wound and restores max health"),
 ("Consumables", "Sedative Inhaler", "Lv 3", "Uncommon", "15 Synthetics, 15 Chemicals", "Hides you from radar, marking and thermal"),
 ("Consumables", "Energy Drink", F, "Common", "10 Chemicals, 10 Metals", "Unlimited stamina"),
 ("Consumables", "Pain Killers", F, "Uncommon", "15 Electronics, 15 Chemicals", "Max health, weaker damage effects and faster regen for a minute"),
 ("Consumables", "Radiation Blockers", F, "Rare", "30 Chemicals, 3 Biomaterials", "Eases the effects of radiation for a minute"),
 ("Consumables", "Smelling Salts", F, "Rare", "30 Chemicals, 3 Detonators", "Unlimited stamina, better movement and faster reloads for 60 seconds"),
 ("Consumables", "Self-Revive Kit", "Lv 48", "Legendary", "1 Stabilized Reagents, 5 Biomaterials, 3 Binding Catalyst", "Revive yourself when you're downed"),
 ("Consumables", "Door Breacher Charge", F, "Ultra", "1 Experimental Compounds, 5 Stock Rod, 3 Volatile Explosives", "Single-use charge that breaches a locked door"),
 ("Plate Carriers", "1-Plate Armor Vest", "Lv 2", "Uncommon", "25 Synthetics, 25 Metals", "One armor plate"),
 ("Plate Carriers", "2-Plate Armor Vest", "Lv 2", "Rare", "50 Synthetics, 5 Reactive Metals", "Two armor plates"),
 ("Plate Carriers", "2-Plate Ballistic Gel Vest", F, "Epic", "50 Synthetics, 3 Binding Catalyst, 10 Reactive Metals", "Two plates that regenerate over time"),
 ("Plate Carriers", "2-Plate Helmet Armor Vest", F, "Epic", "50 Synthetics, 3 Structural Alloy, 10 Reactive Metals", "Two plates, less damage from headshots"),
 ("Plate Carriers", "3-Plate Armor Vest", F, "Legendary", "2 Ballistic Fabric, 5 Nylon Cloth, 10 Reactive Metals", "Three armor plates"),
 ("Plate Carriers", "3-Plate Ballistic Gel Vest", F, "Ultra", "2 Experimental Compounds, 4 Stabilized Reagents, 10 Biomaterials", "Three plates that regenerate over time"),
 ("Plate Carriers", "3-Plate Helmet Armor Vest", F, "Ultra", "2 Nano-Structured Alloy, 4 Alloyed Plating, 10 Reactive Metals", "Three plates, less damage from headshots"),
 ("Plate Carriers", "Tempered Armor Vest", F, "Ultra", "2 Military Composites, 4 Ballistic Fabric, 10 Rigid Synthetics", "Heavy carrier that takes enhanced plates"),
 ("Backpacks", "Small Backpack", "Lv 2", "Uncommon", "25 Synthetics, 25 Metals", "Small, with limited space"),
 ("Backpacks", "Medium Backpack", "Lv 2", None, "50 Synthetics, 5 Rigid Synthetics", "One Secure Slot"),
 ("Backpacks", "Small Secure Backpack", F, "Epic", "50 Metals, 3 Structural Alloy, 10 Rigid Synthetics", "Three Secure Slots"),
 ("Backpacks", "Medium Scavenger Backpack", F, "Epic", "50 Metals, 3 Nylon Cloth, 10 Rigid Synthetics", "Two Secure Slots and room for more resources"),
 ("Backpacks", "Medium Weapon Backpack", F, "Epic", "50 Synthetics, 3 High-Tenacity Fibers, 10 Rigid Synthetics", "A weapon slot and one Secure Slot"),
 ("Backpacks", "Large Backpack", F, None, "2 Nylon Laminate, 5 Structural Alloy, 10 Rigid Synthetics", "Large, with a weapon slot and two Secure Slots"),
 ("Backpacks", "Large Scavenger Backpack", F, "Legendary", "2 Nylon Laminate, 5 High-Tenacity Fibers, 10 Rigid Synthetics", "Large, three Secure Slots and room for more resources"),
 ("Backpacks", "Medium Secure Backpack", F, "Legendary", "2 Alloyed Plating, 5 Nylon Cloth, 10 Reactive Metals", "Four Secure Slots"),
 ("Backpacks", "Large Secure Backpack", F, "Ultra", "2 Prototype RF Module, 4 Alloyed Plating, 10 Rigid Synthetics", "Large, with a weapon slot and four Secure Slots"),
 ("Backpacks", "Secure Scavenger Backpack", F, "Ultra", "2 Military Composites, 4 Nylon Laminate, 10 Reactive Metals", "Large, four Secure Slots and room for more resources"),
 ("Tacticals", "Concussion Grenade", "Lv 4", "Common", "10 Synthetics, 10 Chemicals", "Slows the target's movement and aim"),
 ("Tacticals", "Smoke Grenade", "Lv 4", "Common", "10 Synthetics, 10 Chemicals", "Smoke that blocks sight and automated targeting"),
 ("Tacticals", "Snapshot Grenade", "Lv 9", "Common", "10 Synthetics, 10 Chemicals", "Launches up and scans the area for enemies"),
 ("Tacticals", "Spotter Scope", "Lv 12", "Rare", "50 Synthetics, 5 Electronic Sensors", "Spot and mark enemies nearby"),
 ("Tacticals", "Shock Stick", "Lv 17", "Common", "10 Synthetics, 10 Chemicals", "Sticks to surfaces, shocks enemies, wrecks equipment and sends vehicles haywire"),
 ("Tacticals", "Screamer Mine", F, "Common", "10 Synthetics, 10 Chemicals", "Proximity alarm that flashes enemies nearby"),
 ("Tacticals", "Flash", "Orders", "Common", "10 Synthetics, 10 Chemicals", "A blinding flash that disorients anyone nearby"),
 ("Tacticals", "Decoy Grenade", "Orders", "Common", "10 Synthetics, 10 Chemicals", "Fakes gunfire, movement and radar signatures"),
 ("Tacticals", "Stim", F, "Uncommon", "15 Synthetics, 15 Chemicals", "Starts health regen, refreshes Tactical Sprint, eases flash and stun"),
 ("Tacticals", "Heartbeat Sensor", F, "Uncommon", "25 Synthetics, 25 Chemicals", "A tablet showing roughly where enemies are"),
 ("Lethals", "Frag Grenade", "Lv 7", "Common", "10 Chemicals, 10 Metals", "Shrapnel grenade"),
 ("Lethals", "Throwing Knife", "Lv 7", "Uncommon", "25 Chemicals, 25 Metals", "Retrievable; kills unarmored targets and on headshots"),
 ("Lethals", "C4", "Orders", "Common", "10 Chemicals, 10 Metals", "Sticky explosive you set off remotely"),
 ("Lethals", "Zip Gun", F, "Common", "10 Chemicals, 10 Metals", "Single-shot pistol for close range"),
 ("Lethals", "Drill Charge", F, "Uncommon", "15 Chemicals, 15 Metals", "Burrows into a surface before it blows"),
 ("Lethals", "Trip Wire", F, "Uncommon", "15 Chemicals, 15 Metals", "Thrown trap; several link into a network"),
 ("Lethals", "Claymore", F, "Common", "10 Chemicals, 10 Metals", "Proximity-triggered explosive mine"),
 ("Lethals", "Proximity Mine", F, "Common", "10 Chemicals, 10 Metals", "Goes off when an enemy gets close; heavy damage to vehicles"),
 ("Lethals", "Semtex", "Lv 23", "Common", "10 Chemicals, 10 Metals", "Timed sticky grenade"),
 ("Lethals", "Molotov Cocktail", "Lv 36", "Common", "10 Chemicals, 10 Metals", "Incendiary that bursts on impact"),
 ("Lethals", "Thermite", "Lv 41", "Common", "10 Chemicals, 10 Metals", "Incendiary that sticks to any surface"),
 ("Field Upgrades", "Ammo Box", "Lv 12", "Uncommon", "15 Synthetics, 15 Metals", "Refills ammo and equipment for you and your allies"),
 ("Field Upgrades", "Armor Box", "Lv 14", "Rare", "30 Metals, 3 Reactive Metals", "Armor plates for you and your squad"),
 ("Field Upgrades", "Trophy System", F, "Rare", "15 Electronics, 3 Control Unit", "Destroys up to three incoming projectiles or pieces of equipment"),
 ("Field Upgrades", "Defibrillator", "Complete Operation Critical Extraction", "Rare", "30 Electronics, 3 Control Unit", "Revive downed operators instantly"),
 ("Field Upgrades", "Recon Drone", "Order", "Rare", "30 Metals, 3 Electronic Sensors", "Remote drone that marks enemies, by hand or automatically"),
 ("Field Upgrades", "Portable Radar", F, "Uncommon", "15 Synthetics, 15 Electronics", "Pings nearby enemies every so often"),
 ("Field Upgrades", "Seeker Drone", F, "Uncommon", "15 Synthetics, 15 Electronics", "Deploy a drone that seeks out nearby enemies and snapshots them"),
 ("Field Upgrades", "Razor Wire Trap", F, "Uncommon", "15 Electronics, 15 Metals", "A mine that tangles enemies in razor wire"),
 ("Field Upgrades", "Rebreather", F, "Uncommon", "15 Synthetics, 15 Chemicals", "An oxygen tank for breathing underwater"),
 ("Field Upgrades", "Riot Shield", F, "Uncommon", "15 Synthetics, 15 Metals", "A placeable shield to hold a position"),
 ("Field Upgrades", "Smoke Wall", F, "Uncommon", "15 Electronics, 15 Chemicals", "A fast rocket that leaves a smoke trail to cover a move"),
 ("Field Upgrades", "Inflatable Decoy", "Lv 52", "Uncommon", "15 Synthetics, 15 Electronics", "Proximity decoy mine that pops up a target to distract"),
 ("Field Upgrades", "DDOS", "Orders", "Rare", "30 Electronics, 3 Detonators", "Knocks out electronics and sensors nearby for a short time"),
 ("Field Upgrades", "SAM Airburst Turret", F, "Rare", "30 Metals, 3 Detonators", "Portable turret that shoots down aerial threats"),
 ("Field Upgrades", "Revive Pistol", "Lv 25", "Legendary", "2 Power Regulator, 3 Binding Catalyst, 5 Detonators", "Revive or heal allies from a distance"),
 ("Field Upgrades", "Fulton Drop Marker", F, "Ultra", "1 Prototype RF Module, 3 Comms Module, 5 Control Unit", "Marks a spot and calls in a fulton extraction"),
 ("Fire Support", "Care Package", "Lv 28", "Rare", "20 Electronics, 2 Control Unit, 2 Rigid Synthetics", "Calls in a supply drop"),
 ("Fire Support", "Combat Drone", F, "Epic", "30 Electronics, 2 CPU, 5 Control Unit", "Remote-controlled anti-personnel drone"),
 ("Fire Support", "UAV", "Lv 31", "Epic", "30 Electronics, 2 Structural Alloy, 5 Electronic Sensors", "Shows enemies on the minimap"),
 ("Fire Support", "Bombing Run", F, "Epic", "30 Chemicals, 2 Nitro Compounds, 5 Control Unit", "An aerial bombing run on a target location"),
 ("Fire Support", "Bomb Glider", F, "Epic", "30 Chemicals, 2 Stock Rod, 5 Control Unit", "Hand-held glider with an explosive payload"),
 ("Fire Support", "Artillery Beacon", F, "Legendary", "2 Volatile Explosives, 3 Nitro Compounds, 5 Detonators", "Heat-seeking missiles that track the beacon"),
 ("Fire Support", "Advanced UAV", F, "Legendary", "2 Comms Module, 3 Nitro Compounds, 5 Electronic Sensors", "An orbital UAV that can't be shot down; shows which way enemies face"),
 ("Fire Support", "Impact Warhead", F, "Legendary", "2 Turned Components, 3 Nitro Compounds, 5 Detonators", "A payload that drills through several floors"),
 ("Fire Support", "Railgun Sentry", F, "Legendary", "2 Power Regulator, 3 Nitro Compounds, 5 Control Unit", "Hypersonic flechette cannon that works as a sentry"),
 ("Fire Support", "Crossfire", F, "Ultra", "2 Prototype RF Module, 3 Volatile Explosives, 5 Electronic Sensors", "Airstrikes from two directions at once"),
 ("Gear", "Gas Mask", "Lv 26", "Rare", "30 Chemicals, 3 Rigid Synthetics", "Protects you from radiation"),
 ("Gear", "Durable Gas Mask", F, "Epic", "30 Chemicals, 1 High-Tenacity Fibers, 5 Biomaterials", "Protects you from radiation"),
 ("Gear", "Weak Night Vision Goggles", F, "Uncommon", "25 Metals, 5 Control Unit", "Night vision you can toggle on and off"),
 ("Gear", "Night Vision Goggles", F, "Rare", "50 Metals, 3 Printed Circuit Board, 10 Control Unit", "Night vision you can toggle on and off"),
 ("Gear", "Elite Night Vision Goggles", F, "Legendary", "2 Power Regulator, 3 CPU, 5 Electronic Sensors", "Night vision you can toggle on and off"),
 ("Gear", "Disposable Parachute", "Lv 55", "Rare", "30 Chemicals, 3 Rigid Synthetics", "A parachute with limited uses"),
 ("Gear", "Parachute", F, "Legendary", "2 Turned Components, 5 Nylon Cloth, 10 Rigid Synthetics", "Reusable"),
 ("Ingredients", "Biomaterials", "Upgrade", "Uncommon", "20 Synthetics, 20 Chemicals", "Needs Uncommon Ingredient Printing"),
 ("Ingredients", "Detonators", "Upgrade", "Uncommon", "20 Chemicals, 20 Electronics", "Needs Uncommon Ingredient Printing"),
 ("Ingredients", "Electronic Sensors", "Upgrade", "Uncommon", "20 Synthetics, 20 Electronics", "Needs Uncommon Ingredient Printing"),
 ("Ingredients", "Reactive Metals", "Upgrade", "Uncommon", "20 Chemicals, 20 Metals", "Needs Uncommon Ingredient Printing"),
 ("Ingredients", "Rigid Synthetics", "Upgrade", "Uncommon", "20 Synthetics, 20 Metals", "Needs Uncommon Ingredient Printing"),
 ("Ingredients", "Alloyed Plating", "Upgrade", "Epic", "100 Metals, 3 Structural Alloy", "Needs Epic Ingredient Printing"),
 ("Ingredients", "Ballistic Fabric", "Upgrade", "Epic", "100 Synthetics, 3 High-Tenacity Fibers", "Needs Epic Ingredient Printing"),
 ("Ingredients", "Comms Module", "Upgrade", "Epic", "100 Electronics, 3 CPU", "Needs Epic Ingredient Printing"),
 ("Ingredients", "Nylon Laminate", "Upgrade", "Epic", "100 Synthetics, 3 Nylon Cloth", "Needs Epic Ingredient Printing"),
 ("Ingredients", "Power Regulator", "Upgrade", "Epic", "100 Electronics, 3 Printed Circuit Board", "Needs Epic Ingredient Printing"),
 ("Ingredients", "Stabilized Reagents", "Upgrade", "Epic", "100 Chemicals, 3 Binding Catalyst", "Needs Epic Ingredient Printing"),
 ("Ingredients", "Turned Components", "Upgrade", "Epic", "100 Metals, 3 Stock Rod", "Needs Epic Ingredient Printing"),
 ("Ingredients", "Volatile Explosives", "Upgrade", "Epic", "100 Chemicals, 3 Nitro Compounds", "Needs Epic Ingredient Printing"),
]
UPGRADES = [
 ("Stash Item Upgrade I", "$10,000", "10 Rigid Synthetics, 10 Electronic Sensors. +18 Stash item slots"),
 ("Stash Item Upgrade II", "$50,000", "20 Detonators, 10 Nylon Cloth, 5 Power Regulator. +18 Stash item slots"),
 ("Stash Item Upgrade III", "$100,000", "20 Binding Catalyst, 20 Stock Rod, 10 Alloyed Plating. +18 Stash item slots"),
 ("Stash Weapon Upgrade I", "$50,000", "20 Reactive Metals, 10 Stock Rod, 5 Comms Module. +6 Stash weapon slots"),
 ("MIA Recovery Discount I", None, "5 Regional Combat Notes, 10 Control Unit, 10 Rigid Synthetics. Rescuing an MIA operator costs 5% less"),
 ("MIA Recovery Discount II", None, "5 Nuclear Program Files, 5 Degraded Execution Footage, 10 Binding Catalyst, 10 Nitro Compounds. Rescuing an MIA operator costs another 5% less, 10% with Discount I"),
 ("MIA Recovery Discount III", None, "5 W.M.D Manifest, 5 Foreign Intelligence Targets, 10 Power Regulator, 10 Comms Module. Rescuing an MIA operator costs another 5% less"),
 ("Bank Upgrade I", "$20,000", "Cash only. Your Bank holds up to $250,000"),
 ("Bank Upgrade II", "$50,000", "Cash only. Your Bank holds up to $500,000"),
 ("Bank Upgrade III", "$100,000", "5 Infantry Invasion Plans. Your Bank holds up to $1 million"),
 ("Bank Upgrade IV", "$200,000", "5 Ballistic Flight Logs, 5 Regional Combat Notes. Your Bank holds up to $2 million"),
 ("Gunsmith Upgrade I", "$50,000", "20 Reactive Metals, 10 CPU, 5 Power Regulator. 5% off at the Gunsmith"),
 ("Vendor Item Upgrade I", None, "20 Electronic Sensors, 10 CPU, 10 Printed Circuit Board, 2 Prototype RF Module. More to buy at the Vendor"),
 ("Uncommon Ingredient Printing", "$50,000", "20 Biomaterials, 10 High-Tenacity Fibers, 5 Comms Module. Print Biomaterials, Detonators, Electronic Sensors, Reactive Metals and Rigid Synthetics"),
 ("Epic Ingredient Printing", "$100,000", "10 Binding Catalyst, 10 Printed Circuit Board, 5 Military Composites. Print Alloyed Plating, Ballistic Fabric, Comms Module, Nylon Laminate, Power Regulator, Stabilized Reagents, Turned Components and Volatile Explosives"),
 ("Dog Tag Case Upgrade I", "$10,000", "10 Rigid Synthetics, 10 Biomaterials. +20 dog tags. Needs the Dog Tag Case"),
 ("Dog Tag Case Upgrade II", "$50,000", "20 Detonators, 10 Nylon Cloth, 5 Power Regulator. More dog tag storage"),
 # the higher tiers, from the in-game upgrade lists the user sent (2026-10-27);
 # Stash Item IV, Stash Weapon III and every MIA tier cost no cash
 ("Bank Upgrade V", "$500,000", "10 Degraded Execution Footage. Your Bank holds up to $5 million"),
 ("Bank Upgrade VI", "$500,000", "10 Nuclear Program Files, 10 Encrypted Archive. Your Bank holds up to $10 million"),
 ("Bank Upgrade VII", "$500,000", "10 W.M.D Manifest. Your Bank holds up to $25 million"),
 ("Bank Upgrade VIII", "$500,000", "10 Foreign Intelligence Targets, 10 Cipher Code Ledger. Your Bank holds up to $50 million"),
 ("Bank Upgrade IX", "$500,000", "10 Sanctioned Assassination List. Your Bank holds up to $100 million"),
 ("Stash Item Upgrade IV", None, "5 Gold Skull, 30 Alloyed Plating, 10 Experimental Compounds, 30 Turned Components. +18 Stash item slots"),
 ("Stash Weapon Upgrade II", "$100,000", "20 Structural Alloy, 20 High-Tenacity Fibers, 10 Turned Components. +6 Stash weapon slots"),
 ("Stash Weapon Upgrade III", None, "5 Gold Bar, 30 Stabilized Reagents, 30 Volatile Explosives, 10 Nano-Structured Alloy. +6 Stash weapon slots"),
 ("MIA Recovery Discount IV", None, "5 Sanctioned Assassination List, 30 Ballistic Fabric, 30 Nylon Laminate, 10 Prototype RF Module. Rescuing an MIA operator costs another 5% less"),
 # dmzcodex.com upgrade pages (2026-10-27), not confirmed in game yet
 ("Gunsmith Upgrade II", "$100,000", "20 Nitro Compounds, 10 Comms Module, 10 Military Composites. Another 5% off at the Gunsmith (reported)"),
 ("Vendor Item Upgrade II", None, "20 Control Unit, 10 High-Tenacity Fibers, 10 Nylon Cloth, 2 Nano-Structured Alloy. More to buy at the Vendor (reported; the cash cost isn't known yet)"),
]
GUNS = [
 ("Assault Rifles", [("Han 86", 6000, True), ("M4", 6250), ("Hyeon Burst", 5250), ("Kastov 762", 5500), ("Patriot XMR", 6500), ("Oden", 6250), ("Axion", 5750), ("Cronen Squall", 6750)]),
 ("SMGs", [("ISO Nightshade", 4250), ("VEL 46", 4500), ("Wz.55 Striga", 3500), ("PPSh-41", 3750), ("X-58 Nyx", 4000)]),
 ("Shotguns", [("Rezi 12", 4000, True), ("Warlord", 3500)]),
 ("LMGs", [("FiNN LMG", 8000), ("Type 73", 7500), ("APOC-338", 7750)]),
 ("Marksman Rifles", [("MAR-9", 6500), ("Oris 8.6", 7000), ("Mosin-Nagant", 7500)]),
 ("Pistols", [("Sang 9mm", 1000, True), ("Krait P68", 1000), (".50 GS", 4000), ("Mojave .357", 2500)]),
 ("Launchers", [("RPG-8", 9500), ("PILA", 23750), ("PM-40 Anvil", 28500), ("JOKR", 47500)]),
 ("Melee", [("FSS Carbon Edge 1095", 250, True)]),
]
TRAITS = [
 ("Thermal Padding", "Scout", "Hides you from UAVs and drops Advanced UAVs to normal UAV detection"),
 ("Overwatch", "Scout", "UAV Towers you activate never expire"),
 ("Resource Hoarder", "Scout", "20% more printer resource capacity. Stacks with Pack Rat"),
 ("Investor", "Scout", "A little more cash when you extract"),
 ("Final Intel", "Scout", "The final exfil is marked on your Tac Map from the start"),
 ("Mini Tracker", "Scout", "Looting an unopened container has a 50% chance to send out a radar pulse"),
 ("Key Cash", "Scout", "Opening a locked room with a key pays cash; rarer keys pay more"),
 ("Fast Learner", "Scout", "A little more operator XP"),
 ("Field Crafting", "Scout", "Craft items from Common printer resources while deployed"),
 ("UAV Upgrade", "Scout", "Longer range and duration for UAVs, and they become Advanced UAVs"),
 ("Ammo Scavenger", "Scout", "Double ammo from ammo packs"),
 ("Stealthy", "Scout", "Kill more enemies before a Hunt Squad comes after you"),
 ("Resupply", "Scout", "More ammo from restocks and ammo crates; Armor Boxes give 2 extra plates"),
 ("Resource Pockets", "Scout", "Scrapped items give 20% more printer resources"),
 ("Resource Management", "Scout", "Resources you pick up past your cap top up whichever you have least of"),
 ("Field Medic", "Scout", "Revive allies faster"),
 ("Hostile Looter", "Scout", "Enemies sometimes drop an Uncommon printer ingredient, and very rarely a Rare one"),
 ("Container Looter", "Scout", "A chance of an extra piece of loot in containers"),
 ("Pack Rat", "Scout", "20% more printer resource capacity. Stacks with Resource Hoarder"),
 ("Cash Ops", "Scout", "20% more cash from completing Ops"),
 ("Quick Knife", "Scout", "Your weapon bash becomes a knife attack"),
 ("Popcorn Tacticals", "Warfighter", "Enemies hit by your Tacticals are more likely to drop Tacticals"),
 ("Popcorn Lethals", "Warfighter", "Hostiles hit by your Lethals are more likely to drop Lethals. A random-row trait in the top section"),
 ("Faster Revive", "Survivalist", "Faster revives. One of the two fixed traits in the bottom section"),
 ("Expedited Extraction", "Survivalist", "Exfils arrive much faster. A random-row trait in the top section"),
 ("Rescuer", "Survivalist", "Move faster while dragging a downed teammate. A random-row trait in the top section"),
 ("Rad Blocker", "Survivalist", "Less damage from radiation. A random-row trait in the middle section"),
 ("Fuel Economy", "Survivalist", "Vehicles use less fuel. A random-row trait in the middle section"),
 ("Consumable Stacker", "Survivalist", "Using a consumable that's already active adds to its time, up to twice the normal length. A random-row trait in the middle section"),
 ("Randomized Trait", "Warfighter", "Revealed once you take a trait from the row before"),
]
NEW_INGREDIENTS = [
 ("Stabilized Reagents", "Epic", "Self-Revive Kit, 3-Plate Ballistic Gel Vest. Printable: 100 Chemicals, 3 Binding Catalyst"),
 ("Experimental Compounds", "Legendary", "3-Plate Ballistic Gel Vest"),
 ("Nano-Structured Alloy", "Legendary", "3-Plate Helmet Armor Vest"),
 ("Alloyed Plating", None, "3-Plate Helmet Armor Vest, Medium Secure Backpack"),
 ("Turned Components", "Epic", "Parachute"),
 ("Comms Module", None, "Stash Weapon Upgrade, Uncommon Ingredient Printing"),
 ("Prototype RF Module", "Legendary", "Vendor Item Upgrade"),
 ("Regional Combat Notes", "Uncommon", "MIA Recovery Discount I, Bank Upgrade IV"),
 ("Nuclear Program Files", "Rare", "MIA Recovery Discount II"),
 ("Degraded Execution Footage", "Rare", "MIA Recovery Discount II"),
 ("Infantry Invasion Plans", "Uncommon", "Bank Upgrade III"),
]

# Where each ingredient turns up, from the printer's Ingredient Locations screens
# (video Call of Duty_20261021162314.webm, 2026-10-21)
_TECH = "Mainly the Netshin Tech Complex server rooms, Cheonwang Peak Array server rooms and the Deadtown hillside facade buildings"
_REACTOR = "Mainly the Haneul Nuclear Reactor and electrical substations"
_CLOTH = "Mainly the Citadel main building wings, the Deadtown underground holding area and the Heavenly Luck Casino's Mujin Nightclub"
_AIRBASE = "Mainly the Chang-san Air Base hangar, repair bay and Bubun Yard"
_ARMORY = "Mainly the Chang-san Air Base armory and barracks, and the Songdo Wharf La Grande Vie rooftop"
_MILL = "Mainly the Imjin Farmland rice mill, the Hajin City construction zone and Namjjog Station"
_LAB = "Mainly the NuriGO Mall DRC lab, the Citadel Prison Yard chemical buildings and the Imjin Farmland storage tents"
_HOSPITAL = "Mainly Mirae General Hospital and medical tents"
FOUND = {
 "Encrypted Archive": "Heavenly Luck Casino storage and counting-room containers, and a footlocker and bag in the Mirae Electrical Room at Mirae General Hospital (parking level B2). Both rooms need their keys",
 "Regional Combat Notes": "Civilian and military areas", "Nuclear Program Files": "Computers, and civilian and military areas", "Ballistic Flight Logs": "Civilian and military areas", "Infantry Invasion Plans": "Civilian and military areas",
 "Control Unit": "Computers and tech bags", "Electronic Sensors": "Tech bags and commercial areas",
 "Rigid Synthetics": "Residential areas and civilian duffel bags", "Biomaterials": "Hospitals and chemical lockers",
 "Detonators": "Military and industrial areas", "Reactive Metals": "Industrial areas and toolboxes",
 "CPU": _TECH, "Comms Module": _TECH, "Power Regulator": _REACTOR, "Printed Circuit Board": _REACTOR,
 "Nylon Cloth": _CLOTH, "Nylon Laminate": _CLOTH, "Structural Alloy": _AIRBASE, "Alloyed Plating": _AIRBASE,
 "High-Tenacity Fibers": _ARMORY, "Ballistic Fabric": _ARMORY, "Stock Rod": _MILL, "Turned Components": _MILL,
 "Volatile Explosives": _LAB, "Nitro Compounds": _LAB, "Binding Catalyst": _HOSPITAL, "Stabilized Reagents": _HOSPITAL,
 "Experimental Compounds": "Now and then on Commanders", "Prototype RF Module": "Deathstalkers",
 "Military Composites": "Colossus", "Nano-Structured Alloy": "Tanks",
}

# Named places in FOUND text that have a Tac Map marker (phrase, marker name)
FOUND_PLACES = [
 ("Chang-san Air Base", "Chang-san Air Base"), ("Songdo Wharf", "Songdo Wharf"),
 ("Cheonwang Peak Array", "Cheonwang Peak Array"), ("Deadtown", "Deadtown"),
 ("Haneul Nuclear Reactor", "Haneul Nuclear Reactor"), ("Citadel", "The Citadel"),
 ("Heavenly Luck Casino", "Heavenly Luck Casino"), ("Imjin Farmland rice mill", "Rice Mill"),
 ("Imjin Farmland", "Imjin Farmland"), ("construction zone", "Construction Zone"),
 ("NuriGO Mall", "NuriGO Mall"), ("Mirae General Hospital", "Mirae General Hospital"),
]

def apply(guide, rows):
    imgs = _imgs()
    def img(name): return imgs.get(name.lower())
    def add_img(r, name):
        u = img(name)
        if u: r["image"] = u
        return r
    sec = {s["id"]: s for s in guide}
    out = []
    for g, name, unlock, rarity, cost, what in RECIPES:
        sub = cost if cost == NC else ". ".join(x for x in [cost, what] if x)
        if rarity: sub = f"{rarity}. {sub}"
        r = {"title": name, "subtitle": sub, "group": g}
        if unlock: r["value"] = unlock
        out.append(add_img(r, name))
    sec["recipes"]["rows"] = out
    sec["recipes"]["intro"] = ("Made at the 3D Printer in your FOB before you deploy. \"Find\" means you unlock it by finding the recipe in Hajin and extracting with it, "
                               "which also pays $5,000. \"Orders\" means DMZ Orders. Costs read from the in-game printer; more get added as they're confirmed.")
    # ingredients: images, and the new ones
    res = sec["resources"]["rows"]
    have = {r["title"] for r in res}
    for name, rar, sub in NEW_INGREDIENTS:
        if name not in have:
            r = {"title": name, "subtitle": sub}
            if rar: r["value"] = rar
            res.append(r)
    for r in res: add_img(r, r["title"])
    for s in ("valuables",):
        for r in sec[s]["rows"]: add_img(r, r["title"])
    # stations: the Gunsmith row now points at the price list
    for r in sec["stations"]["rows"]:
        if r["title"] == "Gunsmith":
            r["subtitle"] = "Extract a gun's Weapon Manual once, then buy that gun here whenever you like. Weapon Manuals turn up most in military containers and safes. Prices in Gunsmith prices. 5% off from level 25, and 5% more with Gunsmith Upgrade I"
        if r["title"] == "Bank":
            r["subtitle"] = "Holds your DMZ Cash; cash you extract goes here. Bank Upgrade III raises the cap to $1 million"
        if r["title"] == "Vendor":
            r["subtitle"] = "Sells weapons and gear for DMZ Cash, restocking daily. More slots unlock with DMZ level and Vendor Item Upgrades. Seen on day one: night vision goggles $7,000, a built rifle $46,250"
    i = next(k for k, s in enumerate(guide) if s["id"] == "stations") + 1
    guide.insert(i, {"id": "upgrades", "title": "FOB upgrades", "symbol": "arrow.up.circle.fill",
        "intro": "Printed at the 3D Printer to improve your FOB. Costs read from the in-game printer.",
        "rows": [dict({"title": t, "subtitle": s}, **({"value": v} if v else {})) for t, v, s in UPGRADES]})
    grows = []
    for g, guns in GUNS:
        for gun in guns:
            name, price = gun[0], gun[1]
            starter = len(gun) > 2
            row = {"title": name, "group": g,
                   "subtitle": "Unlocked from the start" if starter else "Extract its Manual to unlock" + ("" if price else ". Price not known yet")}
            if price: row["value"] = f"${price:,}"
            grows.append(row)
    guide.insert(i + 1, {"id": "gunsmith", "title": "Gunsmith prices", "symbol": "scope",
        "intro": "What a base weapon costs at the Gunsmith (level 10). Discounts from level 25 and Gunsmith Upgrade I come off these. Tick a weapon once you've extracted its Weapon Manual.",
        "rows": grows})
    guide.append({"id": "traits", "title": "Traits", "symbol": "brain.head.profile",
        "intro": "Each operator spends trait points across three trees: Warfighter, Scout and Survivalist. Points come from levelling your operator's dog tag (Steel to Onyx III; about 1,900 XP for a point at Silver). The full Scout tree, top to bottom, and what's known of Warfighter:",
        "rows": [dict({"title": t, "subtitle": s}, **({"group": g} if g else {})) for t, g, s in TRAITS]})

# ---- Linked items: every recipe, ingredient, resource, upgrade, valuable and key
import re as _re
RESOURCES = {"Synthetics": "doc.on.doc.fill", "Electronics": "cpu.fill", "Chemicals": "flask.fill", "Metals": "hexagon.fill"}
RARITIES = ["Common", "Uncommon", "Rare", "Epic", "Legendary", "Ultra"]

def item_id(name): return _re.sub(r"[^a-z0-9]+", "-", name.lower().replace("'", "").replace(".", "")).strip("-")

def parse_cost(text):
    """'15 Synthetics, 1 Binding Catalyst' -> [(15, 'Synthetics'), (1, 'Binding Catalyst')]"""
    out = []
    for part in text.split(","):
        m = _re.match(r"\s*(\d+)\s+(.+?)\s*$", part)
        if not m: return None
        out.append((int(m.group(1)), m.group(2)))
    return out

def build_items(guide, markers):
    imgs = _imgs()
    items = {}
    def get(name):
        iid = item_id(name)
        it = items.setdefault(iid, {"id": iid, "name": name})
        if iid in [item_id(r) for r in RESOURCES]:
            it["kind"] = "Resource"; it["symbol"] = RESOURCES[name] if name in RESOURCES else None
        if "image" not in it and imgs.get(name.lower()): it["image"] = imgs[name.lower()]
        return it
    def costs(text):
        parsed = parse_cost(text) if text and text != NC else None
        if not parsed: return None
        for _, n in parsed: get(n)
        return [{"item": item_id(n), "qty": q} for q, n in parsed]

    for g, name, unlock, rarity, cost, what in RECIPES:
        it = get(name)
        it.setdefault("kind", g if g != "Ingredients" else "Ingredient")
        if rarity: it["rarity"] = rarity
        if unlock: it["unlock"] = {"Find": "Find the recipe in Hajin and extract with it", "Orders": "Complete DMZ Orders",
                                   "Order": "Complete the Counterfeit DMZ Order", "Upgrade": None}.get(unlock, f"Reach DMZ level {unlock[3:]}" if unlock.startswith("Lv ") else unlock)
        if not it.get("unlock"): it.pop("unlock", None)
        if unlock == F: it["blueprint"] = True   # found in Hajin: the app's blueprint checklist
        c = costs(cost)
        if c: it["cost"] = c
        if what: it["effect"] = what

    sec = {s["id"]: s for s in guide}
    for r in sec["resources"]["rows"]:
        if r["title"] == "Commanders": continue  # a tip about bosses, not an item
        it = get(r["title"])
        v = r.get("value")
        if v in RARITIES: it["rarity"] = v
        if v == "Resource": it["kind"] = "Resource"
        it.setdefault("kind", "Ingredient")
        sub = r.get("subtitle", "")
        m = _re.search(r"Sells for \$([\d,]+)", sub)
        if m: it["value"] = int(m.group(1).replace(",", ""))
        known = {n.lower() for n in [x[1] for x in RECIPES] + [x[0] for x in UPGRADES]}
        def lists_uses(s): return all(part.strip().lower() in known for part in s.split(","))
        notes = [s for s in _re.split(r"\.\s*", sub)
                 if s and not s.startswith("Sells for") and not s.startswith("Printable") and not lists_uses(s)]
        # "Level 51 gives 2" now shows in the item's Unlocks panel
        notes = [s for s in notes if not _re.match(r"^Level \d+ gives \d+$", s)]
        if notes and it["kind"] != "Resource": it["note"] = ". ".join(notes)
        r["item"] = it["id"]
    for r in sec["valuables"]["rows"]:
        if r["title"] == "Keys": continue
        it = get(r["title"]); it.setdefault("kind", "Valuable")
        m = _re.match(r"\$([\d,]+)", r.get("value", ""))
        if m: it["value"] = int(m.group(1).replace(",", ""))
        rar = r.get("subtitle", "").split(".")[0]
        if rar in RARITIES: it.setdefault("rarity", rar)
        r["item"] = it["id"]
    for r in sec["upgrades"]["rows"]:
        it = get(r["title"]); it["kind"] = "FOB Upgrade"
        first, _, rest = r["subtitle"].partition(". ")
        c = costs(first)
        if c: it["cost"] = c
        elif first: it["note"] = first
        if r.get("value"): it["cash"] = int(r["value"].strip("$").replace(",", ""))
        if rest: it["effect"] = rest
        r["item"] = it["id"]
    key_markers = {m["name"].lower(): m["id"] for m in markers if m["cat"] == "key"}
    for r in sec["keys"]["rows"]:
        it = get(r["title"]); it["kind"] = "Key"; it["symbol"] = "key.fill"
        rar = r.get("subtitle", "").split(".")[0]
        if rar in RARITIES: it["rarity"] = rar
        it["note"] = r["subtitle"].split(". ", 1)[1] if ". " in r["subtitle"] else r["subtitle"]
        if r.get("value"): it["grid"] = r["value"]
        mk = key_markers.get(r["title"].lower())
        if mk: it["marker"] = mk
        it["value"] = 100
        r["item"] = it["id"]
    for r in sec["recipes"]["rows"]:
        r["item"] = item_id(r["title"])
    by_name = {}
    for m in markers:
        by_name.setdefault(m["name"].lower(), m["id"])  # first wins: areas come before fortresses
    for name, where in FOUND.items():
        it = get(name); it["found"] = where
        low, places, taken = where.lower(), [], []
        for phrase, marker in FOUND_PLACES:
            i = low.find(phrase.lower())
            if i < 0 or any(a <= i < b for a, b in taken): continue
            taken.append((i, i + len(phrase)))
            mid = by_name.get(marker.lower())
            if mid and mid not in [p for _, p in places]: places.append((i, mid))
        if places: it["foundPlaces"] = [p for _, p in sorted(places)]
    for it in items.values():
        it.setdefault("kind", "Ingredient")
        if it.get("symbol") is None: it.pop("symbol", None)
    return sorted(items.values(), key=lambda i: i["name"])

# ---- Drops, rewards and weapons
EXTRA_ITEMS = [
 {"id": "bales-dog-tag", "name": "Bale's Dog Tag", "kind": "Valuable", "rarity": "Legendary", "note": "Dropped by Lieutenant Bale. Carrying it marks you for nearby squads until you extract. Sells for $25,000"},
 {"id": "scavengers-dog-tag", "name": "Scavenger's Dog Tag", "kind": "Valuable", "rarity": "Legendary", "note": "Dropped by Lieutenant Scavenger. Sells for $25,000"},
 {"id": "rozes-dog-tag", "name": "Roze's Dog Tag", "kind": "Valuable", "rarity": "Legendary", "note": "Dropped by Lieutenant Roze. Extract it for Boss Board progress. Sells for $25,000"},
 {"id": "iskras-dog-tag", "name": "Iskra's Dog Tag", "kind": "Valuable", "rarity": "Legendary", "note": "Dropped by Lieutenant Iskra. Extract it for Boss Board progress. Sells for $25,000"},
 {"id": "jin-taes-dog-tag", "name": "Jin-Tae's Dog Tag", "kind": "Valuable", "rarity": "Legendary", "note": "Dropped by Lieutenant Jin-Tae. Extract it for Boss Board progress. Sells for $25,000"},
 {"id": "the-doctors-dog-tag", "name": "The Doctor's Dog Tag", "kind": "Valuable", "rarity": "Legendary", "note": "Dropped by The Doctor. Extract it for Boss Board progress. Sells for $25,000"},
 {"id": "goranis-dog-tag", "name": "Gorani's Dog Tag", "kind": "Valuable", "rarity": "Legendary", "note": "Dropped by Lieutenant Gorani. Sells for $25,000"},
 {"id": "hazmat-suit", "name": "Hazmat Suit", "kind": "Gear", "rarity": "Legendary", "note": "Protective suit that shields you from radiation. Discarded when you extract"},
 {"id": "irradiated-container", "name": "Irradiated Container", "kind": "Gear", "rarity": "Ultra", "note": "An Ultra item listed on dmzhub.gg. What it does isn't known yet"},
 {"id": "armor-plate", "name": "Armor Plate", "kind": "Gear", "rarity": "Common", "note": "Extra protection in combat; stacks to 6. Your armor slot fills with plates when you infil, and Ammo Armor Caches refill them (with a cooldown)"},
 {"id": "gas-can", "name": "Gas Can", "kind": "Gear", "rarity": "Common", "note": "Attach it to a vehicle to refuel it. Refill it at Gas Stations and Marine Gas Stations"},
 {"id": "weapon-manual", "name": "Weapon Manual", "kind": "Gear", "note": "Extract one to unlock its weapon for repeat buys at the Gunsmith, plus $5,000. Search military containers and safes"},
 {"id": "encrypted-drive", "name": "Encrypted Drive", "kind": "Gear", "note": "The objective item in the Dead Man's Cache op: collect it from the enemy comms server in Cheongun Outskirts"},
 {"id": "defibrillator", "name": "Defibrillator", "kind": "Gear", "rarity": "Uncommon", "note": "A reward from Operation Critical Extraction; DMZ level 67 gives one"},
 {"id": "tank-water-pump", "name": "Tank Water Pump", "kind": "Gear", "rarity": "Legendary", "note": "Used to repair heavy military tanks"},
 {"id": "tank-alternator", "name": "Tank Alternator", "kind": "Gear", "rarity": "Legendary", "value": 100, "note": "Used to repair heavy military tanks"},
 {"id": "car-battery", "name": "Car Battery", "kind": "Gear", "rarity": "Uncommon", "value": 200, "note": "A repair item for vehicles. Where to find it isn't known yet"},
 {"id": "spark-plug", "name": "Spark Plug", "kind": "Gear", "rarity": "Uncommon", "value": 100, "note": "A repair item for vehicles. Where to find it isn't known yet"},
 {"id": "night-vision-goggles", "name": "Night Vision Goggles", "kind": "Gear", "value": None, "note": "On sale at the Vendor for $7,000 on day one, and a reward from Shopping Hacks. Useful in the dark casino and the underground mall"},
 # dmzcodex.com/items (2026-10-27)
 {"id": "radiation-gear", "name": "Radiation Gear", "kind": "Gear", "note": "Protects you in radiation; the Haneul Nuclear Reactor needs it and a Gas Mask. Search Fire Stations for it"},
 {"id": "lieutenant-dog-tag-case", "name": "Lieutenant Dog Tag Case", "kind": "Valuable", "rarity": "Legendary", "note": "Dropped when you kill a Lieutenant. Extract it for Boss Board progress"},
 {"id": "weapon-insurance-contract", "name": "Weapon Insurance Contract", "kind": "Gear", "note": "Gets back an insured weapon you lose, up to the number of contracts you hold. Two come with the Vault Edition, and some DMZ Order pages give one"},
 {"id": "operator-rescue-beacon", "name": "Operator Rescue Beacon", "kind": "Gear", "note": "Recovers an MIA operator without paying DMZ Cash. Two come with the Vault Edition, and some DMZ Order pages give one"},
 {"id": "recipe", "name": "Recipe", "kind": "Gear", "note": "A recipe found in Hajin. Extract with it to add it to your 3D Printer; it's used up when you do"},
 {"id": "steel-dog-tag", "name": "Steel Dog Tag", "kind": "Valuable", "rarity": "Common", "note": "Looted from a downed operator. The tag's metal shows how far that operator has ranked up; store extracted tags in the Dog Tag Case"},
 {"id": "bronze-dog-tag", "name": "Bronze Dog Tag", "kind": "Valuable", "note": "An operator Dog Tag tier, reached by ranking up an active operator. Loot them from downed operators and keep them in the Dog Tag Case"},
 {"id": "silver-dog-tag", "name": "Silver Dog Tag", "kind": "Valuable", "note": "An operator Dog Tag tier, reached by ranking up an active operator. Loot them from downed operators and keep them in the Dog Tag Case"},
 {"id": "gold-dog-tag", "name": "Gold Dog Tag", "kind": "Valuable", "note": "An operator Dog Tag tier, reached by ranking up an active operator. Loot them from downed operators and keep them in the Dog Tag Case"},
 {"id": "damascus-dog-tag", "name": "Damascus Dog Tag", "kind": "Valuable", "note": "An operator Dog Tag tier, reached by ranking up an active operator. Loot them from downed operators and keep them in the Dog Tag Case"},
 {"id": "onyx-dog-tag", "name": "Onyx Dog Tag", "kind": "Valuable", "note": "An operator Dog Tag tier, reached by ranking up an active operator. Loot them from downed operators and keep them in the Dog Tag Case"},
 {"id": "counterfeit-cash", "name": "Counterfeit Cash", "kind": "Other", "note": "A DMZ Order item: in Execute Intel, hack a UAV Tower in Deadtown and loot it from the soldiers it pings"},
 {"id": "k9-battery-core", "name": "K9 Battery Core", "kind": "Other", "note": "A mission item from Operation Shopping Hacks in NuriGO Mall: collect four working ones"},
 {"id": "drone-motherboard", "name": "Drone Motherboard", "kind": "Other", "note": "A DMZ Order item: in Death from Above, take it from a drone you destroy"},
 {"id": "encrypted-voice-logs", "name": "Encrypted Voice Logs", "kind": "Other", "note": "A mission item: hack the communications broadcast system at Cheonwang Peak Array"},
]

def link_rows(guide, items, weapons):
    imgs = _imgs()
    by_id = {i["id"]: i for i in items}
    for e in EXTRA_ITEMS:
        it = by_id.setdefault(e["id"], {"id": e["id"], "name": e["name"]})
        for k, v in e.items():
            if v is not None and k not in ("id",): it.setdefault(k, v)
        if imgs.get(e["name"].lower()): it.setdefault("image", imgs[e["name"].lower()])
    names = sorted(((i["name"], i["id"]) for i in by_id.values() if i["kind"] not in ("Resource",)), key=lambda x: -len(x[0]))
    def find(text):
        found, taken = [], []
        low = text.lower()
        for name, iid in names:
            for m in _re.finditer(r"(?<![\w-])" + _re.escape(name.lower()) + r"(?![\w-]| tower)", low):
                span = (m.start(), m.end())
                if any(a < span[1] and span[0] < b for a, b in taken): continue
                taken.append(span)
                if iid not in found: found.append(iid)
        return found
    for s in guide:
        if s["id"] not in ("levels", "bosses", "ops", "rules", "stations", "prestige", "infil"): continue
        for r in s["rows"]:
            links = find(r["title"] + " . " + r.get("subtitle", ""))
            if links: r["links"] = links
    wid = {_re.sub(r"[^a-z0-9]", "", n.lower()): i for n, i in weapons.items()}
    for r in next(s for s in guide if s["id"] == "gunsmith")["rows"]:
        w = wid.get(_re.sub(r"[^a-z0-9]", "", r["title"].lower()))
        if w is not None: r["weapon"] = w
    return sorted(by_id.values(), key=lambda i: i["name"])

# ---- Trait trees, laid out like the game (rows top to bottom, emblem last)
TRAIT_IMG = "https://camotracker.djr.li/Images/DMZ/traits/"
TRAIT_TREES = [
 {"id": "warfighter", "name": "Warfighter", "color": "#E0575B", "shape": "hexagon",
  "rows": [["possum", "adaptive-restock"], [None, None, None], [None, None, None], ["viper-sense", "quick-fix"],
           [None, None, None], [None, None, None], ["equipment-professional", "combat-resistance"], [None, None, None]],
  "emblem": "popcorn-tacticals"},
 {"id": "scout", "name": "Scout", "color": "#D8B44A", "shape": "circle",
  "rows": [["overwatch", "thermal-padding"], ["resource-hoarder", "investor", "final-intel"], ["mini-tracker", "key-cash", "fast-learner"],
           ["field-crafting", "uav-upgrade"], ["ammo-scavenger", "stealthy", "resupply"], ["resource-pockets", "resource-management", "field-medic"],
           ["hostile-looter", "container-looter"], ["pack-rat", "cash-ops", "quick-knife"]],
  "emblem": "scout-emblem"},
 {"id": "survivalist", "name": "Survivalist", "color": "#8FB0C4", "shape": "square",
  "rows": [["surv-r1a", "die-hard"], [None, None, None], [None, None, None], ["impact-smokes", "surv-r4b"],
           [None, None, None], [None, None, None], ["surv-r7a", "surv-r7b"], [None, None, None]],
  "emblem": "surv-emblem"},
]
EXTRA_TRAITS = [
 ("possum", "Possum", "Warfighter", "Once per match, self-revive from death into Last Stand with full health"),
 ("adaptive-restock", "Adaptive Restock", "Warfighter", "Enemies drop one extra item"),
 ("viper-sense", "Viper Sense", "Warfighter", "Warns you when enemy operators are nearby"),
 ("quick-fix", "Quick Fix", "Warfighter", "Shorter health regen delay after you kill an enemy operator or hostile"),
 ("equipment-professional", "Equipment Professional", "Warfighter", "Lethals and Tacticals slowly recharge after use, up to the slot's max"),
 ("combat-resistance", "Combat Resistance", "Warfighter", "Less damage from explosives and weaker enemy tactical effects"),
 ("die-hard", "Die Hard", "Survivalist", "In Last Stand, reaching an exfil calls it for you, and you never bleed out"),
 ("impact-smokes", "Impact Smokes", "Survivalist", "Releases smoke when you're downed"),
 ("scout-emblem", None, "Scout", None), ("surv-r1a", None, "Survivalist", None), ("surv-r4b", None, "Survivalist", None),
 ("surv-r7a", None, "Survivalist", None), ("surv-r7b", None, "Survivalist", None), ("surv-emblem", None, "Survivalist", None),
]
UNPLACED = [
 ("Killing Spree", "Kills extend your active effects, up to twice as long"),
 ("Metabolism", "Slowly regenerate health lost to a tourniquet"),
 ("Adrenaline Burst", "A kill resets Tactical Sprint"),
 ("Air Superiority", "UAV Towers and SAM sites last longer"),
 ("Combat Scavenger", "Hostiles have a small chance to drop an ingredient or valuable"),
 ("Consumable Duration", "Consumables last longer"),
 ("Free Revive", "Your first Wound repairs itself"),
 ("LT Hunter", "Lieutenant Towers give extra paid intel"),
 ("Numb the Pain", "Revives also give Pain Killers and Smelling Salts effects"),
 ("Ammo Reserves", "More reserve ammo for every ammo type (Scout)"),
 ("Objective Oriented", "Op reward crates are one rarity higher, up to Rare (Survivalist)"),
 ("Supplied Drops", "A supply drop may hold an extra container, for the whole squad (Survivalist)"),
 ("Bounty Hunter", "Bounties pay more (Warfighter)"),
 ("Bounty Intel", "Bounty Intel costs less (Warfighter)"),
 ("Hostile Ammo", "Hostiles drop an extra ammo pack (Warfighter)"),
 ("Lucky", "When you're hurt or low on supplies, you find useful items more often (Warfighter)"),
 ("Plate Pouch", "Two more spare Plates. Stacks with Plate Organization (Warfighter)"),
 ("Plate Speed", "Plates go in faster (Warfighter)"),
]

# ---- Traits as a wiki: every trait each tree can roll (codcentral.net's
# list, 2026-10-28, cross-checked with allthings.how and games.gg, plus the
# ones seen in our own trees). Majors are fixed; Minors are random per operator.
TRAIT_MAJORS = {
    "Warfighter": [("Equipment Professional", 3), ("Combat Resistance", 3), ("Viper Sense", 6), ("Quick Fix", 6), ("Possum", 9), ("Adaptive Restock", 9)],
    "Scout": [("Hostile Looter", 3), ("Container Looter", 3), ("Field Crafting", 6), ("UAV Upgrade", 6), ("Overwatch", 9), ("Thermal Padding", 9)],
    "Survivalist": [("Faster Revive", 3), ("Consumable Duration", 3), ("Impact Smokes", 6), ("Free Revive", 6), ("Numb the Pain", 9), ("Die Hard", 9)],
}
TRAIT_MINORS = {
    "Warfighter": ["Adrenaline Burst", "Auto Fill", "Bounty Hunter", "Bounty Intel", "Combat Scanner", "Final Intel", "Free Prep", "Hostile Ammo",
                   "Killing Spree", "LT Hunter", "Plate Pouch", "Plate Speed", "Popcorn Lethals", "Popcorn Tacticals", "Quick Knife", "Resupply"],
    "Scout": ["Ammo Reserves", "Ammo Scavenger", "Auto Fill", "Cash Ops", "Combat Scavenger", "Fast Learner", "Faster Learner", "Field Medic", "Final Intel",
              "Investor", "Key Cash", "Mini Tracker", "Operator Tracker", "Pack Rat", "Quick Knife", "Quick Regen", "Resource Hoarder",
              "Resource Management", "Resource Pockets", "Resupply", "Stealthy"],
    "Survivalist": ["Air Superiority", "Consumable Stacker", "Deep Breath", "Expedited Extraction", "Fast Learner", "Faster Learner", "Final Intel",
                    "Fuel Economy", "Lucky", "Mechanic", "Metabolism", "Objective Oriented", "Operator Tracker", "Plate Organization", "Rad Blocker",
                    "Rampage", "Rescuer", "Resupply", "Strong Arm"],
}
# effects for traits the older lists didn't have (the rest come from TRAITS)
TRAIT_EFFECTS = {
    "Auto Fill": "Lethals and Tacticals refill from your backpack by themselves",
    "Bounty Hunter": "Bigger rewards for collecting bounties",
    "Bounty Intel": "Bounty Intel costs less",
    "Combat Scanner": "Downing a player sends one UAV pulse at where they fell",
    "Free Prep": "A Free Loadout adds a random Consumable to your backpack",
    "Hostile Ammo": "Hostiles drop an extra ammo pack",
    "LT Hunter": "Activating a Lieutenant Tower reveals an extra Lieutenant",
    "Plate Pouch": "2 more reserve plates. Stacks with Plate Organization",
    "Plate Speed": "Plates go in faster",
    "Ammo Reserves": "More reserve ammo for every ammo type",
    "Combat Scavenger": "Hostiles have a small chance to drop an ingredient or a valuable",
    "Faster Learner": "Slightly more operator XP. Stacks with Fast Learner",
    "Operator Tracker": "Track enemy operators by their footprints",
    "Quick Regen": "Health starts regenerating a little sooner",
    "Consumable Stacker": "Using a consumable that's already running adds to its time, up to twice as long",
    "Deep Breath": "Hold your breath longer underwater",
    "Lucky": "When you're hurt or short on supplies, you're more likely to find something useful",
    "Mechanic": "Refuel and repair vehicles twice as fast",
    "Objective Oriented": "Op reward crates are one rarity higher, up to Rare",
    "Plate Organization": "2 more reserve plates. Stacks with Plate Pouch",
    "Rad Blocker": "Less damage from radiation",
    "Rampage": "Killing an enemy operator gives you a short Painkiller effect",
    "Rescuer": "Move faster while dragging a downed teammate",
    "Strong Arm": "Throw equipment farther, with a line showing where it lands",
}
# Prestige traits: Pro versions of the row 6 and 9 Majors, random, up to three
TRAIT_PROS = [
    ("Adaptive Restock Pro", "Warfighter", "Hostiles drop rarer extra items"),
    ("Possum Pro", "Warfighter", "Self revive into Last Stand from death once a match, without the tourniquet's health penalty"),
    ("Quick Fix Pro", "Warfighter", "Health starts regenerating straight away when you kill an operator or hostile"),
    ("Viper Sense Pro", "Warfighter", "Hidden from thermal optics and AI targeting, and warned when an enemy operator aims at you"),
    ("Overwatch Pro", "Scout", "UAV Towers you activate never expire, and reach further"),
    ("UAV Upgrade Pro", "Scout", "Longer-lasting, longer-range Advanced UAVs, and a bigger minimap"),
    ("Thermal Padding Pro", "Scout", "Hidden from UAVs, and so is a vehicle you're in"),
    ("Field Crafting Pro", "Scout", "Craft from Common printer resources while deployed, for half the resources"),
    ("Free Revive Pro", "Survivalist", "Your first Wound repairs itself, and you can tourniquet while Wounded"),
    ("Numb the Pain Pro", "Survivalist", "Longer Painkiller and Smelling Salts effects on revives"),
    ("Impact Smokes Pro", "Survivalist", "Bigger, longer smoke when you're downed"),
    ("Die Hard Pro", "Survivalist", "Last Stand calls an exfil you reach, never bleeds out, and moves faster"),
]
TRAITS_INTRO = ("Each operator has three trees, Warfighter, Scout and Survivalist, of nine rows, climbed from the bottom one trait a row. "
                "Rows 3, 6 and 9 are a choice of two Major traits, the same for everyone. The other rows offer three Minor traits picked at random for "
                "each operator, from the lists below; a row shows once you take one from the row under it, and some Minors turn up in more than one tree. "
                "Each operator earns 18 points, one per dog tag rank from Steel I to Onyx III, so two full trees; there's no respec. "
                "Prestiging an operator resets its trees and gives it a random Prestige trait (a Pro Major), up to three; from the fourth Prestige you can swap one.")

def traits_wiki(guide, traits):
    """The Traits section as a list of everything each tree can roll."""
    import os
    icons = {os.path.basename(f)[:-4] for f in __import__("glob").glob(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "..", "Images", "DMZ", "traits", "*.png"))}
    known = {t["name"]: t.get("effect") for t in traits.values() if t.get("name")} | dict(UNPLACED)
    def row(name, group, value=None, effect=None):
        effect = effect or TRAIT_EFFECTS.get(name) or known.get(name)
        assert effect, f"no effect for trait {name}"
        r = {"title": name, "subtitle": effect, "group": group}
        if value: r["value"] = value
        if item_id(name) in icons: r["image"] = TRAIT_IMG + item_id(name) + ".png?v=2"
        return r
    rows = []
    for tree in ("Warfighter", "Scout", "Survivalist"):
        rows += [row(n, f"{tree}: fixed", f"Row {r}") for n, r in TRAIT_MAJORS[tree]]
        rows += [row(n, f"{tree}: random") for n in TRAIT_MINORS[tree]]
    rows += [row(n, "Prestige traits", tree, effect) for n, tree, effect in TRAIT_PROS]
    sec = next(s for s in guide if s["id"] == "traits")
    sec["intro"] = TRAITS_INTRO
    sec["rows"] = rows

def build_traits(guide):
    import os
    icons = {os.path.basename(f)[:-4] for f in __import__("glob").glob(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "..", "Images", "DMZ", "traits", "*.png"))}
    traits = {}
    for name, tree, effect in TRAITS:
        tid = item_id(name)
        traits[tid] = {"id": tid, "name": name, "tree": tree, "effect": effect}
    for tid, name, tree, effect in EXTRA_TRAITS:
        t = traits.setdefault(tid, {"id": tid, "tree": tree})
        if name: t["name"] = name
        if effect: t["effect"] = effect
    for t in traits.values():
        if t["id"] in icons: t["icon"] = TRAIT_IMG + t["id"] + ".png?v=2"
    placed = {x for tr in TRAIT_TREES for row in tr["rows"] for x in row if x} | {tr["emblem"] for tr in TRAIT_TREES}
    missing = placed - set(traits)
    assert not missing, missing
    sec = next(s for s in guide if s["id"] == "traits")
    sec["intro"] = ("Each operator has three trees: Warfighter, Scout and Survivalist. You pick one trait per row, 9 per tree and 18 at most, "
                    "with points from levelling your operator's dog tag (about 1,900 XP a point at Silver). The two-choice rows are fixed; "
                    "the three-choice rows (five of the eight) are random for each operator and show once you take a trait from the row above. "
                    "There's no reroll: the random rows seem to change only when you prestige the operator. "
                    "Scout is shown as one example, from Ghost; yours will differ in the random rows. Tap any trait to see what it does.")
    rows = []
    for t in traits.values():
        if not t.get("name"): continue
        rows.append({"title": t["name"], "subtitle": t.get("effect", ""), "group": t["tree"]})
    order = {"Warfighter": 0, "Scout": 1, "Survivalist": 2}
    rows.sort(key=lambda r: order.get(r["group"], 3))
    for name, effect in UNPLACED:
        rows.append({"title": name, "subtitle": effect, "group": "Not placed in a tree yet"})
    sec["rows"] = rows
    # the app shows the wiki list; the trees stay for older app versions
    traits_wiki(guide, traits)
    return TRAIT_TREES, sorted(traits.values(), key=lambda t: t["id"])

def group_bosses(guide):
    sec = next(s for s in guide if s["id"] == "bosses")
    rows = sec["rows"]
    for r in rows:
        kind = r.pop("value", None)
        r["group"] = "Commanders" if kind == "Commander" else "Lieutenants"
        r["check"] = "boss-" + item_id(r["title"])
    rows.sort(key=lambda r: r["group"] != "Lieutenants")
    sec["intro"] = sec.get("intro", "") + " Tick a boss once you've taken it down."

def check_upgrades(guide):
    sec = next(s for s in guide if s["id"] == "upgrades")
    for r in sec["rows"]:
        r["check"] = "upgrade-" + item_id(r["title"])
    sec["intro"] = sec.get("intro", "") + " Tick the ones you've printed; Keep or sell then stops counting what they needed."

# ---- 2026-10-20 evening sweep: dmzhub.gg, dmzcodex.com, gamerfuzion, mw4map
AREA_PARTS = {
 "14th Political Prison": "Inside: Prison (High), The Fortress Prison Yard (High), The Citadel (Critical).",
 "Chang-san Air Base": "Inside: Air Base Exterior (Critical), Air Base Bunker (Extreme), Admin Complex No. 2.",
 "Deadtown": "Inside: Deadtown Exterior (Low), Re-Education Center (Medium).",
 "Imjin Farmland": "Inside: Farmland Exterior (Low), Jeong Loading Dock (Low), Rice Mill (Medium).",
 "Cheongun Village": "Inside: Cheongun Outskirts (Low), Russian Border Crossing (Low), Heavenly Luck Casino (High).",
 "Haneul Nuclear Reactor": "Inside: Reactor (High, worst radiation), South Korean Border Zone (Medium).",
 "NuriGo Mall": "Inside: NuriGO East (Medium), NuriGO West (High), City Hall, Han-Go Korean BBQ.",
 "The Grid": "Inside: Nenshin Tech Complex (Extreme), Construction Zone, DBN Headquarters, Hanex Bank, Minsok Art School (all Critical), Donpyeong Gate, Hotel Lucera.",
 "Songdo Wharf": "Inside: Shoreline Station (Low), Oamsik Turtle Island (Low), La Grande Vie tower.",
 "Wolves Stadium": "Inside: Theatre (Medium), Baseball Stadium B Station, Ginyeom-il Bridge.",
 "Hajin River Heights": "Inside: Jinseo Park Towers (Medium), South Island (Medium), Compound Echo.",
}
OPS = [
 ("Story Missions", "Critical Extraction", "$25,000", "Mirae General Hospital. Locate the HVT, eliminate any resistance, extract the HVT. Also a Defibrillator"),
 ("Story Missions", "Silent Ledger", "$25,000", "Heavenly Luck Casino, Cheongun Village. Enter the casino, breach the vault, secure the printing plates. Also a Gold Bar and a Polaris Dagor A1"),
 ("Story Missions", "Shopping Hacks", "$25,000", "NuriGO Mall, Lieutenant Jang-ui's encampment. Hack the network, program the protocol, secure any evidence. Also Night Vision Goggles"),
 ("Story Missions", "Iron Citadel", "LTV", "Unlocks the LTV for deployment"),
 ("Story Missions", "Grid Assault", "Heli", "Unlocks the Helicopter for deployment"),
 ("Story Missions", "Weekly Story Missions", "Weekly", "Finish a random one three times a week for the weekly rewards"),
 ("DMZ Orders", "Chapter 1", None, "Gear Up, Crack Shot, First OP"),
 ("DMZ Orders", "Counterfeit: Hostile Force", "Caliber", "Enter a Police Station, search 3 containers inside, eliminate 5 soldiers inside"),
 ("DMZ Orders", "Counterfeit: Robbery", "Caliber", "Open a safe, then extract with $5,000 of backpack and loadout value"),
 ("DMZ Orders", "Counterfeit: Execute Intel", "Caliber", "Hack a UAV Tower in Deadtown, kill 5 North Korean soldiers it pings, loot the counterfeit cash they drop. Finishing the page gives the Recon Drone recipe"),
 ("DMZ Orders", "Underground", None, "Eye in the Sky, Joyride, and placing a Transmitter on top of La Grande Vie in Songdo Wharf"),
 ("DMZ Orders", "Human Intel: Hunter", None, "Climb a Lieutenant Tower and use the terminal at the top to find the nearest Lieutenant"),
 ("DMZ Orders", "Human Intel: Triage Protocol", None, "Head to a Clinic, loot a Bandage and 30 Chemicals"),
 ("DMZ Orders", "Human Intel: No One Left", None, "Clear a Compound and loot the Medical Extraction Intel it drops"),
 ("DMZ Orders", "Chapter 2", None, "Eye in the Sky, Watch for Bumps, Triangulation, Dead Battery, Death from Above, Operation Shopping Hacks"),
 ("Dynamic Ops", "Dynamic Operations", "$10-20K", "Paid into your Bank per op, plus a Supply Drop that improves with each success in the same deployment"),
 ("Dynamic Ops", "Dead Man's Cache", None, "Cheongun Outskirts. Find the enemy comms server and collect the Encrypted Drive"),
 ("Dynamic Ops", "Chemical Denial", None, "Investigate the power outage at the Tank Depot and Chang-san Air Base bunker"),
 ("Dynamic Ops", "Hunt Operators", None, "Take out a rival squad of Operators"),
 ("Dynamic Ops", "Broken Resupply", None, "Hack the comms server"),
 ("Dynamic Ops", "Signal Breaker", None, "Head to the target area"),
 ("Side Ops", "Paid Intel", "+$500", "Reach Lieutenant Bale at the Tank Depot and kill him"),
 ("Side Ops", "Capture a SAM Site", None, "Hack the SAM control computer and defend it while it runs. A captured SAM shoots enemy aircraft, Deathstalker included, until enemies retake it"),
 ("Side Ops", "Activate UAV Tower", None, "Turn on a UAV Tower to see enemies nearby"),
 ("Side Ops", "Download Intel to Locate Lieutenant", None, "Download the intel to find a Lieutenant"),
 ("Side Ops", "Secure Lost Supply Drop", None, "Find and open a lost supply drop"),
 ("Side Ops", "Repair a Truck", None, "Fix a useful truck you come across"),
 ("Other", "Robbery", None, "Extract $5,000 in cash value"),
 ("Other", "Reduce Bounty", "$5,000", "At a Bounty Station. Four kills make you Wanted"),
]
VEHICLES = [
 ("Ground", "Polaris Dagor A1", "Drivable. $5,000 to infil in; also a Silent Ledger reward"), ("Ground", "LTV", "Drivable. $25,000 to infil in once Iron Citadel unlocks it"),
 ("Ground", "Camper", "Drivable"), ("Ground", "Sedan", "Drivable"), ("Ground", "Grizzly", "Drivable"), ("Ground", "Dreadnought", "Drivable"),
 ("Ground", "Cargo Truck", "Drivable"), ("Ground", "D50 Radar Flatbed", "Drivable"),
 ("Water", "RHIB", "Drivable boat. Refuel at Marine Gas Stations"),
 ("Air", "Heli", "Flyable. $50,000 to infil in once Grid Assault unlocks it"), ("Air", "Heavy Chopper", "Rarely flyable"),
 ("Air", "Monarch", "Not player-controlled"), ("Air", "Cargo Plane", "Not player-controlled. $100,000 infil that lets you pick your drop point"),
 ("Rail", "Train", "Runs a fixed route; not player-controlled"), ("Rail", "Tram / monorail", "Loops round Hajin City; not player-controlled"),
]
ENEMIES = [
 ("Infantry", "Tier 1 North Korean Grunts", "The basic soldiers"), ("Infantry", "Tier 2 Armored Soldiers", "Wear armor"),
 ("Infantry", "Tier 3 Armored Gas-Masked Soldiers", "Armor and gas masks"), ("Infantry", "Tier 4 Faceless Armored Soldiers", "The toughest regular troops"),
 ("Infantry", "Juggernaut", "Heavy infantry"), ("Response", "Hunt Squad", "Comes after you once you've killed enough; Stealthy delays it"),
 ("Response", "Elite Strike Team", "A response force"), ("Response", "Lieutenant Escort", "Guards a Lieutenant"), ("Response", "Road Convoys", "Armed convoys on the roads"),
 ("Drones & air", "Attack Infantry Helicopter Patrol", "Air patrol"), ("Drones & air", "Combat Drone Swarm", "Drone swarm"),
 ("Drones & air", "LMG Combat Drone", "Armed drone"), ("Underground", "Autonomous K9", "Robot dogs underground"),
 ("Players", "Rival Operators", "Other squads in Hajin"),
]
KITS = [
 ("Weapon Insurance Contract", None, "Get back an insured weapon you lose, up to the number of contracts you hold. Two come with the Vault Edition"),
 ("Operator Rescue Beacon", None, "Recover an MIA operator without paying DMZ Cash. Two come with the Vault Edition"),
 ("Fulton Drop Marker", "$2,500", "A balloon that sends gear out of Hajin without an exfil"),
 ("Triage Kit", "Lv 27", "Bandages, Medkits, Self-Revives, Pain Killers and an Epic consumable"),
 ("Vault Edition Deployment Kit", "Vault", "2 Weapon Insurance Contracts, 2 Operator Rescue Beacons, 2 Fulton Drop Markers, 2 Medium Backpacks, 2 two-plate carriers"),
 ("Opening kits", None, "Kits come from levels, Orders, missions and events. Open them at the Survival Kits station in your FOB; unopened kits stack without limit"),
]
EFFECTS = {
 "bandage": "Restores max health for 180 seconds after you're hurt",
 "medkit": "Permanently restores the health you've lost to a wound",
 "radiation-blockers": "Cuts the effects of radiation for a minute",
}

def sweep_oct20(guide, markers, items):
    for m in markers:
        if m["cat"] == "area" and m["name"] in AREA_PARTS:
            levels = {"Low": 1, "Medium": 2, "High": 3, "Critical": 4, "Extreme": 5}
            parts = []
            text = AREA_PARTS[m["name"]].removeprefix("Inside: ").rstrip(".")
            # "A, B (all Critical)" gives every name before it that level
            for chunk in _re.split(r",\s*(?![^()]*\))", text):
                mm = _re.match(r"(.+?)(?: \((?:all )?(\w+)(?:,[^)]*)?\))?$", chunk.strip())
                name, lvl = mm.group(1), levels.get(mm.group(2) or "")
                parts.append({"name": name, **({"threat": lvl} if lvl else {})})
            if "(all Critical)" in text:
                for part in parts:
                    if part["name"] in ("Construction Zone", "DBN Headquarters", "Hanex Bank", "Minsok Art School"): part["threat"] = 4
            m["parts"] = parts
        if m["name"] == "Deadtown" and m["cat"] == "area": m["threat"] = 2
    sec = {s["id"]: s for s in guide}
    sec["ops"]["title"] = "Missions & Ops"
    sec["ops"]["rows"] = [dict({"title": t, "subtitle": s, "group": g}, **({"value": v} if v else {})) for g, t, v, s in OPS]
    for r in sec["bosses"]["rows"]:
        extra = {"Bale": " Carries the Dreadnought, a Legendary LMG worth about $16,000.",
                 "Gorani": " Uses an M4.",
                 "Roze": "Holds a dark parking garage with a scoped rifle",
                 "Colossus": " The minigun fires depleted uranium rounds."}.get(r["title"])
        if extra:
            r["subtitle"] = extra if r["title"] == "Roze" else r.get("subtitle", "") + extra
    i = next(k for k, s in enumerate(guide) if s["id"] == "infil") + 1
    guide.insert(i, {"id": "vehicles", "title": "Vehicles", "symbol": "car.fill",
        "intro": "What moves in Hajin. Refuel at Gas Stations (boats at Marine Gas Stations).",
        "rows": [{"title": t, "subtitle": s, "group": g} for g, t, s in VEHICLES]})
    i = next(k for k, s in enumerate(guide) if s["id"] == "bosses") + 1
    guide.insert(i, {"id": "enemies", "title": "Enemies", "symbol": "figure.stand",
        "intro": "Regular troops come in four tiers, each tougher than the last.",
        "rows": [{"title": t, "subtitle": s, "group": g} for g, t, s in ENEMIES]})
    i = next(k for k, s in enumerate(guide) if s["id"] == "valuables") + 1
    guide.insert(i, {"id": "kits", "title": "Survival kits", "symbol": "shippingbox.and.arrow.backward.fill",
        "rows": [dict({"title": t, "subtitle": s}, **({"value": v} if v else {})) for t, v, s in KITS]})
    for it in items:
        if it["id"] in EFFECTS: it["effect"] = EFFECTS[it["id"]]
    # keys: the new one becomes an item too
    if not any(i["id"] == "air-base-drc-weapons-locker" for i in items):
        items.append({"id": "air-base-drc-weapons-locker", "name": "Air Base DRC Weapons Locker", "kind": "Key", "rarity": "Ultra",
                      "symbol": "key.fill", "grid": "B6", "value": 100, "marker": "k-airbase-drc",
                      "note": "The DRC Weapons Locker in the secure armory deep in the Chang-san Air Base bunker"})
    for r in sec["keys"]["rows"]:
        r.setdefault("item", item_id(r["title"]))
    tr = sec["traits"]
    tr["intro"] = tr["intro"].replace("show once you take a trait from the row above", "show once you take a trait from the row below (trees are climbed from the bottom)")

def relink(guide, items, section_ids):
    names = sorted(((i["name"], i["id"]) for i in items if i["kind"] != "Resource"), key=lambda x: -len(x[0]))
    for s in guide:
        if s["id"] not in section_ids: continue
        for r in s["rows"]:
            text = (r["title"] + " . " + r.get("subtitle", "")).lower()
            found, taken = [], []
            for name, iid in names:
                for m in _re.finditer(r"(?<![\w-])" + _re.escape(name.lower()) + r"(?![\w-]| tower)", text):
                    if any(a < m.end() and m.start() < b for a, b in taken): continue
                    taken.append((m.start(), m.end()))
                    if iid not in found: found.append(iid)
            if found: r["links"] = found

# ---- Polish: a symbol for every item without a picture, tidier text
ITEM_SYMBOLS = {
 "stash-item-upgrade-i": "archivebox.fill", "stash-item-upgrade-ii": "archivebox.fill", "stash-item-upgrade-iii": "archivebox.fill", "stash-weapon-upgrade-i": "scope", "mia-recovery-discount-i": "cross.case.fill", "mia-recovery-discount-ii": "cross.case.fill",
 "bank-upgrade-iii": "building.columns.fill", "bank-upgrade-iv": "building.columns.fill", "bank-upgrade-i": "building.columns.fill", "bank-upgrade-ii": "building.columns.fill", "gunsmith-upgrade-i": "wrench.and.screwdriver.fill", "vendor-item-upgrade-i": "cart.fill",
 "uncommon-ingredient-printing": "printer.fill", "epic-ingredient-printing": "printer.filled.and.paper", "dog-tag-case-upgrade-i": "tag.fill", "dog-tag-case-upgrade-ii": "tag.fill",
 "cpu": "cpu.fill", "comms-module": "antenna.radiowaves.left.and.right", "control-unit": "slider.horizontal.3",
 "electronic-sensors": "sensor.fill", "structural-alloy": "cube.fill", "printed-circuit-board": "memorychip.fill",
 "nitro-compounds": "flame.fill", "high-tenacity-fibers": "wind", "nylon-cloth": "tshirt.fill",
 "alloyed-plating": "square.stack.3d.up.fill", "experimental-compounds": "testtube.2", "stabilized-reagents": "flask.fill",
 "nano-structured-alloy": "circle.hexagongrid.fill", "turned-components": "gearshape.2.fill", "prototype-rf-module": "dot.radiowaves.left.and.right",
 "regional-combat-notes": "doc.text.fill", "infantry-invasion-plans": "map.fill", "power-regulator": "bolt.fill",
 "concussion-grenade": "burst.fill", "frag-grenade": "circle.circle.fill", "c4": "bolt.horizontal.fill", "zip-gun": "scope",
 "drill-charge": "screwdriver.fill", "trip-wire": "line.diagonal", "sticky-grenade": "drop.fill", "molotov-cocktail": "flame.fill",
 "thermite": "sparkles", "ammo-box": "shippingbox.fill", "portable-radar": "dot.radiowaves.up.forward", "riot-shield": "shield.fill",
 "ddos": "wifi.slash", "inflatable-decoy": "person.fill.questionmark", "care-package": "arrow.down.circle.fill"
 , "uav": "airplane", "railgun-sentry": "scope", "gas-mask": "aqi.medium", "disposable-parachute": "arrow.down.circle.fill",
 "bomb-glider": "paperplane.fill", "recon-drone": "airplane.circle.fill", "medium-secure-backpack": "bag.fill",
 "night-vision-goggles": "binoculars.fill", "defibrillator": "bolt.heart.fill", "bales-dog-tag": "tag.fill", "scavengers-dog-tag": "tag.fill",
 "spotter-scope": "binoculars.fill", "throwing-knife": "line.diagonal.arrow",
}
KIND_SYMBOLS = {"Ingredient": "cube.fill", "Lethals": "flame.fill", "Tacticals": "eye.fill", "Field Upgrades": "shield.lefthalf.filled",
                "Fire Support": "airplane", "Gear": "bag.fill", "Valuable": "diamond.fill", "Backpacks": "bag.fill",
                "Plate Carriers": "shield.fill", "Consumables": "cross.vial.fill", "Other": "cube.fill", "FOB Upgrade": "arrow.up.circle.fill"}

def polish(guide, items):
    for it in items:
        if "image" not in it and "symbol" not in it:
            it["symbol"] = ITEM_SYMBOLS.get(it["id"]) or KIND_SYMBOLS.get(it["kind"], "cube.fill")
    sec = {s["id"]: s for s in guide}
    for s in guide:
        for r in s["rows"]:
            sub = r.get("subtitle")
            if sub:
                # sentences glued on without a full stop
                r["subtitle"] = _re.sub(r"([a-z0-9)])  ?([A-Z][a-z]+ (?:an|a|the) )", r"\1. \2", sub.replace("Village Uses", "Village. Uses"))
    for r in sec["gunsmith"]["rows"]:
        r["subtitle"] = "Starter weapon" if r.get("subtitle", "").startswith("Unlocked") else "Needs its Weapon Manual"

# ---- FOB upgrades in families, tier by tier
UPGRADE_GROUPS = [  # (name prefix, family, station group)
 ("Stash Item Upgrade", "Stash Item Upgrade", "Stash"), ("Stash Weapon Upgrade", "Stash Weapon Upgrade", "Stash"),
 ("Bank Upgrade", "Bank Upgrade", "Bank"), ("Gunsmith Upgrade", "Gunsmith Upgrade", "Gunsmith"),
 ("Vendor Item Upgrade", "Vendor Item Upgrade", "Vendor"), ("Uncommon Ingredient Printing", "Ingredient Printing", "3D Printer"),
 ("Epic Ingredient Printing", "Ingredient Printing", "3D Printer"), ("MIA Recovery Discount", "MIA Recovery Discount", "Operators"),
 ("Dog Tag Case Upgrade", "Dog Tag Case Upgrade", "Dog Tag Case"),
]
ROMAN = {"I": 1, "II": 2, "III": 3, "IV": 4, "V": 5, "VI": 6, "VII": 7, "VIII": 8, "IX": 9}

def tier_upgrades(guide, items):
    sec = next(s for s in guide if s["id"] == "upgrades")
    by_id = {i["id"]: i for i in items}
    order = [g for _, _, g in UPGRADE_GROUPS]
    def place(title):
        for prefix, family, group in UPGRADE_GROUPS:
            if title.startswith(prefix):
                tail = title[len(prefix):].strip()
                tier = ROMAN.get(tail) or (1 if "Uncommon" in title else 2 if "Epic" in title else 1)
                return family, group, tier
        return title, "Other", 1
    for r in sec["rows"]:
        family, group, tier = place(r["title"])
        r["group"] = group
        it = by_id.get(r.get("item", ""))
        if it:
            it["family"] = family; it["tier"] = tier
    sec["rows"].sort(key=lambda r: (order.index(r["group"]) if r["group"] in order else 99,
                                    [f for _, f, _ in UPGRADE_GROUPS].index(by_id[r["item"]]["family"]) if r["item"] in by_id and by_id[r["item"]].get("family") in [f for _, f, _ in UPGRADE_GROUPS] else 99,
                                    by_id.get(r["item"], {}).get("tier", 1)))

# Sell prices listed on dmzcodex.com item pages (2026-10-21) for ingredients
# the in-game screens we read didn't price
SELL_VALUES = {"biomaterials": 800, "cpu": 500, "infantry-invasion-plans": 1000, "military-composites": 3500,
               "nuclear-program-files": 2000, "nylon-cloth": 1000,
               # from the user, read in game (2026-10-22)
               "alloyed-plating": 1500, "ballistic-fabric": 1500, "binding-catalyst": 500, "comms-module": 1500,
               "control-unit": 200, "degraded-execution-footage": 2000, "detonators": 200, "experimental-compounds": 3500,
               "nitro-compounds": 500, "nylon-laminate": 1500, "printed-circuit-board": 500, "regional-combat-notes": 1000,
               "stabilized-reagents": 1500, "structural-alloy": 500,
               # listed on dmzcodex.com item pages (2026-10-23)
               "turned-components": 1500, "volatile-explosives": 1500,
               # lieutenant dog tags: $25,000 each on the extraction summary (2026-10-28)
               "bales-dog-tag": 25000, "iskras-dog-tag": 25000, "jin-taes-dog-tag": 25000, "rozes-dog-tag": 25000,
               "scavengers-dog-tag": 25000, "the-doctors-dog-tag": 25000, "goranis-dog-tag": 25000,
               "lieutenant-dog-tag-case": 25000,
               # the manual's tooltip: "WEAPON MANUAL | $5000"
               "weapon-manual": 5000}

def sell_values(items):
    for it in items:
        if it["id"] in SELL_VALUES and not it.get("value"):
            it["value"] = SELL_VALUES[it["id"]]


def new_pictures(items):
    import glob, os
    have = {os.path.basename(f)[:-4] for f in glob.glob(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "..", "Images", "DMZ", "*.png"))}
    for it in items:
        if "image" not in it and it["id"] in have:
            it["image"] = IMG_BASE + it["id"] + (".png?v=2" if it["id"] in ("bales-dog-tag",) else ".png?v=1")
            it.pop("symbol", None) if it["kind"] != "Key" else None


KEY_PICTURE_BY_RARITY = {"Epic": "vault-armory", "Rare": "haksan-school-armory", "Legendary": "iskras-control-room",
                         "Ultra": "air-base-drc-weapons-locker", "Uncommon": "the-citadel-south-wing"}

def key_pictures(items):
    for it in items:
        if it["kind"] == "Key" and "image" not in it and it.get("rarity") in KEY_PICTURE_BY_RARITY:
            it["image"] = IMG_BASE + KEY_PICTURE_BY_RARITY[it["rarity"]] + ".png?v=1"

# ---- Missions & Ops as structured cards: place, objectives, rewards, tick
MISSIONS = [
 # group, title, place, objectives, cash, item ids, other rewards
 ("Story Missions", "Operation Critical Extraction", "Mirae General Hospital", ["Locate the HVT (Jin-Tae)", "Eliminate any resistance", "Extract the HVT"], 25000, ["defibrillator"], []),
 ("Story Missions", "Operation Silent Ledger", "Heavenly Luck Casino, Cheongun Village", ["Enter the casino", "Breach the vault", "Secure the printing plates"], 25000, ["gold-bar"], ["Polaris Dagor A1"]),
 ("Story Missions", "Operation Shopping Hacks", "NuriGO Mall, Jang-ui's encampment", ["Hack the network", "Program the protocol", "Secure any evidence"], 25000, ["night-vision-goggles", "coin-mining-den"], []),
 ("Story Missions", "Operation Iron Citadel", "Chang-san Air Base", ["Approach the air base and find an Airbase Access Card", "Upgrade the card at the marked server", "Find the armory doors inside the bunker", "Recover the three keycode parts and open the armory", "Collect the armory manifest", "Plant explosives in the armory", "Plant explosives on three strike aircraft", "Capture the SAM site", "Exfil with the armory manifest"], 25000, ["supreme-leaders-bunker-access-card"], ["Unlocks the LTV infil ($25,000)"]),
 ("Story Missions", "Operation Grid Assault", "The Grid", ["Find the drone control at DBN Headquarters", "Recover the first and second code segments", "Compile the code", "Upload the code", "Broadcast the kill code"], 25000, ["rozes-high-rise-armory"], ["Unlocks the Helicopter infil ($50,000)"]),
 ("Story Missions", "Operation Fallen Ember", "Haneul Nuclear Reactor (Extreme)", ["Breach the reactor", "Secure the rods", "Extract the decontaminated rods"], 25000, ["reactor-drc-locker", "gas-mask"], ["Unlocks the Cargo Plane infil ($100,000)", "Bring radiation gear: hazmat suits hang on the reactor walls"]),
 ("DMZ Orders: Chapter 1", "Gear Up", None, ["Equip a weapon, a backpack, an armor vest and a medkit from your stash"], None, [], []),
 ("DMZ Orders: Chapter 1", "Crack Shot", None, ["Knock down three firing-range targets"], None, [], []),
 ("DMZ Orders: Chapter 1", "First OP", None, ["Deploy to DMZ in Dynamic Operations"], None, [], []),
 ("DMZ Orders: Counterfeit", "Hostile Force", "Any Police Station", ["Enter a Police Station", "Search 3 containers inside", "Eliminate 5 soldiers inside"], None, ["recon-drone"], ['Page reward: the Recon Drone recipe']),
 ("DMZ Orders: Counterfeit", "Robbery", "Compounds and locked rooms", ["Open a safe", "Extract with $5,000 of backpack and loadout value"], None, ["recon-drone"], ['Page reward: the Recon Drone recipe']),
 ("DMZ Orders: Counterfeit", "Execute Intel", "Deadtown", ["Hack a UAV Tower in Deadtown", "Kill 5 North Korean soldiers it pings", "Loot the counterfeit cash they drop"], None, ["recon-drone"], ['Page reward: the Recon Drone recipe']),
 ("DMZ Orders: Counterfeit", "Eyes Everywhere", "Heavenly Luck Casino", ["Print a Recon Drone", "Mark 10 enemies in Heavenly Luck Casino with it"], None, ["recon-drone"], ['Page reward: $20,000, an Operator Rescue Beacon and a Weapon Insurance Contract']),
 ("DMZ Orders: Counterfeit", "Suit Breach", None, ["Eliminate 15 enemies wearing hazmat suits"], None, [], ['Page reward: $20,000, an Operator Rescue Beacon and a Weapon Insurance Contract']),
 ("DMZ Orders: Human Intel", "Hunter", "Any Lieutenant Tower", ["Climb a Lieutenant Tower", "Use the terminal at the top to find the nearest Lieutenant"], None, [], []),
 ("DMZ Orders: Human Intel", "Triage Protocol", "Any Clinic", ["Head to a Clinic", "Loot a Bandage", "Loot 30 Chemicals"], None, [], []),
 ("DMZ Orders: Human Intel", "No One Left", "Any Compound", ["Clear a Compound", "Loot the Medical Extraction Intel it drops"], None, [], []),
 ("DMZ Orders: Human Intel", "Blindness", None, ["Print 4 Flash grenades", "Kill 8 flashed enemies"], None, ["flash"], []),
 ("DMZ Orders: Human Intel", "Payment Due", None, ["Collect a Dynamic Op Phone", "Earn $11,500 from Dynamic Ops"], None, [], []),
 ("DMZ Orders: Underground", "Eye in the Sky", "Any SAM site", ["Take control of a SAM site", "Have the SAM destroy a cargo helicopter", "Loot the crate the helicopter drops"], None, ["ddos", "decoy-grenade", "night-vision-goggles"], ['Page reward: DDOS, Decoy Grenade and Night Vision Goggle recipes, and $20,000']),
 ("DMZ Orders: Underground", "Watch for Bumps", None, ["Steal an enemy vehicle", "Refuel and repair a vehicle at a gas station", "Run over 7 enemies in a vehicle"], None, ["ddos", "decoy-grenade", "night-vision-goggles"], ['Page reward: DDOS, Decoy Grenade and Night Vision Goggle recipes, and $20,000']),
 ("DMZ Orders: Underground", "Triangulation", "Radio towers, La Grande Vie in Songdo Wharf", ["Place a transmitter on top of 2 radio towers", "Place a transmitter on top of La Grande Vie in Songdo Wharf"], None, ["ddos", "decoy-grenade", "night-vision-goggles"], ['Page reward: DDOS, Decoy Grenade and Night Vision Goggle recipes, and $20,000']),
 ("DMZ Orders: Underground", "Dead Battery", None, ["Print a DDOS field upgrade", "Disable 3 enemy vehicles or drones with it"], None, ["ddos"], ['Page reward: $20,000 and a Basic Restock Kit']),
 ("DMZ Orders: Underground", "Death from Above", None, ["Distract a drone with a Decoy Grenade", "Destroy 3 drones", "Collect a Drone Motherboard from a destroyed drone"], None, ["decoy-grenade"], ['Page reward: $20,000 and a Basic Restock Kit']),
 ("DMZ Orders: The Grid", "I'm Over Here", None, ["Distract a drone with an Inflatable Decoy", "Destroy 8 Combat Drones", "Destroy 3 Heavy Combat Drones"], None, ["inflatable-decoy", "combat-drone"], []),
 ("DMZ Orders: The Grid", "Worth Every Penny", None, ["Buy a weapon from the Vendor", "Kill 50 enemies with a Rare or better weapon"], None, [], []),
 ("DMZ Orders: The Grid", "No Time", None, ["Finish a Dynamic Operation in under 8 minutes"], None, [], []),
 ("DMZ Orders: The Grid", "Opulent", None, ["Finish 6 Side Ops in one deployment"], None, [], []),
 ("DMZ Orders: The Grid", "Civil Service", "City Hall, NuriGO Mall", ["Enter NuriGO Mall", "Find City Hall", "Extract the Financial Ledger Fragments from City Hall's second floor"], None, [], ["The page ends with Operation Grid Assault"]),
 ('DMZ Orders: Page 10', 'Crashed Crate', None, ['Retrieve 3 lost supply drops', 'Complete a Loot Radio Tower Side Op'], None, [], ['Page reward: $20,000, a Large Backpack and a Basic Triage Kit']),
 ('DMZ Orders: Page 10', 'Surprise Me', None, ['Complete 5 Dynamic Ops', 'Complete a Story Mission using Random Mission Deploy'], None, [], ['Page reward: $20,000, a Large Backpack and a Basic Triage Kit']),
 ('DMZ Orders: Page 10', 'Healer', None, ['Print or extract 3 Reactive Metals', 'Extract 30 Metals', 'Print an Armor Box'], None, ['reactive-metals', 'metals', 'armor-box'], ['Page reward: $20,000, a Large Backpack and a Basic Triage Kit']),
 ('DMZ Orders: Page 11', 'Information Power', None, ['Buy Lieutenant intel at the Boss Board', 'Kill a Lieutenant'], None, [], ['Page reward: $20,000, a Defibrillator, an Inflatable Decoy and the C4 recipe']),
 ('DMZ Orders: Page 11', 'Arms Deal', None, ['Buy a gun at the Gunsmith', 'Equip a weapon with at least 3 attachments'], None, [], ['Page reward: $20,000, a Defibrillator, an Inflatable Decoy and the C4 recipe']),
 ('DMZ Orders: Page 11', 'Friendly Face', None, ['Choose Request Truce on the ping wheel'], None, [], ['Page reward: $20,000, a Defibrillator, an Inflatable Decoy and the C4 recipe']),
 ('DMZ Orders: Page 14', 'Lethal Tools', None, ['Print 6 Lethals', 'Kill 13 enemy soldiers with Lethals'], None, [], ['Page reward: $20,000, 2 Structural Alloy and 2 Stock Rod']),
 ('DMZ Orders: Page 14', 'Committed', None, ['Extract after the radiation starts spreading'], None, [], ['Page reward: $20,000, 2 Structural Alloy and 2 Stock Rod']),
 ('DMZ Orders: Page 14', 'Nothing Is Secure', None, ['Open 4 safes', 'Extract with at least $20,000 of backpack and loadout value'], None, [], ['Page reward: $20,000, 2 Structural Alloy and 2 Stock Rod']),
 ('DMZ Orders: Radiation and medical page', 'Recognition', None, ['Kill 15 enemies with an unsuppressed weapon in a High threat location'], None, [], ['Page reward: $20,000, a UAV and an Armor Box']),
 ('DMZ Orders: Radiation and medical page', 'Radiation Station', 'Any Fire Station', ['Find a Fire Station', 'Loot 3 Gas Masks or Radiation Pill Bottles', 'Search 5 containers while in radiation'], None, ['gas-mask'], ['Page reward: $20,000, a UAV and an Armor Box']),
 ('DMZ Orders: Radiation and medical page', 'Healer', None, ['Track the Medkit recipe at the 3D Printer', 'Print a Medkit'], None, ['medkit'], ['Page reward: $20,000, a UAV and an Armor Box']),
 ('DMZ Orders: Operation Rewards page', 'Operation Rewards', 'Cheongun Village', ['Collect a Dynamic Op Phone in Cheongun Village', 'Complete the Dynamic Op', 'Loot the Dynamic Op crate'], None, [], []),
 ('DMZ Orders: Operation Rewards page', 'Preparation', None, ['Print a Medium Backpack', 'Print a 2-Plate Armor Vest'], None, ['medium-backpack', '2-plate-armor-vest'], []),
 ('DMZ Orders: Operation Rewards page', 'Work Quietly', None, ['Fit a suppressor to a weapon at the Gunsmith', 'Print a Throwing Knife', 'Kill 8 enemies in a row without taking damage'], None, ['throwing-knife'], []),
 ('DMZ Orders: Goliath page', 'Goliath', None, ['Hit Colossus with Thermite or a Drill Charge', 'Hit Colossus with a Shock Stick'], None, [], ['Page reward: $20,000, the Large Backpack recipe and a Weapon Restock Kit']),
 ('DMZ Orders: Goliath page', 'Click, Boom', None, ['Print 5 C4 charges', 'Kill 12 armored enemies with C4', 'Kill 5 enemies with one C4 blast'], None, ['c4'], ['Page reward: $20,000, the Large Backpack recipe and a Weapon Restock Kit']),
 ('DMZ Orders: Goliath page', 'Navigate With Care', None, ['Pay for a Polaris DAGOR A1 infil', 'Clear a North Korean convoy', 'Loot and extract the Chemical Components found after clearing a convoy'], None, [], ['Page reward: $20,000, the Large Backpack recipe and a Weapon Restock Kit']),
 ('DMZ Orders: Fire Insurance page', 'Fire Insurance', None, ['Print 5 Thermite Lethals', 'Stick 5 enemy vehicles with Thermite'], None, ['thermite'], ['Page reward: $20,000, 2 CPU, 2 Nylon Cloth and an Inflatable Decoy']),
 ('DMZ Orders: Fire Insurance page', 'Quiet', None, ['Loot 10 containers in The Grid without taking damage'], None, [], ['Page reward: $20,000, 2 CPU, 2 Nylon Cloth and an Inflatable Decoy']),
 ('DMZ Orders: Fire Insurance page', 'Mechanic', None, ['Repair a radar truck', 'Kill 19 enemies pinged by a radar truck'], None, [], ['Page reward: $20,000, 2 CPU, 2 Nylon Cloth and an Inflatable Decoy']),
 ('DMZ Orders: Jail Break page', 'Jail Break', None, ['Kill 15 enemies in the 14th Political Prison', 'Destroy a reinforcement helicopter', 'Kill 10 enemies in the Citadel'], None, [], ['Page reward: $20,000, an Armor Survival Kit (variant not confirmed), an Operator Rescue Beacon and a Weapon Insurance Contract']),
 ('DMZ Orders: Jail Break page', 'Keep Out', None, ['Kill 3 Lieutenants', "Loot a Lieutenant's key", "Enter a Lieutenant's room and loot the Lieutenant's gun"], None, [], ['Page reward: $20,000, an Armor Survival Kit (variant not confirmed), an Operator Rescue Beacon and a Weapon Insurance Contract']),
 # pages 18 to 23 from the Gamer's Heroes orders guide (2026-10-28); pages can differ by the route you take
 ('DMZ Orders: Page 18', 'How Bulletproof?', None, ['Kill 30 soldiers', 'Kill 15 armored soldiers', 'Kill 5 Lieutenants'], None, [], []),
 ('DMZ Orders: Page 18', 'Abandoned', 'NuriGO Mall', ['Kill 10 K9 enemies during Operation Shopping Hacks', 'Extract 3 Pristine Cores (reach the body before it explodes)'], None, [], []),
 ('DMZ Orders: Page 18', 'Locksmith', None, ['Find 5 keys (opening any 3 locked doors also counts)'], None, [], []),
 ('DMZ Orders: Page 19', 'Avionics', None, ['Find or print 5 Electronic Sensors and Structural Alloy', 'Print a UAV'], None, [], []),
 ('DMZ Orders: Page 19', 'Philanthropist', None, ['Complete the weekly Random Mission Deploy 3 times'], None, [], []),
 ('DMZ Orders: Page 19', 'Multi-Talented', None, ['Capture 6 SAM sites', 'Clear 4 Compounds', 'Open 12 Supply Drops (Care Packages count)'], None, [], []),
 ('DMZ Orders: Page 20', 'Ears Everywhere', 'Cheonwang Peak Array', ['Hack the Communications Broadcast System on the OBN TV building\'s second floor', 'Loot the Encrypted Voice Logs'], None, [], []),
 ('DMZ Orders: Page 20', 'The Vault', 'Wolves Stadium, Hanex Branch Bank', ['Find a Battery and put it in the Electric Panel', 'Take the Bank Branch Vault Access Key from behind the teller stations', 'Find the Note with 3 of the code\'s digits, then work out the last one at the vault'], None, [], []),
 ('DMZ Orders: Page 20', 'Massive Damage', None, ['Hit a tank with a DDOS 3 times', 'Destroy it with a rocket launcher (RPG or JOKR)'], None, [], []),
 ('DMZ Orders: Page 21', 'Hard Carry', None, ['Print or extract 2 Nylon Laminate (you can bring them in, drop them and pick them up)', 'Gather Structural Alloy', 'Print a Large Backpack'], None, [], []),
 ('DMZ Orders: Page 21', 'Stalking the Stalker', 'The Grid', ['Take a SAM site at the edge of The Grid', 'Kill the Deathstalkers, one with an RPG or JOKR'], None, [], []),
 ('DMZ Orders: Page 22', 'DRC', None, ['Loot a DRC Weapon Locker (Chang-san Air Base Armory, Haneul Nuclear Reactor or NuriGO Mall labs)'], None, [], []),
 ('DMZ Orders: Page 22', 'Unstoppable', None, ['Kill 10 Commanders', 'Kill 15 Lieutenants', 'Extract 5 Lieutenant Dog Tags'], None, [], []),
 ('DMZ Orders: Page 22', 'Astronaut', 'Haneul Nuclear Reactor', ['Loot containers at the reactor with at least a purple Gas Mask', 'Take the last exfil after the timer runs out'], None, [], []),
 ('DMZ Orders: Page 23', 'Rule of Three', None, ['Print or extract 2 Ballistic Fabric', 'Extract 5 Nylon Cloth', 'Print a 3-Plate Armor Vest'], None, [], []),
 ('DMZ Orders: Page 23', 'Temp Job', None, ['Complete 40 Side Ops'], None, [], []),
 ('DMZ Orders: Page 23', 'No Time', None, ['Complete 4 Dynamic Ops in one deployment'], None, [], []),
 ('DMZ Orders: Page 23, other route', 'Rule of Three', None, ['Extract 2 Weapon Manuals', 'Extract 4 Recipes', 'Extract 1 Ultra weapon'], None, [], []),
 ('DMZ Orders: Page 23, other route', 'Rule of Three', None, ['Build a Legendary sniper rifle with at least 5 attachments at the Gunsmith', 'Kill 100 enemies with it'], None, [], []),
 ('DMZ Orders: Page 23, other route', 'Rule of Three', None, ['Earn $250,000 from Story Missions or Dynamic Ops'], None, [], []),
 ("Dynamic Ops", "Dead Man's Cache", "Cheongun Outskirts", ["Find the enemy comms server", "Collect the Encrypted Drive"], None, [], ["$10,000 to $20,000", "Supply Drop"]),
 ("Dynamic Ops", "Chemical Denial", "Tank Depot, Chang-san Air Base bunker", ["Investigate the power outage"], None, [], ["$10,000 to $20,000", "Supply Drop"]),
 ("Dynamic Ops", "Hunt Operators", None, ["Take out a rival squad of Operators"], None, [], ["$10,000 to $20,000", "Supply Drop"]),
 ("Dynamic Ops", "Broken Resupply", None, ["Hack the comms server"], None, [], ["$10,000 to $20,000", "Supply Drop"]),
 ("Dynamic Ops", "Signal Breaker", None, ["Head to the target area"], None, [], ["$10,000 to $20,000", "Supply Drop"]),
 ("Side Ops", "Paid Intel", "Tank Depot", ["Reach Lieutenant Bale", "Kill Bale"], 500, ["bales-dog-tag"], []),
 ("Side Ops", "Capture a SAM Site", None, ["Hack the SAM control computer", "Defend it while the hack runs"], None, [], ["A SAM that shoots enemy aircraft, Deathstalker included"]),
 ("Side Ops", "Activate UAV Tower", "Any UAV Tower", ["Turn on a UAV Tower"], None, [], ["Enemies nearby show on your minimap"]),
 ("Side Ops", "Download Intel to Locate Lieutenant", None, ["Download the intel"], None, [], ["A Lieutenant's location"]),
 ("Side Ops", "Secure Lost Supply Drop", None, ["Find and open a lost supply drop"], None, [], []),
 ("Side Ops", "Repair a Truck", None, ["Fix a useful truck you come across"], None, [], ["A working truck"]),
]
OPS_NOTES = [
 ("Weekly Story Missions", "Finish a random Story Mission three times a week for the weekly rewards"),
 ("Dynamic Operations", "Dynamic Ops pay $10,000 to $20,000 into your Bank, plus a Supply Drop that improves with each success in the same deployment"),
 ("Reduce Bounty", "$5,000 at a Bounty Station. Four kills make you Wanted"),
]

# What an order's prints use up, and the ingredients it wants extracted
# (which can be brought in from the stash and extracted again), by tick
# key: Keep/Sell holds them back until the order is ticked. Manuals,
# recipes and dog tags have to be found in that match, so aren't here.
ORDER_PRINTS = {
    "op-eyes-everywhere": [("recon-drone", 1)],
    "op-preparation": [("medium-backpack", 1), ("2-plate-armor-vest", 1)],
    "op-work-quietly": [("throwing-knife", 1)],
    "op-healer": [("medkit", 1)],
    "op-blindness": [("flash", 4)],
    "op-dead-battery": [("ddos", 1)],
    "op-click-boom": [("c4", 5)],
    "op-fire-insurance": [("thermite", 5)],
    "op-page-10-healer": [("armor-box", 1)],
    "op-avionics": [("uav", 1)],
    "op-hard-carry": [("large-backpack", 1)],
    "op-rule-of-three": [("3-plate-armor-vest", 1)],
}
ORDER_EXTRACTS = {
    "op-page-10-healer": [("reactive-metals", 3)],
    "op-hard-carry": [("nylon-laminate", 2)],
    "op-rule-of-three": [("ballistic-fabric", 2), ("nylon-cloth", 5)],
}
# Tips for orders, by tick key (Gamer's Heroes orders guide, 2026-10-28)
ORDER_TIPS = {
    "op-execute-intel": ["Kill the 5 the tower pings, then clear the rest of them for the Counterfeit Cash"],
    "op-suit-breach": ["The Nuclear Reactor Checkpoint is full of them, and you don't need radiation gear there"],
    "op-eyes-everywhere": ["Each tag only lasts a few seconds, so mark them one after another"],
    "op-operation-rewards": ["If no Dynamic Op phone turns up in Cheongun Village, deploy again"],
    "op-eye-in-the-sky": ["Songdo Wharf's SAM site works well"],
    "op-watch-for-bumps": ["Clear the gas station's enemies before you refuel"],
    "op-triangulation": ["Climb the radio towers marked with the DMZ Orders icon"],
    "op-dead-battery": ["A vehicle or drone only counts when it shows red"],
    "op-death-from-above": ["The Drone Motherboard stays on the last drone after it goes down"],
    "op-radiation-station": ["There's a Fire Station south of the reactor, in the mall",
                             "Enemies at the Nuclear Reactor Checkpoint drop Gas Masks and Radiation Pill Bottles",
                             "For containers in radiation, try the reactor's outskirts or that match's bomb site (the yellow area)"],
    "op-healer": ["The Medkit recipe is under Consumables at the 3D Printer"],
    "op-crashed-crate": ["Lost supply crates are the red smoke at the West Bridge, the hospital and a small island to the east; usually 2 of the 3 spawn",
                         "They aren't shared: each player needs their own 3"],
    "op-page-10-healer": ["Reactive Metals turn up in garages, construction sites and around vehicles"],
    "op-goliath": ["The Shock Stick has to physically hit Colossus"],
    "op-click-boom": ["Shoot an armored enemy's armor off before the C4"],
    "op-navigate-with-care": ["Cancel the infil (or swap squad leader) for a refund and you can pay for it again"],
    "op-keep-out": ["Lieutenants rarely drop keys: Operation Grid Assault gives Roze's High-Rise Armory key, or a friend can drop you one"],
    "op-nothing-is-secure": ["Most compounds have a safe, and Cheonwang Peak Array has three"],
    "op-mechanic": ["Gas stations often have repair parts, and stripping one radar truck's parts fixes the next"],
    "op-no-time": ["Ghost Shipment is a quick one"],
    "op-civil-service": ["Deploy into Operation Shopping Hacks to start at NuriGO Mall"],
    "op-abandoned": ["Get to a K9's body before it explodes"],
    "op-locksmith": ["Keys you bring in, drop and pick up again count"],
    "op-multi-talented": ["The same SAM site can be taken again"],
    "op-massive-damage": ["A Shock Stick works on it once the DDOS is used up"],
    "op-the-vault": ["The battery's spot changes from match to match"],
    "op-hard-carry": ["Nylon Laminate you bring in, drop and pick up again counts"],
    "op-stalking-the-stalker": ["Rice Mills usually has an enemy with an RPG"],
    "op-astronaut": ["Stay until the final exfil once the timer runs out"],
    "op-no-time-2": ["Stay out of The Grid"],
}
# Orders that share a title get their page in the tick key; the radiation
# page's Healer keeps the plain key (it's the earlier page)
CHECK_KEYS = {("DMZ Orders: Page 10", "Healer"): "op-page-10-healer"}

# DMZ Orders pages in the game's order (page numbers from the Gamer's Heroes
# orders guide; the route you take can change which page comes next)
ORDER_PAGES = {
    "Story Missions": (0, "Story Missions"),
    "DMZ Orders: Chapter 1": (1, "DMZ Orders: Page 1"),
    "DMZ Orders: Counterfeit": (2, "DMZ Orders: Pages 2-3, Counterfeit"),
    "DMZ Orders: Operation Rewards page": (4, "DMZ Orders: Page 4"),
    "DMZ Orders: Underground": (5, "DMZ Orders: Pages 5-6, Underground"),
    "DMZ Orders: Radiation and medical page": (7, "DMZ Orders: Page 7"),
    "DMZ Orders: Human Intel": (8, "DMZ Orders: Pages 8-9, Human Intel"),
    "DMZ Orders: Goliath page": (12, "DMZ Orders: Page 12, Hornet's Nest"),
    "DMZ Orders: Jail Break page": (13, "DMZ Orders: Page 13, Hornet's Nest"),
    "DMZ Orders: Fire Insurance page": (15, "DMZ Orders: Page 15"),
    "DMZ Orders: The Grid": (16, "DMZ Orders: Pages 16-17, The Grid"),
    "DMZ Orders: Page 23, other route": (23.5, "DMZ Orders: Page 23, other route"),
}
# Repeatable ops: guide reading, not ticked
REPEATABLE = ("Dynamic Ops", "Side Ops")

def structured_ops(guide):
    sec = next(s for s in guide if s["id"] == "ops")
    rows, wiki = [], []
    seen = set()
    for g, title, place, objectives, cash, items, other in MISSIONS:
        r = {"title": title, "group": g}
        if g not in REPEATABLE:
            # tick keys come from the list's own order, so they never change
            check = CHECK_KEYS.get((g, title)) or "op-" + item_id(title)
            n = 2
            while check in seen:   # a later order with the same title
                check = f"op-{item_id(title)}-{n}"; n += 1
            seen.add(check)
            r["check"] = check
            if check in ORDER_PRINTS: r["prints"] = [{"item": i, "qty": q} for i, q in ORDER_PRINTS[check]]
            if check in ORDER_EXTRACTS: r["extracts"] = [{"item": i, "qty": q} for i, q in ORDER_EXTRACTS[check]]
            if check in ORDER_TIPS: r["tips"] = ORDER_TIPS[check]
            # what an order needs shows as its own line, not with the rewards
            needed = {n["item"] for n in r.get("prints", []) + r.get("extracts", [])}
            items = [i for i in items if i not in needed]
        # a page's reward is shown once, with the page
        page_reward = next((o[len("Page reward: "):] for o in other if o.startswith("Page reward: ")), None)
        other = [o for o in other if not o.startswith("Page reward: ")]
        if page_reward: r["pageReward"] = page_reward
        if place: r["place"] = place
        if objectives: r["objectives"] = objectives
        if cash: r["cash"] = cash
        if items: r["links"] = items
        if other: r["rewards"] = other
        if not objectives and not cash and not items and not other: r["subtitle"] = "Objectives not confirmed yet"
        (wiki if g in REPEATABLE else rows).append(r)
    unknown = (set(ORDER_PRINTS) | set(ORDER_EXTRACTS) | set(ORDER_TIPS)) - seen
    assert not unknown, f"order needs or tips for no order: {unknown}"

    def page(r):
        g = r["group"]
        if g in ORDER_PAGES: return ORDER_PAGES[g][0]
        return float(g.split("Page ")[1])   # "DMZ Orders: Page 10"
    rows.sort(key=page)   # stable: orders keep their order within a page
    for r in rows: r["group"] = ORDER_PAGES.get(r["group"], (0, r["group"]))[1]
    sec["title"] = "Missions & Orders"
    sec["symbol"] = "checklist"
    sec["rows"] = rows
    sec["intro"] = ("Story Missions, then the DMZ Orders pages in the game's order. Tick an order, or each step, as you finish it. "
                    "Which page comes next can depend on the route you take.")
    guide.insert(guide.index(sec) + 1, {
        "id": "dynamic-ops", "title": "Dynamic & Side Ops", "symbol": "bolt.fill", "rows": wiki,
        "intro": ("Finish a random Story Mission three times a week for the weekly rewards. "
                  "Dynamic Ops pay $10,000 to $20,000 into your Bank, plus a Supply Drop that gets better with each one you finish in the same deployment. "
                  "A Bounty Station clears your bounty for $5,000; four kills make you Wanted.")})

# ---- Where keys turn up, from the sources players report (dmzcodex.com/map)
KEY_ALIASES = {"supremeleaderaccesscard": "supreme-leaders-bunker-access-card"}
# where the listed source reads badly as a sentence
KEY_FOUND = {"jin-taes-private-lounge": "Dropped by Jin-Tae (reported)",
             "jang-uis-converted-power-room": "Dropped by Jang-ui at the Netshin Tech Complex (reported)",
             "shopping-drc-locker": "A safe in the Cheonwang Peak Array server building. Random loot elsewhere (reported)",
             "air-base-access-card-multi-use": "Found during Operation Iron Citadel"}

def key_sources(items, markers, codex_keys):
    norm = lambda s: _re.sub(r"[^a-z0-9]", "", s.lower().replace("black market", "blackmarket").removesuffix(" key"))
    by_norm = {norm(i["name"]): i for i in items if i["kind"] == "Key"}
    places = sorted(((m["name"], m["id"]) for m in markers if m["cat"] in ("area", "place", "fortress")), key=lambda p: -len(p[0]))
    for k in codex_keys:
        n = norm(k["name"])
        it = by_norm.get(n) or next((i for i in items if i["id"] == KEY_ALIASES.get(n)), None)
        if not it or it.get("found") or not k["sources"]: continue
        lines, found_at = [], []
        for s in k["sources"]:
            name, kind = s["name"], (s.get("kind") or "")
            reported = kind.startswith("Reported")
            if "Mission reward" in kind: line = f"A reward from {name}"
            elif "drop" in kind.lower() and ("boss" in kind.lower() or "Lieutenant" in kind): line = f"Dropped by {name}"
            elif name == "Loot containers": line = "Loot containers around Hajin"
            else: line = name
            lines.append(line + (" (reported)" if reported and not line.endswith(")") else ""))
            low = name.lower()
            for pname, mid in places:
                if pname.lower() in low and mid not in found_at: found_at.append(mid); break
        it["found"] = KEY_FOUND.get(it["id"]) or ". ".join(lines)
        if found_at: it["foundPlaces"] = found_at

# ---- FOB upgrades: each family shows its FOB station's icon
FAMILY_PICTURE = {"Bank Upgrade": "bank", "Stash Item Upgrade": "stash", "Stash Weapon Upgrade": "stash",
                  "MIA Recovery Discount": "operators", "Gunsmith Upgrade": "gunsmith", "Vendor Item Upgrade": "vendor",
                  "Ingredient Printing": "printer", "Dog Tag Case Upgrade": "dog-tag-case"}

def fob_pictures(items):
    for it in items:
        pic = FAMILY_PICTURE.get(it.get("family", ""))
        if it["kind"] == "FOB Upgrade" and pic and "image" not in it:
            it["image"] = IMG_BASE + "fob/" + pic + ".png?v=1"
            it.pop("symbol", None)
