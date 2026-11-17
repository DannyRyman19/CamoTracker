"""Trains the stash tile detector (stash_tiles.tflite) on synth_grid.py's screens.

The iPhone's HajinStashTiles.mlmodel is a Create ML object detector. Here
it's a small CenterNet: MobileNetV3-Small features at strides 8/16/32
merged into one 40 x 40 map (for a 320 x 320 input), each cell giving
"a tile's centre is here" (a sigmoid), where in the cell, and the box's
width and height. Every tile in a stash is about the same size and they
never overlap, so a centre heatmap suits them better than anchors, and it
decodes in a few lines of Kotlin (StashTileDetector).

Images are stretched to the square (scale-fill), as on iPhone.

usage: train_tiles.py OUT_DIR VAL_DIR TRAIN_DIR [TRAIN_DIR...] [--epochs 24] [--size 320]
writes OUT_DIR/stash_tiles.tflite and prints precision/recall on VAL_DIR
"""
import argparse, json, math, os, random
import numpy as np
from PIL import Image

ap = argparse.ArgumentParser()
ap.add_argument('out'); ap.add_argument('val'); ap.add_argument('train', nargs='+')
ap.add_argument('--epochs', type=int, default=24)
ap.add_argument('--size', type=int, default=320)
ap.add_argument('--crops', type=int, default=1, help='extra random-aspect crops per training screen')
ap.add_argument('--seed', type=int, default=1)
args = ap.parse_args()

import tensorflow as tf
import keras
random.seed(args.seed); np.random.seed(args.seed); tf.random.set_seed(args.seed)
S, STRIDE = args.size, 8
G = S // STRIDE
os.makedirs(args.out, exist_ok=True)


def boxes_of(entry):
    out = []
    for a in entry['annotations']:
        c = a['coordinates']
        out.append((c['x'] - c['width'] / 2, c['y'] - c['height'] / 2, c['x'] + c['width'] / 2, c['y'] + c['height'] / 2))
    return out


def squash(im, boxes, crop=None):
    """Crop (x0, y0, x1, y1) of the photo, stretched to S x S, and its boxes."""
    W, H = im.size
    x0, y0, x1, y1 = crop or (0, 0, W, H)
    im = im.crop((int(x0), int(y0), int(x1), int(y1))).resize((S, S), Image.BILINEAR)
    sx, sy = S / (int(x1) - int(x0)), S / (int(y1) - int(y0))
    out = []
    for bx0, by0, bx1, by1 in boxes:
        cx0, cy0, cx1, cy1 = max(bx0, x0), max(by0, y0), min(bx1, x1), min(by1, y1)
        if cx1 - cx0 <= 0 or cy1 - cy0 <= 0: continue
        # mostly cut off: not a tile any more (as synth_grid labels the photo's edge)
        if (cx1 - cx0) * (cy1 - cy0) < 0.6 * (bx1 - bx0) * (by1 - by0): continue
        out.append(((cx0 - int(x0)) * sx, (cy0 - int(y0)) * sy, (cx1 - int(x0)) * sx, (cy1 - int(y0)) * sy))
    return np.asarray(im, dtype=np.uint8), out


def random_crop(W, H):
    """A crop at another aspect (a 16:9 screenshot, a tall phone photo)."""
    for _ in range(20):
        aspect = math.exp(random.uniform(math.log(0.5), math.log(2.0)))
        area = random.uniform(0.55, 1.0) * W * H
        w, h = math.sqrt(area * aspect), math.sqrt(area / aspect)
        if w <= W and h <= H:
            x, y = random.uniform(0, W - w), random.uniform(0, H - h)
            return (x, y, x + w, y + h)
    return None


def load(dirs, crops):
    X, B = [], []
    for d in dirs:
        for e in json.load(open(os.path.join(d, 'annotations.json'))):
            im = Image.open(os.path.join(d, e['image'])).convert('RGB')
            boxes = boxes_of(e)
            x, b = squash(im, boxes); X.append(x); B.append(b)
            for _ in range(crops):
                c = random_crop(*im.size)
                if c:
                    x, b = squash(im, boxes, c); X.append(x); B.append(b)
    return np.stack(X), B


def targets(boxes):
    heat = np.zeros((G, G), np.float32)
    reg = np.zeros((G, G, 4), np.float32)      # offset x, y in the cell; width, height in cells
    mask = np.zeros((G, G), np.float32)
    ys, xs = np.mgrid[0:G, 0:G]
    for x0, y0, x1, y1 in boxes:
        cx, cy = (x0 + x1) / 2 / STRIDE, (y0 + y1) / 2 / STRIDE
        w, h = (x1 - x0) / STRIDE, (y1 - y0) / STRIDE
        ix, iy = min(G - 1, int(cx)), min(G - 1, int(cy))
        sigma = max(0.35, min(w, h) / 6)
        g = np.exp(-((xs - ix) ** 2 + (ys - iy) ** 2) / (2 * sigma ** 2))
        heat = np.maximum(heat, g)
        heat[iy, ix] = 1
        reg[iy, ix] = (cx - ix, cy - iy, w, h)
        mask[iy, ix] = 1
    return np.concatenate([heat[..., None], reg, mask[..., None]], -1)


print('loading')
X, BX = load(args.train, args.crops)
VX, VB = load([args.val], 0)
Y = np.stack([targets(b) for b in BX])
print('train', X.shape, 'val', VX.shape, 'tiles', sum(len(b) for b in BX))

