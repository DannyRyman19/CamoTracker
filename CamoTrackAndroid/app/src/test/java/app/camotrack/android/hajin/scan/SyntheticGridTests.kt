package app.camotrack.android.hajin.scan

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.abs

/**
 * The whole grid reader on a made-up photo: the iPhone tests' real tiles
 * laid out as a stash (133 px tiles every 148, grey outlines), seen at an
 * angle. A fake classifier tells the tiles apart by colour, so this checks
 * the straightening, border fitting, voting, counts and totals.
 */
class SyntheticGridTests {
    private val names = listOf("r0c0", "r0c1", "r1c2", "r2c0", "r3c2", "r4c3")
    private val counts = listOf(1, 4, 8, 10, 9, 10)
    private val refs = names.map { testTile("stash_tile_$it") }
    private val rowsInGrid = 3

    /** The stash straight on: tiles of row 0 are the real ones, then two rows of empties. */
    private fun screen(pad: Int = 60, top: Int = pad, tile: Int = 133): Pair<Raster, List<Box>> {
        val pitch = 148
        val w = 2 * pad + 5 * pitch + tile; val h = top + pad + (rowsInGrid - 1) * pitch + tile
        val px = IntArray(w * h) { Raster.rgb(22, 23, 25) }
        val boxes = ArrayList<Box>()
        for (r in 0 until rowsInGrid) for (c in 0 until 6) {
            val x0 = pad + c * pitch; val y0 = top + r * pitch
            boxes.add(Box(x0.toDouble(), y0.toDouble(), tile.toDouble(), tile.toDouble()))
            val src = if (r == 0) refs[c].resized(tile, tile) else null
            for (y in 0 until tile) for (x in 0 until tile) {
                val edge = x < 2 || y < 2 || x >= tile - 2 || y >= tile - 2
                px[(y0 + y) * w + x0 + x] = when {
                    edge -> Raster.rgb(150, 150, 150)
                    src != null -> src.pixels[y * tile + x]
                    else -> Raster.rgb(30, 31, 34)
                }
            }
        }
        return Raster(w, h, px) to boxes
    }

    /** The screen seen at an angle on a bigger photo: the photo and where the
     *  screen's corners went (fractions). */
    private fun photo(screen: Raster, quad: List<Pt>, w: Int, h: Int): Raster {
        val toPhoto = TileLattice.homography(listOf(
            doubleArrayOf(0.0, 0.0, quad[0].x * w, quad[0].y * h), doubleArrayOf(screen.width.toDouble(), 0.0, quad[1].x * w, quad[1].y * h),
            doubleArrayOf(screen.width.toDouble(), screen.height.toDouble(), quad[2].x * w, quad[2].y * h),
            doubleArrayOf(0.0, screen.height.toDouble(), quad[3].x * w, quad[3].y * h)))!!
        val back = TileLattice.invert(toPhoto)!!
        val out = IntArray(w * h)
        for (y in 0 until h) for (x in 0 until w) {
            val (sx, sy) = TileLattice.apply(back, x + 0.5, y + 0.5)
            out[y * w + x] = if (sx < 0 || sy < 0 || sx >= screen.width || sy >= screen.height) Raster.rgb(60, 55, 50)
                             else screen.sample(sx - 0.5, sy - 0.5)
        }
        return Raster(w, h, out)
    }

    /** A coarse thumbnail of a tile's middle, to tell the tiles apart. */
    private fun thumb(r: Raster): IntArray {
        val c = r.cropped(Box(30.0, 30.0, 140.0, 140.0))!!.resized(8, 8)
        return IntArray(64 * 3) { k -> val i = k / 3; when (k % 3) { 0 -> c.r(i); 1 -> c.g(i); else -> c.b(i) } }
    }
    private val refThumbs = refs.map(::thumb) + listOf(thumb(Raster.filled(200, 200, Raster.rgb(30, 31, 34))))

    /** Names a tile by the nearest reference thumbnail (the last is empty). */
    private val classifier = TileClassifier { tile ->
        val t = thumb(tile)
        val all = refThumbs.mapIndexed { k, ref ->
            (if (k < refs.size) "item-$k" else "empty") to ref.indices.sumOf { abs(ref[it] - t[it]) }
        }.sortedBy { it.second }
        all.mapIndexed { k, (id, _) -> Classification(id, if (k == 0) 0.9f else 0.1f / all.size) }
    }

