#!/usr/bin/env python3
"""Makes the notification icon: the app icon's 사, white on clear (Android
tints it), in each density. A notification's small icon has to be a flat
shape; the launcher icon itself would show as a white square.

    /usr/bin/python3 CamoTrackAndroid/tools/make_notification_icon.py   (needs Pillow, and AppleSDGothicNeo on a Mac)
"""
import os
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
RES = os.path.join(HERE, "..", "app", "src", "main", "res")
HANGUL = "/System/Library/Fonts/AppleSDGothicNeo.ttc"
SIZES = {"mdpi": 24, "hdpi": 36, "xhdpi": 48, "xxhdpi": 72, "xxxhdpi": 96}
BIG = 960          # drawn large, then scaled down
INK = 0.83         # the glyph's share of the square (2dp clear all round, of 24)

font = ImageFont.truetype(HANGUL, 600)
stroke = round(600 * 0.04)  # the same weight as on the launcher icon
probe = ImageDraw.Draw(Image.new("L", (10, 10)))
l, t, r, b = probe.textbbox((0, 0), "사", font=font, stroke_width=stroke)
glyph = Image.new("L", (r - l, b - t), 0)
ImageDraw.Draw(glyph).text((-l, -t), "사", font=font, fill=255, stroke_width=stroke, stroke_fill=255)
scale = BIG * INK / max(glyph.size)
glyph = glyph.resize((round(glyph.width * scale), round(glyph.height * scale)), Image.LANCZOS)
mask = Image.new("L", (BIG, BIG), 0)
mask.paste(glyph, ((BIG - glyph.width) // 2, (BIG - glyph.height) // 2))

for density, px in SIZES.items():
    folder = os.path.join(RES, f"drawable-{density}")
    os.makedirs(folder, exist_ok=True)
    alpha = mask.resize((px, px), Image.LANCZOS)
    icon = Image.new("RGBA", (px, px), (255, 255, 255, 0))
    icon.putalpha(alpha)
    icon.save(os.path.join(folder, "ic_notification.png"), optimize=True)
    print("wrote", density, px)
