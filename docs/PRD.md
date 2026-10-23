# Photo River — Product Requirements

Status: draft v0.1, 2026-10-23. Owner: Justin Chuang. This document collects the thinking from the first design conversation so that later work (in Claude Code or by hand) starts from the same place.

## 1. Summary

Photo River is a set of local-first, cinematic visualizations of one person's photo library: twenty years and roughly twenty thousand photos from Apple Photos. It treats the library as the richest "event log" most people own (every photo has a time, most have a place, many have people and scene labels) and renders it as something you can fly through, not a report you read.

One view exists in v0: **Time River**, a slowly flowing river of photo cards with constant photo density. A small exporter turns the Photos library into a single JSON file. Nothing leaves the Mac.

## 2. Background and motivation

The project started as a brainstorm about a "Cloud AI OS": an operating system where all application logic runs in the cloud and devices are thin clients that only render. The angle that mattered was AI agents. Today every app is a data silo. In an agent-first world the data should live together, owned by the person, and apps become *surfaces* over it: windows that an agent composes on demand and dismisses when the task is done, like Jarvis in Iron Man.

That vision is hard to attack head-on. The most tractable starting point is a data set that is already consolidated, already owned by the user, and already rich: the personal photo library. Apple Photos stores timestamps, GPS, face clusters, scene labels, places and aesthetic scores in a local SQLite database. It is a twenty-year personal event log sitting on disk. Photo River is the first "surface" over that log.

Decisions made in the conversation:

- **Not Google Takeout.** The owner does not want to route personal data through a cloud export. Apple Photos on a Mac is the source.
- **Not an "artsy" infographic.** Heatmaps, stream graphs, quiet poster-style charts were considered and rejected. The target register is kinetic and cinematic: Flightradar, NASA visualizations, a PS5 home screen.
- **Constant density, variable time.** When a trip produces 400 photos in three days and a winter month produces none, a clock-driven animation either floods or starves. The river coordinate is the photo index; time slows where photos are dense.
- **Local-first.** A native Mac app that reads the Photos library in place: no server, no accounts, no upload.

## 3. Goals

1. Make twenty years of photos *feel* like twenty years: rhythm, trips, eras, the people who came and went.
2. Be beautiful enough to leave running on a screen, and responsive enough to explore by hand (scroll, drag, click, jump).
3. Keep every byte of personal data on the user's machine.
4. Keep the stack small: one Swift package built with the Command Line Tools (no Xcode project), so the owner can iterate in an editor or with Claude Code.
5. Define a small data contract so other sources (another photo app, a folder of EXIF files) can feed the same views.

## 4. Non-goals (for now)

- A general photo manager, editing, albums, sharing.
- Cloud sync, multi-user, mobile apps.
- Face recognition or scene classification of our own; we read what Apple already computed.
- Pixel-perfect fidelity on phones. Pages must work at phone width, but the desktop/TV experience is the priority.

## 5. Users

One user: the owner of the library. A secondary audience is anyone the owner shows it to on a large screen. The library size to design for is 20k–50k photos over 10–25 years.

## 6. Product principles

- **Cinematic, not decorative.** Motion must carry information (time passing, a flight, a dense month). Effects that do not encode anything are kept subtle (stars, dust, reflections).
- **Deadpan telemetry over sentiment.** Counters, coordinates and flight logs say more than captions. If narration is added, it speaks like a flight computer.
- **The data contract comes first.** Views never read the Photos database; they read `data/photos.json` (see `DATA.md`). The exporter is the only code that touches the library.
- **Honest placeholders.** When real thumbnails are absent, cards are painted procedurally and the app says so. Synthetic data is always labeled.

## 7. Current scope (v0)

### 7.1 Time River (`mac/`, a native macOS app)

A river of photo cards flows from oldest (left) to newest (right) under a starfield, above a dark reflective water surface.

