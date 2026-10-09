# CamoTracker repo

Several apps and the camotracker.djr.li Jekyll site share this repository.
The root working tree often holds unrelated uncommitted work (BO2, images):
scope `git add` to the folder being changed and never `git clean` here.

## MW4 Camo Tracker (`MW4CamoTracker/`)

- **Adding weapons, camos or seasons, fixing data, and what the "new content"
  notification says (custom wording, or silent):** follow
  `MW4CamoTracker/CONTENT.md`. Edit `MW4CamoTracker/Resources/*.json`, bump
  each changed file's `version`, run `MW4CamoTracker/Tools/publish_data.py`
  (`--title`/`--body` to announce, `--silent` for a fix, `--dry-run` to
  check), then commit `Resources/` and `Data/MW4/` together. Pushing to
  `master` is what makes it live, so confirm before pushing.
- Never remove or renumber a `weaponId` or a camo `itemId`: saved progress is
  keyed on them.
- Tests: `xcodebuild test -project MW4CamoTracker.xcodeproj -scheme
  MW4CamoTracker -destination 'platform=iOS Simulator,name=<an iPad>'` runs
  the unit and UI bundles. The UI tests are written for an iPad's grid.
- The default branch is `master`. TestFlight builds come from
  `.github/workflows/testflight.yml`.
