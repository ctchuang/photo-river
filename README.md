# Photo River

A slow river of your photos.

Photo River turns twenty years of an Apple Photos library into cinematic, local-first visualizations. Nothing is uploaded: a small script reads the metadata that Photos already keeps on your Mac (time, GPS, people, scene labels, aesthetic scores) and a few static web pages render it.

One view exists today:

- **Time River** (`web/time-river.html`): photo cards drift under a starfield, oldest to newest, with constant photo density. The river's coordinate is the photo index, not the clock, so a trip with 400 photos in three days flows slowly and an empty winter month passes in a blink. Scroll to zoom, drag to scrub, click a card to enlarge it, and pull out the timeline at the bottom to jump to a year or month.

The page ships with a synthetic sample library (`data/sample/photos.json`, 20,613 fake photos over 2006–2026) so you can see it work before exporting your own.

The product thinking behind this, and the backlog of ideas, is in [docs/PRD.md](docs/PRD.md). The data format is in [docs/DATA.md](docs/DATA.md).

## Requirements

- macOS with the Photos app (the exporter reads the local Photos library database).
- [Homebrew](https://brew.sh). Everything else is installed through it.
- A modern browser with WebGL (Safari, Chrome, Firefox, Edge).

## Setup

1. Install Homebrew if you do not have it yet:

   ```sh
   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
   ```

2. Install `pipx` with Homebrew, then `osxphotos` with `pipx`. osxphotos is the open-source library that reads the Photos database; pipx keeps it in its own environment so it never fights with your system Python:

   ```sh
   brew install pipx
   pipx ensurepath
   pipx install osxphotos
   ```

   Open a new terminal window after `pipx ensurepath` so the `osxphotos` command is on your `PATH`.

3. Give your terminal Full Disk Access, otherwise macOS will not let the exporter open the Photos database: System Settings → Privacy & Security → Full Disk Access → add Terminal (or iTerm, or whatever you use).

4. Clone this repository:

   ```sh
   git clone https://github.com/ctchuang/photo-river.git
   cd photo-river
   ```

## Try it with the sample data

```sh
python3 -m http.server 8000
```

Then open <http://localhost:8000/web/time-river.html>. The page loads `data/photos.json` if it exists and fall back to `data/sample/photos.json`.

## Export your own library

The exporter runs inside the pipx environment that has osxphotos:

```sh
pipx run --spec osxphotos python3 scripts/export_photos.py > data/photos.json
```

If you installed osxphotos another way, plain `python3 scripts/export_photos.py > data/photos.json` works as long as `import osxphotos` succeeds.

The default export is minimal: timestamps and GPS only. Add `--full` to also export people, scene labels, Apple's aesthetic score and the camera model (used by future views), and `--movies` to include videos. The output is a single JSON file that stays in `data/`, which is ignored by git.

Reload the page. The synthetic badge disappears and the river is yours.

### Thumbnails (coming next)

Time River can show real thumbnails instead of generated placeholders. Set `meta.thumbs` in `data/photos.json` to a path template such as `../data/thumbs/{i}.jpg`, where `{i}` is the photo's index in the export. A thumbnail export script is the next item on the roadmap.

## Repository layout

```
web/        the visualizations (plain HTML + three.js from a CDN, no build step)
data/       the synthetic sample and your own export (ignored by git)
scripts/    export_photos.py (Apple Photos → JSON), gen_synthetic.py (fake library)
docs/       PRD and data format
```

## Privacy

`export_photos.py` reads only metadata and writes one JSON file into `data/`, which `.gitignore` keeps out of the repository. No image data is read, and nothing is sent anywhere. The pages are static files served from your own machine; the only network requests are for the three.js library and a web font from public CDNs.

## License

[MIT](LICENSE).
