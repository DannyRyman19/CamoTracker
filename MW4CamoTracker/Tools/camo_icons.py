"""Renders Camo Track's unlockable app icons: the main icon's lettering (CAMO,
사, TRACK, from tools-mw4-icon.py) over each camo's own picture from
Images/Camos/MW4 (the 256px icons from the Call of Duty wiki), with the 사 in
that camo's colour.

    python3 MW4CamoTracker/Tools/camo_icons.py            # all of them
    python3 MW4CamoTracker/Tools/camo_icons.py Chiral     # names containing "Chiral"

Writes each AppIcon-<Name>.appiconset/icon-1024.png and the 240px
AppIcon-<Name>-Preview the in-app picker shows. Needs numpy and Pillow, and a
heavy Hangul face (AppleSDGothicNeo on a Mac).

The camo art is Activision's: if App Review objects to it on the icons, the
fallback is drawing patterns in their place (see git history, 2026-11-17).
"""
import importlib.util
import os
import sys

import numpy as np
from PIL import Image, ImageFilter

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
APP = os.path.join(REPO, "MW4CamoTracker")
ASSETS = os.path.join(APP, "Resources", "Assets.xcassets")
CAMOS = os.path.join(REPO, "Images", "Camos", "MW4")
LATIN = os.path.join(APP, "Resources", "HitmarkerText-VF.ttf")
HANGUL = "/System/Library/Fonts/AppleSDGothicNeo.ttc"

spec = importlib.util.spec_from_file_location("icon", os.path.join(REPO, "tools-mw4-icon.py"))
icon = importlib.util.module_from_spec(spec)
spec.loader.exec_module(icon)
W, H = icon.W, icon.H

# Icon -> (camo picture, 사 colour, how much the middle darkens behind the type)
ICONS = {
    "Gold":               ("gold.png",                "FFE27A", 0.50),
    "Platinum":           ("platinum.png",            "F4F8FC", 0.50),
    "HarmonicBreak":      ("harmonic_break.png",      "FF6A5E", 0.42),
    "Divergence":         ("divergence.png",          "FFD23A", 0.50),
    "MercurialDrift":     ("mercurial_drift.png",     "FFB347", 0.50),
    "PolyatomicReforged": ("polyatomic_reforged.png", "C9C2FF", 0.42),
    "OrionReforged":      ("orion_reforged.png",      "FF8FC4", 0.30),
    "Parallax":           ("parallax.png",            "D07FE6", 0.50),
    "DamascusReforged":   ("damascus_reforged.png",   "FF9A5C", 0.45),
    "Empyros":            ("empyros.png",             "6FF0B8", 0.45),
    "Chiral":             ("chiral.png",              "FF3B30", 0.35),
    "RippleTide":         ("ripple_tide.png",         "FFC94A", 0.35),
    "Helio":              ("helio.png",               "FF8FA0", 0.35),
    "Flashpoint":         ("flashpoint.png",          "FFB15A", 0.45),
}

ys, xs = np.mgrid[0:H, 0:W].astype(np.float64)
fx, fy = xs / W, ys / H
GRAIN = icon.Noise(77123)


def ground(picture, scrim_amount):
    src = Image.open(os.path.join(CAMOS, picture)).convert("RGB")
    w, h = src.size
    m = int(min(w, h) * 0.04)  # trim any edge on the tile
    big = src.crop((m, m, w - m, h - m)).resize((W, H), Image.BICUBIC).filter(ImageFilter.GaussianBlur(1.2))
    col = np.asarray(big).astype(np.float64) / 255
    # Darker behind CAMO 사 TRACK so they read on every camo; full strength at the edges
    scrim = np.exp(-((fx - 0.5) / 0.30) ** 2) * np.clip((0.92 - np.abs(fy - 0.5) * 2) / 0.3, 0, 1)
    col *= (1 - scrim_amount * scrim)[..., None]
    r = np.sqrt((fx - 0.5) ** 2 + (fy - 0.48) ** 2) / 0.72
    col *= (0.62 + 0.38 * np.maximum(0, 1 - r ** 1.5))[..., None]
    col += ((GRAIN.value(xs * 0.9, ys * 0.9) - 0.5) * 0.05)[..., None]  # fine grain hides the upscale
    rgba = np.dstack([np.clip(col, 0, 1), np.ones((H, W))])
    return Image.fromarray((rgba * 255).astype(np.uint8), "RGBA")


def write(name, picture, glyph, scrim_amount):
    icon.nebula = lambda _ramp: ground(picture, scrim_amount)
    rgb = tuple(int(glyph[i:i + 2], 16) for i in (0, 2, 4))
    folder = os.path.join(ASSETS, f"AppIcon-{name}.appiconset")
    path = os.path.join(folder, "icon-1024.png")
    icon.icon_png(icon.render(LATIN, HANGUL, False, None, rgb), path)
    preview = os.path.join(ASSETS, f"AppIcon-{name}-Preview.imageset", "preview.png")
    Image.open(path).resize((240, 240), Image.LANCZOS).save(preview)
    print("wrote", name)


if __name__ == "__main__":
    only = sys.argv[1] if len(sys.argv) > 1 else ""
    for name, (picture, glyph, scrim_amount) in ICONS.items():
        if only in name:
            write(name, picture, glyph, scrim_amount)
