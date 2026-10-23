# Data format

Every view reads one file, `data/photos.json`, written by `scripts/export_photos.py` (or `scripts/gen_synthetic.py` for the sample). It is a set of parallel column arrays: index `i` in every array is the same photo. Columns keep the file small (about 25 bytes per photo) and let the pages build typed arrays without copying.

```json
{
  "meta": {
    "source": "apple-photos",          // or "synthetic"
    "exported": "2026-10-23",
    "count": 20613,
    "full": false,                     // true when --full was used
    "movies": false,
    "thumbs": "../data/thumbs/{i}.jpg" // optional: thumbnail path template, {i} = index
  },
  "t":    [1157068800, ...],   // unix seconds, ascending
  "lat":  [25.033, null, ...], // WGS84 degrees, null when the photo has no location
  "lng":  [121.565, null, ...],
  "hour": [11.25, ...],        // local hour of day in the photo's own time zone (0–23.99)

  // --full only
  "persons": [["Alice", "Bob"], [], ...],  // named face clusters, "_UNKNOWN_" removed
  "labels":  [["Beach", "Sky"], ...],      // Apple's on-device scene labels
  "score":   [0.71, null, ...],            // Apple's overall aesthetic score, 0–1
  "camera":  ["iPhone 15 Pro", null, ...]
}
```

## Rules the pages rely on

- `t` is sorted ascending. Everything (the river coordinate, year and month boundaries, flight inference) is a binary search over `t`.
- `lat`/`lng` may be `null`; such photos count in totals but never place anything on the map.
- Flights are not in the file. Photo Globe infers them: two consecutive geotagged photos more than 400 km apart form one flight, timestamped at the second photo.
- "Home" is not in the file either. Time River takes the most common 1° cell per year as that year's home, and marks photos more than 150 km from it as "away". The synthetic generator uses the same rule in reverse to decide which placeholder scene to paint.
- Thumbnails are optional. When `meta.thumbs` is present, Time River replaces `{i}` with the photo index and loads the image lazily as the card enters the view; otherwise it paints a procedural placeholder.

## Why not the Photos database directly

The pages are static files; they cannot open `Photos.sqlite`. The exporter is the only code that touches the library, and it only reads. Keeping the contract this small also means any other source (another photo manager, a folder of EXIF-tagged files) can feed the same views by writing the same JSON.
