"""Paints a dry-brush gold "4" onto an icon rendered with tools-mw4-icon.swift --no-four.

Our own brushwork of a plain numeral, not the game's logo art (Apple rejected that).
usage: uv run --with pillow python tools-mw4-brush4.py <in.png> <out.png> <x> <y> <w> <h>
x/y/w/h: the box the swift tool printed ("four: ..."); the brush 4 is sized from it.
"""
import math, random, sys
from PIL import Image, ImageChops, ImageDraw, ImageFilter

GOLD = (255, 208, 0)
SS = 4  # supersample

def bezier(p0, p1, p2, t):
    a = [(1 - t) ** 2 * p0[i] + 2 * (1 - t) * t * p1[i] + t * t * p2[i] for i in (0, 1)]
    return a

def stroke(d, rng, p0, p1, p2, width, taper_end=0.35, fray=0.3, bristles=70):
    """One brush stroke along a quadratic curve: blunt start, tapered and frayed end."""
    steps = 260
    pts = [bezier(p0, p1, p2, i / steps) for i in range(steps + 1)]
    normals = []
    for i in range(steps + 1):
        a, b = pts[max(0, i - 1)], pts[min(steps, i + 1)]
        dx, dy = b[0] - a[0], b[1] - a[1]
        n = math.hypot(dx, dy) or 1
        normals.append((-dy / n, dx / n))
    for _ in range(bristles):
        o = rng.uniform(-0.5, 0.5)
        edge = abs(o) * 2
        end = 1 - rng.random() ** 1.5 * fray * (0.3 + edge)  # outer bristles run dry first
        start = rng.random() ** 3 * 0.04
        r = width / bristles * rng.uniform(1.6, 2.6)
        gap_phase, gap_freq = rng.uniform(0, 6.28), rng.uniform(8, 22)
        prev = None
        for i, (x, y) in enumerate(pts):
            t = i / steps
            if t < start or t > end:
                prev = None; continue
            w = width * (min(1, 0.75 + t * 6)) * (1 - max(0, (t - (1 - taper_end)) / taper_end) * 0.85)
            # dry streaks: more gaps near the end and at the edges
            dry = math.sin(gap_phase + t * gap_freq) * 0.5 + 0.5
            if dry < (t ** 2) * 0.55 * (0.4 + edge) + (edge > 0.85) * 0.2:
                prev = None; continue
            nx, ny = normals[i]
            px, py = x + nx * o * w, y + ny * o * w
            if prev:
                d.line([prev, (px, py)], fill=255, width=max(1, int(r * 2)))
            prev = (px, py)

def main():
    src, out = sys.argv[1], sys.argv[2]
    bx, by, bw, bh = map(float, sys.argv[3:7])
    base = Image.open(src).convert("RGBA")
    W, H = base.size
    rng = random.Random(4)

    # The brush 4 runs taller than the type's cap height, dripping below it.
    h = bh * 1.75
    w = bw * 1.12
    ox, oy = bx - bw * 0.04, by - bh * 0.1
    P = lambda u, v: ((ox + u * w) * SS, (oy + v * h) * SS)
    sw = w * 0.3 * SS

    mask = Image.new("L", (W * SS, H * SS), 0)
    d = ImageDraw.Draw(mask)
    stroke(d, rng, P(0.66, 0.01), P(0.36, 0.30), P(0.03, 0.60), sw * 0.95, taper_end=0.25, fray=0.18)
    stroke(d, rng, P(-0.02, 0.60), P(0.50, 0.63), P(1.02, 0.55), sw * 0.9, taper_end=0.4, fray=0.35)
    stroke(d, rng, P(0.70, -0.02), P(0.70, 0.55), P(0.63, 1.0), sw * 1.05, taper_end=0.55, fray=0.45)
    mask = mask.filter(ImageFilter.GaussianBlur(SS * 0.6)).resize((W, H), Image.LANCZOS)

    shadow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    shadow.putalpha(ImageChops.offset(mask, 0, 7).point(lambda a: int(a * 0.6)).filter(ImageFilter.GaussianBlur(10)))
    gold = Image.new("RGBA", (W, H), GOLD + (0,))
    gold.putalpha(mask)
    im = Image.alpha_composite(Image.alpha_composite(base, shadow), gold)
    im.save(out)
    print("wrote", out)

if __name__ == "__main__":
    main()
