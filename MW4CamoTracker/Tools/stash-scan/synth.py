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
    cube(d, random.randint(10, 18), random.randint(165, 178), random.randint(10, 14))
    if random.random() < 0.4:  # pin
        d.line([(8, 30), (26, 12)], fill=(230, 230, 230), width=4)
    # frame lines from neighbours
    if random.random() < 0.6:
        d.rectangle([0, 0, 199, 199], outline=(150, 150, 150), width=random.randint(1, 3))
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
    for k in range(N):
        photograph(tile(icon, rid)).save(os.path.join(OUT, rid, f'{k:04d}.jpg'), quality=92)
# empty tiles
os.makedirs(os.path.join(OUT, 'empty'), exist_ok=True)
for k in range(N):
    t = background(None)
    d = ImageDraw.Draw(t)
    d.rectangle([0, 0, 199, 199], outline=(150, 150, 150), width=random.randint(1, 4))
    photograph(t).save(os.path.join(OUT, 'empty', f'{k:04d}.jpg'), quality=92)
print('done')
