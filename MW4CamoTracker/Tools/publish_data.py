#!/usr/bin/env python3
"""
publish_data.py - copy the bundled JSON into Data/MW4/ and regenerate the
manifest the app reads, so new weapons and camos reach installed apps without
an App Store update.

    python3 MW4CamoTracker/Tools/publish_data.py

DataService fetches Data/MW4/manifest.json first and only downloads a file
whose `version` differs from the one it has cached, so the manifest is
generated from each file's own `version` field rather than typed by hand: a
manifest version that disagrees with the file it points at either re-downloads
forever or never updates at all.

Bump the `version` inside the source JSON when you change it, then run this.
jsDelivr caches a branch-pinned path (@master) for around 12 hours, so purge
https://purge.jsdelivr.net/gh/DannyRyman19/CamoTracker@master/Data/MW4/manifest.json
if you need it live sooner.
"""
import json
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]          # the CamoTracker repo
RES = ROOT / "MW4CamoTracker" / "Resources"
OUT = ROOT / "Data" / "MW4"
MODES = ["multiplayer", "warzone", "dmz"]

OUT.mkdir(parents=True, exist_ok=True)


def version_of(path):
    v = json.loads(path.read_text(encoding="utf-8")).get("version")
    if not v:
        raise SystemExit(f"{path.name} has no top-level \"version\"")
    return v


manifest = {"catalog": {}, "modes": {}}

src = RES / "weapons.json"
shutil.copy2(src, OUT / "weapons.json")
manifest["catalog"] = {"version": version_of(src), "path": "weapons.json"}

for mode in MODES:
    src = RES / f"{mode}.json"
    shutil.copy2(src, OUT / f"{mode}.json")
    manifest["modes"][mode] = {"version": version_of(src), "path": f"{mode}.json"}

(OUT / "manifest.json").write_text(
    json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

print(f"published -> {OUT}")
print(f"  catalog {manifest['catalog']['version']}")
for mode, entry in manifest["modes"].items():
    print(f"  {mode:12} {entry['version']}")
