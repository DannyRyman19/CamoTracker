package app.camotrack.android.hajin.scan

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.double
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Reading stash counts from the text found in a photo (HajinStashScanTests). */
class StashScanTests {
    private val items = listOf(
        ScanItem("synthetics", "Synthetics", "Resource"),
        ScanItem("chemicals", "Chemicals", "Resource"),
        ScanItem("reactive-metals", "Reactive Metals", "Ingredient"),
        ScanItem("biomaterials", "Biomaterials", "Ingredient"),
    )

    /** A line of text at a vertical position (Vision boxes start at the bottom). */
    private fun line(text: String, x: Double = 0.4, top: Double, height: Double = 0.02) =
        TextLine(text, Box(x, 1 - top - height, 0.12, height))

    @Test fun haveIsTheFirstNumberOfHaveOverNeed() {
        assertEquals(607, RecipeReader.have("607/50"))
        assertEquals(6, RecipeReader.have("6 / 5"))
        assertEquals(1240, RecipeReader.have("Synthetics 1,240/50"))
        assertNull(RecipeReader.have("Stash item"))
    }

    @Test fun aPrinterRecipeGivesEachIngredientsCountFromTheLineBelow() {
        val found = RecipeReader.counts(listOf(
            line("Synthetics", top = 0.40), line("607/50", top = 0.43),
            line("Reactive Metals", top = 0.50), line("6/5", top = 0.53),
        ), items)
        assertEquals(mapOf("synthetics" to 607, "reactive-metals" to 6), found)
    }

    @Test fun stashResourceTotalsArePlainNumbersEvenWithTheNameCutOff() {
        val found = RecipeReader.counts(listOf(
            line("THETICS", x = 0.0, top = 0.80), line("846", x = 0.0, top = 0.83),
            line("CHEMICALS", x = 0.0, top = 0.88), line("793", x = 0.0, top = 0.91),
        ), items)
        assertEquals(mapOf("synthetics" to 846, "chemicals" to 793), found)
    }

    @Test fun aPlainNumberNeverCountsForAnIngredient() {
        // Only resources show a bare total; an ingredient needs have/need
        assertTrue(RecipeReader.counts(listOf(line("Reactive Metals", top = 0.50), line("10", top = 0.53)), items).isEmpty())
    }

    @Test fun aBigScreenTitleDoesNotTakeTheCountUnderIt() {
        val found = RecipeReader.counts(listOf(line("BIOMATERIALS", top = 0.10, height = 0.06), line("20/10", top = 0.17)), items)
        assertNull(found["biomaterials"])
    }

    @Test fun anOcrSlipStillMatches() {
        val found = RecipeReader.counts(listOf(line("Biomaterlals", top = 0.40), line("12/10", top = 0.43)), items)
        assertEquals(12, found["biomaterials"])
    }

    @Test fun bankAndLevelFromTheStashScreen() {
        val lines = listOf(line("BANK", x = 0.05, top = 0.05), line("$33,050 / $1M", x = 0.12, top = 0.05),
                           line("LVL", x = 0.02, top = 0.30), line("38", x = 0.02, top = 0.33))
        assertEquals(33050, RecipeReader.bank(lines))
        assertEquals(38, RecipeReader.level(lines))
        assertEquals(12, RecipeReader.level(listOf(line("LVL 12", top = 0.3))))
        assertNull(RecipeReader.bank(listOf(line("STASH", top = 0.1))))
    }

    @Test fun severalPrinterPhotosTakeTheCountReadMostOften() {
        val merged = RecipeReader.merged(listOf(mapOf("a" to 4), mapOf("a" to 5), mapOf("a" to 4, "b" to 2), mapOf("b" to 3)))
        assertEquals(mapOf("a" to 4, "b" to 3), merged)
    }

