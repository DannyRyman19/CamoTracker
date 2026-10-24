#!/bin/bash
# make.sh - record and assemble the App Store app preview video.
#
#   Tools/preview/make.sh [out-dir]              English only (default)
#   Tools/preview/make.sh --all-languages        every shipped locale
#   Tools/preview/make.sh --lang de [out-dir]    one language
#
# Builds the app for the simulator, uses a dedicated "MW4 Preview 17 Pro Max"
# simulator (created on first run, so a sim you have open is never touched),
# and per language seeds a save whose Warzone Kastov 762 is one camo short,
# then records three takes. Each take is set up by the screenshot harness
# (SS_SCREEN / SS_WEAPON) and played by the preview harness (SS_DEMO, see
# Sources/ContentView.swift), which waits for the `ss_go` file this script
# drops once recording has started:
#
#   grind    the weapon's camo list -> the 10/10 bar fills -> the last camo
#            is ticked -> the real Gold "Camos complete" banner and confetti
#   suggest  the Warzone tab's Suggested card, pointing at the next weapon
#   stats    the Stats tab: mode completion and the Mastery tracks
#
# The app is launched with `-AppleLanguages (<code>)`, so the UI comes out in
# that language. plate.swift renders the captions in the same language and
# assemble.py cuts and joins the takes (886x1920, full bleed, 30 fps).
#
# --all-languages writes fastlane/previews/<locale>/mw4-camo-tracker-preview.mp4;
# anything else writes <out-dir>/mw4-camo-tracker-preview-<lang>.mp4.
set -euo pipefail
cd "$(dirname "$0")/../.."

LANGS=(en)
ALL=0
OUT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --all-languages) LANGS=(en de es fr nl); ALL=1; shift ;;
    --lang) LANGS=("$2"); shift 2 ;;
    *) OUT="$1"; shift ;;
  esac
done
OUT="${OUT:-$HOME/Desktop/MW4CamoTracker-preview}"

asc_locale () { # <lang> -> App Store Connect locale directory
  case "$1" in
    en) echo "en-US" ;; de) echo "de-DE" ;; es) echo "es-ES" ;;
    fr) echo "fr-FR" ;; nl) echo "nl-NL" ;; *) echo "$1" ;;
  esac
}
posix_locale () { # <lang> -> the AppleLocale the region formats follow
  case "$1" in
    en) echo "en_US" ;; de) echo "de_DE" ;; es) echo "es_ES" ;;
    fr) echo "fr_FR" ;; nl) echo "nl_NL" ;; *) echo "$1" ;;
  esac
}

SIM_NAME="MW4 Preview 17 Pro Max"
BID="com.DannyRyman.MW4CamoTracker"
DD="build/ss"
# The weapon the grind take finishes: Kastov 762, matching PREVIEW_WEAPON in
# Tools/screenshots/seed.py and demoWeaponId in Sources/ContentView.swift.
DEMO_WEAPON=3

echo "==> build"
xcodebuild -project MW4CamoTracker.xcodeproj -scheme MW4CamoTracker \
  -sdk iphonesimulator -configuration Debug \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro Max" \
  -derivedDataPath "$DD" build >/dev/null
APP="$DD/Build/Products/Debug-iphonesimulator/MW4CamoTracker.app"

UDID=$(xcrun simctl list devices available -j | /usr/bin/python3 -c "
import json, sys
for devices in json.load(sys.stdin)['devices'].values():
    for d in devices:
        if d['name'] == '$SIM_NAME':
            print(d['udid']); raise SystemExit
")
if [[ -z "$UDID" ]]; then
  UDID=$(xcrun simctl create "$SIM_NAME" com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro-Max)
fi
echo "==> sim $UDID"

xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b >/dev/null
xcrun simctl install "$UDID" "$APP"
xcrun simctl status_bar "$UDID" override --time "9:41" \
  --dataNetwork wifi --wifiMode active --wifiBars 3 \
  --cellularMode active --cellularBars 4 --batteryState discharging --batteryLevel 100
# One launch so the data container exists to seed into.
xcrun simctl launch "$UDID" "$BID" >/dev/null; sleep 5
xcrun simctl terminate "$UDID" "$BID" 2>/dev/null || true
DATA=$(xcrun simctl get_app_container "$UDID" "$BID" data)

seed () {
  # Re-seeded per language: each run of takes finishes the weapon, so every
  # language has to start from the same save. cfprefsd goes down BEFORE the
  # write (it holds the domain in memory from the last launch and would flush
  # its own copy over the file on the way out) - see Tools/screenshots/make.sh.
  xcrun simctl terminate "$UDID" "$BID" 2>/dev/null || true
  xcrun simctl spawn "$UDID" launchctl stop com.apple.cfprefsd.xpc.daemon 2>/dev/null || true
  sleep 2
  /usr/bin/python3 Tools/screenshots/seed.py --preview "$DATA/Library/Preferences/$BID.plist"
}

take () { # <take> <seconds after go> <extra SIMCTL_CHILD_ env...>
  local name="$1" secs="$2"; shift 2
  xcrun simctl terminate "$UDID" "$BID" 2>/dev/null || true; sleep 1
  env SIMCTL_CHILD_SS_DEMO="$name" "$@" \
    xcrun simctl launch "$UDID" "$BID" \
      -AppleLanguages "($LANG_CODE)" -AppleLocale "$(posix_locale "$LANG_CODE")" >/dev/null
  # Content load and the weapon art off the CDN, so the take opens on a
  # settled screen rather than on placeholder scopes.
  sleep 12
  local go log
  go="$DATA/tmp/ss_go"
  log="$WORK/takes/$name.log"
  xcrun simctl io "$UDID" recordVideo --codec=h264 --force "$WORK/takes/$name.mov" 2>"$log" &
  local rec=$!
  until grep -q "Recording started" "$log" 2>/dev/null; do sleep 0.05; done
  # assemble.py's segment times assume go lands one second in.
  sleep 1
  touch "$go"
  sleep "$secs"
  kill -INT "$rec"; wait "$rec" || true
  rm -f "$go"
  echo "    $name"
}

for LANG_CODE in "${LANGS[@]}"; do
  WORK="build/preview/$LANG_CODE"
  rm -rf "$WORK"; mkdir -p "$WORK/takes"
  if [[ $ALL -eq 1 ]]; then
    DEST="fastlane/previews/$(asc_locale "$LANG_CODE")/mw4-camo-tracker-preview.mp4"
  else
    DEST="$OUT/mw4-camo-tracker-preview-$LANG_CODE.mp4"
  fi
  mkdir -p "$(dirname "$DEST")"

  echo "==> seed [$LANG_CODE]"
  seed
  echo "==> record [$LANG_CODE]"
  take grind   11.5 SIMCTL_CHILD_SS_SCREEN=warzone SIMCTL_CHILD_SS_WEAPON=$DEMO_WEAPON
  take suggest 4.5  SIMCTL_CHILD_SS_SCREEN=warzone
  take stats   4.5  SIMCTL_CHILD_SS_SCREEN=stats
  xcrun simctl terminate "$UDID" "$BID" 2>/dev/null || true

  echo "==> plates [$LANG_CODE]"
  swift Tools/preview/plate.swift "$WORK/plates" "$LANG_CODE"
  echo "==> assemble [$LANG_CODE]"
  /usr/bin/python3 Tools/preview/assemble.py "$WORK" "$DEST"
done

echo "==> done"
