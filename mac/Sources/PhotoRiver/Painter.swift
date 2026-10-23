import CoreGraphics
import Foundation

/// Deterministic 0..<1 noise per integer, so every photo keeps the same card layout and placeholder.
func rand01(_ i: Int) -> Double {
    var x = UInt32(truncatingIfNeeded: i &+ 0x9e3779b9)
    x = (x ^ (x >> 16)) &* 0x85ebca6b
    x = (x ^ (x >> 13)) &* 0xc2b2ae35
    x ^= x >> 16
    return Double(x) / 4294967296
}

enum SceneKind { case sky, sea, city, street, food, people, green, night }

/// Bitmaps for the cards: procedural placeholder "photos" when there is no real image, and cover-cropped thumbnails.
/// Contexts are BGRA, top row first, so their bytes upload straight into a Metal texture.
enum Painter {
    /// Card size in points; textures are painted at a scale on top of this.
    static func cardSize(portrait: Bool) -> CGSize { portrait ? CGSize(width: 176, height: 256) : CGSize(width: 256, height: 176) }

    static let tripKinds: [SceneKind] = [.sky, .sea, .city, .street, .green, .city, .sky, .food]
    static let homeKinds: [SceneKind] = [.food, .people, .green, .night, .street, .sky, .people, .food]

    static func context(_ size: CGSize, scale: CGFloat) -> CGContext {
        let w = Int(size.width * scale), h = Int(size.height * scale)
        return CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                         space: CGColorSpace(name: CGColorSpace.sRGB)!,
                         bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
    }

    /// A placeholder photo for photo `i`, `scale` pixels per card point.
    static func placeholder(_ i: Int, kind: SceneKind, portrait: Bool, scale: CGFloat) -> CGContext {
        let size = cardSize(portrait: portrait)
        let c = context(size, scale: scale)
        c.translateBy(x: 0, y: CGFloat(c.height))
        c.scaleBy(x: scale, y: -scale)  // y down, in card points
        paint(c, w: size.width, h: size.height, i: i, kind: kind)
        return c
    }

    /// `image` scaled to fill the card without stretching, centered.
    static func cover(_ image: CGImage, portrait: Bool, scale: CGFloat) -> CGContext {
        let c = context(cardSize(portrait: portrait), scale: scale)
        let W = CGFloat(c.width), H = CGFloat(c.height)
        let s = max(W / CGFloat(image.width), H / CGFloat(image.height))
        let dw = CGFloat(image.width) * s, dh = CGFloat(image.height) * s
        c.interpolationQuality = .high
        c.draw(image, in: CGRect(x: (W - dw) / 2, y: (H - dh) / 2, width: dw, height: dh))
        return c
    }

    // ---------- the painter ----------

    private static let palettes: [SceneKind: [[String]]] = [
        .sky: [["#f7b977", "#e97a6e", "#4b3b7c"], ["#a9d8ff", "#5a98d8", "#1f447f"], ["#ffd9a6", "#ff9d72", "#6e3f7d"], ["#dfe9ff", "#9fb6e6", "#4e5f98"]],
        .sea: [["#c6ecff", "#52acdc", "#124474"], ["#e3f7ff", "#5fb9cd", "#1d627e"], ["#9fd0e8", "#2f7fb0", "#0d3556"]],
        .city: [["#1c2748", "#3d4f82", "#0a0f20"], ["#2d2444", "#7e4e70", "#100a21"], ["#33435e", "#8db3d2", "#111a29"], ["#4a3a2a", "#c48a5a", "#1a120c"]],
        .street: [["#cdbb9f", "#8e7758", "#3c2f24"], ["#d9cab3", "#9e907d", "#4b4138"], ["#b9c4cf", "#6f7f8f", "#2e3640"]],
        .food: [["#f5e6cb", "#dca45e", "#7c4c2c"], ["#f9f0e2", "#eab56e", "#8c3c2c"], ["#efe7df", "#c9a98f", "#5a3d33"]],
        .people: [["#f2dbca", "#cb9c7c", "#5c3c3c"], ["#ebe4da", "#b9ab9c", "#3c3c4c"], ["#d9e4ef", "#8ea4bb", "#2c3a4c"]],
        .green: [["#e1f0ca", "#71a85c", "#204c2c"], ["#d1e8c4", "#51905c", "#183c2c"], ["#f0f4d8", "#a8c46a", "#3a5a2a"]],
        .night: [["#0b1026", "#1c2c5c", "#060810"], ["#130b26", "#5c2c7c", "#080610"], ["#0a1a2a", "#1c5c7c", "#050a10"]],
    ]
    private static let foodColors = ["#c0392b", "#e67e22", "#8e6a3b", "#6a8f3b", "#f1c40f", "#a04b2b", "#d98b6a"]
    private static let skins = ["#f1c9a5", "#e0b08a", "#c68f6a", "#8d5a3b"]
    private static let cloth = ["#2c3e50", "#8e44ad", "#c0392b", "#16a085", "#f39c12", "#ecf0f1", "#34495e"]

