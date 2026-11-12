# Hajin guide build

`Resources/hajin.json` (the DMZ tab: Tac Map pins, guide sections, items,
traits) is generated. **Edit these scripts, never the JSON**: a hand edit is
lost the next time the guide is built.

```sh
cd MW4CamoTracker
python3 Tools/hajin/build_hajin.py      # writes Resources/hajin.json
xcodebuild test -scheme MW4CamoTrackerTests -destination 'platform=iOS Simulator,name=iPhone 17'
```

- `build_hajin.py`: map categories and blurbs, area write-ups, and the guide
  tables (levels, stations, bosses, keys, valuables, infil, missions,
  prestige). Bump `version` and `updated` at the bottom on every change.
- `video_data.py`: everything read from in-game screens and later sweeps:
  recipes, FOB upgrades, Gunsmith prices, ingredients and where they drop,
  traits and the trait trees, extra items, missions and orders, sell values.
- `markers.json`: the official Activision Tac Map markers. Refresh with
  `curl -s 'https://map-vnext-server.infra-ext.activision.com/mapdata/all?mapPath=/content/atvi/callofduty/guides/web/en/modernwarfare4/dmz-maps/hajin' -o Tools/hajin/markers.json`
- `imgmap.json`: item name to picture URL.
- Item pictures added 2026-11-12 (the Season 1 valuables, the five loot
  boxes, Specter Fabric Sample, SR-16 Bio Agent Sample, Counterfeit Cash,
  K9 Battery Core, Jin-Tae's Private Lounge) are from the item pages on
  dmzcodex.com, whose robots.txt allows automated reading and asks to be
  cited as the source.
- `codex_map.json`: community map layers from dmzcodex.com/map (exfils,
  player spawns, safes and other loot spots, key doors, and where each key
  turns up), already in our map's coordinates. Refresh with
  `python3 Tools/hajin/fetch_codex_map.py`; it fits dmzcodex's crop of the
  same official map onto ours from the markers both share, and stops if
  the fit is off. Boss spawn areas are `BOSS_SPAWNS` in `build_hajin.py`.
- `atlas_map.json`: safes, hidden caches, chemical storage and dead drops
  placed in the game's own map data, as shown on the dmz.tips Hajin atlas
  (viewed in a browser 2026-11-12; the site blocks automated fetching, so
  there is no refresh script). Already in our map's coordinates: its world
  positions were fitted onto ours from 94 markers both maps share. The build
  skips a spot we already pin and names the rest by grid square. Dead drops
  are placements, not a promise one is there every deployment. The atlas's
  loot tables are also where the Season 1 valuables, loot boxes, Counter UAV
  and four keys in `EXTRA_ITEMS` and the Keys table came from.

Pictures: an item gets `Images/DMZ/<item id>.png` and a trait gets
`Images/DMZ/traits/<trait id>.png` when that file exists in this repo
(FOB upgrades use their station's icon from `Images/DMZ/fob/`), so add
the picture to `Images/DMZ` (it is served from camotracker.djr.li) and
rebuild. Keys without their own picture use one per rarity.

Sources: data the player reads off the game wins; a dmzhub.gg listing on its
own is enough to add an item or key (say plainly what isn't known yet, e.g.
"Where its door is isn't known yet").
