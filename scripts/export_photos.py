#!/usr/bin/env python3
"""Export Apple Photos metadata (no images) to photos.json for the Photo River pages.

Everything runs on your Mac; nothing is uploaded. The output is a single JSON file
with timestamps and GPS, plus (with --full) people, scene labels, Apple's aesthetic
score and camera model for later visualizations.

Setup (once, from the repository root):
    brew install uv
    uv sync          # creates .venv/ with osxphotos

Run (Terminal needs Full Disk Access: System Settings > Privacy & Security > Full Disk Access):
    uv run scripts/export_photos.py > data/photos.json            # minimal: time + GPS only
    uv run scripts/export_photos.py --full > data/photos.json     # also people, labels, score, camera
    uv run scripts/export_photos.py --movies > data/photos.json   # include videos too
    uv run scripts/export_photos.py --library PATH > data/photos.json  # a specific .photoslibrary

Output shape (column arrays, same index = same photo):
    {"meta": {...}, "t": [unix seconds], "lat": [..|null], "lng": [..|null],
     "hour": [local hour of day, 0-23.99],
     "persons": [[names]], "labels": [[labels]], "score": [0-1|null], "camera": [str|null]}  (--full only)
"""
import sys, json, datetime as dt

try:
    import osxphotos
except ImportError:
    sys.stderr.write("osxphotos is not installed. Run `uv sync` in the repository root, then `uv run scripts/export_photos.py`.\n")
    sys.exit(1)

full = "--full" in sys.argv
movies = "--movies" in sys.argv
library = sys.argv[sys.argv.index("--library") + 1] if "--library" in sys.argv[:-1] else None

# PhotosDB() alone finds the library through com.apple.Photos.plist, which macOS can refuse
# to let us read; fall back to the System Photo Library that photolibraryd records.
library = library or osxphotos.utils.get_last_library_path() or osxphotos.utils.get_system_library_path()
if not library:
    sys.stderr.write("Could not find your Photos library. Pass it explicitly:\n"
                     '    uv run scripts/export_photos.py --library ~/Pictures/"Photos Library.photoslibrary"\n')
    sys.exit(1)

db = osxphotos.PhotosDB(library)
photos = db.photos(images=True, movies=movies, intrash=False)
sys.stderr.write(f"library: {db.library_path}\nphotos: {len(photos)}\n")

rows = []
for p in photos:
    if p.date is None:
        continue
    lat, lng = (None, None)
    if p.location and p.location[0] is not None:
        lat, lng = round(p.location[0], 4), round(p.location[1], 4)
    local = p.date  # timezone-aware, in the photo's own zone
    hour = round(local.hour + local.minute / 60.0, 2)
    row = {"t": int(local.timestamp()), "lat": lat, "lng": lng, "hour": hour}
    if full:
        row["persons"] = [n for n in (p.persons or []) if n and n != "_UNKNOWN_"]
        row["labels"] = list(p.labels or [])
        row["score"] = round(p.score.overall, 3) if p.score and p.score.overall is not None else None
        row["camera"] = p.exif_info.camera_model if p.exif_info else None
    rows.append(row)

rows.sort(key=lambda r: r["t"])

out = {
    "meta": {
        "source": "apple-photos",
        "exported": dt.date.today().isoformat(),
        "count": len(rows),
        "full": full,
        "movies": movies,
    },
    "t": [r["t"] for r in rows],
    "lat": [r["lat"] for r in rows],
    "lng": [r["lng"] for r in rows],
    "hour": [r["hour"] for r in rows],
}
if full:
    out["persons"] = [r["persons"] for r in rows]
    out["labels"] = [r["labels"] for r in rows]
    out["score"] = [r["score"] for r in rows]
    out["camera"] = [r["camera"] for r in rows]

json.dump(out, sys.stdout, separators=(",", ":"), ensure_ascii=False)
with_gps = sum(1 for r in rows if r["lat"] is not None)
sys.stderr.write(f"exported: {len(rows)} photos, {with_gps} with GPS\n")
