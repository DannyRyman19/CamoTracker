"""Generate whole stash screens for the tile detector: a 6-wide grid of
tiles (filled and empty), the header over it, seen at a phone's angle on a
TV, with every tile's box labelled in Create ML's object detection format.

usage: synth_grid.py TILES_DIR BACKDROPS_DIR OUT_DIR COUNT
  TILES_DIR      tiles to build grids from (folders of 200 px tiles, e.g.
                 synth.py's output; a folder named "empty" gives the empty slots)
  BACKDROPS_DIR  photos to put the screen over (anything without a stash grid)
"""
import json, math, os, random, sys, io
from PIL import Image, ImageDraw, ImageFilter, ImageEnhance, ImageFont

TILES, BACKS, OUT, N = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4])
HERE = os.path.dirname(os.path.abspath(__file__))
FONT = os.path.join(HERE, '..', '..', 'Resources', 'HitmarkerText-VF.ttf')
TILE, PITCH, COLS = 133, 148, 6   # the game's tile and spacing, in screenshot pixels

filled, empty = [], []
for d in sorted(os.listdir(TILES)):
    p = os.path.join(TILES, d)
    if not os.path.isdir(p): continue
    files = [os.path.join(p, f) for f in os.listdir(p) if f.endswith(('.png', '.jpg'))]
    (empty if d == 'empty' else filled).extend(files)
backs = [os.path.join(BACKS, f) for f in os.listdir(BACKS) if f.endswith(('.png', '.jpg'))]

def font(size):
    f = ImageFont.truetype(FONT, size)
    try: f.set_variation_by_name(b'Bold')
    except Exception: pass
    return f

def screen():
    """The stash panel straight on: header, frame, tiles. Returns the image
    and each tile's corners in its pixels."""
    rows = random.randint(2, 11)
    used = random.randint(0, rows * COLS)
    pad = 30
    w = COLS * PITCH - (PITCH - TILE) + 2 * pad
    head = 120
    h = head + rows * PITCH - (PITCH - TILE) + 2 * pad
    bg = tuple(random.randint(14, 40) for _ in range(3))
    im = Image.new('RGB', (w + 400, h + 200), bg)
    ox, oy = random.randint(20, 380), random.randint(20, 180)
    d = ImageDraw.Draw(im)
    # header: "ALL   9/18 WEAPONS   79/94 ITEMS"
    f = font(random.randint(26, 38))
    d.text((ox + pad, oy + 40), random.choice(['ALL', '', 'ALL']), font=f, fill=(225, 225, 225))
    d.text((ox + pad + w * 0.32, oy + 40), f"{random.randint(1, 30)}/{random.choice([12, 18, 24, 30])} WEAPONS", font=f, fill=(225, 225, 225))
    d.text((ox + pad + w * 0.62, oy + 40), f"{random.randint(10, 148)}/{random.choice([40, 58, 76, 94, 112, 148])} ITEMS", font=f, fill=(225, 225, 225))
    # the case outline round the grid
    if random.random() < 0.8:
        d.rectangle([ox + 8, oy + head - 14, ox + w - 8, oy + h - 8], outline=(150, 150, 150), width=random.randint(2, 4))
    quads = []
    for k in range(rows * COLS):
        r, c = divmod(k, COLS)
        x, y = ox + pad + c * PITCH, oy + head + pad + r * PITCH
        src = random.choice(filled) if k < used else (random.choice(empty) if empty else None)
        if src:
            t = Image.open(src).convert('RGB').resize((TILE, TILE), Image.BILINEAR)
            im.paste(t, (x, y))
        else:
            d.rectangle([x, y, x + TILE, y + TILE], fill=bg, outline=(150, 150, 150), width=2)
        quads.append([(x, y), (x + TILE, y), (x + TILE, y + TILE), (x, y + TILE)])
    # the sidebar's icons and text, so the detector learns to skip them
    if random.random() < 0.6:
        for i in range(random.randint(4, 12)):
            d.text((random.randint(0, max(1, ox - 10)), oy + 60 + i * 60), random.choice(['ALL', 'WEAPONS', 'GEAR', 'KEYS', 'MISC']), font=font(26), fill=(200, 200, 200))
    return im, quads

def solve(src, dst):
    """Perspective coefficients mapping dst corners back to src (PIL's form)."""
    import itertools
    A, B = [], []
    for (x, y), (u, v) in zip(dst, src):
        A.append([x, y, 1, 0, 0, 0, -u * x, -u * y]); B.append(u)
        A.append([0, 0, 0, x, y, 1, -v * x, -v * y]); B.append(v)
    # Gaussian elimination
    n = 8
    M = [A[i] + [B[i]] for i in range(n)]
    for i in range(n):
        p = max(range(i, n), key=lambda r: abs(M[r][i])); M[i], M[p] = M[p], M[i]
        for r in range(n):
            if r != i:
                f = M[r][i] / M[i][i]
                M[r] = [a - f * b for a, b in zip(M[r], M[i])]
    return [M[i][n] / M[i][i] for i in range(n)]