base = keras.applications.MobileNetV3Small(input_shape=(S, S, 3), include_top=False, weights='imagenet',
                                           include_preprocessing=True, minimalistic=False)
c8 = base.get_layer('expanded_conv_2_add').output
c16 = base.get_layer('expanded_conv_7_add').output
c32 = base.get_layer('expanded_conv_10_add').output
L = keras.layers


def conv(x, n, k=3):
    x = L.Conv2D(n, k, padding='same', use_bias=False)(x)
    x = L.BatchNormalization()(x)
    return L.ReLU()(x)


p32 = conv(c32, 64, 1)
p16 = L.Add()([conv(c16, 64, 1), L.UpSampling2D(interpolation='bilinear')(p32)])
p8 = L.Add()([conv(c8, 64, 1), L.UpSampling2D(interpolation='bilinear')(conv(p16, 64))])
f = conv(conv(p8, 64), 64)
heat = L.Conv2D(1, 1, activation='sigmoid', bias_initializer=keras.initializers.Constant(-2.19), name='heat')(f)
reg = L.Conv2D(4, 1, name='reg')(f)
model = keras.Model(base.input, L.Concatenate(name='out')([heat, reg]))


def loss(y, p):
    gt, mask = y[..., 0], y[..., 5]
    hp = tf.clip_by_value(p[..., 0], 1e-4, 1 - 1e-4)
    pos = tf.cast(gt >= 1, tf.float32)
    focal = -(pos * (1 - hp) ** 2 * tf.math.log(hp) + (1 - pos) * (1 - gt) ** 4 * hp ** 2 * tf.math.log(1 - hp))
    n = tf.maximum(tf.reduce_sum(mask), 1.0)
    off = tf.reduce_sum(tf.abs(p[..., 1:3] - y[..., 1:3]) * mask[..., None])
    size = tf.reduce_sum(tf.abs(p[..., 3:5] - y[..., 3:5]) * mask[..., None])
    return (tf.reduce_sum(focal) + off + 0.2 * size) / n


ds = tf.data.Dataset.from_tensor_slices((X, Y)).shuffle(len(X), seed=args.seed).batch(32)
color = keras.Sequential([L.RandomBrightness(0.15, value_range=(0, 255)), L.RandomContrast(0.2)])
ds = ds.map(lambda a, b: (tf.clip_by_value(color(tf.cast(a, tf.float32), training=True), 0, 255), b)).prefetch(4)
steps = args.epochs * math.ceil(len(X) / 32)
model.compile(keras.optimizers.Adam(keras.optimizers.schedules.CosineDecay(2e-3, steps, alpha=0.02)), loss)
model.fit(ds, epochs=args.epochs, verbose=2)


def decode(out, threshold=0.5):
    """The same decoding as StashTileDetector.kt: 3x3 peaks over the threshold."""
    h = out[..., 0]
    boxes = []
    for y in range(G):
        for x in range(G):
            v = h[y, x]
            if v < threshold: continue
            if v < h[max(0, y - 1):y + 2, max(0, x - 1):x + 2].max(): continue
            ox, oy, w, hh = out[y, x, 1:]
            cx, cy = (x + ox) * STRIDE, (y + oy) * STRIDE
            boxes.append((cx - w * STRIDE / 2, cy - hh * STRIDE / 2, cx + w * STRIDE / 2, cy + hh * STRIDE / 2, float(v)))
    return boxes


def iou(a, b):
    ix = max(0, min(a[2], b[2]) - max(a[0], b[0])); iy = max(0, min(a[3], b[3]) - max(a[1], b[1]))
    i = ix * iy
    return i / ((a[2] - a[0]) * (a[3] - a[1]) + (b[2] - b[0]) * (b[3] - b[1]) - i + 1e-9)


def score(preds, truths):
    tp = fp = fn = 0
    for p, t in zip(preds, truths):
        used = set()
        for b in sorted(p, key=lambda b: -b[4]):
            m = max(range(len(t)), key=lambda k: iou(b, t[k]) if k not in used else -1, default=None)
            if m is not None and m not in used and iou(b, t[m]) >= 0.5: tp += 1; used.add(m)
            else: fp += 1
        fn += len(t) - len(used)
    return tp / max(tp + fp, 1), tp / max(tp + fn, 1)


raw = model.predict(VX.astype(np.float32), batch_size=32, verbose=0)
for th in (0.3, 0.4, 0.5):
    pr, rc = score([decode(o, th) for o in raw], VB)
    print(f'keras val @ {th}: precision {pr:.4f} recall {rc:.4f}')

model.export(os.path.join(args.out, 'tiles_saved'), verbose=False)
conv_ = tf.lite.TFLiteConverter.from_saved_model(os.path.join(args.out, 'tiles_saved'))
conv_.optimizations = [tf.lite.Optimize.DEFAULT]
tfl = conv_.convert()
path = os.path.join(args.out, 'stash_tiles.tflite')
open(path, 'wb').write(tfl)
print('tflite', len(tfl) // 1024, 'KB')
it = tf.lite.Interpreter(model_path=path); it.allocate_tensors()
i0, o0 = it.get_input_details()[0], it.get_output_details()[0]
outs = []
for x in VX:
    it.set_tensor(i0['index'], x[None].astype(np.float32)); it.invoke(); outs.append(it.get_tensor(o0['index'])[0])
pr, rc = score([decode(o) for o in outs], VB)
print(f'tflite val @ 0.5: precision {pr:.4f} recall {rc:.4f}')
