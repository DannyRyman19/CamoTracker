"""Trains the stash tile classifier (stash_icons.tflite) on synth.py's tiles.

The iPhone's HajinStashIcons.mlmodel is Create ML's scene print plus a
logistic regressor; this is the same idea on a mobile backbone: an
ImageNet MobileNetV3 with a softmax head, first trained on frozen features,
then fine-tuned end to end with light augmentation. Real tiles (the iOS
repo's Tools/stash-scan/real) are only used to report accuracy.

usage: train_icons.py SYN_DIR REAL_DIR REFS_OTHER_DIR OUT_DIR [--backbone large|small] [--size 224]
         [--head-epochs 40] [--tune-epochs 8]
writes OUT_DIR/stash_icons.tflite, OUT_DIR/stash_icons_labels.txt and
OUT_DIR/stash_icons_aliases.txt (item id -> class, for items sharing a picture)
"""
import argparse, hashlib, os, random, sys
import numpy as np
from PIL import Image

ap = argparse.ArgumentParser()
ap.add_argument('syn'); ap.add_argument('real'); ap.add_argument('refs_other'); ap.add_argument('out')
ap.add_argument('--backbone', default='large')
ap.add_argument('--size', type=int, default=224)
ap.add_argument('--head-epochs', type=int, default=40)
ap.add_argument('--tune-epochs', type=int, default=8)
ap.add_argument('--seed', type=int, default=1)
args = ap.parse_args()

import tensorflow as tf
import keras
random.seed(args.seed); np.random.seed(args.seed); tf.random.set_seed(args.seed)
S = args.size
os.makedirs(args.out, exist_ok=True)

classes = sorted(d for d in os.listdir(args.syn) if os.path.isdir(os.path.join(args.syn, d)))
index = {c: i for i, c in enumerate(classes)}

# Items that share a picture share a class named x-<first id>: map every
# item id to its class so real tiles of the other ids score correctly
alias = {}
groups = {}
for f in sorted(os.listdir(args.refs_other)):
    if f.endswith('.png'):
        groups.setdefault(hashlib.md5(open(os.path.join(args.refs_other, f), 'rb').read()).hexdigest(), []).append(f[:-4])
for ids in groups.values():
    cls = ids[0] if len(ids) == 1 else 'x-' + ids[0]
    for i in ids: alias[i] = cls
for c in classes: alias.setdefault(c[2:] if c.startswith('x-') else c, c)


def load(path):
    return np.asarray(Image.open(path).convert('RGB').resize((S, S), Image.BILINEAR), dtype=np.uint8)


def folder(root, mapping):
    xs, ys, names = [], [], []
    for d in sorted(os.listdir(root)):
        p = os.path.join(root, d)
        if not os.path.isdir(p): continue
        cls = mapping(d)
        if cls is None:
            print('no class for', d); continue
        for f in sorted(os.listdir(p)):
            if f.startswith('.'): continue
            xs.append(load(os.path.join(p, f))); ys.append(index[cls]); names.append(f'{d}/{f}')
    return np.stack(xs), np.array(ys), names


X, Y, _ = folder(args.syn, lambda d: d)
R, RY, rnames = folder(args.real, lambda d: alias.get(d))
print('synthetic', X.shape, 'real', R.shape, 'classes', len(classes))

# Hold out a tenth of the synthetic tiles to watch overfitting
perm = np.random.permutation(len(X))
cut = len(X) // 10
vi, ti = perm[:cut], perm[cut:]

Backbone = keras.applications.MobileNetV3Large if args.backbone == 'large' else keras.applications.MobileNetV3Small
base = Backbone(input_shape=(S, S, 3), include_top=False, weights='imagenet', pooling='avg',
                include_preprocessing=True, minimalistic=False)
base.trainable = False

augment = keras.Sequential([
    keras.layers.RandomTranslation(0.04, 0.04, fill_mode='nearest'),
    keras.layers.RandomZoom(0.06, fill_mode='nearest'),
    keras.layers.RandomBrightness(0.12, value_range=(0, 255)),
    keras.layers.RandomContrast(0.15),
])

