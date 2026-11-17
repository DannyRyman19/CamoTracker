#!/usr/bin/env python3
"""Copies the iPhone app's text into the Android app: each language's
Localizable.strings and .stringsdict (plurals) from MW4CamoTracker/Resources
become app/src/main/assets/strings/<lang>.json, keyed exactly as on iOS.
Rerun after changing the iOS strings.

    python3 CamoTrackAndroid/tools/convert_strings.py

Format specifiers become Java's: %@ -> %s, %1$@ -> %1$s, %ld -> %d."""
import json, os, plistlib, re, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
IOS = os.path.join(HERE, "..", "..", "MW4CamoTracker", "Resources")
OUT = os.path.join(HERE, "..", "app", "src", "main", "assets", "strings")
LANGS = ["en", "de", "es", "fr", "it", "nl", "pt"]

def java(fmt):
    fmt = re.sub(r"%(\d+\$)?@", lambda m: "%" + (m.group(1) or "") + "s", fmt)
    return re.sub(r"%(\d+\$)?l{1,2}([du])", lambda m: "%" + (m.group(1) or "") + "d", fmt)

def strings(path):
    # plutil reads the old-style plist format .strings files use
    raw = subprocess.run(["plutil", "-convert", "json", "-o", "-", path], capture_output=True, check=True).stdout
    return {k: java(v) for k, v in json.loads(raw).items()}

def plurals(path):
    if not os.path.exists(path): return {}
    with open(path, "rb") as f: d = plistlib.load(f)
    out = {}
    for key, entry in d.items():
        fmt = entry.get("NSStringLocalizedFormatKey", "")
        var = re.search(r"%#@(\w+)@", fmt)
        if not var: continue
        rule = entry.get(var.group(1), {})
        forms = {k: java(v) for k, v in rule.items() if k in ("zero", "one", "two", "few", "many", "other")}
        out[key] = {"format": java(fmt.replace(var.group(0), "{" + var.group(1) + "}")), "forms": forms}
    return out

os.makedirs(OUT, exist_ok=True)
for lang in LANGS:
    folder = os.path.join(IOS, f"{lang}.lproj")
    data = {"strings": strings(os.path.join(folder, "Localizable.strings")),
            "plurals": plurals(os.path.join(folder, "Localizable.stringsdict"))}
    with open(os.path.join(OUT, f"{lang}.json"), "w") as f:
        json.dump(data, f, ensure_ascii=False, indent=0, sort_keys=True)
    print(lang, len(data["strings"]), "strings,", len(data["plurals"]), "plurals")
