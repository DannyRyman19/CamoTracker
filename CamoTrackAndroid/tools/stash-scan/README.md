# Stash photo reader: the Android models

The Android port of the iPhone's DMZ stash photo reader lives in
`app/src/main/java/app/camotrack/android/hajin/scan/` and uses two
TensorFlow Lite models in `app/src/main/assets/models/`:

| File | iPhone counterpart | What it is |
|---|---|---|
| `stash_icons.tflite` + `stash_icons_labels.txt` | `HajinStashIcons.mlmodel` | tile classifier: one class per ingredient, one per distinct picture of every other guide item (`x-<first id>` when items share it), `empty` (167 on 2026-11-17). Input 1x224x224x3 float RGB 0-255 (the 200 px tile stretched), output softmax in label order. |
| `stash_tiles.tflite` | `HajinStashTiles.mlmodel` | tile detector: a small CenterNet. Input 1x320x320x3 float RGB 0-255 (the whole photo stretched to the square, as iPhone's `.scaleFill`), output 1x40x40x5: per cell a tile-centre score, the centre's offset in the cell, the box's width and height in cells. Decoded by `TileHeatmap.decode`. |

Create ML models can't be converted (they sit on Apple's FeaturePrint), so
these are retrained from the same generated data, made by the iPhone repo's
own generators in `MW4CamoTracker/Tools/stash-scan/` (read its README first:
it explains the tiles, the classes and the real tiles in `real/`).

## Retraining

Everything goes in a scratch folder (`$W` below), never system-wide. Python
3.11 from `uv`, TensorFlow 2.19; all packages pinned to releases before
the cut-off date.

```sh
W=/private/tmp/stash-train            # any scratch folder
IOS=~/CamoTracker/MW4CamoTracker/Tools/stash-scan
HERE=~/CamoTracker/CamoTrackAndroid/tools/stash-scan
export UV_PYTHON_INSTALL_DIR=~/.cache/uv-python UV_CACHE_DIR=~/.cache/uv
uv python install 3.11
uv venv -p 3.11 $W/venv
VIRTUAL_ENV=$W/venv uv pip install --exclude-newer 2026-10-31 "tensorflow==2.19.0" "pillow==11.2.1" "numpy<2.2"
P=$W/venv/bin/python

# 1. Tiles, exactly as the iPhone README makes them
cd $IOS
$P fetch_icons.py $W/stash
$P synth.py $W/stash/refs $W/stash/syn 90
$P synth.py $W/stash/refs_other_unique $W/stash/syn 40

# 2. The classifier (~25 min on an M1 Max CPU): head on frozen
#    MobileNetV3-Large features, then 8 epochs fine-tuning; prints its
#    score on real/ (and on real/ again through the .tflite)
$P $HERE/train_icons.py $W/stash/syn $IOS/real $W/stash/refs_other $W/icons

# 3. Stash screens for the detector: the tiles plus the real ones, over
#    backdrops (any photos without a stash grid: 300 of the repo's calling
#    cards and camo pictures, at most 800 px)
mkdir -p $W/grid/backdrops
$P - $W/grid/backdrops <<'EOF'
import os, random, sys
from PIL import Image
random.seed(3); root = os.path.expanduser('~/CamoTracker/Images'); files = []
for sub in ['CallingCards', 'Camos', 'seasons', 'BO7', 'MW3', 'BO6']:
    for dp, _, fs in os.walk(os.path.join(root, sub)):
        files += [os.path.join(dp, f) for f in fs if f.lower().endswith(('.png', '.jpg'))]
random.shuffle(files); n = 0
for f in files:
    try: im = Image.open(f).convert('RGB')
    except Exception: continue
    if min(im.size) < 200: continue
    im.thumbnail((800, 800)); im.save(f'{sys.argv[1]}/b{n:03d}.jpg', quality=85); n += 1
    if n >= 300: break
EOF
mkdir -p $W/grid/tiles && cp -R $W/stash/syn/. $W/grid/tiles/
for d in $IOS/real/*; do mkdir -p $W/grid/tiles/$(basename $d); cp $d/* $W/grid/tiles/$(basename $d)/; done
for s in 11 21 31 41; do $P $HERE/run_synth_grid.py $IOS/synth_grid.py $s $W/grid/tiles $W/grid/backdrops $W/grid/train$s 1000; done
$P $HERE/run_synth_grid.py $IOS/synth_grid.py 12 $W/grid/tiles $W/grid/backdrops $W/grid/val 300   # held out

# 4. The detector (~75 min): 24 epochs on the 4,000 screens plus one
#    random-aspect crop of each
$P $HERE/train_tiles.py $W/tiles $W/grid/val $W/grid/train11 $W/grid/train21 $W/grid/train31 $W/grid/train41

# 5. Into the app
cp $W/icons/stash_icons.tflite $W/icons/stash_icons_labels.txt $W/tiles/stash_tiles.tflite \
   ~/CamoTracker/CamoTrackAndroid/app/src/main/assets/models/
```

`run_synth_grid.py` runs the iPhone's `synth_grid.py` with another seed (its
README says to change `random.seed` for the validation set).

## Checking against the iPhone models

`eval/` compares the two on the same data, on a Mac:

```sh
cd $HERE/eval
xcrun coremlcompiler compile $IOS/../../Sources/HajinStashIcons.mlmodel $W/coreml
xcrun coremlcompiler compile $IOS/../../Sources/HajinStashTiles.mlmodel $W/coreml
swiftc -O coreml_eval.swift -o $W/coreml_eval
$W/coreml_eval classify $W/coreml/HajinStashIcons.mlmodelc $IOS/real $W/coreml_real.json   # Core ML on real tiles
$W/coreml_eval detect $W/coreml/HajinStashTiles.mlmodelc $W/grid/val $W/coreml_val.json      # Core ML detector
$P predict_tiles.py $W/tiles/stash_tiles.tflite $W/grid/val $W/tflite_val.json               # this detector
for f in $W/coreml_val.json $W/tflite_val.json; do $P score_boxes.py $W/grid/val/annotations.json $f; $P lattice_eval.py $W/grid/val/annotations.json $f; done
```

