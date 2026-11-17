import json, sys
"""score_boxes.py ANNOTATIONS PRED_JSON: precision/recall at IoU .5, with the iOS
post-processing (conf > .5, one box per tile, tile-sized)."""
ann = {e['image']: [(a['coordinates']['x'] - a['coordinates']['width'] / 2, a['coordinates']['y'] - a['coordinates']['height'] / 2,
                     a['coordinates']['x'] + a['coordinates']['width'] / 2, a['coordinates']['y'] + a['coordinates']['height'] / 2)
                    for a in e['annotations']] for e in json.load(open(sys.argv[1]))}
pred = json.load(open(sys.argv[2]))
def iou(a, b):
    ix = max(0, min(a[2], b[2]) - max(a[0], b[0])); iy = max(0, min(a[3], b[3]) - max(a[1], b[1])); i = ix * iy
    return i / ((a[2] - a[0]) * (a[3] - a[1]) + (b[2] - b[0]) * (b[3] - b[1]) - i + 1e-9)
def post(bs, th):
    bs = sorted([b for b in bs if b[4] > th], key=lambda b: -b[4])
    kept = []
    for b in bs:
        bb = (b[0], b[1], b[0] + b[2], b[1] + b[3], b[4])
        if not any(iou(k, bb) > 0.35 for k in kept): kept.append(bb)
    if not kept: return kept
    sizes = sorted(((k[2] - k[0]) * (k[3] - k[1])) ** .5 for k in kept); med = sizes[len(sizes) // 2]
    return [k for k in kept if med * .65 < ((k[2] - k[0]) * (k[3] - k[1])) ** .5 < med * 1.5]
for th in (0.3, 0.5):
    tp = fp = fn = 0; perfect = 0
    for name, t in ann.items():
        p = post(pred.get(name, []), th); used = set()
        for b in p:
            m = max(range(len(t)), key=lambda k: iou(b, t[k]) if k not in used else -1, default=None)
            if m is not None and m not in used and iou(b, t[m]) >= .5: tp += 1; used.add(m)
            else: fp += 1
        fn += len(t) - len(used)
    print(f'@{th}: precision {tp / max(tp + fp, 1):.4f} recall {tp / max(tp + fn, 1):.4f} (tp {tp} fp {fp} fn {fn})')
