// Draws the Photo River app icon at 1024x1024 with CoreGraphics (no Xcode, no assets).
//   swift mac/icon/make-icon.swift OUT.png
// `make icon` turns the PNG into mac/AppIcon.icns.
//
// The picture is the app's idea: a river of light winds out of a glowing horizon toward you,
// and above it photo cards drift the same way, small in the distance and large up close.

import AppKit
import CoreGraphics

let S: CGFloat = 1024
let body = CGRect(x: 100, y: 100, width: 824, height: 824)  // macOS icon grid: 824pt tile, 100pt margin
let corner: CGFloat = 185
let horizon: CGFloat = 620

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255, alpha: a)
}

func gradient(_ stops: [(CGFloat, CGColor)]) -> CGGradient {
    CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: stops.map { $0.1 } as CFArray,
               locations: stops.map { $0.0 })!
}

func vertical(_ ctx: CGContext, _ r: CGRect, _ stops: [(CGFloat, CGColor)]) {
    ctx.drawLinearGradient(gradient(stops), start: CGPoint(x: r.midX, y: r.minY), end: CGPoint(x: r.midX, y: r.maxY),
                           options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
}

// deterministic pseudo-random, so the icon is the same on every run
var seed: UInt64 = 0x9E3779B97F4A7C15
func rand() -> CGFloat {
    seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17
    return CGFloat(seed % 10_000) / 10_000
}

// ---------- card contents (drawn in a w x h box with origin at the top left) ----------

func paintSunset(_ ctx: CGContext, _ w: CGFloat, _ h: CGFloat) {
    vertical(ctx, CGRect(x: 0, y: 0, width: w, height: h),
             [(0, rgb(0x3a2d7a)), (0.45, rgb(0xe06d82)), (0.68, rgb(0xffc37a))])
    let sun = CGRect(x: w * 0.56 - h * 0.13, y: h * 0.56 - h * 0.13, width: h * 0.26, height: h * 0.26)
    ctx.setFillColor(rgb(0xfff2cf)); ctx.fillEllipse(in: sun)
    ctx.setFillColor(rgb(0x2b1d45))
    ctx.move(to: CGPoint(x: 0, y: h * 0.72))
    ctx.addCurve(to: CGPoint(x: w * 0.55, y: h * 0.74), control1: CGPoint(x: w * 0.18, y: h * 0.58), control2: CGPoint(x: w * 0.36, y: h * 0.62))
    ctx.addCurve(to: CGPoint(x: w, y: h * 0.66), control1: CGPoint(x: w * 0.72, y: h * 0.84), control2: CGPoint(x: w * 0.86, y: h * 0.60))
    ctx.addLine(to: CGPoint(x: w, y: h)); ctx.addLine(to: CGPoint(x: 0, y: h)); ctx.closePath(); ctx.fillPath()
}

func paintSea(_ ctx: CGContext, _ w: CGFloat, _ h: CGFloat) {
    vertical(ctx, CGRect(x: 0, y: 0, width: w, height: h * 0.52), [(0, rgb(0x5aa9ec)), (1, rgb(0xd4ecff))])
    vertical(ctx, CGRect(x: 0, y: h * 0.52, width: w, height: h * 0.3), [(0, rgb(0x2f8fcf)), (1, rgb(0x16568f))])
    ctx.saveGState(); ctx.clip(to: CGRect(x: 0, y: h * 0.52, width: w, height: h)); ctx.restoreGState()
    ctx.setFillColor(rgb(0xf2dcae))
    ctx.move(to: CGPoint(x: 0, y: h * 0.86))
    ctx.addCurve(to: CGPoint(x: w, y: h * 0.74), control1: CGPoint(x: w * 0.4, y: h * 0.74), control2: CGPoint(x: w * 0.7, y: h * 0.84))
    ctx.addLine(to: CGPoint(x: w, y: h)); ctx.addLine(to: CGPoint(x: 0, y: h)); ctx.closePath(); ctx.fillPath()
}

func paintHills(_ ctx: CGContext, _ w: CGFloat, _ h: CGFloat) {
    vertical(ctx, CGRect(x: 0, y: 0, width: w, height: h), [(0, rgb(0x8cc9f5)), (0.6, rgb(0xe9f6ff))])
    let layers: [(UInt32, CGFloat, CGFloat)] = [(0x7fbf7a, 0.50, 0.12), (0x4d9a55, 0.64, 0.10), (0x2e6e3c, 0.80, 0.08)]
    for (i, (c, y, amp)) in layers.enumerated() {
        ctx.setFillColor(rgb(c))
        ctx.move(to: CGPoint(x: 0, y: h * (y + (i % 2 == 0 ? amp : -amp * 0.3))))
        ctx.addCurve(to: CGPoint(x: w, y: h * y), control1: CGPoint(x: w * 0.35, y: h * (y - amp)), control2: CGPoint(x: w * 0.65, y: h * (y + amp)))
        ctx.addLine(to: CGPoint(x: w, y: h)); ctx.addLine(to: CGPoint(x: 0, y: h)); ctx.closePath(); ctx.fillPath()
    }
}

func paintCity(_ ctx: CGContext, _ w: CGFloat, _ h: CGFloat) {
    vertical(ctx, CGRect(x: 0, y: 0, width: w, height: h), [(0, rgb(0x2a2350)), (1, rgb(0x8a4f78))])
    ctx.setFillColor(rgb(0x140f26))
    var x: CGFloat = 0
    var i = 0
    while x < w {
        let bw = w * (0.12 + 0.06 * CGFloat(i % 3)), bh = h * (0.35 + 0.18 * CGFloat((i * 7) % 4) / 3)
        ctx.fill(CGRect(x: x, y: h - bh, width: bw - w * 0.02, height: bh))
        x += bw; i += 1
    }
}

func paintGolden(_ ctx: CGContext, _ w: CGFloat, _ h: CGFloat) {
    vertical(ctx, CGRect(x: 0, y: 0, width: w, height: h), [(0, rgb(0xffe0a8)), (0.6, rgb(0xff9f6e)), (1, rgb(0x7a3f62))])
}

typealias Painter = (CGContext, CGFloat, CGFloat) -> Void

struct Card { let x, y, w, h, angle: CGFloat; let paint: Painter }

// the river's centre line, from the horizon (t = 0) to the bottom edge of the tile (t = 1)
let riverPath: [CGPoint] = [CGPoint(x: 790, y: horizon), CGPoint(x: 560, y: 640), CGPoint(x: 360, y: 760), CGPoint(x: 480, y: 1010)]
func riverPoint(_ t: CGFloat) -> CGPoint {
    let u = 1 - t, p = riverPath
    let a = u * u * u, b = 3 * u * u * t, c = 3 * u * t * t, d = t * t * t
    return CGPoint(x: a * p[0].x + b * p[1].x + c * p[2].x + d * p[3].x, y: a * p[0].y + b * p[1].y + c * p[2].y + d * p[3].y)
}
func riverWidth(_ t: CGFloat) -> CGFloat { 6 + 300 * pow(t, 1.6) }

// back to front: small cards near the river's source first, the big one last
let cards: [Card] = [
    Card(x: 790, y: 572, w: 60, h: 44, angle: 4, paint: paintGolden),
    Card(x: 712, y: 535, w: 100, h: 74, angle: -5, paint: paintCity),
    Card(x: 610, y: 470, w: 160, h: 118, angle: 6, paint: paintHills),
    Card(x: 655, y: 320, w: 210, h: 156, angle: -4, paint: paintSea),
    Card(x: 380, y: 420, w: 330, h: 244, angle: -8, paint: paintSunset),
]

func cardPath(_ c: Card) -> CGPath {
    CGPath(roundedRect: CGRect(x: -c.w / 2, y: -c.h / 2, width: c.w, height: c.h),
           cornerWidth: c.w * 0.07, cornerHeight: c.w * 0.07, transform: nil)
}

func drawCard(_ ctx: CGContext, _ c: Card, shadow: Bool) {
    ctx.saveGState()
    ctx.translateBy(x: c.x, y: c.y)
    ctx.rotate(by: c.angle * .pi / 180)
    if shadow {
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: c.h * 0.06), blur: c.h * 0.22, color: rgb(0x000000, 0.55))
        ctx.addPath(cardPath(c)); ctx.setFillColor(rgb(0x1a2238)); ctx.fillPath()
        ctx.restoreGState()
    }
    ctx.addPath(cardPath(c)); ctx.clip()
    ctx.translateBy(x: -c.w / 2, y: -c.h / 2)
    c.paint(ctx, c.w, c.h)
    ctx.restoreGState()
    // hairline rim so the card separates from the night sky at small sizes
    ctx.saveGState()
    ctx.translateBy(x: c.x, y: c.y)
    ctx.rotate(by: c.angle * .pi / 180)
    ctx.addPath(cardPath(c)); ctx.setStrokeColor(rgb(0xffffff, 0.35)); ctx.setLineWidth(max(1.5, c.w * 0.008)); ctx.strokePath()
    ctx.restoreGState()
}

