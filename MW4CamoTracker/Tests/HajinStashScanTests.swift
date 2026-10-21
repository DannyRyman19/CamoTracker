import CoreGraphics
import Foundation
import Testing
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
}
