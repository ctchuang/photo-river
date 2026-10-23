import Foundation
import Photos

/// The photos the river shows, as parallel arrays in time order (index i is the same photo everywhere).
/// Built either from the Photos library through PhotoKit, or from a photos.json file (the synthetic sample).
final class Library {
    let t: [Double]            // unix seconds, ascending
    let lat: [Double]
    let lng: [Double]
    let geo: [Bool]            // false when the photo has no location
    let trip: [Bool]           // more than 150 km from that year's home
    let portrait: [Bool]?      // real orientation; nil for the sample, whose cards pick one at random
    let assets: [PHAsset]      // empty for a JSON library
    let synthetic: Bool

    var count: Int { t.count }

    init(t: [Double], lat: [Double?], lng: [Double?], portrait: [Bool]?, assets: [PHAsset], synthetic: Bool) {
        let n = t.count
        var la = [Double](repeating: 0, count: n), lo = la, g = [Bool](repeating: false, count: n)
        for i in 0..<n {
            if let a = lat[i], let b = lng[i] { la[i] = a; lo[i] = b; g[i] = true }
        }
        self.t = t; self.lat = la; self.lng = lo; self.geo = g
        self.portrait = portrait; self.assets = assets; self.synthetic = synthetic
        self.trip = Library.awayFlags(t: t, lat: la, lng: lo, geo: g)
    }

    /// Home per year is the most common 1° cell; a photo more than 150 km from it is "away".
    private static func awayFlags(t: [Double], lat: [Double], lng: [Double], geo: [Bool]) -> [Bool] {
        let cal = Calendar.current
        let years = t.map { cal.component(.year, from: Date(timeIntervalSince1970: $0)) }
        func cell(_ i: Int) -> Int { (Int(floor(lat[i])) + 90) * 1000 + (Int(floor(lng[i])) + 180) }
        var counts: [Int: [Int: Int]] = [:]
        for i in t.indices where geo[i] { counts[years[i], default: [:]][cell(i), default: 0] += 1 }
        var home: [Int: (Double, Double)] = [:]
        for (y, m) in counts {
            let best = m.max { $0.value < $1.value }!.key
            home[y] = (Double(best / 1000 - 90) + 0.5, Double(best % 1000 - 180) + 0.5)
        }
        return t.indices.map { i in
            guard geo[i], let h = home[years[i]] else { return false }
            return haversine(lat[i], lng[i], h.0, h.1) > 150
        }
    }

    /// First index whose time is at or after `x`.
    func lowerBound(_ x: Double) -> Int {
        var lo = 0, hi = t.count
        while lo < hi { let m = (lo + hi) / 2; if t[m] < x { lo = m + 1 } else { hi = m } }
        return lo
    }

    func date(_ i: Int) -> Date { Date(timeIntervalSince1970: t[i]) }

    // ---------- sources ----------

    /// Every image in the Photos library, oldest first. Photos dated exactly 1980-01-01 00:00 are skipped:
    /// that is the placeholder date for images with no capture time (screenshots, downloaded PNGs).
    static func fromPhotos(progress: @escaping (Int, Int) -> Void) -> Library {
        let opts = PHFetchOptions()
        opts.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        opts.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        let result = PHAsset.fetchAssets(with: opts)
        let total = result.count
        let placeholder = DateComponents(calendar: .current, year: 1980, month: 1, day: 1).date!.timeIntervalSince1970

        var rows: [(t: Double, lat: Double?, lng: Double?, portrait: Bool, asset: PHAsset)] = []
        rows.reserveCapacity(total)
        result.enumerateObjects { a, n, _ in
            if n % 1000 == 0 { progress(n, total) }
            guard let d = a.creationDate?.timeIntervalSince1970, d != placeholder else { return }
            let c = a.location?.coordinate
            rows.append((d, c?.latitude, c?.longitude, a.pixelHeight > a.pixelWidth, a))
        }
        rows.sort { $0.t < $1.t }
        return Library(t: rows.map(\.t), lat: rows.map(\.lat), lng: rows.map(\.lng),
                       portrait: rows.map(\.portrait), assets: rows.map(\.asset), synthetic: false)
    }

    /// A photos.json file in the format described in docs/DATA.md.
    static func fromJSON(_ url: URL) throws -> Library {
        struct File: Decodable {
            struct Meta: Decodable { let source: String? }
            let meta: Meta?
            let t: [Double]
            let lat: [Double?]
            let lng: [Double?]
        }
        let f = try JSONDecoder().decode(File.self, from: Data(contentsOf: url))
        return Library(t: f.t, lat: f.lat, lng: f.lng, portrait: nil, assets: [], synthetic: f.meta?.source == "synthetic")
    }

    /// The synthetic sample: bundled in the app, or read from the repository when run outside the bundle.
    static func sampleURL() -> URL? {
        if let u = Bundle.main.url(forResource: "sample-photos", withExtension: "json") { return u }
        for p in ["data/sample/photos.json", "../data/sample/photos.json"] where FileManager.default.fileExists(atPath: p) {
            return URL(fileURLWithPath: p)
        }
        return nil
    }
}

func haversine(_ aLat: Double, _ aLng: Double, _ bLat: Double, _ bLng: Double) -> Double {
    let r = Double.pi / 180
    let dp = (bLat - aLat) * r, dl = (bLng - aLng) * r
    let h = pow(sin(dp / 2), 2) + cos(aLat * r) * cos(bLat * r) * pow(sin(dl / 2), 2)
    return 2 * 6371 * asin(sqrt(h))
}
