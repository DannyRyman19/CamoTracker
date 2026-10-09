"""Renders the MW4 Camo Tracker app icon and splash foreground.

    python3 tools-mw4-icon.py <latin font> <hangul font> <icon-1024.png> <splash-fg.png>

  latin font   MW4CamoTracker/Resources/HitmarkerText-VF.ttf
  hangul font  any heavy Hangul face (AppleSDGothicNeo.ttc on a Mac,
               wqy-zenhei.ttc on Linux)

Layout: CAMO, a gold 사 (Korean "four"), TRACKER, over an amber nebula. No
"MW", "MW4" or game logo art anywhere: App Review rejected the game's lockup
(4.1) and then the typed "MW4" too, as another developer's product name.

A numpy port of the earlier CoreGraphics tool, so it runs anywhere: same
seeded value-noise nebula, distressed white type with a drop shadow.
"""
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

W, H = 1196, 1200
GOLD = (255, 208, 0)


# ─── value-noise fBm (same seeding as the Swift tool) ──────────────────
class Noise:
    def __init__(self, seed):
        m = (1 << 64) - 1
        s = (seed * 6364136223846793005 + 1442695040888963407) & m
        t = list(range(256))
        for i in range(255, 0, -1):
            s = (s * 6364136223846793005 + 1442695040888963407) & m
            j = (s >> 33) % (i + 1)
            t[i], t[j] = t[j], t[i]
        self.perm = np.array([t[i & 255] for i in range(512)], dtype=np.int64)

    def _grad(self, x, y):
        return self.perm[(self.perm[x & 255] + y) & 255] / 255.0

    def value(self, x, y):
        xi, yi = np.floor(x).astype(np.int64), np.floor(y).astype(np.int64)
        xf, yf = x - np.floor(x), y - np.floor(y)
        u, v = xf * xf * (3 - 2 * xf), yf * yf * (3 - 2 * yf)
        a, b = self._grad(xi, yi), self._grad(xi + 1, yi)
        c, d = self._grad(xi, yi + 1), self._grad(xi + 1, yi + 1)
        return (a * (1 - u) + b * u) * (1 - v) + (c * (1 - u) + d * u) * v

    def fbm(self, x, y, octaves=6):
        f, amp, fr, norm = 0.0, 0.5, 1.0, 0.0
        for _ in range(octaves):
            f = f + amp * self.value(x * fr, y * fr)
            norm += amp
            amp *= 0.5
            fr *= 2
        return f / norm


def nebula():
    n1, n2 = Noise(20260908), Noise(77123)
    ys, xs = np.mgrid[0:H, 0:W].astype(np.float64)
    fx, fy = xs / W, ys / H
    wx = n1.fbm(fx * 3.0, fy * 3.0) * 1.6
    wy = n2.fbm(fx * 3.0 + 5.2, fy * 3.0 + 1.3) * 1.6
    v = n1.fbm(fx * 4.2 + wx, fy * 4.2 + wy, octaves=7)
    v = np.clip((v - 0.30) / 0.44, 0, 1) ** 1.30
    r = np.sqrt((fx - 0.5) ** 2 + (fy - 0.48) ** 2) / 0.72
    vign = np.maximum(0, 1 - r ** 1.5)
    t = np.clip(v * (0.35 + 0.85 * vign), 0, 1)
    lo = t < 0.40
    k_lo, k_hi = t / 0.40, (t - 0.40) / 0.60
    rr = np.where(lo, 0.030 + k_lo * 0.42, 0.450 + k_hi * 0.550)
    gg = np.where(lo, 0.014 + k_lo * 0.20, 0.214 + k_hi * 0.606)
    bb = np.where(lo, 0.004 + k_lo * 0.010, 0.014 + k_hi * 0.056)
    grain = (n2.value(xs * 0.7, ys * 0.7) - 0.5) * 0.05
    rgb = np.stack([rr + grain, gg + grain, bb + grain], axis=-1)
    alpha = np.ones((H, W, 1))
    return Image.fromarray((np.clip(np.concatenate([rgb, alpha], -1), 0, 1) * 255).astype(np.uint8), "RGBA")


