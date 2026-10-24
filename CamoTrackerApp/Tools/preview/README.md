# App Store app preview

One command records and assembles the 6.9" app preview video:

```
Tools/preview/make.sh [out-dir]              # English, default ~/Desktop/MW4CamoTracker-preview
Tools/preview/make.sh --all-languages        # every shipped locale
Tools/preview/make.sh --lang de [out-dir]    # one language
```

Output: 886 x 1920, 30 fps, H.264 High with a silent stereo AAC track (the
audio format Apple's preview spec lists), ~16.8 s. `--all-languages` writes
`fastlane/previews/<locale>/mw4-camo-tracker-preview.mp4`, which is what the
`fastlane previews` lane uploads; anything else writes
`<out>/mw4-camo-tracker-preview-<lang>.mp4`.

## How it works

- **A dedicated simulator**, "MW4 Preview 17 Pro Max", is created on first
  run, so a simulator you already have open is never touched.
- **`Tools/screenshots/seed.py --preview`** writes the usual in-progress save
  with one change: the Warzone track of the Kastov 762 (`PREVIEW_WEAPON`) is
  one camo short, with the camo before it part-filled, so the video can
  finish the weapon on camera. cfprefsd is stopped before the write, or it
  flushes the last launch's save back over the seed.
- **The DEBUG harness** sets up each take (`SS_SCREEN` / `SS_WEAPON`, as for
  screenshots) and `SS_DEMO=<take>` plays it, in `Sources/ContentView.swift`.
  It waits for `make.sh` to start recording (the script drops `ss_go` in the
  app's tmp dir), then fills the 10/10 bar and ticks the last camo through
  the same `setCamoAmount` / `toggleCamo` calls the buttons make, so the
  progress bars, the Gold milestone banner and its confetti are all the real
  thing. The rating prompt is held off while `SS_DEMO` is set, or the system
  sheet would land in the middle of the take. All `#if DEBUG`.
- **The language** comes from `-AppleLanguages (<code>)` on launch, the same
  lever the screenshots use.
- **`plate.swift`** renders one overlay per caption: the Hitmarker headline
  over a dark gradient that fades into the top of the recording. The
  recording itself fills the frame edge to edge. Don't put a backdrop, card
  or device frame around it: App Review rejects that (previews may only add
  narration and video or text overlays to the screen capture). The caption
  sets live in its `captionSets`, one per language, and it refuses a
  character Hitmarker has no glyph for.
- **`assemble.py`** cuts the takes into captioned segments (`SEGMENTS`) and
  crossfades them together. Consecutive segments of one take overlap, so a
  caption change reads as the headline crossfading over continuous footage.

## Retiming

The harness sleeps (the `SS_DEMO` task in `ContentView.swift`) and the
segment times in `assemble.py` describe the same clock: recording time =
harness time + 1.0 s. Change one, change the other. The takes are kept in
`build/preview/<lang>/takes/`, so a caption or cut change only needs, per
language:

```
swift Tools/preview/plate.swift build/preview/de/plates de
/usr/bin/python3 Tools/preview/assemble.py build/preview/de fastlane/previews/de-DE/mw4-camo-tracker-preview.mp4
```

A change to the cut moves the poster frame too: `PREVIEW_POSTER_FRAME` in
`fastlane/Fastfile`.

## Uploading

```
ASC_KEY_ID=... ASC_ISSUER_ID=... ASC_KEY_P8=<base64 of the .p8> fastlane previews
```

`deliver` cannot manage previews, so the lane goes through the App Store
Connect API and replaces the video in each locale's iPhone 6.7"/6.9" preview
set. It needs a version in an editable state; an approved version's media
cannot be changed.
