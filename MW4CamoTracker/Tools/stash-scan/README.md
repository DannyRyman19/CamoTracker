# Stash photo reader: the icon model

`Sources/HajinStashIcons.mlmodel` names each tile of a photographed DMZ stash
grid. It is an image classifier with one class per ingredient, one per
distinct picture of every other guide item (keys, gear, valuables...; items
sharing a picture share a class, named `x-<first id>`), plus `empty` (a blank
tile). Only ingredient counts reach My stash; the rest are recognised so they
aren't mistaken for ingredients on the All or Misc tabs. It's trained only on generated tiles: each
guide picture pasted onto a game-style tile (rarity colour, dot pattern, a
count, the cube mark, sometimes a pin), then damaged the way a phone photo of
a TV is (colour cast, blur, moire, glare, JPEG, a slight tilt).

Retrain it when ingredients or their pictures change:

```sh
cd MW4CamoTracker/Tools/stash-scan
python3 fetch_icons.py /tmp/stash        # guide pictures -> /tmp/stash/refs, refs_other
python3 synth.py /tmp/stash/refs /tmp/stash/syn 90
python3 synth.py /tmp/stash/refs_other_unique /tmp/stash/syn 40   # one file per distinct picture
swiftc -O train.swift -o /tmp/stash/train   # augmentation off: with ~125 classes it runs out of buffers
/tmp/stash/train /tmp/stash/syn <real-tiles-dir> /tmp/stash/HajinStashIcons.mlmodel 25
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