def distress():
    """Speckle mask (0.55…1) that eats into the white type."""
    dn = Noise(4242)
    ys, xs = np.mgrid[0:H, 0:W].astype(np.float64)
    s = dn.fbm(xs * 0.045, ys * 0.045, octaves=4) * 0.55 + dn.value(xs * 0.34, ys * 0.34) * 0.45
    return np.where(s < 0.30, 0.55, np.where(s < 0.38, 0.55 + (s - 0.30) / 0.08 * 0.45, 1.0))


def fitted(font_path, text, target_w, axes=None, index=0):
    probe = ImageFont.truetype(font_path, 200, index=index)
    if axes:
        probe.set_variation_by_axes(axes)
    left, _, right, _ = probe.getbbox(text)
    font = ImageFont.truetype(font_path, max(1, round(200 * target_w / (right - left))), index=index)
    if axes:
        font.set_variation_by_axes(axes)
    return font


def text_layer(font, text, centre_y, colour, stroke):
    """`text` centred horizontally, its ink centred on `centre_y`."""
    layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    l, t, r, b = d.textbbox((0, 0), text, font=font, stroke_width=stroke)
    d.text(((W - (r - l)) / 2 - l, centre_y - (b - t) / 2 - t), text, font=font,
           fill=colour, stroke_width=stroke, stroke_fill=colour)
    return layer


def with_shadow(base, layer, offset, blur, alpha):
    a = np.asarray(layer)[..., 3].astype(np.float64) * alpha
    shadow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    shadow.putalpha(Image.fromarray(a.astype(np.uint8)))
    shadow = shadow.transform((W, H), Image.AFFINE, (1, 0, -offset[0], 0, 1, -offset[1]))
    shadow = shadow.filter(ImageFilter.GaussianBlur(blur))
    return Image.alpha_composite(Image.alpha_composite(base, shadow), layer)


def distressed(layer, mask, tint_base, tint_span):
    px = np.asarray(layer).astype(np.float64)
    a = px[..., 3] / 255.0 * (0.88 + 0.12 * mask)
    tint = tint_base + tint_span * mask
    rgb = px[..., :3] * tint[..., None]
    return Image.fromarray(np.dstack([rgb, a * 255]).clip(0, 255).astype(np.uint8), "RGBA")


def render(latin, hangul, transparent):
    base = Image.new("RGBA", (W, H), (0, 0, 0, 0)) if transparent else nebula()
    mask = distress()
    for word, target_w, centre_y in (("CAMO", 700, 262), ("TRACKER", 880, 942)):
        font = fitted(latin, word, target_w, axes=[700])
        # CoreGraphics' line width is the whole stroke; Pillow's is per side.
        layer = text_layer(font, word, centre_y, (255, 255, 255, 255), round(font.size * 0.045 / 2))
        base = with_shadow(base, distressed(layer, mask, 0.84, 0.10), (0, 6), 18 / 2, 0.55)
    # 사: sized by height so it fills the band between the two words.
    probe = ImageFont.truetype(hangul, 200)
    l, t, r, b = probe.getbbox("사")
    four = ImageFont.truetype(hangul, round(200 * 380 / (b - t)))
    # Thickened with a stroke so it carries the same weight as the Latin type.
    layer = text_layer(four, "사", 602, GOLD + (255,), round(four.size * 0.04))
    return with_shadow(base, distressed(layer, mask, 0.92, 0.08), (0, 7), 20 / 2, 0.6)


def main():
    if len(sys.argv) != 5:
        sys.exit(__doc__)
    latin, hangul, icon_out, splash_out = sys.argv[1:]
    icon = render(latin, hangul, transparent=False)
    top = (H - W) // 2
    icon.crop((0, top, W, top + W)).resize((1024, 1024), Image.LANCZOS).convert("RGB").save(icon_out)
    render(latin, hangul, transparent=True).save(splash_out)
    print(f"wrote {icon_out} and {splash_out}")


if __name__ == "__main__":
    main()
