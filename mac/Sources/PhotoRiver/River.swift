import AppKit
import MetalKit
import Observation
import Photos
import simd

// River layout, in river units (constant photo density by construction: every photo gets S along the river).
let S = 0.42
private let lanes: [Float] = [-0.95, -0.1, 0.8, 1.7, 2.6]
private let poolSize = 170
private let fovY: Float = 40 * .pi / 180
private let minCamZ = 7.0, maxCamZ = 34.0   // camera distance: fully zoomed in, fully zoomed out
private let textureScale: CGFloat = 1.5   // card texture pixels per card point
private let fullScale: CGFloat = 5        // placeholder "original" pixels per card point
let speeds: [(name: String, value: Double)] = [("Slow", 1.1), ("Medium", 2.2), ("Fast", 5.5)]

// ---------- what SwiftUI shows ----------

struct Tip: Equatable { var main: String; var sub: String; var at: CGPoint }

struct Focus: Equatable {
    var index: Int
    var main: String
    var sub: String
    var image: NSImage?
    var progress: Double?   // iCloud download progress, 0...1
    var error: String?
}

struct YearCell: Identifiable { var id: Int { year }; let year: Int; let count: Int; let start: Int }
struct MonthCell: Identifiable { let id: Int; let name: String; let count: Int; let start: Int }

@Observable final class RiverUI {
    var loading: String? = "Loading…"
    var badge: String?
    var year = "——"
    var date = ""
    var countText = ""
    var playing = false
    var speed = 2.2
    var tip: Tip?
    var focus: Focus?

    var years: [YearCell] = []
    var timelineRight = ""
    var nowYear = 0
    var nowFraction = 0.0
    var monthsYear = 0
    var months: [MonthCell] = []
    var timelineOpen = false
    var timelinePinned = false
    var total = 0
}

// ---------- one card in the pool ----------

private struct CardParams {
    var x, y, z, w, h: Float
    var portrait: Bool
    var rx, ry, rz, phase, bob, sway: Float
    var kind: SceneKind
}

private final class Card {
    var index = -1
    var token = 0              // bumped on every reuse so late image callbacks for the old photo are dropped
    var p: CardParams!
    var texture: MTLTexture?
    var glow: Float = 0
    var model = matrix_identity_float4x4
    var request: PHImageRequestID?
    var loading = false        // an image (thumbnail or placeholder) has been asked for
}

/// The Time River: owns the simulation (scroll position, camera, flow), the card pool and its images,
/// drives the Metal renderer once per display frame, and publishes what the SwiftUI overlay shows.
final class River: NSObject, MTKViewDelegate {
    let ui = RiverUI()
    let renderer = Renderer(pixelFormat: .bgra8Unorm)
    private(set) var lib: Library?

    private let reduced = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    private let cal = Calendar.current
    private let images = PHCachingImageManager()
    private let work = DispatchQueue(label: "photo-river.paint", qos: .userInitiated, attributes: .concurrent)

    // simulation
    private var pos = 0.0
    private var playing = false { didSet { ui.playing = playing } }
    private var dragging = false
    private var jump: (from: Double, to: Double, start: Double, dur: Double)?
    private var hover = -1
    private var camZ = minCamZ, camZTarget = minCamZ   // start zoomed all the way in
    private var ended = false
    private var mouse: CGPoint?            // view points, origin bottom-left
    private var viewSize = CGSize(width: 1, height: 1)
    private var unitsPerPoint = 0.02
    private var viewProj = matrix_identity_float4x4

    private var pool: [Card] = [], active: [Int: Card] = [:], free: [Card] = []
    private var yearRanges: [Range<Int>] = []
    private var y0 = 0
    private var fullRequest: PHImageRequestID?

    private let t0 = CACurrentMediaTime()
    private var lastTime = CACurrentMediaTime(), lastHover = 0.0, lastInfo = 0.0
    private var started = false
    private var keyMonitor: Any?

    override init() {
        super.init()
        pool = (0..<poolSize).map { _ in Card() }
        free = pool
    }

    // ---------- loading ----------

