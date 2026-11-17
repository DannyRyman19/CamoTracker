"""Runs stash_tiles.tflite over a folder of photos and writes its boxes in
coreml_eval's format ({image: [[x, y, w, h, confidence], ...]}, pixels, origin
top left), decoded as StashTileDetector/TileHeatmap.kt does, for
score_boxes.py and lattice_eval.py.

usage: predict_tiles.py MODEL.tflite IMAGE_DIR OUT.json
"""
import json, os, sys
import numpy as np
from PIL import Image
import tensorflow as tf

model, folder, out = sys.argv[1:4]
it = tf.lite.Interpreter(model_path=model); it.allocate_tensors()
i0, o0 = it.get_input_details()[0], it.get_output_details()[0]
S = i0['shape'][1]
result = {}
for f in sorted(os.listdir(folder)):
    if not f.endswith(('.jpg', '.png')): continue
    im = Image.open(os.path.join(folder, f)).convert('RGB')
    W, H = im.size
    x = np.asarray(im.resize((S, S), Image.BOX if W > S else Image.BILINEAR), dtype=np.float32)
    it.set_tensor(i0['index'], x[None]); it.invoke()
    o = it.get_tensor(o0['index'])[0]
    G = o.shape[0]; stride = S / G
    heat = o[..., 0]
    boxes = []
    for y in range(G):
        for xx in range(G):
            v = heat[y, xx]
            if v < 0.2 or v < heat[max(0, y - 1):y + 2, max(0, xx - 1):xx + 2].max(): continue
            ox, oy, w, h = o[y, xx, 1:]
            cx, cy = (xx + ox) * stride, (y + oy) * stride
            boxes.append([float((cx - w * stride / 2) * W / S), float((cy - h * stride / 2) * H / S),
                          float(w * stride * W / S), float(h * stride * H / S), float(v)])
    result[f] = boxes
json.dump(result, open(out, 'w'))
print(len(result), 'photos')
