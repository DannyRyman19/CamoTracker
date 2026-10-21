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
