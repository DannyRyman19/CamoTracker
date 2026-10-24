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

Pictures: an item gets `Images/DMZ/<item id>.png` and a trait gets
`Images/DMZ/traits/<trait id>.png` when that file exists in this repo, so add
the picture to `Images/DMZ` (it is served from camotracker.djr.li) and
rebuild. Keys without their own picture use one per rarity.

Sources: data the player reads off the game wins; a dmzhub.gg listing on its
own is enough to add an item or key (say plainly what isn't known yet, e.g.
"Where its door is isn't known yet").