    func start() {
        guard !started else { return }
        started = true
        installKeys()
        if CommandLine.arguments.contains("--sample") { loadSample(note: nil); return }
        ui.loading = "Asking for access to Photos…"
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
            DispatchQueue.main.async {
                switch status {
                case .authorized, .limited: self.loadPhotos()
                default: self.loadSample(note: "No access to Photos · showing the synthetic sample")
                }
            }
        }
    }

    private func loadPhotos() {
        ui.loading = "Reading your Photos library…"
        DispatchQueue.global(qos: .userInitiated).async {
            let lib = Library.fromPhotos { n, total in
                DispatchQueue.main.async { self.ui.loading = "Reading your Photos library… \(fmtInt(n)) / \(fmtInt(total))" }
            }
            DispatchQueue.main.async {
                if lib.count == 0 { self.loadSample(note: "No photos in your library · showing the synthetic sample") } else { self.ready(lib) }
            }
        }
    }

    private func loadSample(note: String?) {
        guard let url = Library.sampleURL(), let lib = try? Library.fromJSON(url) else {
            ui.loading = "Could not find the sample library (sample-photos.json)"
            return
        }
        ready(lib, note: note)
    }

    private func ready(_ lib: Library, note: String? = nil) {
        self.lib = lib
        let synthetic = lib.synthetic ? "Synthetic photos · images are generated by code" : nil
        ui.badge = [note, synthetic].compactMap { $0 }.joined(separator: " · ").nilIfEmpty
        buildTimeline()
        ui.loading = nil
        pos = 0
        updateInfo()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { if !self.playing && !self.ended { self.playing = true } }
    }

    // ---------- controls ----------

    func togglePlay() {
        if ended { jumpTo(0) }
        playing.toggle()
    }

    func restart() { jumpTo(0); playing = true }

    func setSpeed(_ v: Double) { ui.speed = v }

    func jumpTo(_ target: Double) {
        guard let lib else { return }
        let to = max(0, min(Double(lib.count) * S, target))
        closeFocus()
        jump = (pos, to, CACurrentMediaTime(), max(0.7, min(2.6, abs(to - pos) * 0.0009)))
        ended = false
    }

    func jumpToPhoto(_ i: Int) { jumpTo(Double(i) * S) }

    /// ←/→: a month back or forward; while a photo is open, the previous or next photo.
    func step(_ dir: Int) {
        guard let lib else { return }
        if let f = ui.focus {
            let i = max(0, min(lib.count - 1, f.index + dir))
            guard i != f.index else { return }
            pos = Double(i) * S
            open(i)
            return
        }
        let d = lib.date(nowIndex())
        guard let first = cal.date(from: cal.dateComponents([.year, .month], from: d)),
              let target = cal.date(byAdding: .month, value: dir, to: first) else { return }
        jumpToPhoto(lib.lowerBound(target.timeIntervalSince1970))
    }

    // ---------- the photo viewer: click a card, the river stops, the full image opens ----------

    func open(_ i: Int) {
        guard let lib else { return }
        cancelFull()
        let d = describe(i)
        hover = -1
        ui.tip = nil
        ui.focus = Focus(index: i, main: d.main, sub: d.sub)

        if lib.assets.isEmpty {
            let p = params(i)
            work.async {
                let img = Painter.placeholder(i, kind: p.kind, portrait: p.portrait, scale: fullScale).makeImage()
                DispatchQueue.main.async {
                    guard self.ui.focus?.index == i, let img else { return }
                    self.ui.focus?.image = NSImage(cgImage: img, size: .zero)
                }
            }
            return
        }

        let o = PHImageRequestOptions()
        o.deliveryMode = .opportunistic     // a quick preview first, then the full-quality image
        o.isNetworkAccessAllowed = true     // download the original from iCloud if it is not on this Mac
        o.progressHandler = { p, _, _, _ in
            DispatchQueue.main.async { if self.ui.focus?.index == i { self.ui.focus?.progress = p < 1 ? p : nil } }
        }
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let target = CGSize(width: viewSize.width * scale, height: viewSize.height * scale)
        fullRequest = images.requestImage(for: lib.assets[i], targetSize: target, contentMode: .aspectFit, options: o) { img, info in
            guard self.ui.focus?.index == i else { return }
            if let img {
                self.ui.focus?.image = img
                if !((info?[PHImageResultIsDegradedKey] as? Bool) ?? false) { self.ui.focus?.progress = nil }
            } else if let err = info?[PHImageErrorKey] as? Error {
                self.ui.focus?.error = "Could not load this photo: \(err.localizedDescription)"
            }
        }
    }

    func closeFocus() {
        guard ui.focus != nil else { return }
        cancelFull()
        ui.focus = nil
    }

    private func cancelFull() {
        if let r = fullRequest { images.cancelImageRequest(r); fullRequest = nil }
    }

    // ---------- input (from RiverMTKView) ----------

    func beginDrag() { dragging = true; NSCursor.closedHand.set() }
    func endDrag() { dragging = false; NSCursor.openHand.set() }

    func drag(by dx: CGFloat) {
        guard let lib, ui.focus == nil else { return }
        pos = max(-2, min(Double(lib.count) * S + 2, pos - Double(dx) * unitsPerPoint))
        jump = nil
        ended = false
    }

    func zoom(by factor: Double) { camZTarget = max(minCamZ, min(maxCamZ, camZTarget * factor)) }

    func click(at p: CGPoint) {
        if ui.focus != nil { closeFocus(); return }
        let i = pick(p)
        if i >= 0 { open(i) }
    }

    func mouseMoved(to p: CGPoint?) {
        mouse = p
        if let p, ui.tip != nil { ui.tip?.at = CGPoint(x: p.x, y: viewSize.height - p.y) }
    }

    private func installKeys() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self, self.lib != nil else { return e }
            switch e.keyCode {
            case 49: self.togglePlay(); return nil                                   // space
            case 53 where self.ui.focus != nil: self.closeFocus(); return nil        // esc
            case 123: self.step(-1); return nil                                      // ←
            case 124: self.step(1); return nil                                       // →
            default: return e
            }
        }
    }

    // ---------- timeline / info ----------

    private func nowIndex() -> Int {
        guard let lib else { return 0 }
        return max(0, min(lib.count - 1, Int((pos / S).rounded())))
    }

    private func startIndex(year: Int, month: Int = 1) -> Int {
        lib!.lowerBound(DateComponents(calendar: cal, year: year, month: month, day: 1).date!.timeIntervalSince1970)
    }

    private func buildTimeline() {
        guard let lib else { return }
        y0 = cal.component(.year, from: lib.date(0))
        let y1 = cal.component(.year, from: lib.date(lib.count - 1))
        yearRanges = (y0...y1).map { startIndex(year: $0)..<startIndex(year: $0 + 1) }
        ui.years = (y0...y1).enumerated().map { k, y in YearCell(year: y, count: yearRanges[k].count, start: yearRanges[k].lowerBound) }
        ui.total = lib.count
        ui.timelineRight = "\(y0) → \(y1) · \(fmtInt(lib.count)) photos · width = photo count"
        showMonths(y0)
    }

    func showMonths(_ y: Int) {
        guard lib != nil else { return }
        ui.monthsYear = y
        ui.months = (1...12).map { m in
            let a = startIndex(year: y, month: m), b = m == 12 ? startIndex(year: y + 1) : startIndex(year: y, month: m + 1)
            return MonthCell(id: m, name: monthNames[m - 1], count: b - a, start: a)
        }
    }

    private func updateInfo() {
        guard let lib else { return }
        let i = nowIndex(), d = lib.date(i)
        let y = cal.component(.year, from: d)
        ui.year = String(y)
        ui.date = Fmt.infoDate.string(from: d)
        ui.countText = "\(fmtInt(i + 1)) / \(fmtInt(lib.count)) photos"
        let k = y - y0
        if yearRanges.indices.contains(k) {
            let r = yearRanges[k]
            ui.nowFraction = r.count > 0 ? max(0, min(1, (pos / S - Double(r.lowerBound)) / Double(r.count))) : 0
        }
        if ui.nowYear != y {
            ui.nowYear = y
            if !(ui.timelineOpen && ui.timelinePinned) { showMonths(y) }
        }
    }

    private func describe(_ i: Int) -> (main: String, sub: String) {
        guard let lib else { return ("", "") }
        let place = lib.geo[i] ? fmtCoord(lib.lat[i], lib.lng[i]) + (lib.trip[i] ? " · away" : " · near home") : "no location"
        return (Fmt.tipDate.string(from: lib.date(i)), "\(place) · #\(fmtInt(i + 1))" + (lib.synthetic ? " · synthetic" : ""))
    }

    // ---------- cards ----------

    private func params(_ i: Int) -> CardParams {
        func r(_ k: Int) -> Float { Float(rand01(i * 13 + k)) }
        let lane = (i * 2 + (r(1) < 0.18 ? 1 : 0)) % lanes.count
        let portrait = lib?.portrait?[i] ?? (r(5) < 0.32)
        let sc = 0.8 + r(6) * 0.28
        return CardParams(
            x: (r(4) - 0.5) * 0.5, y: lanes[lane] + (r(2) - 0.5) * 0.3, z: -4.0 + r(3) * 4.8,
            w: (portrait ? 0.95 : 1.42) * sc, h: (portrait ? 1.28 : 0.95) * sc, portrait: portrait,
            rx: (r(7) - 0.5) * 0.22, ry: (r(8) - 0.5) * 0.55, rz: (r(9) - 0.5) * 0.16,
            phase: r(10) * 2 * .pi, bob: 0.035 + r(11) * 0.05, sway: 0.5 + r(12) * 0.6,
            kind: ((lib?.trip[i] ?? false) ? Painter.tripKinds : Painter.homeKinds)[Int(r(14) * 8)])
    }

    private func acquire(_ i: Int) -> Card? {
        guard let lib, let c = free.popLast() else { return nil }
        c.index = i
        c.token += 1
        c.p = params(i)
        c.texture = nil
        c.glow = 0
        c.loading = false
        active[i] = c
        return c
    }

    /// Asks for a card's image. Deferred while a jump sweeps past thousands of photos, so PhotoKit is not
    /// flooded with requests for cards that are gone a frame later.
    private func load(_ c: Card) {
        guard let lib else { return }
        c.loading = true
        let i = c.index, token = c.token, p = c.p!
        if lib.assets.isEmpty { paintPlaceholder(c, token: token, p: p); return }
        let o = PHImageRequestOptions()
        o.deliveryMode = .opportunistic
        o.resizeMode = .fast
        o.isNetworkAccessAllowed = false   // cards use the previews Photos already keeps; never download for a card
        let edge = 256 * textureScale
        c.request = images.requestImage(for: lib.assets[i], targetSize: CGSize(width: edge, height: edge), contentMode: .aspectFill, options: o) { img, info in
            guard c.token == token else { return }
            let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
            guard let cg = img?.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                if !degraded { self.paintPlaceholder(c, token: token, p: p) }
                return
            }
            self.work.async {
                let t = self.renderer.texture(from: Painter.cover(cg, portrait: p.portrait, scale: textureScale))
                DispatchQueue.main.async { if c.token == token { c.texture = t } }
            }
        }
    }

    private func paintPlaceholder(_ c: Card, token: Int, p: CardParams) {
        let i = c.index
        work.async {
            let t = self.renderer.texture(from: Painter.placeholder(i, kind: p.kind, portrait: p.portrait, scale: textureScale))
            DispatchQueue.main.async { if c.token == token { c.texture = t } }
        }
    }

    private func release(_ c: Card) {
        if let r = c.request { images.cancelImageRequest(r); c.request = nil }
        active[c.index] = nil
        c.index = -1
        c.token += 1
        c.texture = nil
        free.append(c)
    }

    // ---------- frame ----------

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) { viewSize = view.bounds.size }

    func draw(in view: MTKView) {
        let now = CACurrentMediaTime()
        let dt = min(0.1, now - lastTime)
        lastTime = now
        viewSize = view.bounds.size
        let t = now - t0

        if let j = jump {
            let k = min(1, (now - j.start) / j.dur)
            pos = j.from + (j.to - j.from) * easeInOut(k)
            if k >= 1 { jump = nil }
        } else if playing, !dragging, ui.focus == nil, !ended, let lib {
            pos += ui.speed * dt
            if pos >= Double(lib.count) * S + 1.5 { pos = Double(lib.count) * S + 1.5; ended = true; playing = false }
        }
        camZ += (camZTarget - camZ) * (1 - exp(-dt * 6))

        // camera
        let aspect = Float(max(1, view.drawableSize.width) / max(1, view.drawableSize.height))
        let v = float4x4.lookAt(eye: [0, 1.0, Float(camZ)], target: [0, 0.55, 0])
        let pr = float4x4.perspective(fovY: fovY, aspect: aspect, near: 0.1, far: 400)
        viewProj = pr * v
        let vis = 2 * camZ * Double(tan(fovY / 2)) * Double(aspect)
        unitsPerPoint = vis / Double(max(1, viewSize.width))

        let (reflections, cards) = updateCards(t: Float(t), vis: vis)

        if let m = mouse, ui.focus == nil, !dragging {
            if now - lastHover > 0.05 { lastHover = now; updateHover(m) }
        } else if hover >= 0 {
            hover = -1
            ui.tip = nil
        }
        if now - lastInfo > 0.09 { lastInfo = now; updateInfo() }

        let scale = Float(view.window?.backingScaleFactor ?? 2)
        let frame = FrameU(view: v, proj: pr, viewProj: viewProj, time: Float(t), starTime: reduced ? 0 : Float(t), pixelRatio: min(scale, 2))
        renderer.draw(in: view, frame: frame, reflections: reflections, cards: cards)
    }

    private func updateCards(t: Float, vis: Double) -> ([CardDraw], [CardDraw]) {
        guard let lib else { return ([], []) }
        let n = lib.count
        let half = vis / 2 + 2.5
        let lo = max(0, Int(floor((pos - half) / S))), hi = min(n - 1, Int(ceil((pos + half) / S)))
        let focus = ui.focus?.index
        for (i, c) in active where (i < lo || i > hi) && i != focus { release(c) }
        if lo <= hi { for i in lo...hi where active[i] == nil { if acquire(i) == nil { break } } }

        let sw: Float = reduced ? 0 : 1
        let wy = Renderer.waterY
        var fronts: [(z: Float, d: CardDraw)] = [], backs: [CardDraw] = []
        for (i, c) in active {
            let p = c.p!
            if !c.loading && jump == nil { load(c) }
            let x = Float(Double(i) * S - pos) + p.x
            let py = p.y + sin(t * p.sway + p.phase) * p.bob * sw
            let rx = p.rx + sin(t * 0.7 * p.sway + p.phase) * 0.05 * sw
            let ry = p.ry + sin(t * 0.5 * p.sway + p.phase * 1.3) * 0.08 * sw
            let rz = p.rz + sin(t * 0.6 * p.sway + p.phase * 0.7) * 0.03 * sw
            let isFocus = i == focus, isHover = i == hover && focus == nil
            let scale: Float = isHover ? 1.07 : 1
            let dist = max(0, Float(camZ) - p.z)
            let fade = max(0, min(1, 1 - (dist - 16) / 22))
            c.glow += ((isHover || isFocus ? 1 : 0) - c.glow) * 0.2

            c.model = .translation(x, py, p.z) * .rotation(rx, ry, rz) * .scale(p.w * scale, p.h * scale, 1)
            var u = CardU(model: c.model, size: [p.w, p.h])
            u.opacity = fade * (focus != nil && !isFocus ? 0.35 : 1)
            u.glow = c.glow
            u.dim = focus != nil && !isFocus ? 0.55 : 1
            fronts.append((isFocus ? .infinity : p.z, CardDraw(u: u, texture: c.texture)))

            var b = u
            b.model = .translation(x, 2 * wy - py, p.z) * .rotation(-rx, ry, -rz) * .scale(p.w * scale, -p.h * scale, 1)
            b.opacity = fade * (focus != nil ? 0.3 : 1)
            b.glow = 0
            b.refl = 1
            backs.append(CardDraw(u: b, texture: c.texture))
        }
        fronts.sort { $0.z < $1.z }   // back to front
        return (backs, fronts.map(\.d))
    }

    /// Which card is under a point: intersect the view ray with each card's plane.
    private func updateHover(_ m: CGPoint) {
        let best = pick(m)
        guard best != hover else { return }
        hover = best
        if best >= 0 {
            let d = describe(best)
            ui.tip = Tip(main: d.main, sub: d.sub, at: CGPoint(x: m.x, y: viewSize.height - m.y))
        } else {
            ui.tip = nil
        }
    }

    private func pick(_ m: CGPoint) -> Int {
        let ndc = SIMD2<Float>(Float(m.x / viewSize.width) * 2 - 1, Float(m.y / viewSize.height) * 2 - 1)
        let inv = viewProj.inverse
        var a = inv * SIMD4<Float>(ndc.x, ndc.y, 0, 1), b = inv * SIMD4<Float>(ndc.x, ndc.y, 1, 1)
        a /= a.w; b /= b.w
        let o = SIMD4<Float>(a.x, a.y, a.z, 1), d = SIMD4<Float>(b.x - a.x, b.y - a.y, b.z - a.z, 0)
        var best = -1, bestT = Float.infinity
        for (i, c) in active {
            let mi = c.model.inverse
            let lo = mi * o, ld = mi * d
            guard abs(ld.z) > 1e-7 else { continue }
            let t = -lo.z / ld.z
            let hx = lo.x + ld.x * t, hy = lo.y + ld.y * t
            if t > 0, t < bestT, abs(hx) <= 0.5, abs(hy) <= 0.5 { best = i; bestT = t }
        }
        return best
    }
}

// ---------- formatting ----------

let monthNames = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

enum Fmt {
    private static func make(_ f: String) -> DateFormatter {
        let d = DateFormatter()
        d.locale = Locale(identifier: "en_US_POSIX")
        d.dateFormat = f
        return d
    }
    static let infoDate = make("MMM d · HH:mm")
    static let tipDate = make("MMM d, yyyy HH:mm")
    static let ints: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "en_US")
        return f
    }()
}

func fmtInt(_ n: Int) -> String { Fmt.ints.string(from: NSNumber(value: n)) ?? String(n) }

func fmtCoord(_ lat: Double, _ lng: Double) -> String {
    String(format: "%.2f%@ %.2f%@", abs(lat), lat >= 0 ? "N" : "S", abs(lng), lng >= 0 ? "E" : "W")
}

func easeInOut(_ t: Double) -> Double { t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2 }

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
