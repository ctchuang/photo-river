// Tests for Library: what the river asks PhotoKit for, and the pure helpers it builds on.
// None of them read the Photos library, so they need no permission.
//   make test

import Foundation
import Photos
import Testing
@testable import PhotoRiver

@Suite struct FetchOptionsTests {
    @Test func hiddenPhotosAreExcluded() {
        #expect(Library.fetchOptions().includeHiddenAssets == false)
    }

    @Test func onlyImagesAreFetched() throws {
        let predicate = try #require(Library.fetchOptions().predicate)
        #expect(predicate.predicateFormat == "mediaType == \(PHAssetMediaType.image.rawValue)")
    }

    @Test func oldestFirst() throws {
        let sort = try #require(Library.fetchOptions().sortDescriptors?.first)
        #expect(sort.key == "creationDate")
        #expect(sort.ascending)
    }
}

@Suite struct PlaceholderDateTests {
    @Test func isMidnightOnNewYear1980LocalTime() {
        let c = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second],
                                                from: Date(timeIntervalSince1970: Library.placeholderDate))
        #expect([c.year, c.month, c.day, c.hour, c.minute, c.second] == [1980, 1, 1, 0, 0, 0])
    }
}

@Suite struct LibraryTests {
    /// Unix seconds for noon on a date, local time.
    func noon(_ y: Int, _ m: Int, _ d: Int) -> Double {
        DateComponents(calendar: .current, year: y, month: m, day: d, hour: 12).date!.timeIntervalSince1970
    }

    @Test func photosWithoutLocationAreNotOnTheMap() {
        let lib = Library(t: [1, 2], lat: [25.03, nil], lng: [121.56, nil], portrait: nil, assets: [], synthetic: false)
        #expect(lib.geo == [true, false])
        #expect(lib.count == 2)
    }

    @Test func photosFarFromThatYearsHomeAreTrips() {
        // Three photos at home in Taipei, one in Rome the same year, one with no location.
        let t = [noon(2010, 3, 1), noon(2010, 4, 1), noon(2010, 5, 1), noon(2010, 9, 19), noon(2010, 10, 1)]
        let lat: [Double?] = [25.03, 25.04, 25.05, 41.90, nil]
        let lng: [Double?] = [121.56, 121.53, 121.52, 12.47, nil]
        let lib = Library(t: t, lat: lat, lng: lng, portrait: nil, assets: [], synthetic: false)
        #expect(lib.trip == [false, false, false, true, false])
    }

    @Test func lowerBoundFindsTheFirstPhotoAtOrAfterATime() {
        let lib = Library(t: [10, 20, 20, 30], lat: [nil, nil, nil, nil], lng: [nil, nil, nil, nil],
                          portrait: nil, assets: [], synthetic: false)
        #expect(lib.lowerBound(0) == 0)
        #expect(lib.lowerBound(20) == 1)
        #expect(lib.lowerBound(25) == 3)
        #expect(lib.lowerBound(99) == 4)
    }

    @Test func haversineDistances() {
        #expect(haversine(25.03, 121.56, 25.03, 121.56) == 0)
        // Taipei to Rome is about 9,612 km along the great circle (checked with the spherical law of cosines).
        #expect(abs(haversine(25.03, 121.56, 41.90, 12.47) - 9_612) < 1)
    }

    @Test func readsTheSyntheticSample() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("data/sample/photos.json")
        let lib = try Library.fromJSON(url)
        #expect(lib.synthetic)
        #expect(lib.count == 20_613)
        #expect(zip(lib.t, lib.t.dropFirst()).allSatisfy { $0 <= $1 })
    }
}
