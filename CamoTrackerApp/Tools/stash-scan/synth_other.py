"""Adds an 'other' class to the synthetic set: tiles of non-ingredient icons
(gear, keys, valuables, consumables), so the All tab's extras are ignored."""
import sys, os, random
__file__ = os.path.abspath(sys.argv[0])
sys.argv = [sys.argv[0], sys.argv[1], sys.argv[2], '0']
exec(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'synth.py')).read().split('random.seed(7)')[0])
from PIL import Image
random.seed(11)
icons = [(f[:-4], Image.open(os.path.join(REFS, f)).convert('RGBA')) for f in sorted(os.listdir(REFS)) if f.endswith('.png')]
os.makedirs(os.path.join(OUT, 'other'), exist_ok=True)
for k in range(300):
    rid, icon = random.choice(icons)
    photograph(tile(icon, rid)).save(os.path.join(OUT, 'other', f'{k:04d}.jpg'), quality=92)
print('other done')