- **River coordinate = photo index.** Each photo occupies the same length of river (`S` units), so density is constant by construction. Flow speed is in river units per second; three presets (slow, medium, fast).
- **Cards.** 3D planes with rounded corners, a slight random tilt on all three axes and a slow sway (the "floating" projective/affine feel), laid on five lanes at varying depth for parallax. A faded reflection sits below the water line.
- **Photos.** Cards show the previews Photos already keeps (PhotoKit, never downloaded for a card), cover-cropped, with each photo's real orientation.
- **Placeholders.** For the synthetic sample, or a photo with no local preview, each card is painted procedurally from one of eight scene families (sky, sea, city, street, food, people, green, night) with film grain and a vignette. Photos taken away from that year's home prefer travel scenes.
- **Interaction.** Mouse wheel / pinch zooms the camera; horizontal drag scrubs the river; hovering a card lifts it and shows date, coordinates, away/near-home and index; clicking a card stops the river and opens the full image over it (downloaded from iCloud with a progress bar if the original is not on the Mac), where ←/→ step to the previous or next photo and a click or Esc closes it; horizontal two-finger scroll also scrubs; Space toggles flow; ←/→ jump a month.
- **Timeline.** A glass bar at the bottom shows the years, each as wide as its photo count. Hovering pulls out a second row with the twelve months of the hovered year. Clicking a year or month animates the river to that point. A playhead follows the cells.
- **HUD.** Large year, date and time of the photo at the center of the view, running count, and a synthetic badge when applicable.
- **Look.** PS5-inspired: deep navy gradient, thin system type (SF Pro, ultralight for the year), frosted-glass pills and bars, white highlight for the active state, generous spacing.

### 7.2 Exporter (`scripts/export_photos.py`)

