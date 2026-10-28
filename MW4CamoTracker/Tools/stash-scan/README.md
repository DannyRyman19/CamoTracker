# Stash photo reader: the icon model

`Sources/HajinStashIcons.mlmodel` names each tile of a photographed DMZ stash
grid. It is an image classifier with one class per ingredient, one per
distinct picture of every other guide item (keys, gear, valuables...; items
sharing a picture share a class, named `x-<first id>`), plus `empty` (a blank
tile). Only ingredient counts reach My stash; the rest are recognised so they
aren't mistaken for ingredients on the All or Misc tabs. It's trained only on generated tiles: each
guide picture pasted onto a game-style tile (rarity colour, dot pattern, a
count, the cube mark or a valuable's diamond, sometimes a pin; valuables get
as many tiles as an ingredient; blueprint items also on the
backpack's blue blueprint tile, and the weapon manual mostly on its TSD
stamp), then damaged the way a phone photo of
a TV is (colour cast, blur, moire, glare, JPEG, a slight tilt).

Retrain it when ingredients or their pictures change:

```sh
cd MW4CamoTracker/Tools/stash-scan
python3 fetch_icons.py /tmp/stash        # guide pictures (from the repo's Images/DMZ) -> /tmp/stash/refs, refs_other
python3 synth.py /tmp/stash/refs /tmp/stash/syn 90
python3 synth.py /tmp/stash/refs_other_unique /tmp/stash/syn 40   # one file per distinct picture
# Create ML fails ("Failed to create CVPixelBufferPool") on all ~8,800
# tiles: train on 60 a class, picked at random (~7,400)
python3 -c "import os,random;random.seed(1);s='/tmp/stash/syn';[os.makedirs(f'/tmp/stash/cap/{c}',exist_ok=True) or [os.link(f'{s}/{c}/{f}',f'/tmp/stash/cap/{c}/{f}') for f in random.sample(sorted(os.listdir(f'{s}/{c}')),min(60,len(os.listdir(f'{s}/{c}'))))] for c in os.listdir(s)]"
swiftc -O train.swift -o /tmp/stash/train   # augmentation off: with ~125 classes it runs out of buffers
/tmp/stash/train /tmp/stash/cap <real-tiles-dir> /tmp/stash/HajinStashIcons.mlmodel 25
cp /tmp/stash/HajinStashIcons.mlmodel ../../Sources/
```

`synth.py` needs Pillow (`/usr/bin/python3` on this Mac has it). The real
tiles folder is for checking only: straightened 200 px tiles from real stash
photos, in one folder per item id. The model uses Vision's scene print
revision 2, so the feature is iOS 17+ (revision 1 works on iOS 16 but scored
94% on real tiles against 100%).

The rest of the reader is in `Sources/HajinStashGrid.swift`: straightening
from the four corners, fitting the grid to the tiles' grey frame lines,
voting across three crops per tile, and the stack-count reader (digit
templates from real stash photos plus the Hitmarker font). Debug builds write
what they read to `Documents/grid_debug.txt`; `SS_GRID_PHOTO`,
`SS_GRID_CORNERS` and `SS_GRID_READ=1` run it from launch.

# Finding the grid: the tile detector

`Sources/HajinStashTiles.mlmodel` finds stash tiles (filled or empty) in a
photo; `HajinTileLattice` fits the 6-wide grid through them (columns and
rows from each tile's neighbours, a perspective fit, the solid block of
rows and columns with two or more tiles). It's the finder's first choice;
the header-and-frame-line ways are the fallback when it finds under 8.
It's trained on generated stash screens: grids built from tiles (synth.py's,
plus real ones), tilted to a phone's angle over a backdrop, with TV damage.

```sh
python3 synth_grid.py <tiles> <backdrops> /tmp/grid/train 1200
python3 synth_grid.py <tiles> <backdrops> /tmp/grid/val 150      # change random.seed first
swiftc -O train_grid.swift -o /tmp/grid/train_grid
/tmp/grid/train_grid /tmp/grid/train /tmp/grid/val /tmp/grid/HajinStashTiles.mlmodel 1500
cp /tmp/grid/HajinStashTiles.mlmodel ../../Sources/
```

The detector doesn't run in the simulator (it returns almost nothing), so
check it on a device: copy photos to the app's `Documents/gridbatch/` and
launch a Debug build with `SS_GRID_BATCH=1`; the corners land in
`gridbatch/corners.json`. Run the model with `.scaleFill`: it was trained on
images stretched to its square, and letterboxing shifts every box's x.
On the seven real photos (2026-10-27) the corners are 1.5% of the photo
off on average, against 8.6% for the old finder.
