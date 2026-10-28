"""Generate synthetic stash tiles (200x200, like a straightened grid cell) for
each ingredient icon, roughed up the way a phone photo of a TV is.
usage: synth.py REFS_DIR OUT_DIR PER_CLASS"""
import json, os, random, sys, math, io
from PIL import Image, ImageDraw, ImageFilter, ImageEnhance, ImageFont

REFS, OUT, N = sys.argv[1], sys.argv[2], int(sys.argv[3])
HERE = os.path.dirname(os.path.abspath(__file__))
FONT = os.path.join(HERE, '..', '..', 'Resources', 'HitmarkerText-VF.ttf')
RARITY = {'Uncommon': (173, 225, 38), 'Rare': (0, 144, 255), 'Epic': (139, 117, 255), 'Legendary': (235, 128, 51),
          'Common': (150, 150, 150), 'Ultra': (230, 60, 60)}
guide = json.load(open(os.path.join(HERE, '..', '..', 'Resources', 'hajin.json')))
rarity = {i['id']: i.get('rarity') for i in guide['items']}
blueprints = {i['id'] for i in guide['items'] if i.get('blueprint')}
# rarities the guide lacks, read off the stash photo
rarity.update({'experimental-compounds': 'Legendary', 'control-unit': 'Uncommon'})

