"""Saves the community map layers from dmzcodex.com/map (exfils, player
spawns, loot spots, key doors and where keys turn up) as codex_map.json,
in the same 0...1 coordinates as our cropped Tac Map.

dmzcodex draws the same official Activision map with a different crop, so
the conversion is fitted on every official marker both maps share (ammo
caches, gas stations, compounds...) and checked: the fit has to land those
within half a percent of the map, or the script stops.

    python3 Tools/hajin/fetch_codex_map.py      # writes Tools/hajin/codex_map.json
"""
import html, json, os, re, sys, urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
CROP = (750, 740, 2660)  # as in build_hajin.py
SHARED = {"ammo-armor-caches": "dmz_ammoCache", "gas-stations": "dmz_gasStation", "uav-towers": "dmz_uavTower",
          "clinics": "dmz_clinic", "compounds": "dmz_compound", "marine-gas-stations": "dmz_marineGasStation",
          "fire-stations": "dmz_fireStation", "police-stations": "dmz_policeStation", "lieutenant-hunts": "dmz_lieutenantHunt"}

def fetch(url):
    return urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": "CamoTracker guide build"})).read().decode()

page = fetch("https://dmzcodex.com/map/")
pins = []
for m in re.finditer(r'<button[^>]*class="mk"[^>]*>', page):
    a = dict(re.findall(r'([a-z-]+)="([^"]*)"', m.group(0)))
    st = re.search(r"left:([\d.]+)%;top:([\d.]+)%", a.get("style", ""))
    if st and a.get("data-layer-el"):
        pins.append({"layer": a["data-layer-el"], "id": a.get("data-mk"), "label": html.unescape(a.get("aria-label", "")),
                     "x": float(st.group(1)) / 100, "y": float(st.group(2)) / 100})
keys = json.loads(re.search(r'<script type="application/json" id="key-map-data"[^>]*>(.*?)</script>', page, re.S).group(1))

# Fit codex -> ours on the official markers both maps carry
official = [f for f in json.load(open(os.path.join(HERE, "markers.json")))["features"]]
def ours(f):
    x, y = f["geometry"]["coordinates"]
    return (x - CROP[0]) / CROP[2], (y - CROP[1]) / CROP[2]
def fit(a, b):
    ma, mb = sum(a) / len(a), sum(b) / len(b)
    s = sum((x - ma) * (y - mb) for x, y in zip(a, b)) / sum((x - ma) ** 2 for x in a)
    return s, mb - s * ma
xf = (1.54, -0.28, 1.54, -0.28)  # a rough start, refined below
for _ in range(3):
    pairs = []
    for p in pins:
        if p["layer"] not in SHARED: continue
        px, py = p["x"] * xf[0] + xf[1], p["y"] * xf[2] + xf[3]
        cands = [ours(f) for f in official if f["properties"]["category"] == SHARED[p["layer"]]]
        best = min(cands, key=lambda o: (o[0] - px) ** 2 + (o[1] - py) ** 2)
        if ((best[0] - px) ** 2 + (best[1] - py) ** 2) ** 0.5 < 0.03: pairs.append((p, best))
    sx, ox = fit([p["x"] for p, _ in pairs], [o[0] for _, o in pairs])
    sy, oy = fit([p["y"] for p, _ in pairs], [o[1] for _, o in pairs])
    xf = (sx, ox, sy, oy)
worst = max(((p["x"] * sx + ox - o[0]) ** 2 + (p["y"] * sy + oy - o[1]) ** 2) ** 0.5 for p, o in pairs)
if len(pairs) < 40 or worst > 0.005:
    raise SystemExit(f"map fit failed: {len(pairs)} shared markers, worst {worst:.4f}")
conv = lambda x, y: (round(x * sx + ox, 4), round(y * sy + oy, 4))

out_pins = []
for p in pins:
    if p["layer"] in SHARED or p["layer"] in ("grid", "poi", "places", "strongholds"): continue
    x, y = conv(p["x"], p["y"])
    if 0 <= x <= 1 and 0 <= y <= 1: out_pins.append({**p, "x": x, "y": y})
out_keys = []
for k in keys:
    doors = []
    for d in k.get("doors", []):
        x, y = conv(d["x"] / 100, d["y"] / 100)
        doors.append({"name": d["name"], "scope": d.get("scope"), "grid": d.get("zoneGrid"), "x": x, "y": y})
    out_keys.append({"name": k["name"].replace("’", "'"), "doors": doors,
                     "sources": [{"name": s["name"].replace("’", "'"), "kind": s.get("kind")} for s in k.get("sources", [])]})
json.dump({"source": "dmzcodex.com/map", "fit": {"shared": len(pairs), "worst": round(worst, 5)},
           "pins": out_pins, "keys": out_keys},
          open(os.path.join(HERE, "codex_map.json"), "w"), ensure_ascii=False, indent=1)
print(len(out_pins), "pins,", len(out_keys), "keys; fit on", len(pairs), "shared markers, worst", round(worst, 5))