    private static let noise: CGImage = {
        var px = [UInt8](repeating: 0, count: 96 * 96)
        for k in px.indices { px[k] = UInt8(max(0, min(255, 128 + (Double.random(in: 0..<1) - 0.5) * 140))) }
        let provider = CGDataProvider(data: Data(px) as CFData)!
        return CGImage(width: 96, height: 96, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: 96,
                       space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: 0),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    }()

    private static func paint(_ c: CGContext, w: CGFloat, h: CGFloat, i: Int, kind: SceneKind) {
        func rnd(_ k: Int) -> CGFloat { CGFloat(rand01(i * 37 + k)) }
        func pick<T>(_ a: [T], _ k: Int) -> T { a[Int(rnd(k) * CGFloat(a.count))] }
        func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) { c.fill(CGRect(x: x, y: y, width: w, height: h)) }
        func circle(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) { c.fillEllipse(in: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r)) }
        func line(_ x0: CGFloat, _ y0: CGFloat, _ x1: CGFloat, _ y1: CGFloat) {
            c.beginPath(); c.move(to: CGPoint(x: x0, y: y0)); c.addLine(to: CGPoint(x: x1, y: y1)); c.strokePath()
        }

        let pal = pick(palettes[kind]!, 1)
        linear(c, CGPoint(x: 0, y: 0), CGPoint(x: 0, y: h), [(0, hex(pal[0])), (0.55, hex(pal[1])), (1, hex(pal[2]))])
        c.saveGState()
        switch kind {
        case .sky:
            let sx = w * (0.25 + 0.5 * rnd(2)), sy = h * (0.2 + 0.35 * rnd(3)), sr = w * (0.06 + 0.08 * rnd(4))
            radial(c, CGPoint(x: sx, y: sy), 0, sr * 4, [(0, rgba(255, 250, 230, 0.95)), (0.18, rgba(255, 240, 200, 0.6)), (1, rgba(255, 220, 180, 0))])
            c.setFillColor(rgba(255, 255, 255, 0.18))
            for k in 0..<4 {
                let cx = w * rnd(10 + k), cy = h * (0.3 + 0.3 * rnd(20 + k)), rx = w * (0.1 + 0.12 * rnd(30 + k)), ry = h * 0.035
                c.fillEllipse(in: CGRect(x: cx - rx, y: cy - ry, width: 2 * rx, height: 2 * ry))
            }
            c.setFillColor(rgba(20, 16, 40, 0.55)); rect(0, h * 0.78, w, h)
        case .sea:
            let hy = h * (0.42 + 0.16 * rnd(2))
            c.setFillColor(rgba(255, 255, 255, 0.25)); rect(0, hy - 1, w, 2)
            c.setStrokeColor(rgba(255, 255, 255, 0.22)); c.setLineWidth(1.2)
            for k in 0..<9 {
                let y = hy + CGFloat(k + 1) * (h - hy) / 10 + rnd(40 + k) * 4
                line(w * rnd(50 + k) * 0.5, y, w * (0.5 + rnd(60 + k) * 0.5), y)
            }
        case .city:
            let n = 7 + Int(rnd(2) * 7)
            var x: CGFloat = 0
            for k in 0..<n {
                let bw = w / CGFloat(n) * (0.6 + rnd(10 + k) * 0.8), bh = h * (0.25 + rnd(20 + k) * 0.5)
                c.setFillColor(rgba(8, 10, 22, 0.55 + rnd(30 + k) * 0.35)); rect(x, h - bh, bw, bh)
                c.setFillColor(rgba(255, 220, 150, 0.75))
                for r in 0..<14 where rnd(100 + k * 20 + r) < 0.45 {
                    rect(x + 3 + CGFloat(r % 3) * (bw / 3.4), h - bh + 6 + CGFloat(r / 3) * (bh / 5), 2.5, 3.5)
                }
                x += bw * 0.92
            }
        case .street:
            let vx = w * (0.35 + 0.3 * rnd(2)), vy = h * (0.4 + 0.15 * rnd(3))
            c.setStrokeColor(rgba(255, 255, 255, 0.14)); c.setLineWidth(1.5)
            for k in 0..<7 { line(vx, vy, w * CGFloat(k) / 6, h) }
            c.setFillColor(rgba(10, 8, 8, 0.45)); rect(0, 0, w * (0.08 + 0.1 * rnd(4)), h * 0.75); rect(w * (0.82 + 0.1 * rnd(5)), 0, w, h * 0.7)
            c.setFillColor(rgba(255, 230, 200, 0.5)); rect(w * 0.22, h * 0.3, w * 0.03, w * 0.03); rect(w * 0.74, h * 0.34, w * 0.025, w * 0.025)
        case .food:
            let cx = w * 0.5 + (rnd(2) - 0.5) * w * 0.2, cy = h * 0.55, pr = min(w, h) * 0.36
            c.saveGState()
            c.addEllipse(in: CGRect(x: cx - pr, y: cy - pr, width: 2 * pr, height: 2 * pr)); c.clip()
            radial(c, CGPoint(x: cx, y: cy), pr * 0.2, pr, [(0, rgba(255, 255, 255, 0.95)), (1, rgba(235, 228, 220, 0.9))])
            c.restoreGState()
            for k in 0..<5 {
                c.setFillColor(hex(pick(foodColors, 10 + k)))
                circle(cx + (rnd(20 + k) - 0.5) * pr * 1.1, cy + (rnd(30 + k) - 0.5) * pr * 1.1, pr * (0.12 + rnd(40 + k) * 0.2))
            }
        case .people:
            for k in 0..<5 {
                c.setFillColor(rgba(255, 255, 255, 0.05 + rnd(50 + k) * 0.12))
                circle(w * rnd(60 + k), h * rnd(70 + k) * 0.7, w * (0.04 + rnd(80 + k) * 0.08))
            }
            let n = 1 + Int(rnd(2) * 3)
            for k in 0..<n {
                let cx = w * CGFloat(k + 1) / CGFloat(n + 1) + (rnd(10 + k) - 0.5) * w * 0.12
                let hr = min(w, h) * (0.09 + rnd(20 + k) * 0.05), cy = h * (0.42 + rnd(30 + k) * 0.1)
                c.setFillColor(hex(pick(cloth, 40 + k)))
                let body = CGRect(x: cx - hr * 1.6, y: cy + hr * 0.9, width: hr * 3.2, height: h)
                let cr = min(hr, body.width / 2, body.height / 2)
                c.addPath(CGPath(roundedRect: body, cornerWidth: cr, cornerHeight: cr, transform: nil)); c.fillPath()
                c.setFillColor(hex(pick(skins, 50 + k))); circle(cx, cy, hr)
                c.setFillColor(rgba(30, 20, 20, 0.85))
                c.beginPath(); c.addArc(center: CGPoint(x: cx, y: cy - hr * 0.35), radius: hr * 1.02, startAngle: .pi, endAngle: 2 * .pi, clockwise: false); c.fillPath()
            }
        case .green:
            for k in 0..<9 {
                let tx = w * rnd(10 + k), th = h * (0.3 + rnd(20 + k) * 0.5), tw = w * (0.06 + rnd(30 + k) * 0.08)
                c.setFillColor(rgba(20, 60, 30, 0.35 + rnd(40 + k) * 0.45))
                c.beginPath(); c.move(to: CGPoint(x: tx, y: h - th)); c.addLine(to: CGPoint(x: tx - tw, y: h)); c.addLine(to: CGPoint(x: tx + tw, y: h)); c.closePath(); c.fillPath()
            }
            linear(c, CGPoint(x: w * 0.2, y: 0), CGPoint(x: w * 0.8, y: h), [(0, rgba(255, 255, 220, 0.22)), (1, rgba(255, 255, 220, 0))])
        case .night:
            c.setStrokeColor(rgba(255, 200, 120, 0.5)); c.setLineWidth(2); c.setLineCap(.round)
            for k in 0..<6 {
                let y = h * (0.4 + rnd(10 + k) * 0.5)
                line(w * rnd(20 + k) * 0.6, y, w * (0.4 + rnd(30 + k) * 0.6), y + (rnd(40 + k) - 0.5) * 10)
            }
            c.setFillColor(rgba(255, 255, 255, 0.8))
            for k in 0..<10 { rect(w * rnd(50 + k), h * rnd(60 + k) * 0.6, 1.5, 1.5) }
        }
        c.restoreGState()

        // film grain in device pixels (so it stays fine at any scale), then a vignette
        c.saveGState()
        c.concatenate(c.ctm.inverted())
        c.setAlpha(0.16)
        c.draw(noise, in: CGRect(x: 0, y: 0, width: 96, height: 96), byTiling: true)
        c.restoreGState()
        radial(c, CGPoint(x: w / 2, y: h / 2), min(w, h) * 0.35, max(w, h) * 0.75, [(0, rgba(0, 0, 0, 0)), (1, rgba(0, 0, 0, 0.38))])
    }

    // ---------- small CG helpers ----------

    private static let srgb = CGColorSpace(name: CGColorSpace.sRGB)!

    private static func rgba(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat) -> CGColor {
        CGColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: a)
    }

    private static func hex(_ s: String) -> CGColor {
        let v = Int(s.dropFirst(), radix: 16) ?? 0
        return rgba(CGFloat(v >> 16 & 255), CGFloat(v >> 8 & 255), CGFloat(v & 255), 1)
    }

    private static func gradient(_ stops: [(CGFloat, CGColor)]) -> CGGradient {
        CGGradient(colorsSpace: srgb, colors: stops.map(\.1) as CFArray, locations: stops.map(\.0))!
    }

    /// Fills the current clip, extending the end colors like a canvas gradient does.
    private static func linear(_ c: CGContext, _ a: CGPoint, _ b: CGPoint, _ stops: [(CGFloat, CGColor)]) {
        c.drawLinearGradient(gradient(stops), start: a, end: b, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    }

    private static func radial(_ c: CGContext, _ center: CGPoint, _ r0: CGFloat, _ r1: CGFloat, _ stops: [(CGFloat, CGColor)]) {
        c.drawRadialGradient(gradient(stops), startCenter: center, startRadius: r0, endCenter: center, endRadius: r1,
                             options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    }
}