def background(col):
    """Dark tile with a dot lattice tinted by the rarity colour, strongest at the top."""
    t = Image.new('RGB', (200, 200), (24, 25, 27))
    d = ImageDraw.Draw(t)
    period = random.choice([5, 6, 6, 7])
    tint = random.uniform(0.25, 0.6)
    for y in range(10, 200, period):
        f = tint * max(0.0, 1 - y / random.uniform(150, 260))
        base = tuple(int(40 + (c - 40) * f) for c in col) if col else (58, 59, 61)
        for x in range(2, 200, period):
            d.rectangle([x, y, x + period // 2, y + period // 2], fill=base)
    if col:
        d.rectangle([0, 0, 200, random.randint(6, 11)], fill=col)
    return t

def cube(d, x, y, s):
    d.rectangle([x, y, x + s, y + s], outline=(235, 235, 235), width=2)
    d.polygon([(x, y), (x + s // 3, y - s // 3), (x + s + s // 3, y - s // 3), (x + s, y)], outline=(235, 235, 235))

# Valuables (not dog tags) and the intel ingredients sit on the stash's
# Valuables tab and carry a diamond, not the cube
DIAMOND = {i['id'] for i in guide['items'] if i['kind'] == 'Valuable' and 'dog-tag' not in i['id']} | {
    'ballistic-flight-logs', 'degraded-execution-footage', 'infantry-invasion-plans', 'nuclear-program-files', 'regional-combat-notes'}

def diamond(d, x, y, s):
    """The cut-gem mark: a flat top, a crown line, facets to the point."""
    w = (235, 235, 235)
    top, crown, bottom = y - s // 2, y - s // 5, y + s // 2
    d.polygon([(x + s // 4, top), (x + s - s // 4, top), (x + s, crown), (x + s // 2, bottom), (x, crown)], outline=w, width=2)
    d.line([(x, crown), (x + s, crown)], fill=w, width=2)
    for fx in (s // 3, s * 2 // 3):
        d.line([(x + fx, crown), (x + s // 2, bottom)], fill=w, width=1)

def tile(icon, rid):
    col = RARITY.get(rarity.get(rid) or '', None)
    if random.random() < 0.15:
        col = random.choice(list(RARITY.values()))
    t = background(col)
    s = int(200 * random.uniform(0.5, 0.78))
    ic = icon.copy()
    ic.thumbnail((s, s), Image.LANCZOS)
    if random.random() < 0.5:
        ic = ic.rotate(random.uniform(-6, 6), resample=Image.BICUBIC, expand=True)
    x = int((200 - ic.width) / 2 + random.uniform(-14, 10))
    y = int((200 - ic.height) / 2 + random.uniform(-4, 18))
    t.paste(ic, (x, y), ic)
    d = ImageDraw.Draw(t)
    f = ImageFont.truetype(FONT, random.randint(30, 42)); f.set_variation_by_name(b'Bold')
    n = str(random.choice([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 10, 10]))
    d.text((random.randint(150, 168) - 18 * (len(n) - 1), random.randint(10, 22)), n, font=f, fill=(240, 240, 240))
    if (rid[2:] if rid.startswith('x-') else rid) in DIAMOND:
        diamond(d, random.randint(8, 16), random.randint(172, 182), random.randint(20, 26))
    else:
        cube(d, random.randint(10, 18), random.randint(165, 178), random.randint(10, 14))
    if random.random() < 0.4:  # pin
        d.line([(8, 30), (26, 12)], fill=(230, 230, 230), width=4)
    # frame lines from neighbours
    if random.random() < 0.6:
        d.rectangle([0, 0, 199, 199], outline=(150, 150, 150), width=random.randint(1, 3))
    return t

def badge(d):
    """The small white card badge blueprints and manuals carry, bottom left."""
    x, y = random.randint(4, 10), random.randint(146, 156)
    w, h = random.randint(38, 48), random.randint(24, 30)
    d.rounded_rectangle([x, y, x + w, y + h], radius=4, fill=(235, 238, 242))
    for k in (0.36, 0.64):
        d.line([(x + w * 0.2, y + h * k), (x + w * 0.8, y + h * k)], fill=(110, 115, 125), width=3)

def blueprint_tile(icon):
    """A blueprint as a backpack shows it: royal blue, pale rings and arcs
    round the middle, a light square set in from the edge, the badge."""
    top = (random.randint(25, 45), random.randint(95, 125), random.randint(220, 250))
    bottom = (random.randint(12, 25), random.randint(60, 85), random.randint(185, 215))
    t = Image.new('RGB', (200, 200))
    d = ImageDraw.Draw(t)
    for y in range(200):
        f = y / 199
        d.line([(0, y), (200, y)], fill=tuple(int(a + (b - a) * f) for a, b in zip(top, bottom)))
    # faint: a shade or two lighter than the blue
    ring = tuple(min(255, c + random.randint(30, 55)) for c in top)
    for r in (34, 62, 94):
        d.ellipse([100 - r, 100 - r, 100 + r, 100 + r], outline=ring, width=2)
    cx, cy = random.choice([(170, 170), (30, 170), (170, 30)])
    d.arc([cx - 124, cy - 124, cx + 124, cy + 124], 0, 360, fill=ring, width=2)
    inset = random.randint(10, 16)
    d.rectangle([inset, inset, 200 - inset, 200 - inset], outline=(150, 200, 255), width=random.randint(2, 4))
    s = int(200 * random.uniform(0.5, 0.72))
    ic = icon.copy(); ic.thumbnail((s, s), Image.LANCZOS)
    t.paste(ic, (int((200 - ic.width) / 2 + random.uniform(-8, 8)), int((200 - ic.height) / 2 + random.uniform(-10, 6))), ic)
    badge(d)
    if random.random() < 0.6:
        d.rectangle([0, 0, 199, 199], outline=(150, 150, 150), width=random.randint(1, 3))
    return t

def manual_tile(icon):
    """A weapon manual: the manual over the big olive TECHNICAL SERVICES
    DEPT stamp that fills the tile, and the badge."""
    t = Image.new('RGB', (200, 200), (random.randint(55, 75), random.randint(52, 68), random.randint(30, 42)))
    d = ImageDraw.Draw(t)
    ink = (random.randint(150, 185), random.randint(140, 170), random.randint(80, 105))
    cx, cy = 100 + random.randint(-12, 12), 100 + random.randint(-12, 12)
    for r, w in ((112, 14), (84, 4), (62, 3)):
        d.ellipse([cx - r, cy - r, cx + r, cy + r], outline=ink, width=w)
    # the stamp's lettering round the ring, as dashes
    for k in range(28):
        a = k / 28 * 2 * math.pi
        x, y = cx + 98 * math.cos(a), cy + 98 * math.sin(a)
        d.line([(x - 4, y - 4), (x + 4, y + 4)], fill=ink, width=3)
    s = int(200 * random.uniform(0.6, 0.78))
    ic = icon.copy(); ic.thumbnail((s, s), Image.LANCZOS)
    if random.random() < 0.5:
        ic = ic.rotate(random.uniform(-8, 8), resample=Image.BICUBIC, expand=True)
    t.paste(ic, (int((200 - ic.width) / 2 + random.uniform(-8, 8)), int((200 - ic.height) / 2 + random.uniform(-10, 6))), ic)
    badge(d)
    return t

def photograph(t):
    """Phone-photo-of-a-TV damage."""
    w = 200
    if random.random() < 0.7:  # slight perspective / crop misalignment
        dx, dy = [random.uniform(-10, 10) for _ in range(2)]
        sc = random.uniform(0.92, 1.08)
        t = t.transform((w, w), Image.AFFINE, (sc, random.uniform(-0.04, 0.04), dx, random.uniform(-0.04, 0.04), sc, dy),
                        resample=Image.BILINEAR, fillcolor=(30, 30, 32))
    t = ImageEnhance.Color(t).enhance(random.uniform(0.6, 1.8))
    t = ImageEnhance.Brightness(t).enhance(random.uniform(0.75, 1.35))
    t = ImageEnhance.Contrast(t).enhance(random.uniform(0.8, 1.4))
    if random.random() < 0.6:  # colour cast
        r, g, b = t.split()
        k = [random.uniform(0.85, 1.15) for _ in range(3)]
        t = Image.merge('RGB', [c.point(lambda v, kk=kk: min(255, int(v * kk))) for c, kk in zip((r, g, b), k)])
    if random.random() < 0.5:  # moire stripes
        ov = Image.new('RGB', (w, w)); od = ImageDraw.Draw(ov)
        per, ang = random.uniform(3, 9), random.uniform(0, math.pi)
        for i in range(-w, 2 * w, 2):
            v = int(127 + 127 * math.sin(i / per))
            od.line([(i, 0), (i + w * math.cos(ang), w)], fill=(v, v, v), width=2)
        t = Image.blend(t, ov, random.uniform(0.03, 0.12))
    if random.random() < 0.4:  # glare
        ov = Image.new('RGB', (w, w), (255, 255, 255))
        mask = Image.linear_gradient('L').rotate(random.uniform(0, 360)).resize((w, w)).point(lambda v: int(v * random.uniform(0.1, 0.35)))
        t = Image.composite(ov, t, mask)
    t = t.filter(ImageFilter.GaussianBlur(random.uniform(0, 1.8)))
    if random.random() < 0.5:
        t = t.resize((random.randint(70, 140),) * 2, Image.BILINEAR).resize((w, w), Image.BILINEAR)
    b = io.BytesIO(); t.save(b, 'JPEG', quality=random.randint(35, 90)); b.seek(0)
    return Image.open(b).convert('RGB')

random.seed(7)
for f in sorted(os.listdir(REFS)):
    if not f.endswith('.png'): continue
    rid = f[:-4]
    icon = Image.open(os.path.join(REFS, f)).convert('RGBA')
    os.makedirs(os.path.join(OUT, rid), exist_ok=True)
    item = rid[2:] if rid.startswith('x-') else rid
    # Valuables get as many tiles as an ingredient: with fewer, a look-alike
    # ingredient (a paper one) wins the close calls
    for k in range(max(N, 90) if item in DIAMOND else N):
        # A manual is nearly always on its stamp
        styled = manual_tile(icon) if item == 'weapon-manual' and random.random() < 0.7 else tile(icon, rid)
        photograph(styled).save(os.path.join(OUT, rid, f'{k:04d}.jpg'), quality=92)
    # Blueprints, in the backpack's blueprint style: the reader spots the
    # blue and asks the model which blueprint it is
    if item in blueprints:
        for k in range(N, N + N * 2 // 3):
            photograph(blueprint_tile(icon)).save(os.path.join(OUT, rid, f'{k:04d}.jpg'), quality=92)
def empty_tile(k):
    """A stash or backpack slot with nothing in it, or, in a backpack's
    Secure slots, a locked slot (dots round its edge) or a free one (a grey
    shield), so neither reads as an item."""
    style = k % 3
    if style == 0:
        t = background(None)
        d = ImageDraw.Draw(t)
        d.rectangle([0, 0, 199, 199], outline=(150, 150, 150), width=random.randint(1, 4))
        return t
    shade = random.randint(16, 30)
    t = Image.new('RGB', (200, 200), (shade, shade + 1, shade + 4))
    d = ImageDraw.Draw(t)
    if style == 1:
        dot, step = (random.randint(70, 110),) * 3, random.randint(14, 20)
        for v in range(4, 200, step):
            for x, y in ((v, 4), (v, 195), (4, v), (195, v)):
                d.rectangle([x - 1, y - 1, x + 2, y + 2], fill=dot)
    else:
        d.rectangle([0, 0, 199, 199], outline=(70, 72, 76), width=random.randint(2, 4))
        g = random.randint(80, 105)
        w, top = random.randint(70, 90), random.randint(48, 60)
        d.polygon([(100 - w / 2, top), (100, top - 8), (100 + w / 2, top), (100 + w / 2, top + 55),
                   (100, top + 100), (100 - w / 2, top + 55)], fill=(g, g, g + 2))
    return t

# empty tiles
os.makedirs(os.path.join(OUT, 'empty'), exist_ok=True)
for k in range(N):
    photograph(empty_tile(k)).save(os.path.join(OUT, 'empty', f'{k:04d}.jpg'), quality=92)
print('done')
