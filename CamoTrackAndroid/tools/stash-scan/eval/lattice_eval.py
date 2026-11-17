"""lattice_eval.py ANNOTATIONS PRED_JSON [threshold]: the grid's corners from the
predicted boxes (a port of HajinTileLattice + fromDetector) against the corners
from the true boxes, as a fraction of the photo's longer side."""
import json, sys, math
import numpy as np
from PIL import Image
import os
HALF = 0.45
def median(v): v = sorted(v); return v[len(v) // 2] if v else 0
def apply(h, x, y):
    w = h[6] * x + h[7] * y + h[8]; return ((h[0] * x + h[1] * y + h[2]) / w, (h[3] * x + h[4] * y + h[5]) / w)
def homography(pairs):
    A = np.zeros((8, 8)); b = np.zeros(8)
    for x, y, u, v in pairs:
        for row, t in (([x, y, 1, 0, 0, 0, -u * x, -u * y], u), ([0, 0, 0, x, y, 1, -v * x, -v * y], v)):
            row = np.array(row); A += np.outer(row, row); b += row * t
    try: return list(np.linalg.solve(A, b)) + [1.0]
    except np.linalg.LinAlgError: return None
def invert(h):
    m = np.array(h).reshape(3, 3)
    try: return list(np.linalg.inv(m).ravel())
    except np.linalg.LinAlgError: return None
def fit(boxes):
    if len(boxes) < 4: return None
    c = [((b[0] + b[2]) / 2, (b[1] + b[3]) / 2) for b in boxes]
    size = median([math.sqrt((b[2] - b[0]) * (b[3] - b[1])) for b in boxes])
    across, down = [], []; nb = [[] for _ in c]
    for a in range(len(c)):
        for b_ in range(len(c)):
            if a == b_: continue
            dx, dy = c[b_][0] - c[a][0], c[b_][1] - c[a][1]; l = math.hypot(dx, dy)
            if not (size * 0.6 < l < size * 1.7): continue
            nb[a].append(b_)
            if abs(dx) > abs(dy): across.append((dx, dy) if dx > 0 else (-dx, -dy))
            else: down.append((dx, dy) if dy > 0 else (-dx, -dy))
    if not across or not down: return None
    u = (median([d[0] for d in across]), median([d[1] for d in across])); v = (median([d[0] for d in down]), median([d[1] for d in down]))
    det = u[0] * v[1] - u[1] * v[0]
    if abs(det) < 1e-6: return None
    steps = lambda d: ((d[0] * v[1] - d[1] * v[0]) / det, (u[0] * d[1] - u[1] * d[0]) / det)
    mx, my = sum(p[0] for p in c) / len(c), sum(p[1] for p in c) / len(c)
    seed = max(range(len(c)), key=lambda k: (len(nb[k]), -math.hypot(c[k][0] - mx, c[k][1] - my)))
    cell = [None] * len(c); cell[seed] = (0, 0); q = [seed]
    while q:
        a = q.pop(0)
        for b_ in nb[a]:
            if cell[b_] is not None: continue
            s, t = steps((c[b_][0] - c[a][0], c[b_][1] - c[a][1]))
            if abs(s - round(s)) < 0.3 and abs(t - round(t)) < 0.3:
                cell[b_] = (cell[a][0] + round(s), cell[a][1] + round(t)); q.append(b_)
    h = None
    for _ in range(3):
        pairs = [(cell[k][0], cell[k][1], c[k][0], c[k][1]) for k in range(len(c)) if cell[k] is not None]
        if len(pairs) < 4: break
        f = homography(pairs)
        if f is None: break
        h = f; inv = invert(f)
        if inv is None: break
        taken = {}; nxt = [None] * len(c)
        for k in range(len(c)):
            x, y = apply(inv, *c[k]); err = math.hypot(x - round(x), y - round(y))
            if err >= 0.3: continue
            key = (round(x), round(y))
            if key in taken and taken[key][1] <= err: continue
            if key in taken: nxt[taken[key][0]] = None
            taken[key] = (k, err); nxt[k] = key
        cell = nxt
    if h is None: return None
    cells = [x for x in cell if x is not None]
    return (h, cells) if len(cells) >= 4 else None
def block(idx):
    cnt = {}
    for i in idx: cnt[i] = cnt.get(i, 0) + 1
    good = sorted(k for k, v in cnt.items() if v >= 2)
    if not good: return None
    runs = []; start = last = good[0]
    for k in good[1:]:
        if k != last + 1: runs.append((start, last)); start = k
        last = k
    runs.append((start, last))
    return max(runs, key=lambda r: sum(cnt[i] for i in range(r[0], r[1] + 1)))
def corners(boxes, columns=6):
    f = fit(boxes)
    if not f: return None
    h, found = f
    if len(found) < 8: return None
    rows = block([j for _, j in found])
    if not rows: return None
    cells = [(i, j) for i, j in found if rows[0] <= j <= rows[1]]
    cols = block([i for i, _ in cells])
    if not cols: return None
    lo, hi = cols
    firsts = list(range(lo, hi - columns + 2)) if hi - lo + 1 >= columns else list(range(hi - columns + 1, lo + 1))
    best = max(firsts, key=lambda f_: sum(1 for i, _ in cells if f_ <= i < f_ + columns))
    l, r = best - HALF, best + columns - 1 + HALF; t, b = rows[0] - HALF, rows[1] + HALF
    return [apply(h, x, y) for x, y in ((l, t), (r, t), (r, b), (l, b))]
def post(bs, th):
    bs = sorted([b for b in bs if b[4] > th], key=lambda b: -b[4]); kept = []
    def iou(a, b):
        ix = max(0, min(a[2], b[2]) - max(a[0], b[0])); iy = max(0, min(a[3], b[3]) - max(a[1], b[1])); i = ix * iy
        return i / ((a[2] - a[0]) * (a[3] - a[1]) + (b[2] - b[0]) * (b[3] - b[1]) - i + 1e-9)
    for b in bs:
        bb = (b[0], b[1], b[0] + b[2], b[1] + b[3])
        if not any(iou(k, bb) > 0.35 for k in kept): kept.append(bb)
    if not kept: return kept
    med = median([((k[2] - k[0]) * (k[3] - k[1])) ** .5 for k in kept])
    return [k for k in kept if med * .65 < ((k[2] - k[0]) * (k[3] - k[1])) ** .5 < med * 1.5]
if __name__ == '__main__':
    ann = json.load(open(sys.argv[1])); pred = json.load(open(sys.argv[2])); th = float(sys.argv[3]) if len(sys.argv) > 3 else 0.5
    d = os.path.dirname(sys.argv[1]); errs = []; missing = 0; n = 0
    for e in ann:
        truth = [(a['coordinates']['x'] - a['coordinates']['width'] / 2, a['coordinates']['y'] - a['coordinates']['height'] / 2,
                  a['coordinates']['x'] + a['coordinates']['width'] / 2, a['coordinates']['y'] + a['coordinates']['height'] / 2) for a in e['annotations']]
        tc = corners(truth)
        if tc is None: continue
        n += 1
        W, H = Image.open(os.path.join(d, e['image'])).size
        pc = corners(post(pred.get(e['image'], []), th))
        if pc is None: missing += 1; continue
        errs.append(sum(math.hypot(a[0] - b[0], a[1] - b[1]) for a, b in zip(tc, pc)) / 4 / max(W, H))
    errs.sort()
    print(f'{n} screens: no grid {missing}; corner error mean {np.mean(errs) * 100:.2f}% median {errs[len(errs) // 2] * 100:.2f}% '
          f'within 2%: {sum(e < .02 for e in errs)} within 5%: {sum(e < .05 for e in errs)}')