inp = keras.Input((S, S, 3), dtype='float32')
feat = base(inp, training=False)
drop = keras.layers.Dropout(0.2)(feat)
out = keras.layers.Dense(len(classes), activation='softmax', kernel_regularizer=keras.regularizers.l2(1e-4))(drop)
model = keras.Model(inp, out)


def dataset(ix, train):
    ds = tf.data.Dataset.from_tensor_slices((X[ix], Y[ix]))
    if train: ds = ds.shuffle(len(ix), seed=args.seed)
    ds = ds.batch(64).map(lambda a, b: (tf.cast(a, tf.float32), b))
    if train: ds = ds.map(lambda a, b: (tf.clip_by_value(augment(a, training=True), 0, 255), b))
    return ds.prefetch(4)


def real_accuracy(predict):
    p = predict(R)
    top = p.argmax(1)
    ok = top == RY
    for k in np.where(~ok)[0]:
        print('  MISS', rnames[k], '->', classes[top[k]], f'{p[k, top[k]]:.2f}', '(truth', f'{p[k, RY[k]]:.2f})')
    return ok.mean(), ok.sum()


# 1. The head alone, on frozen features (computed once: fast)
fx = base.predict(X.astype(np.float32), batch_size=128, verbose=0)
head_in = keras.Input((fx.shape[1],))
head_out = model.layers[-1](model.layers[-2](head_in))
head = keras.Model(head_in, head_out)
head.compile(keras.optimizers.Adam(1e-3), 'sparse_categorical_crossentropy', metrics=['accuracy'])
head.fit(fx[ti], Y[ti], validation_data=(fx[vi], Y[vi]), epochs=args.head_epochs, batch_size=64, verbose=2)
acc, n = real_accuracy(lambda a: model.predict(a.astype(np.float32), batch_size=128, verbose=0))
print(f'after head: real {n}/{len(R)} = {acc:.4f}')

# 2. Fine-tune everything (BatchNorm frozen) at a low rate
if args.tune_epochs > 0:
    base.trainable = True
    for layer in base.layers:
        if isinstance(layer, keras.layers.BatchNormalization): layer.trainable = False
    model.compile(keras.optimizers.Adam(1e-4), 'sparse_categorical_crossentropy', metrics=['accuracy'])
    model.fit(dataset(ti, True), validation_data=dataset(vi, False), epochs=args.tune_epochs, verbose=2)
    acc, n = real_accuracy(lambda a: model.predict(a.astype(np.float32), batch_size=128, verbose=0))
    print(f'after fine-tune: real {n}/{len(R)} = {acc:.4f}')

# 3. TFLite: float32 input 0..255 RGB (S x S), softmax out; weights int8
#    (dynamic range), checked again on the real tiles
model.export(os.path.join(args.out, 'icons_saved'), verbose=False)
conv = tf.lite.TFLiteConverter.from_saved_model(os.path.join(args.out, 'icons_saved'))
conv.optimizations = [tf.lite.Optimize.DEFAULT]
tfl = conv.convert()
path = os.path.join(args.out, 'stash_icons.tflite')
open(path, 'wb').write(tfl)
print('tflite', len(tfl) // 1024, 'KB')
interp = tf.lite.Interpreter(model_path=path)
interp.allocate_tensors()
i0, o0 = interp.get_input_details()[0], interp.get_output_details()[0]


def tfl_predict(a):
    out = []
    for x in a:
        interp.set_tensor(i0['index'], x[None].astype(np.float32)); interp.invoke()
        out.append(interp.get_tensor(o0['index'])[0])
    return np.stack(out)


acc, n = real_accuracy(tfl_predict)
print(f'tflite: real {n}/{len(R)} = {acc:.4f}')
with open(os.path.join(args.out, 'stash_icons_labels.txt'), 'w') as f:
    f.write('\n'.join(classes) + '\n')
with open(os.path.join(args.out, 'stash_icons_aliases.txt'), 'w') as f:
    f.write('\n'.join(f'{k}\t{v}' for k, v in sorted(alias.items()) if k != v) + '\n')
