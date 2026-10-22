"""Downloads the guide's item pictures into refs/ (ingredients) and
refs_other/ (everything else that has one), for synth.py."""
import json, os, sys, urllib.request
HERE = os.path.dirname(os.path.abspath(__file__))
guide = json.load(open(os.path.join(HERE, '..', '..', 'Resources', 'hajin.json')))
for item in guide['items']:
    if not item.get('image') or item['kind'] in ('Resource', 'FOB Upgrade'):
        continue
    folder = os.path.join(sys.argv[1] if len(sys.argv) > 1 else '.', 'refs' if item['kind'] == 'Ingredient' else 'refs_other')
    os.makedirs(folder, exist_ok=True)
    path = os.path.join(folder, item['id'] + '.png')
    if not os.path.exists(path):
        urllib.request.urlretrieve(item['image'], path)
print('ok')

# One file per distinct picture of the non-ingredients: items that share a
# picture (most keys, the lieutenants' dog tags) become one class, x-<first id>
import hashlib, shutil
root = sys.argv[1] if len(sys.argv) > 1 else '.'
src, dst = os.path.join(root, 'refs_other'), os.path.join(root, 'refs_other_unique')
shutil.rmtree(dst, ignore_errors=True); os.makedirs(dst)
groups = {}
for f in sorted(os.listdir(src)):
    if f.endswith('.png'):
        groups.setdefault(hashlib.md5(open(os.path.join(src, f), 'rb').read()).hexdigest(), []).append(f[:-4])
for ids in groups.values():
    shutil.copy(os.path.join(src, ids[0] + '.png'), os.path.join(dst, (ids[0] if len(ids) == 1 else 'x-' + ids[0]) + '.png'))
print(len(groups), 'distinct pictures')