// ---------- compose ----------

let ctx = CGContext(data: nil, width: Int(S), height: Int(S), bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.translateBy(x: 0, y: S); ctx.scaleBy(x: 1, y: -1)  // top-left origin, y down

let tile = CGPath(roundedRect: body, cornerWidth: corner, cornerHeight: corner, transform: nil)

// drop shadow under the tile, as in Apple's macOS icon template
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 28, color: rgb(0x000000, 0.35))
ctx.addPath(tile); ctx.setFillColor(rgb(0x0a1230)); ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(tile); ctx.clip()

// sky and water
vertical(ctx, CGRect(x: 0, y: body.minY, width: S, height: horizon - body.minY),
         [(0, rgb(0x060b22)), (0.65, rgb(0x15235a)), (1, rgb(0x2c4290))])
vertical(ctx, CGRect(x: 0, y: horizon, width: S, height: body.maxY - horizon),
         [(0, rgb(0x16245a)), (0.3, rgb(0x0c1638)), (1, rgb(0x060a1c))])

// horizon glow where the river begins
ctx.saveGState()
ctx.translateBy(x: riverPath[0].x, y: horizon); ctx.scaleBy(x: 1, y: 0.3)
ctx.drawRadialGradient(gradient([(0, rgb(0xd5e3ff, 0.85)), (0.25, rgb(0x8fb0ff, 0.3)), (1, rgb(0x8fb0ff, 0))]),
                       startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: 400, options: [])