def project(c, x, y):
    """Where src point (x, y) lands: invert the dst -> src homography."""
    a, b, cc, d, e, f, g, h = c
    m = [[a, b, cc], [d, e, f], [g, h, 1.0]]
    det = (m[0][0] * (m[1][1] * m[2][2] - m[1][2] * m[2][1]) - m[0][1] * (m[1][0] * m[2][2] - m[1][2] * m[2][0])
           + m[0][2] * (m[1][0] * m[2][1] - m[1][1] * m[2][0]))
    inv = [[(m[1][1] * m[2][2] - m[1][2] * m[2][1]) / det, (m[0][2] * m[2][1] - m[0][1] * m[2][2]) / det, (m[0][1] * m[1][2] - m[0][2] * m[1][1]) / det],
           [(m[1][2] * m[2][0] - m[1][0] * m[2][2]) / det, (m[0][0] * m[2][2] - m[0][2] * m[2][0]) / det, (m[0][2] * m[1][0] - m[0][0] * m[1][2]) / det],
           [(m[1][0] * m[2][1] - m[1][1] * m[2][0]) / det, (m[0][1] * m[2][0] - m[0][0] * m[2][1]) / det, (m[0][0] * m[1][1] - m[0][1] * m[1][0]) / det]]
    X = inv[0][0] * x + inv[0][1] * y + inv[0][2]
    Y = inv[1][0] * x + inv[1][1] * y + inv[1][2]
    Z = inv[2][0] * x + inv[2][1] * y + inv[2][2]
    return X / Z, Y / Z

def photograph(im, quads):
    """Put the screen in a photo: tilt, place over a backdrop, TV damage."""
    W, H = random.choice([(480, 640), (640, 480), (512, 512), (480, 640)])
    sw, sh = im.size
    s = random.uniform(0.55, 1.05) * min(W / sw, H / sh)
    cx, cy = W / 2 + random.uniform(-0.15, 0.15) * W, H / 2 + random.uniform(-0.15, 0.15) * H
    j = lambda: random.uniform(-0.12, 0.12) * s * max(sw, sh)
    dst = [(cx - sw * s / 2 + j(), cy - sh * s / 2 + j()), (cx + sw * s / 2 + j(), cy - sh * s / 2 + j()),
           (cx + sw * s / 2 + j(), cy + sh * s / 2 + j()), (cx - sw * s / 2 + j(), cy + sh * s / 2 + j())]
    src = [(0, 0), (sw, 0), (sw, sh), (0, sh)]
    coeffs = solve(src, dst)
    back = Image.open(random.choice(backs)).convert('RGB') if backs else Image.new('RGB', (W, H), (40, 40, 40))
    back = back.resize((W, H)).filter(ImageFilter.GaussianBlur(random.uniform(3, 8)))
    warped = im.transform((W, H), Image.PERSPECTIVE, coeffs, Image.BILINEAR)
    mask = Image.new('L', (sw, sh), 255).transform((W, H), Image.PERSPECTIVE, coeffs, Image.BILINEAR)
    out = Image.composite(warped, back, mask)
    boxes = []
    for q in quads:
        pts = [project(coeffs, x, y) for x, y in q]
        xs, ys = [p[0] for p in pts], [p[1] for p in pts]
        full = (max(xs) - min(xs)) * (max(ys) - min(ys))
        x0, x1, y0, y1 = max(0, min(xs)), min(W, max(xs)), max(0, min(ys)), min(H, max(ys))
        # a tile mostly out of the photo isn't labelled (or shown much)
        if x1 - x0 > 4 and y1 - y0 > 4 and (x1 - x0) * (y1 - y0) > 0.6 * full:
            boxes.append({'label': 'tile', 'coordinates': {'x': (x0 + x1) / 2, 'y': (y0 + y1) / 2, 'width': x1 - x0, 'height': y1 - y0}})
    # TV-photo damage
    out = ImageEnhance.Brightness(out).enhance(random.uniform(0.7, 1.3))
    out = ImageEnhance.Contrast(out).enhance(random.uniform(0.75, 1.3))
    out = ImageEnhance.Color(out).enhance(random.uniform(0.6, 1.5))
    if random.random() < 0.35:
        ov = Image.new('RGB', (W, H)); od = ImageDraw.Draw(ov)
        per, ang = random.uniform(3, 9), random.uniform(0, math.pi)
        for i in range(-W, 2 * W, 2):
            v = int(127 + 127 * math.sin(i / per))
            od.line([(i, 0), (i + H * math.cos(ang), H)], fill=(v, v, v), width=2)
        out = Image.blend(out, ov, random.uniform(0.01, 0.04))
    if random.random() < 0.4:
        ov = Image.new('RGB', (W, H), (255, 255, 255))
        m = Image.linear_gradient('L').rotate(random.uniform(0, 360)).resize((W, H)).point(lambda v: int(v * random.uniform(0.1, 0.4)))
        out = Image.composite(ov, out, m)
    out = out.filter(ImageFilter.GaussianBlur(random.uniform(0, 1.4)))
    b = io.BytesIO(); out.save(b, 'JPEG', quality=random.randint(45, 92)); b.seek(0)
    return Image.open(b).convert('RGB'), boxes

random.seed(11)
os.makedirs(OUT, exist_ok=True)
ann = []
for k in range(N):
    im, quads = screen()
    photo, boxes = photograph(im, quads)
    name = f'g{k:05d}.jpg'
    photo.save(os.path.join(OUT, name), quality=90)
    ann.append({'image': name, 'annotations': boxes})
json.dump(ann, open(os.path.join(OUT, 'annotations.json'), 'w'))
print(N, 'screens,', sum(len(a['annotations']) for a in ann), 'tiles')
