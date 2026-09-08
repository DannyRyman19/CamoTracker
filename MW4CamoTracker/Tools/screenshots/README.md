# App Store screenshots

One command builds the six 6.7" marketing shots (1284 x 2778):

```
Tools/screenshots/make.sh [out-dir]     # default: ~/Desktop/MW4CamoTracker-screenshots
```

Output: `<out>/raw/*.png` (straight simulator captures) and `<out>/framed/*.png`
(headline + nebula backdrop + rounded device card).

## How it works

- **`frame.swift`** - the compositor. CoreGraphics + CoreText, no deps, renders
  at exact pixels. The backdrop is the logo's own amber nebula, regenerated here
  from the same fBm and seeds as `tools-mw4-logo.swift` (the shipped
  `SplashBackground` is square and would need cropping to a 1:2.16 canvas). It
  is held darker than the logo's, because a headline and a screenshot card both
  sit on top of it. Headlines are Hitmarker at weight 700, first line in
  `appInk` and second in the mark's gold. Per-shot headline and any top/bottom
  crop live in the `shots` array.
- **`seed.py`** - writes a believable save into the simulator's app defaults, so
  nothing reads as an empty first run. Everything is derived from the shipped
  JSON rather than hardcoded, because the modes genuinely differ: Multiplayer
  has 4 camos per weapon at 10/25/50/75, Warzone has 3 at 1/3/10, and DMZ has no
  weapon camos at all, only objectives. Run with `/usr/bin/python3` (Homebrew
  python's `plistlib` is broken right now: `pyexpat` links against a `libexpat`
  missing a symbol it wants).
- **The DEBUG harness** in `Sources/ContentView.swift` reads `SS_SCREEN` from
  the launch environment, jumps straight to that tab, and suppresses both the
  splash and onboarding:
  - `SS_SCREEN=multiplayer` / `warzone` / `dmz` / `stats`
  - `SS_CAT=<categoryId>` or `SS_WEAPON=<weaponId>` deep-links one level past
    the tab root, for the category list and weapon detail shots

  It is all `#if DEBUG`; a normal launch (no env) is untouched.

## What gets seeded

| mode | state |
|---|---|
| Multiplayer | every weapon Gold, Mercurial Drift on all of them, Polyatomic Reforged on the ARs |
| Warzone | mid-grind, roughly two thirds |
| DMZ | early, a few objectives ticked |
| Levels | M4, Kastov 762, ISO Nightshade and KG-7 Vulcan maxed; the rest scattered |

Kastov 762 is pinned so the Pinned card is populated. The RNG is seeded, so the
same save comes out every run and the shots stay reproducible.

## Gotchas

The key formats have to match `TrackerViewModel.swift` exactly or the seed
silently does nothing:

- weapon mastery is `wmastery|<mode>|<weaponId>|<tier>`, **not** `mastery|`
- `weaponLevels: [Int: Int]` encodes as a JSON object with **stringified**
  keys (`{"1": 68}`). Swift's Codable special-cases String and Int dictionary
  keys; only other key types flatten to `[k, v, k, v, ...]`. Get this wrong and
  the whole `ProgressStore` fails to decode, leaving the app on an empty save
  with no error anywhere.

`make.sh` waits 12s after each launch before capturing, because weapon art comes
off the CDN and a half-loaded list of placeholder scopes ruins the shot.

## Shots

| file | headline | screen |
|---|---|---|
| `multiplayer` | EVERY WEAPON / EVERY CAMO | Multiplayer tab |
| `stats` | WATCH IT / ALL ADD UP | Stats tab |
| `warzone` | ONE APP / ALL THREE MODES | Warzone tab |
| `dmz` | DMZ OBJECTIVES / COVERED TOO | DMZ tab |
| `category` | BROWSE BY / WEAPON CLASS | Assault Rifles list |
| `weapon` | EVERY CHALLENGE / PER GUN | Kastov 762 detail |

Upload under the 6.7" slot in App Store Connect; it covers every current iPhone
size.