Optional; the app no longer needs it. Reads the Photos library through [osxphotos](https://github.com/RhetTbull/osxphotos) and writes column arrays: `t`, `lat`, `lng`, `hour`, plus `persons`, `labels`, `score`, `camera` with `--full`. Videos are excluded unless `--movies`. Output goes to `data/photos.json`, which is git-ignored.

### 7.3 Synthetic sample (`scripts/gen_synthetic.py`)

A plausible fake life for development: 2006–2026, two homes (Taipei, then the Bay Area, then Taipei), 61 trips, weekend and holiday rhythms, a baby in 2016, a lockdown dip in 2020, phone cameras improving over time. 20,613 photos, 128 inferred flights. Committed as `data/sample/photos.json`.

## 8. Roadmap and idea backlog

Ordered roughly by how soon they are worth doing. Items marked **(agreed)** came up as next steps in the conversation; the rest are candidates.

1. **Real thumbnails and full images (done).** The native app reads previews and originals through PhotoKit, so no thumbnail export is needed.
2. **River pacing and card density (agreed).** Tune `S`, lane spacing, depth range and card scale against real thumbnails; consider aesthetic score for size.
3. **Fog-of-war opening.** The globe starts fully fogged; each photo clears a few kilometers around it; twenty years of time-lapse reveals the map, with a counter for the fraction of the Earth revealed. Good as a 30-second opening shot.
4. **People as an orrery.** Home is the sun; each named person is a planet whose orbital period is their real recurrence interval (someone seen every six months has a six-month orbit; a once-in-five-years friend is a comet). Watch orbits change as children are born, friends move away, relationships end. Needs `--full` export.
5. **Space-time cube.** Hägerstrand's time geography: a map on the floor, time on the vertical axis, the owner's life as a worm rising through it; trips are side excursions, moves are whole-worm shifts. Rotatable, sliceable.
6. **Life spectrogram.** FFT of the photo timestamps as a spectrogram: weekly and yearly periodicities, and how they change (weekends brighten after a job, 3 a.m. appears after a newborn, nightlife frequencies vanish).
7. **Bar chart race.** People, cities and scene labels racing over twenty years; rank swaps mark life transitions.
8. **Ghost lap.** Each year is one lap of a track from January to December; twenty cars run at once, speed = photo density; 2008-you and 2023-you take the summer corner side by side.
9. **Powers of Ten spine.** One scrubber from 10⁹ s (the whole library as a sphere) through a year (globe and arcs), a day (minute-by-minute replay on a map) down to a single burst (ten near-identical frames at 10⁻¹ s). Each zoom level has its own visual; the other views plug into it.
10. **Flight-computer narration.** Optional machine voice-over for a rendered "twenty years in three minutes" film: timestamps, coordinates, frame counts, persons identified. Deadpan by design.
11. **Jarvis mode.** Voice or text intent ("show me every time I was on a boat") reconfigures all views at once: the globe turns, the fog shows only those cells, the spectrogram narrows, the river keeps only matching cards. This is the direct link back to the Cloud AI OS idea: views are generated surfaces over one data layer.
12. **Fly into real cities.** Photorealistic 3D tiles with photos pinned at their GPS position and heading, and a camera dolly along the day's path.
13. **Annotations written back.** A conversational narrator proposes hypotheses from the data ("this summer you seem to have gone to the beach with A a lot"); corrections are appended as annotations the library never had. Over years these become more valuable than the photos.
14. **Chapters (optional, kept tasteful).** Automatic change-point detection on cast, home, camera and rhythm to produce a table of contents; only if it can be done without the "artsy" feel the owner rejected.

## 9. Design direction

- Palette: deep navy to near-black gradient, white type, light-blue accent glow, frosted glass panels (`rgba(255,255,255,0.06)` with a 1 px edge), 14–18 px radii.
- Type: SF Pro, ultralight to regular, tabular numbers. Large, thin, generous tracking.
- Motion: ease-in-out jumps, exponential smoothing for camera and zoom, nothing bounces. Respect the system Reduce Motion setting by removing sway and twinkle.
- Reference: PS5 home screen and media gallery. Anti-reference: quiet editorial infographics, pastel dashboards, emoji.

## 10. Technical architecture

- **App**: a SwiftPM executable in `mac/` (Swift, macOS 14+), packaged into `build/PhotoRiver.app` by `make app` with an ad-hoc signature. Metal draws the river (shaders compiled at launch from source, since the Command Line Tools have no `metal` compiler); SwiftUI draws the glass overlay. `@State` is avoided because its macro plugin ships only with Xcode.
- **Data**: PhotoKit, read in place: every image with its date, location and orientation, oldest first. `--sample` loads the bundled `data/sample/photos.json` instead (see `DATA.md`). Homes and away/near-home flags are derived in the app.
- **Performance budget**: 20k–50k photos; 60–120 fps on an Apple-silicon laptop. Time River keeps a pool of 170 cards and paints or loads textures off the main thread only as cards enter the view.
- **Exporter**: Python 3 + osxphotos, in a project `.venv/` managed by uv (`pyproject.toml` + `uv.lock`). Reads only; writes one JSON, and with `--thumbs` a folder of JPEG thumbnails.

## 11. Privacy and data handling

- The app reads the Photos library through PhotoKit, read-only, after the user grants access. The optional `export_photos.py` also only reads.
- `data/photos.json` and `data/thumbs/` are git-ignored. Only the synthetic sample is committed.
- The app makes no network requests of its own; the only downloads are originals PhotoKit fetches from the owner's iCloud when a photo is opened.
- `--full` exports people's names and scene labels. Treat that file as personal.

## 12. Success criteria

- v0: the app runs on the sample and on a real library without errors; the owner recognizes trips, moves and rhythms without any labels telling them.
- v1: real thumbnails in the river, and the owner is willing to leave it running on a TV for an evening.
- Later: at least one agent-driven view (Jarvis mode) that reconfigures the visualization from a single sentence.

## 13. Open questions

- Month and year boundaries use the viewer's local time zone; photos taken abroad are grouped by the viewer's zone, not the photo's. Should the exporter emit a per-photo zone offset?
- How to handle photos without GPS (older cameras, screenshots)? They are counted but cannot be placed on a map; the river shows them without a location line.
- Thumbnail size and format: 320 px JPEG at quality 70 is the working assumption; HEIC sources need conversion in the exporter.
- Multiple libraries, shared libraries, and videos (currently excluded by default).
- Whether to compute "home" per year (current) or detect moves explicitly.

## Appendix A. Where the ideas came from

A condensed trail of the original conversation, kept so the reasoning is not lost:

1. *Benefits of a cloud OS with thin clients*: device independence, cheap hardware, central security, and above all a single place where an AI agent can see and act on all of a person's data.
2. *Data becoming universal*: user-owned entity graph with apps as tenants; "soft schema" where models extract structure at read time instead of pre-agreed schemas (WinFS, the Semantic Web and Solid all died on schema agreement); an append-only personal event log with apps as materialized views; windows as materialized intents of (data, intent, device); apps decomposing into connectors, verbs and a few curated surfaces; permissions per entity and purpose; the risk of building a bigger silo (product vs protocol).
3. *Which verticals fit*: contact centers and enterprise ops, DevOps incident handling, healthcare, personal finance, government data exchange; the heuristic "pick a cross-silo entity (patient, case, incident, trip), not an industry".
4. *Why not travel planners*: every current product is chat over inventory. The interesting observation was that the universal data layer in travel already exists by accident: the confirmation email.
5. *"Fun" ideas*: life as git branches (fork the event log for what-ifs), chat-less group planning by agent negotiation, walk-up computing where every screen is yours (Sun Ray, 1999), a skins marketplace of views over one's data, hiring agents like staff, a public API of oneself.
6. *The photo library as the first graph*: no Takeout; cinematic not artsy; the globe, the river, and the backlog above.
