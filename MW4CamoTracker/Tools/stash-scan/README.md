# Stash photo reader: the icon model

`Sources/HajinStashIcons.mlmodel` names each tile of a photographed DMZ stash
grid. It is an image classifier with one class per ingredient, plus `empty`
(a blank tile) and `other` (anything that isn't an ingredient, e.g. gear or
keys on the stash's All tab). It's trained only on generated tiles: each
guide picture pasted onto a game-style tile (rarity colour, dot pattern, a
count, the cube mark, sometimes a pin), then damaged the way a phone photo of
a TV is (colour cast, blur, moire, glare, JPEG, a slight tilt).

Retrain it when ingredients or their pictures change:

```sh
cd MW4CamoTracker/Tools/stash-scan
python3 fetch_icons.py /tmp/stash        # guide pictures -> /tmp/stash/refs, refs_other
python3 synth.py /tmp/stash/refs /tmp/stash/syn 150
python3 synth_other.py /tmp/stash/refs_other /tmp/stash/syn
swiftc -O train.swift -o /tmp/stash/train
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