    /** "Send this photo": the report carries the reader's working and the
     *  player's corrections, as JSON that parses back. */
    @Test fun scanReportJSON() {
        val report = ScanReport(40, 30, listOf(PhotoQuality.BLURRY), listOf(Pt(0.1, 0.2)), listOf(Pt(0.12345678, 0.2)), true,
                                listOf(Tile(0, 1, "biomaterials", 0.9f, 10)), mapOf("biomaterials" to 10), setOf("biomaterials"),
                                mapOf("biomaterials" to 0.9f), 33_050, 38)
        val json = Json.parseToJsonElement(report.json(mapOf("biomaterials" to 4), mapOf("biomaterials" to 12), emptySet())).jsonObject
        assertEquals(38, json["level"]!!.jsonPrimitive.int)
        assertEquals("blurry", json["quality"]!!.jsonArray[0].jsonPrimitive.content)
        assertEquals(12, json["editedByPlayer"]!!.jsonObject["biomaterials"]!!.jsonPrimitive.int)
        assertEquals(0.1235, json["corners"]!!.jsonArray[0].jsonArray[0].jsonPrimitive.double, 1e-12)
        assertEquals(10, json["tiles"]!!.jsonArray[0].jsonObject["count"]!!.jsonPrimitive.int)
    }
}

/** The grid fitted to tile boxes alone: an angled 6 x 7 grid with gaps and two strays (HajinTileLatticeTests). */
class TileLatticeTests {
    @Test fun anAngledGridWithGapsAndStraysGivesItsCorners() {
        val h = doubleArrayOf(150.0, 6.0, 300.0, -4.0, 148.0, 400.0, 0.00004, 0.0001, 1.0)
        val boxes = ArrayList<Box>()
        for (j in 0 until 7) for (i in 0 until 6) {
            if ((i + j) % 5 == 0 && j > 0) continue
            val (x, y) = TileLattice.apply(h, i.toDouble(), j.toDouble())
            boxes.add(Box(x - 60, y - 60, 120.0, 120.0))
        }
        boxes.add(Box(40.0, 1500.0, 120.0, 120.0))     // a stray, off the grid
        boxes.add(Box(1900.0, 200.0, 120.0, 120.0))
        val fit = TileLattice.fit(boxes)!!
        val rows = TileLattice.block(fit.cells.map { it.j })!!
        val cols = TileLattice.block(fit.cells.filter { it.j in rows }.map { it.i })!!
        assertEquals(7, rows.count())
        assertEquals(6, cols.count())
        val corners = TileLattice.corners(fit.h, cols.first, rows, 2000, 2000)
        // its top-left tile's outer corner, wherever the walk numbered it from
        val (tlx, tly) = TileLattice.apply(h, -TileLattice.HALF, -TileLattice.HALF)
        assertTrue(Math.abs(corners[0].x * 2000 - tlx) < 3 && Math.abs(corners[0].y * 2000 - tly) < 3)
        val (brx, bry) = TileLattice.apply(h, 5 + TileLattice.HALF, 6 + TileLattice.HALF)
        assertTrue(Math.abs(corners[2].x * 2000 - brx) < 3 && Math.abs(corners[2].y * 2000 - bry) < 3)
    }

    @Test fun theDetectorsBoxesBecomeTheGridsCorners() {
        // the same grid as detections, through the finder's first way in
        val h = doubleArrayOf(150.0, 6.0, 300.0, -4.0, 148.0, 400.0, 0.00004, 0.0001, 1.0)
        val found = ArrayList<Detection>()
        for (j in 0 until 7) for (i in 0 until 6) {
            val (x, y) = TileLattice.apply(h, i.toDouble(), j.toDouble())
            found.add(Detection(Box(x - 60, y - 60, 120.0, 120.0), 0.9f))
            found.add(Detection(Box(x - 58, y - 61, 118.0, 121.0), 0.6f))   // a duplicate, dropped
        }
        val image = Raster.filled(2000, 2000, Raster.rgb(20, 20, 20))
        val q = GridFinder.fromDetector(image, TileLattice.tiles(found))!!
        val (tlx, tly) = TileLattice.apply(h, -TileLattice.HALF, -TileLattice.HALF)
        assertEquals(tlx, q[0].x * 2000, 3.0)
        assertEquals(tly, q[0].y * 2000, 3.0)
    }
}