`lattice_eval.py` is the number that matters: the grid's corners found from
each detector's boxes (the same lattice fit as `TileLattice`/`GridFinder.fromDetector`)
against the corners from the true boxes, as a share of the photo's long side.

Then on a device or emulator (installs only the test APK; the app must be
a current debug build):

```sh
./gradlew assembleDebugAndroidTest
adb install -r -t app/build/outputs/apk/androidTest/debug/app-debug-androidTest.apk
adb shell am instrument -w -e class app.camotrack.android.hajin.scan.ScanModelsOnDeviceTest \
    app.camotrack.android.test/androidx.test.runner.AndroidJUnitRunner
adb logcat -d -s StashScan
```

`ScanModelsOnDeviceTest` needs `app/src/androidTest/assets/scan/`: `real/`
(a copy of the iPhone's real tiles), `stash_icons_aliases.txt` (from
`train_icons.py`), `python_icons.tsv` (the training script's own TFLite
answers, so a preprocessing slip in Kotlin shows) and `grids/` (40 held-out
screens). Regenerate `python_icons.tsv` after retraining:

```sh
$P - <<'EOF'
import os, numpy as np, tensorflow as tf
from PIL import Image
A = os.path.expanduser('~/CamoTracker/CamoTrackAndroid/app/src')
it = tf.lite.Interpreter(model_path=A + '/main/assets/models/stash_icons.tflite'); it.allocate_tensors()
i0, o0 = it.get_input_details()[0], it.get_output_details()[0]
labels = open(A + '/main/assets/models/stash_icons_labels.txt').read().split()
root, out = A + '/androidTest/assets/scan/real', []
for c in sorted(os.listdir(root)):
    for f in sorted(os.listdir(os.path.join(root, c))):
        x = np.asarray(Image.open(os.path.join(root, c, f)).convert('RGB').resize((224, 224), Image.BILINEAR), dtype=np.float32)
        it.set_tensor(i0['index'], x[None]); it.invoke(); p = it.get_tensor(o0['index'])[0]
        out.append(f'{c}/{f}\t{labels[p.argmax()]}\t{p.max():.4f}')
open(A + '/androidTest/assets/scan/python_icons.tsv', 'w').write('\n'.join(out) + '\n')
EOF
```

## Results (2026-11-17)

Real tiles (`real/`, 220 tiles cut from real stash and backpack photos;
none of them used in training):

| | Core ML (iPhone) | `stash_icons.tflite` |
|---|---|---|
| right | 215 / 220 (97.7%) | **219 / 220 (99.5%)**, the same on a device through the Kotlin preprocessing (all 220 answers equal Python's) |
| misses | Cipher Code Ledger as Sanctioned Assassination List (x2), Encrypted Archive as Nuclear Program Files (x2), Weak NVGs | Weak NVGs as Large Scavenger Backpack (gear for gear; My stash never sees either) |
| size | 1.0 MB (+ the OS's scene print) | 3.4 MB (MobileNetV3-Large, int8 weights) |

Trained on 10,450 synth.py tiles (90 per ingredient and valuable, 40 for
everything else, 90 empty; a tenth held out): head 40 epochs, fine-tune 8
epochs (training accuracy 99.8%, held-out synthetic 99.3%). MobileNetV3-Small
was tried too (1.2 MB): 220/220 in Keras but 218/220 once quantized, and both
misses were ingredients read as other items, so Large it is.

Tile detector, on 300 held-out generated screens (seed 12) that neither
model saw, scored by `eval/`:

| | Core ML (iPhone) | `stash_tiles.tflite` |
|---|---|---|
| boxes at confidence 0.5 (IoU 0.5) | precision 70.9%, recall 85.9% | precision 99.7%, recall 92.8% |
| grid not found (under 8 tiles) | 7 / 300 | 2 / 300 |
| grid corners off (mean / median, share of the photo's long side) | 1.56% / 1.11% | **0.46% / 0.18%** |
| size | 6.7 MB | 1.1 MB |

The iPhone README measured its detector at 1.5% on seven real photos, in
line with its 1.56% here. There are no full real stash photos in either
repo, so the detector hasn't been checked on real ones: add some (with
their corners) and run `lattice_eval.py` on them before trusting it fully.
Trained on 4,000 screens (`run_synth_grid.py` seeds 11/21/31/41, 1,000 each)
plus one random-aspect crop of each (16:9 and tall photos stretch
differently into the square), 24 epochs, batch 32, Adam with cosine decay
from 2e-3.

## What it adds to the app

Per device (arm64-v8a; Play's per-ABI split): the two models 4.6 MB, LiteRT's
`libtensorflowlite_jni.so` 4.5 MB, ML Kit's bundled OCR
(`libmlkit_google_ocr_pipeline.so` 11.1 MB plus 1.5 MB of its models), about
21.7 MB installed, roughly 11 MB to download compressed. A universal APK
carries all four ABIs' libraries: about +67 MB. To cut it, switch to
`com.google.android.gms:play-services-mlkit-text-recognition` (the same API,
OCR downloaded by Play services: ~12.6 MB less per ABI) and/or LiteRT in
Play services (`play-services-tflite-java`, ~4.5 MB less); nothing in
`hajin.scan` but the Gradle line changes for the first.
