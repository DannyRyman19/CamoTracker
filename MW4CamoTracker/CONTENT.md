# MW4 Camo Tracker: updating content

How new weapons, camos, seasons and fixes reach installed apps **without an
App Store update**, and how to control what the notification says. Written so
that a request like "add these Season 1 weapons and announce it" or "fix the
Frostbite count, don't notify anyone" can be carried out from this page alone.

## How it works

The app ships with a copy of the data and checks a manifest on the CDN for
anything newer.

| What | Where |
|---|---|
| The data you edit (source of truth) | `MW4CamoTracker/Resources/weapons.json`, `multiplayer.json`, `warzone.json`, `dmz.json` |
| What installed apps download | `Data/MW4/` (same four files plus `manifest.json`), served by jsDelivr from the `master` branch |
| The script that copies one to the other | `MW4CamoTracker/Tools/publish_data.py` |
| A local editor for the JSON, with image upload | `python3 MW4CamoTracker/Tools/editor/serve.py` |
| Weapon and camo images | `Images/Guns/MW4/`, `Images/Camos/MW4/` in this repo, served at `https://camotracker.djr.li/Images/...` |

An installed app fetches `manifest.json` when it opens, and again in the
background every few hours when iOS allows. For each file whose `version` in
the manifest differs from the one it has, it downloads that file. If the
check ran in the background and found something, it posts one notification.

Nothing is live until the commit is **pushed to `master`**.

## The three things you will be asked for

Every one of them is the same four steps: edit `Resources/`, bump the
`version` of each file you touched, run the publish script, commit and push.
Only the publish flags differ.

### 1. New content with an announcement (a season, new weapons)

```sh
python3 MW4CamoTracker/Tools/publish_data.py \
  --title '{"en": "Season 1 is live", "de": "Season 1 ist da", "es": "Ya está aquí la Temporada 1", "fr": "La Saison 1 est là", "nl": "Seizoen 1 is er"}' \
  --body  '{"en": "New weapons and camos to track.", "de": "Neue Waffen und Tarnungen zum Verfolgen."}'
```

Plain text instead of JSON means English only: `--title "Season 1 is live"`.
A language you leave out falls back to English. Either flag can be used on
its own; the missing line uses the built-in wording.

### 2. A fix nobody needs telling about

```sh
python3 MW4CamoTracker/Tools/publish_data.py --silent
```

The corrected data downloads as usual and no notification is posted.

### 3. An ordinary update

```sh
python3 MW4CamoTracker/Tools/publish_data.py
```

Posts the built-in notification: "New Content Available", with a body naming
what changed (Weapons, Multiplayer, Warzone, DMZ).

Add `--dry-run` to any of them to see what would be published and what the
notification would say, without writing anything.

The message belongs to one publish. The script rewrites the manifest's
`notification` block every time data changes, so an announcement or a
`--silent` never carries over to the next update by accident. To change the
message after publishing but before pushing, run the script again with the
new flags.

## Step by step

1. **Edit** the files in `MW4CamoTracker/Resources/` (by hand or with the
   editor).
2. **Bump `version`** at the top of every file you changed (`0.7.0` to
   `0.7.1`; any different string works, the app only checks that it differs).
   The publish script refuses to run if a file changed and its version did
   not, because installed apps would never fetch it.
3. **Publish** with one of the commands above. Read what it prints: which
   files changed, and what the notification will be.
4. **Commit `Resources/` and `Data/MW4/` together and push to `master`.**
5. **Optional: skip the CDN cache.** jsDelivr caches `@master` paths for about
   12 hours. To go live at once, open the purge URL for the manifest and for
   each file that changed:
   `https://purge.jsdelivr.net/gh/DannyRyman19/CamoTracker@master/Data/MW4/manifest.json`
6. **Check it is live:**
   `curl -s https://cdn.jsdelivr.net/gh/DannyRyman19/CamoTracker@master/Data/MW4/manifest.json`

## Rules that protect players' progress

Progress is saved against ids, so these matter more than anything else here.
The publish script enforces the first two.

- **Never remove or renumber a `weaponId`.** A weapon that leaves the game
  stays in the file.
- **Never remove or renumber a camo's `itemId`** within a weapon.
- **New weapons take the next unused `weaponId`** (one more than the highest
  in `weapons.json`), and need a camo entry in each mode file, or that mode
  shows "no camo data" for them.
- **Leave `baseWeaponCount` alone.** It is the launch roster size, and the
  mode-wide Mastery capstone is gated on it, so a player can finish a new
  weapon in place of a launch one they skipped. Adding weapons does not
  change it.
- **Every piece of text needs all five languages** (`en`, `fr`, `es`, `de`,
  `nl`). A missing one falls back to English in the app. Weapon and Mastery
  camo names are proper nouns and are the same in every language.

## What the files hold

`weapons.json` (the catalog, shared by every mode):

- `categories[]`: `categoryId`, `name`, `weapons[]`.
- Each weapon: `weaponId`, `name`, `maxLevel`, `unlockRequirement` (a
  sentence; the app reads the unlock level out of its digits), `imageURL`.
- `weaponPrestige[]`: the prestige stages after a weapon's normal levels, in
  order. Each has a `name` and a `maxLevel` (`null` means the weapon's own).
  Add or remove entries to change how many times a weapon can prestige.

`multiplayer.json`, `warzone.json`, `dmz.json` (one per mode):

- `weaponCamos[]`: `weaponId` and its `camos[]`. Each camo has `itemId`,
  `name`, `tier`, `unlockLevel` (the weapon level it opens at), `imageURL`
  and a `requirement` with `amount`, `unit` and a `description` sentence.
- `objectives[]`: mode-only, non-weapon content (DMZ's missions and
  contracts).
- `mastery` (optional): overrides that mode's three Mastery camos. Each of
  `tier1`, `tier2`, `tier3` may set `name`, `amount`, `unit`, `description`
  and `colors` (hex strings); anything left out keeps the app's built-in
  value. Lowering an amount never shows a player "8/5": progress is capped
  on read and kept on disk.

`manifest.json` is generated. Do not edit it by hand. Its `notification`
block is what the publish flags write:

```json
"notification": {
  "title": { "en": "Season 1 is live" },
  "body":  { "en": "New weapons and camos to track." }
}
```

or `"notification": { "silent": true }`.

## What still needs an app update

- A new mode, or a new kind of content the app has no screen for.
- New interface text (anything in `Localizable.strings`).
- A fourth Mastery tier, or a change to how tiers unlock.
- New built-in notification wording. (Custom wording per update does not.)

When an app update does ship, the `Resources/` copies go out inside it as
the starting data, which is why they and `Data/MW4/` are kept identical.

## Things to know

- **The notification only fires from the background check.** Someone who
  opens the app before iOS runs that check gets the new data straight away
  and no notification, which is the right outcome.
- **iOS decides when the background check runs.** It can be hours or days
  after you publish, and it may never run for someone who rarely opens the
  app. There is no server, so there is no "send now".
- **One notification per update per device**, however many files changed.
- Versions of the app before 1.0 build 8 crashed in the background check and
  never notified. None of those reached the App Store.
