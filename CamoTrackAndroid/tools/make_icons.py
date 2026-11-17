#!/usr/bin/env python3
"""Makes the Android launcher icons from the iPhone app's: the main icon and
each camo icon (AppIcon-<Name>.appiconset/icon-1024.png in the iOS asset
catalog, made by MW4CamoTracker/Tools/camo_icons.py), as adaptive icons:
the art a little inside the 72/108 safe zone over a blurred copy of itself,
so the round or squircle mask never cuts the lettering. Also a 240px preview
of each for the in-app picker. Rerun after the iOS icons change.

    python3 CamoTrackAndroid/tools/make_icons.py   (needs Pillow)
"""
import os, glob
from PIL import Image, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
IOS = os.path.join(HERE, "..", "..", "MW4CamoTracker", "Resources", "Assets.xcassets")
RES = os.path.join(HERE, "..", "app", "src", "main", "res")
SIZES = {"mdpi": 108, "hdpi": 162, "xhdpi": 216, "xxhdpi": 324, "xxxhdpi": 432}
LEGACY = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}

def snake(name):  # "HarmonicBreak" -> "harmonic_break"
    return "".join("_" + c.lower() if c.isupper() else c for c in name).lstrip("_")

def make(src, base):
    for d, px in SIZES.items():
        folder = os.path.join(RES, f"mipmap-{d}")
        os.makedirs(folder, exist_ok=True)
        src.resize((px, px), Image.LANCZOS).filter(ImageFilter.GaussianBlur(px / 18)).save(f"{folder}/{base}_background.png")
        fg = Image.new("RGBA", (px, px), (0, 0, 0, 0))
        inner = int(px * 0.70)
        fg.paste(src.resize((inner, inner), Image.LANCZOS), ((px - inner) // 2, (px - inner) // 2))
        fg.save(f"{folder}/{base}_foreground.png")
        src.resize((LEGACY[d], LEGACY[d]), Image.LANCZOS).save(f"{folder}/{base}.png")
    os.makedirs(os.path.join(RES, "mipmap-anydpi-v26"), exist_ok=True)
    with open(os.path.join(RES, "mipmap-anydpi-v26", f"{base}.xml"), "w") as f:
        f.write(f'''<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@mipmap/{base}_background" />
    <foreground android:drawable="@mipmap/{base}_foreground" />
</adaptive-icon>
''')
    os.makedirs(os.path.join(RES, "drawable-nodpi"), exist_ok=True)
    src.resize((240, 240), Image.LANCZOS).convert("RGB").save(os.path.join(RES, "drawable-nodpi", f"{base.replace('ic_launcher', 'icon_preview')}.png"))

for folder in sorted(glob.glob(os.path.join(IOS, "AppIcon*.appiconset"))):
    name = os.path.basename(folder)[len("AppIcon"):-len(".appiconset")].lstrip("-")
    pngs = sorted(glob.glob(os.path.join(folder, "*.png")), key=os.path.getsize)
    if not pngs: continue
    src = Image.open(pngs[-1]).convert("RGBA")
    base = "ic_launcher" + ("_" + snake(name) if name else "")
    make(src, base)
    print("made", base)
