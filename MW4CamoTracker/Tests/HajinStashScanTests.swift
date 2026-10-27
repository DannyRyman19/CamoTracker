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
/// corners it finds to `corners.json` there. Only runs when GRID_PHOTOS is
/// set (TEST_RUNNER_GRID_PHOTOS=<folder> on xcodebuild). The tile detector
/// doesn't run in the simulator, so this checks the fallback; SS_GRID_BATCH
/// does the same on a device.
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

/// The grid fitted to tile boxes alone (the detector itself doesn't run in
/// the simulator): an angled 6 x 7 grid with gaps and two strays.
struct HajinTileLatticeTests {
    @Test func anAngledGridWithGapsAndStraysGivesItsCorners() throws {
        // lattice (i, j) -> image, a mild perspective
        let h: [Double] = [150, 6, 300, -4, 148, 400, 0.00004, 0.0001, 1]
        var boxes: [CGRect] = []
        for j in 0..<7 { for i in 0..<6 where !((i + j) % 5 == 0 && j > 0) {
            let (x, y) = HajinTileLattice.apply(h, Double(i), Double(j))
            boxes.append(CGRect(x: x - 60, y: y - 60, width: 120, height: 120))
        } }
        boxes.append(CGRect(x: 40, y: 1500, width: 120, height: 120))    // a stray, off the grid
        boxes.append(CGRect(x: 1900, y: 200, width: 120, height: 120))
        let (fit, found) = try #require(HajinTileLattice.fit(boxes))
        let rows = try #require(HajinTileLattice.block(found.map(\.j)))
        let cols = try #require(HajinTileLattice.block(found.filter { rows.contains($0.j) }.map(\.i)))
        #expect(rows.count == 7)
        #expect(cols.count == 6)
        let size = CGSize(width: 2000, height: 2000)
        let corners = HajinTileLattice.corners(fit, first: cols.lowerBound, rows: rows, size: size)
        // its top-left tile's outer corner, wherever the walk numbered it from
        let (tlx, tly) = HajinTileLattice.apply(h, -HajinTileLattice.half, -HajinTileLattice.half)
        #expect(abs(corners[0].x * 2000 - tlx) < 3 && abs(corners[0].y * 2000 - tly) < 3)
        let (brx, bry) = HajinTileLattice.apply(h, 5 + HajinTileLattice.half, 6 + HajinTileLattice.half)
        #expect(abs(corners[2].x * 2000 - brx) < 3 && abs(corners[2].y * 2000 - bry) < 3)
    }
}
