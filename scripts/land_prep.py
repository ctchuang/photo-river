"""Turn Natural Earth 110m countries into (a) a dotted land grid and (b) simplified
outlines, as compact JSON for the globe page.

Run from the repository root. Output: data/land.json  {"dots": [lat, lng, lat, lng, ...], "lines": [[lat,lng,...], ...]}
"""
import json, math, os, urllib.request

RAW = "data/raw_countries.geojson"
URL = "https://raw.githubusercontent.com/vasturiano/globe.gl/master/example/datasets/ne_110m_admin_0_countries.geojson"
if not os.path.exists(RAW):
    print("downloading Natural Earth 110m countries ...")
    urllib.request.urlretrieve(URL, RAW)
g = json.load(open(RAW))

rings = []          # outer + inner rings of every polygon
for f in g["features"]:
    geom = f["geometry"]
    polys = geom["coordinates"] if geom["type"] == "MultiPolygon" else [geom["coordinates"]]
    for poly in polys:
        for ring in poly:
            rings.append([(x, y) for x, y in ring])


def point_in_ring(x, y, ring):
    inside = False
    n = len(ring)
    j = n - 1
    for i in range(n):
        xi, yi = ring[i]
        xj, yj = ring[j]
        if (yi > y) != (yj > y):
            xx = (xj - xi) * (y - yi) / (yj - yi) + xi
            if x < xx:
                inside = not inside
        j = i
    return inside


# bounding boxes for a cheap reject
boxes = []
for r in rings:
    xs = [p[0] for p in r]
    ys = [p[1] for p in r]
    boxes.append((min(xs), min(ys), max(xs), max(ys)))


def on_land(x, y):
    hits = 0
    for r, b in zip(rings, boxes):
        if b[0] <= x <= b[2] and b[1] <= y <= b[3] and point_in_ring(x, y, r):
            hits += 1
    return hits % 2 == 1   # holes (lakes) are inner rings -> even count


# grid: constant ~1.1 degree spacing in latitude, longitude spacing scaled by cos(lat)
dots = []
lat = -89.0
STEP = 1.15
while lat <= 89.0:
    step_lng = STEP / max(0.15, math.cos(math.radians(lat)))
    lng = -180.0
    while lng < 180.0:
        if on_land(lng, lat):
            dots.append(round(lat, 2))
            dots.append(round(lng, 2))
        lng += step_lng
    lat += STEP

# outlines, lightly thinned
lines = []
for r in rings:
    pts = r[::2] if len(r) > 40 else r
    if len(pts) < 4:
        continue
    flat = []
    for x, y in pts:
        flat.append(round(y, 2))
        flat.append(round(x, 2))
    lines.append(flat)

json.dump({"dots": dots, "lines": lines}, open("data/land.json", "w"), separators=(",", ":"))
print("dots:", len(dots) // 2, "lines:", len(lines), "verts:", sum(len(l) // 2 for l in lines))