ctx.restoreGState()

// stars, denser and brighter toward the top
for _ in 0..<60 {
    let x = body.minX + rand() * body.width, t = rand(), y = body.minY + 20 + t * t * (horizon - body.minY - 60)
    let r = 1.2 + rand() * 2.4 * (1 - t * 0.6)
    ctx.setFillColor(rgb(0xffffff, 0.25 + rand() * 0.6 * (1 - t)))
    ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
}
for (x, y, r) in [(240.0, 250.0, 5.0), (800.0, 205.0, 4.0)] as [(CGFloat, CGFloat, CGFloat)] {
    ctx.drawRadialGradient(gradient([(0, rgb(0xffffff, 0.9)), (0.25, rgb(0xcfe0ff, 0.45)), (1, rgb(0xcfe0ff, 0))]),
                           startCenter: CGPoint(x: x, y: y), startRadius: 0, endCenter: CGPoint(x: x, y: y), endRadius: r * 6, options: [])
}

// the river: a ribbon around the centre line, widening toward the viewer, with a soft glow
let ribbon = CGMutablePath()
var left: [CGPoint] = [], right: [CGPoint] = []
for i in 0...200 {
    let t = CGFloat(i) / 200, p = riverPoint(t), q = riverPoint(min(1, t + 0.005)), o = riverPoint(max(0, t - 0.005))
    let dx = q.x - o.x, dy = q.y - o.y, len = max(0.0001, (dx * dx + dy * dy).squareRoot()), half = riverWidth(t) / 2
    left.append(CGPoint(x: p.x - dy / len * half, y: p.y + dx / len * half))
    right.append(CGPoint(x: p.x + dy / len * half, y: p.y - dx / len * half))
}
ribbon.addLines(between: left + right.reversed()); ribbon.closeSubpath()
ctx.saveGState()
ctx.clip(to: CGRect(x: 0, y: horizon, width: S, height: S - horizon))
ctx.setShadow(offset: .zero, blur: 46, color: rgb(0x7f9ff5, 0.9))
ctx.addPath(ribbon); ctx.setFillColor(rgb(0x3d5bb0, 0.55)); ctx.fillPath()
ctx.setShadow(offset: .zero, blur: 0, color: nil)
ctx.addPath(ribbon); ctx.clip()
vertical(ctx, CGRect(x: 0, y: horizon, width: S, height: body.maxY - horizon),
         [(0, rgb(0xe3ecff, 0.95)), (0.2, rgb(0x9db7f7, 0.7)), (0.65, rgb(0x5674cc, 0.5)), (1, rgb(0x34509e, 0.4))])
ctx.restoreGState()
ctx.saveGState()
ctx.addPath(ribbon); ctx.clip()
// ripples: a few soft glints across the current, smaller near the horizon
for i in 0..<16 {
    let t = 0.08 + CGFloat(i) / 16 * 0.9, p = riverPoint(t), half = riverWidth(t) / 2
    let w = 6 + half * (0.15 + 0.3 * rand()), x = p.x + (rand() - 0.5) * half
    ctx.setFillColor(rgb(0xf0f5ff, 0.35 - t * 0.2))
    ctx.addPath(CGPath(roundedRect: CGRect(x: x - w / 2, y: p.y + (rand() - 0.5) * 8, width: w, height: 1.5 + t * 3),
                       cornerWidth: 1 + t * 1.5, cornerHeight: 0.7 + t * 1.5, transform: nil))
    ctx.fillPath()
}
ctx.restoreGState()

for c in cards { drawCard(ctx, c, shadow: true) }

ctx.restoreGState()

// inner rim light on the tile
ctx.addPath(tile.copy(strokingWithWidth: 3, lineCap: .round, lineJoin: .round, miterLimit: 1))
ctx.clip()
vertical(ctx, body, [(0, rgb(0xffffff, 0.22)), (0.4, rgb(0xffffff, 0.04)), (1, rgb(0xffffff, 0.08))])

let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.png")
let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
try! rep.representation(using: .png, properties: [:])!.write(to: out)
