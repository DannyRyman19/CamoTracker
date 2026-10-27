import CoreGraphics
import Foundation
import Testing
import UIKit
@testable import MW4CamoTracker

/// Reading stash counts from the text Vision finds in a photo.
struct HajinStashScanTests {

    private func items() throws -> [HajinGuide.Item] {
        let json = #"""
        [{"id": "synthetics", "name": "Synthetics", "kind": "Resource"},
         {"id": "chemicals", "name": "Chemicals", "kind": "Resource"},
         {"id": "reactive-metals", "name": "Reactive Metals", "kind": "Ingredient"},
         {"id": "biomaterials", "name": "Biomaterials", "kind": "Ingredient"}]
        """#
        return try JSONDecoder().decode([HajinGuide.Item].self, from: Data(json.utf8))
    }

    /// A line of text at a vertical position (Vision boxes start at the bottom).
    private func line(_ text: String, x: CGFloat = 0.4, top: CGFloat, height: CGFloat = 0.02) -> HajinStashScanner.Line {
        HajinStashScanner.Line(text: text, box: CGRect(x: x, y: 1 - top - height, width: 0.12, height: height))
    }

    @Test func haveIsTheFirstNumberOfHaveOverNeed() {
        #expect(HajinStashScanner.have(in: "607/50") == 607)
        #expect(HajinStashScanner.have(in: "6 / 5") == 6)
        #expect(HajinStashScanner.have(in: "Synthetics 1,240/50") == 1240)
        #expect(HajinStashScanner.have(in: "Stash item") == nil)
    }

    @Test func aPrinterRecipeGivesEachIngredientsCountFromTheLineBelow() throws {
        let found = HajinStashScanner.counts(in: [
            line("Synthetics", top: 0.40), line("607/50", top: 0.43),
            line("Reactive Metals", top: 0.50), line("6/5", top: 0.53),
        ], items: try items())
        #expect(found == ["synthetics": 607, "reactive-metals": 6])
    }

    @Test func stashResourceTotalsArePlainNumbersEvenWithTheNameCutOff() throws {
        let found = HajinStashScanner.counts(in: [
            line("THETICS", x: 0, top: 0.80), line("846", x: 0, top: 0.83),
            line("CHEMICALS", x: 0, top: 0.88), line("793", x: 0, top: 0.91),
        ], items: try items())
        #expect(found == ["synthetics": 846, "chemicals": 793])
    }

    @Test func aPlainNumberNeverCountsForAnIngredient() throws {
        // Only resources show a bare total; an ingredient needs have/need
        let found = HajinStashScanner.counts(in: [line("Reactive Metals", top: 0.50), line("10", top: 0.53)], items: try items())
        #expect(found.isEmpty)
    }

    @Test func aBigScreenTitleDoesNotTakeTheCountUnderIt() throws {
        // A printable ingredient's own recipe page: the title is large text
        let found = HajinStashScanner.counts(in: [
            line("BIOMATERIALS", top: 0.10, height: 0.06), line("20/10", top: 0.17),
        ], items: try items())
        #expect(found["biomaterials"] == nil)
    }

    /// "Send this photo": the report carries the reader's working and the
    /// player's corrections, as JSON that parses back.
    @Test @MainActor func scanReportJSON() throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 30)).image { _ in }
        let report = HajinScanReport(image: image, quality: [.blurry], guessedCorners: [CGPoint(x: 0.1, y: 0.2)],
                                     corners: [CGPoint(x: 0.12345678, y: 0.2)], moved: true,
                                     tiles: [.init(row: 0, column: 1, id: "biomaterials", confidence: 0.9, count: 10)],
                                     found: ["biomaterials": 10], unsure: ["biomaterials"], sureness: ["biomaterials": 0.9],
                                     cash: 33_050, level: 38)
        let data = try #require(report.json(had: ["biomaterials": 4], edited: ["biomaterials": 12], skipped: []))
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["level"] as? Int == 38)
        #expect(json["quality"] as? [String] == ["blurry"])
        #expect((json["editedByPlayer"] as? [String: Int])?["biomaterials"] == 12)
        #expect((json["corners"] as? [[Double]])?.first?.first == 0.1235)
        #expect((json["tiles"] as? [[String: Any]])?.first?["count"] as? Int == 10)
        #expect(report.photoData() != nil)
    }

    /// "Add another photo": the next photo's counts go on top of what was
    /// read, an item in both keeping the higher count, and the carried
    /// counts are used once.
    @available(iOS 17.0, *)
    @MainActor @Test func anotherPhotoAddsToTheCountsWithoutCountingTwice() {
        let flow = HajinScanFlow()
        flow.addPhoto(["biomaterials": 10, "gold-skull": 2], photos: 1)
        let next = flow.merged(HajinGridResult(counts: ["gold-skull": 3, "gold-bar": 1], unsure: []))
        #expect(next.counts == ["biomaterials": 10, "gold-skull": 3, "gold-bar": 1])
        #expect(next.photos == 2)
        #expect(flow.carried == nil)
        #expect(flow.merged(HajinGridResult(counts: ["cpu": 4], unsure: [])).counts == ["cpu": 4])
    }
}
/// Runs the grid finder over a folder of real stash photos and writes the
/// corners it finds to `corners.json` there, for checking by eye. Only runs
/// when GRID_PHOTOS is set (TEST_RUNNER_GRID_PHOTOS=<folder> on xcodebuild).
struct HajinGridFinderHarness {
    @Test func findGridsInRealPhotos() throws {
        guard let folder = ProcessInfo.processInfo.environment["GRID_PHOTOS"] else { return }
        var out: [String: [[Double]]] = [:]
        for name in try FileManager.default.contentsOfDirectory(atPath: folder).sorted() where name.hasSuffix(".jpg") || name.hasSuffix(".png") {
            guard let image = UIImage(contentsOfFile: folder + "/" + name)?.normalisedUp(),
                  let corners = HajinStashGridFinder.guess(image) else { out[name] = []; continue }
            out[name] = corners.map { [Double($0.x), Double($0.y)] }
        }
        try JSONSerialization.data(withJSONObject: out, options: [.prettyPrinted, .sortedKeys])
            .write(to: URL(fileURLWithPath: folder + "/corners.json"))
    }
}
