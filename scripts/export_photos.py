#!/usr/bin/env python3
"""Export Apple Photos metadata to photos.json for the Photo River pages.

Everything runs on your Mac; nothing is uploaded. The output is a single JSON file
with timestamps and GPS, plus (with --full) people, scene labels, Apple's aesthetic
score and camera model for later visualizations. With --thumbs it also writes small
JPEG thumbnails to data/thumbs/, made from the previews Photos already keeps.

Setup (once, from the repository root):
    brew install uv
    uv sync          # creates .venv/ with osxphotos

Run (Terminal needs Full Disk Access: System Settings > Privacy & Security > Full Disk Access):
    uv run scripts/export_photos.py > data/photos.json            # minimal: time + GPS only
    uv run scripts/export_photos.py --full > data/photos.json     # also people, labels, score, camera
    uv run scripts/export_photos.py --movies > data/photos.json   # include videos too
    uv run scripts/export_photos.py --thumbs > data/photos.json   # also data/thumbs/<id>.jpg
    uv run scripts/export_photos.py --library PATH > data/photos.json  # a specific .photoslibrary

Photos dated exactly 1980-01-01 00:00 are skipped: that is the placeholder date for
images with no capture time (screenshots, downloaded PNGs), not a real date.

Output shape (column arrays, same index = same photo):
    {"meta": {...}, "t": [unix seconds], "lat": [..|null], "lng": [..|null],
     "hour": [local hour of day, 0-23.99],
     "persons": [[names]], "labels": [[labels]], "score": [0-1|null], "camera": [str|null]}  (--full only)
     "id": [Photos uuid]}  (--thumbs only; meta.thumbs = "../data/thumbs/{id}.jpg")
"""
import sys, json, os, pathlib, subprocess, datetime as dt
from concurrent.futures import ThreadPoolExecutor

try:
    import osxphotos
except ImportError:
    sys.stderr.write("osxphotos is not installed. Run `uv sync` in the repository root, then `uv run scripts/export_photos.py`.\n")
    sys.exit(1)

full = "--full" in sys.argv
movies = "--movies" in sys.argv
thumbs = "--thumbs" in sys.argv
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
    if p.date.replace(tzinfo=None) == dt.datetime(1980, 1, 1):
        continue  # placeholder date, see above
    lat, lng = (None, None)
    if p.location and p.location[0] is not None:
        lat, lng = round(p.location[0], 4), round(p.location[1], 4)
    local = p.date  # timezone-aware, in the photo's own zone
    hour = round(local.hour + local.minute / 60.0, 2)
    row = {"t": int(local.timestamp()), "lat": lat, "lng": lng, "hour": hour, "photo": p}
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
if thumbs:
    out["meta"]["thumbs"] = "../data/thumbs/{id}.jpg"
    out["id"] = [r["photo"].uuid for r in rows]
if full:
    out["persons"] = [r["persons"] for r in rows]
    out["labels"] = [r["labels"] for r in rows]
    out["score"] = [r["score"] for r in rows]
    out["camera"] = [r["camera"] for r in rows]


# ---------- thumbnails ----------
THUMB_DIR = pathlib.Path(__file__).resolve().parent.parent / "data" / "thumbs"
THUMB_EDGE = 384  # long edge in px; cards are 256x176, so this leaves room to crop


def thumb_source(p):
    """Smallest preview Photos has rendered (edits and rotation already applied), else the edited or original file."""
    for path in reversed(p.path_derivatives or []):  # sorted largest first
        if os.path.exists(path):
            return path
    for path in (p.path_edited, p.path):
        if path and os.path.exists(path):
            return path
    return None


def make_thumb(p):
    dest = THUMB_DIR / f"{p.uuid}.jpg"
    if dest.exists():
        return "kept"
    src = thumb_source(p)
    if src is None:
        return "missing"  # e.g. an iCloud original that was never downloaded; the page paints a placeholder
    tmp = dest.with_suffix(".tmp.jpg")
    r = subprocess.run(["sips", "-Z", str(THUMB_EDGE), "-s", "format", "jpeg", "-s", "formatOptions", "70", src, "--out", str(tmp)],
                       capture_output=True)
    if r.returncode != 0 or not tmp.exists():
        tmp.unlink(missing_ok=True)
        return "failed"
    tmp.rename(dest)
    return "made"


if thumbs:
    THUMB_DIR.mkdir(parents=True, exist_ok=True)
    counts = {}
    with ThreadPoolExecutor(max_workers=os.cpu_count() or 4) as pool:
        for n, status in enumerate(pool.map(make_thumb, (r["photo"] for r in rows)), 1):
            counts[status] = counts.get(status, 0) + 1
            if n % 500 == 0 or n == len(rows):
                sys.stderr.write(f"\rthumbs: {n}/{len(rows)}")
    # drop thumbnails of photos that are no longer exported (deleted, trashed, filtered)
    keep = {f"{r['photo'].uuid}.jpg" for r in rows}
    stale = [f for f in THUMB_DIR.glob("*.jpg") if f.name not in keep]
    for f in stale:
        f.unlink()
    sys.stderr.write("\nthumbs: " + ", ".join(f"{k} {v}" for k, v in sorted(counts.items())) + f", removed {len(stale)} stale\n")

json.dump(out, sys.stdout, separators=(",", ":"), ensure_ascii=False)
with_gps = sum(1 for r in rows if r["lat"] is not None)
sys.stderr.write(f"exported: {len(rows)} photos, {with_gps} with GPS\n")