    @Test fun anAngledStashReadsEveryTileAndCount() {
        val (screen, _) = screen()
        // the screen's corners on the photo, a phone's angle
        val quad = listOf(Pt(0.12, 0.18), Pt(0.86, 0.22), Pt(0.9, 0.7), Pt(0.08, 0.66))
        val photo = photo(screen, quad, 1600, 1200)
        // the grid's corners: the tiles' outer edges, through the same perspective
        val sw = screen.width.toDouble(); val sh = screen.height.toDouble()
        val corners = listOf(Pt(60 / sw, 60 / sh), Pt((sw - 60) / sw, 60 / sh), Pt((sw - 60) / sw, (sh - 60) / sh), Pt(60 / sw, (sh - 60) / sh))
            .map { quadPoint(quad, it.x, it.y) }
        assertEquals(rowsInGrid, StashGrid.measureRows(photo, corners))
        val tiles = StashGridReader(classifier).read(photo, corners)
        assertEquals(6 * rowsInGrid, tiles.size)
        for (c in 0 until 6) {
            val t = tiles.first { it.row == 0 && it.column == c }
            assertEquals("tile $c", "item-$c", t.id)
            assertEquals("count of tile $c", counts[c], t.count)
            assertNotNull(t.place)
        }
        assertTrue(tiles.filter { it.row > 0 }.all { it.id == "empty" })
        val totals = StashGrid.totals(tiles)
        assertEquals(10, totals.counts["item-3"])
        assertEquals(6, totals.counts.size)
        assertTrue(totals.unsure.isEmpty())
    }

    @Test fun theDetectorsTilesFindTheGrid() {
        val (screen, boxes) = screen()
        val quad = listOf(Pt(0.12, 0.18), Pt(0.86, 0.22), Pt(0.9, 0.7), Pt(0.08, 0.66))
        val photo = photo(screen, quad, 1600, 1200)
        // a perfect detector: each tile's box on the photo
        val found = boxes.map { b ->
            val pts = listOf(Pt(b.minX, b.minY), Pt(b.maxX, b.minY), Pt(b.maxX, b.maxY), Pt(b.minX, b.maxY))
                .map { quadPoint(quad, it.x / screen.width, it.y / screen.height) }.map { Pt(it.x * 1600, it.y * 1200) }
            Detection(Box.ltrb(pts.minOf { it.x }, pts.minOf { it.y }, pts.maxOf { it.x }, pts.maxOf { it.y }), 0.9f)
        }
        val q = GridFinder.guess(photo, found) { emptyList() }!!
        val sw = screen.width.toDouble(); val sh = screen.height.toDouble()
        val truth = listOf(Pt(60 / sw, 60 / sh), Pt((sw - 60) / sw, 60 / sh), Pt((sw - 60) / sw, (sh - 60) / sh), Pt(60 / sw, (sh - 60) / sh))
            .map { quadPoint(quad, it.x, it.y) }
        for (k in 0 until 4) assertTrue("corner $k ${q[k]} vs ${truth[k]}", (q[k] - truth[k]).length() < 0.015)
    }

    /** A straight screenshot with the header read: the text-and-lines ways in. */
    @Test fun aStraightScreenshotIsFramedFromItsHeader() {
        // Tiles nearly touching: these ways look for one line per border
        val (screen, boxes) = screen(pad = 100, top = 220, tile = 145)
        val w = screen.width.toDouble(); val h = screen.height.toDouble()
        val left = boxes.first().minX; val right = boxes.last().maxX
        val baseline = boxes.first().minY - 0.58 * (right - left) / 6
        // Vision's space: origin bottom left
        val lines = listOf(TextLine("ALL", Box(left / w, 1 - baseline / h, 60 / w, 30 / h)),
                           TextLine("79/94 ITEMS", Box((right - 200) / w, 1 - baseline / h, 200 / w, 30 / h)))
        val truth = listOf(Pt(left / w, boxes.first().minY / h), Pt(right / w, boxes.first().minY / h),
                           Pt(right / w, boxes.last().maxY / h), Pt(left / w, boxes.last().maxY / h))
        for ((name, q) in listOf("straight" to GridFinder.fromStraightLattice(screen, lines), "header" to GridFinder.fromHeader(screen, lines))) {
            assertNotNull(name, q)
            for (k in 0 until 4) assertTrue("$name corner $k ${q!![k]} vs ${truth[k]}", (q[k] - truth[k]).length() < 0.03)
        }
        // and the guess, with no detector, picks one of them
        assertNotNull(GridFinder.guess(screen, emptyList()) { lines })
    }

    @Test fun photoQuality() {
        val (screen, _) = screen()
        val sharp = PhotoQuality.issues(screen)
        assertTrue(PhotoQuality.SMALL in sharp)
        assertTrue(PhotoQuality.BLURRY !in sharp && PhotoQuality.GLARE !in sharp)
        val flat = PhotoQuality.issues(Raster.filled(1200, 1000, Raster.rgb(20, 20, 20)))
        assertEquals(listOf(PhotoQuality.BLURRY, PhotoQuality.DARK), flat)
        assertTrue(PhotoQuality.GLARE in PhotoQuality.issues(Raster.filled(1200, 1000, Raster.rgb(250, 250, 250))))
    }
}
