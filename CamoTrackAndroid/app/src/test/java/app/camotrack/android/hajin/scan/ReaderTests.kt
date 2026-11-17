package app.camotrack.android.hajin.scan

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** The post-match backpack's text (HajinBackpack), ML Kit's lines, the detector's map, routing. */
class ReaderTests {
    /** A line by its top-left box in fractions (converted to Vision's bottom-left boxes). */
    private fun line(text: String, x: Double, top: Double, w: Double = 0.1, h: Double = 0.02) = TextLine(text, Box(x, 1 - top - h, w, h))

    @Test fun cyrillicLookAlikesAreReadAsLatin() {
        assertEquals("BACKPACK", PostMatchReader.normalised("ВАСКРАСК"))
        assertEquals("SECURESLOTS", PostMatchReader.normalised("Secure slots"))
    }

    @Test fun theSortPanelGivesFourResourcesCappedByMax() {
        val lines = listOf(line("SORT", 0.70, 0.20, 0.05), line("043", 0.70, 0.25), line("O10", 0.70, 0.28),
                           line("29", 0.70, 0.31), line("080", 0.70, 0.34), line("MAX 100", 0.70, 0.37))
        // "29" isn't three digits, so only three values: nothing
        assertTrue(PostMatchReader.resources(lines).isEmpty())
        val full = listOf(line("SORT", 0.70, 0.20, 0.05), line("843", 0.70, 0.25), line("O10", 0.70, 0.28),
                          line("029", 0.70, 0.31), line("000", 0.70, 0.34), line("MAX 100", 0.70, 0.37))
        // 843 is over the cap of 100: a misread 043; metals at 0 left out
        assertEquals(mapOf("synthetics" to 43, "electronics" to 10, "chemicals" to 29), PostMatchReader.resources(full))
    }

    @Test fun theBackpackIsFramedFromItsHeaderSortAndSecureSlots() {
        val lines = listOf(line("MEDIUM BACKPACK", 0.20, 0.10, 0.2, 0.03), line("SORT", 0.70, 0.10, 0.05),
                           line("SECURE SLOTS", 0.20, 0.70, 0.15))
        assertTrue(PostMatchReader.isBackpack(lines))
        val q = PostMatchReader.guess(lines, 1000, 1000)!!
        assertEquals(0.20, q[0].x, 1e-9)
        assertTrue(q[1].x > 0.6 && q[1].x < 0.7)
        assertTrue(q[3].y < 0.70 && q[3].y > 0.6)
        val secure = PostMatchReader.secureRow(q, lines, 1000, 1000)
        assertTrue(secure[0].y > q[3].y)
        assertEquals(4, PostMatchReader.COLUMNS)
        assertNull(PostMatchReader.guess(listOf(line("SORT", 0.7, 0.1)), 1000, 1000))
    }

    @Test fun platesAndDogTagsNeverReachTheStash() {
        assertTrue(PostMatchReader.discarded("armor-plate"))
        assertTrue(PostMatchReader.discarded("lieutenant-dog-tag-case"))
        assertTrue(!PostMatchReader.discarded("gold-bar"))
    }

    @Test fun aLineSplitsWhereItsWordsAreFarApart() {
        val words = listOf(
            TextSegments.Word("ALL", 100.0, 50.0, 150.0, 80.0),
            TextSegments.Word("9/18", 400.0, 50.0, 460.0, 80.0), TextSegments.Word("WEAPONS", 470.0, 50.0, 600.0, 80.0),
            TextSegments.Word("79/94", 800.0, 50.0, 870.0, 80.0), TextSegments.Word("ITEMS", 878.0, 50.0, 960.0, 80.0))
        val lines = TextSegments.split(words, 1000, 1000)
        assertEquals(listOf("ALL", "9/18 WEAPONS", "79/94 ITEMS"), lines.map { it.text })
        // Vision's box: origin bottom left
        assertEquals(0.92, lines[0].box.minY, 1e-9)
        assertEquals(0.96, lines[2].bottomRight.x, 1e-9)
    }

    @Test fun theDetectorsMapDecodesToPeaksInPhotoPixels() {
        val grid = 4; val side = 32
        val out = FloatArray(grid * grid * 5)
        fun set(x: Int, y: Int, vararg v: Float) = v.forEachIndexed { c, f -> out[(y * grid + x) * 5 + c] = f }
        set(1, 1, 0.9f, 0.5f, 0.5f, 2f, 2f)    // a tile centred at (12, 12), 16 px
        set(2, 1, 0.6f, 0.5f, 0.5f, 2f, 2f)    // its weaker neighbour: not a peak
        set(3, 3, 0.4f, 0f, 0f, 1f, 1f)
        val found = TileHeatmap.decode(out, grid, side, 320, 640)
        assertEquals(2, found.size)
        assertEquals(0.9f, found[0].confidence)
        assertEquals(Box(40.0, 80.0, 160.0, 320.0), found[0].box)
    }

    @Test fun aPhotoIsRoutedByItsText() {
        val items = listOf(ScanItem("biomaterials", "Biomaterials", "Ingredient"))
        fun engine(lines: List<TextLine>) = ScanEngine({ emptyList() }, null, { lines })
        val image = Raster.filled(10, 10, 0)
        assertEquals(PhotoKind.Backpack, engine(listOf(line("LARGE BACKPACK", 0.1, 0.1, 0.2))).route(image, items))
        assertEquals(PhotoKind.Stash, engine(listOf(line("79/94 ITEMS", 0.6, 0.1))).route(image, items))
        assertEquals(PhotoKind.Stash, engine(emptyList()).route(image, items))
        val printer = engine(listOf(line("Biomaterials", 0.4, 0.4), line("20/10", 0.4, 0.43))).route(image, items)
        assertEquals(PhotoKind.Printer(TextRead(mapOf("biomaterials" to 20), null, null)), printer)
    }

    @Test fun straighteningAQuadGivesItsPicture() {
        // a 100 x 100 picture, left half red, right half blue
        val img = Raster(100, 100, IntArray(100 * 100) { if (it % 100 < 50) Raster.rgb(200, 0, 0) else Raster.rgb(0, 0, 200) })
        val flat = img.straightened(listOf(Pt(0.25, 0.25), Pt(0.75, 0.25), Pt(0.75, 0.75), Pt(0.25, 0.75)), 20, 10)
        assertNotNull(flat)
        assertEquals(200, flat!!.r(0))
        assertEquals(200, flat.b(19))
        val small = img.resized(10, 10)
        assertEquals(200, small.r(0)); assertEquals(200, small.b(9))
    }
}
