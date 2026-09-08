#!/bin/bash
# make.sh - build App Store screenshots end to end.
#
#   Tools/screenshots/make.sh [out-dir]
#
# Builds the app for the simulator, boots an iPhone 17 Pro Max, seeds a
# realistic save, drives the DEBUG screenshot harness (SS_SCREEN launch env,
# see ContentView.swift) to four screens, captures each, and composites them
# into 1284x2778 marketing shots via frame.swift.
#
# Raw captures land in <out>/raw, framed shots in <out>/framed.
set -euo pipefail
cd "$(dirname "$0")/../.."

OUT="${1:-$HOME/Desktop/MW4CamoTracker-screenshots}"
RAW="$OUT/raw"; FRAMED="$OUT/framed"
mkdir -p "$RAW" "$FRAMED"

SIM_NAME="iPhone 17 Pro Max"
BID="com.DannyRyman.MW4CamoTracker"
DD="build/ss"

echo "==> build"
xcodebuild -project MW4CamoTracker.xcodeproj -scheme MW4CamoTracker \
  -sdk iphonesimulator -configuration Debug \
  -destination "platform=iOS Simulator,name=$SIM_NAME" \
  -derivedDataPath "$DD" build >/dev/null
APP="$DD/Build/Products/Debug-iphonesimulator/MW4CamoTracker.app"

# Parse the JSON rather than the human-readable list: the plain-text format
# puts the udid and the state in parentheses and is easy to mis-slice.
UDID=$(xcrun simctl list devices available -j | /usr/bin/python3 -c "
import json, sys
name = sys.argv[1]
for runtime, devices in json.load(sys.stdin)['devices'].items():
    for d in devices:
        if d['name'] == name and d.get('isAvailable'):
            print(d['udid']); raise SystemExit
sys.exit('no available simulator named ' + name)
" "$SIM_NAME")
echo "==> sim $UDID"
# Erase first: a signed-in Apple account on the device throws an "Apple Account
# Verification" alert over the app a few seconds after launch, right into the
# capture window, and leftover state from previous runs shows up too.
xcrun simctl shutdown "$UDID" 2>/dev/null || true
xcrun simctl erase "$UDID"
xcrun simctl boot "$UDID" 2>/dev/null || true
sleep 8
xcrun simctl install "$UDID" "$APP"
xcrun simctl status_bar "$UDID" override --time "9:41" \
  --dataNetwork wifi --wifiMode active --wifiBars 3 \
  --cellularMode active --cellularBars 4 --batteryState discharging --batteryLevel 100

# One launch so the data container exists, then seed it and drop the prefs
# cache so the app re-reads what we wrote rather than its own last snapshot.
xcrun simctl launch "$UDID" "$BID" >/dev/null; sleep 5
xcrun simctl terminate "$UDID" "$BID" 2>/dev/null || true
DATA=$(xcrun simctl get_app_container "$UDID" "$BID" data)
# cfprefsd goes down BEFORE the write, not after: it holds the domain in memory
# from that first launch and flushes its own copy over the file on the way out,
# which silently discards everything seed.py just wrote.
xcrun simctl spawn "$UDID" launchctl stop com.apple.cfprefsd.xpc.daemon 2>/dev/null || true
sleep 2
/usr/bin/python3 Tools/screenshots/seed.py "$DATA/Library/Preferences/$BID.plist"

shot () { # <screen> <name> [category-id] [weapon-id]
  xcrun simctl terminate "$UDID" "$BID" 2>/dev/null || true; sleep 1
  env SIMCTL_CHILD_SS_SCREEN="$1" SIMCTL_CHILD_SS_CAT="${3:-}" SIMCTL_CHILD_SS_WEAPON="${4:-}" \
    xcrun simctl launch "$UDID" "$BID" >/dev/null
  # Long enough for the weapon art to come down off the CDN; a half-loaded
  # list of placeholder scopes is the one thing that ruins these shots.
  sleep 12
  xcrun simctl io "$UDID" screenshot "$RAW/$2.png" >/dev/null
  echo "    $2"
}
echo "==> capture"
shot multiplayer multiplayer
shot stats       stats
shot warzone     warzone
shot dmz         dmz
shot multiplayer category 0 ""    # Assault Rifles list
shot multiplayer weapon   "" 3    # Kastov 762 detail

echo "==> frame"
swift Tools/screenshots/frame.swift "$RAW" "$FRAMED"
echo "==> done -> $FRAMED"
