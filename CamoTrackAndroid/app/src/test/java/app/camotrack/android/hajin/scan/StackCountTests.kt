package app.camotrack.android.hajin.scan

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.ByteArrayOutputStream
import java.io.DataInputStream
import java.util.zip.Inflater

/** Real tiles from the iPhone's tests, as Rasters. */
internal fun testTile(name: String): Raster {
    val stream = StackCountTests::class.java.getResourceAsStream("/hajin/scan/$name.png") ?: error("no $name.png")
    return stream.use { decodePng(it.readBytes()) }
}

/** A minimal PNG reader for the test tiles (8-bit RGB or RGBA, not interlaced):
 *  javax.imageio isn't on a unit test's compile path. */
internal fun decodePng(bytes: ByteArray): Raster {
    val input = DataInputStream(bytes.inputStream())
    input.skipBytes(8)
    var w = 0; var h = 0; var channels = 0
    val idat = ByteArrayOutputStream()
    while (true) {
        val len = input.readInt()
        val type = String(ByteArray(4).also { input.readFully(it) })
        val data = ByteArray(len).also { input.readFully(it) }
        input.readInt()
        when (type) {
            "IHDR" -> {
                w = java.nio.ByteBuffer.wrap(data, 0, 4).int; h = java.nio.ByteBuffer.wrap(data, 4, 4).int
                require(data[8].toInt() == 8 && data[12].toInt() == 0) { "8-bit, non-interlaced only" }
                channels = when (data[9].toInt()) { 2 -> 3; 6 -> 4; else -> error("RGB or RGBA only") }
            }
            "IDAT" -> idat.write(data)
            "IEND" -> break
        }
    }
    val inflater = Inflater().apply { setInput(idat.toByteArray()) }
    val stride = w * channels
    val raw = ByteArray((stride + 1) * h)
    var got = 0
    while (got < raw.size) got += inflater.inflate(raw, got, raw.size - got)
    val out = ByteArray(stride * h)
    for (y in 0 until h) {
        val filter = raw[y * (stride + 1)].toInt()
        for (x in 0 until stride) {
            val cur = raw[y * (stride + 1) + 1 + x].toInt() and 0xFF
            val a = if (x >= channels) out[y * stride + x - channels].toInt() and 0xFF else 0
            val b = if (y > 0) out[(y - 1) * stride + x].toInt() and 0xFF else 0
            val c = if (x >= channels && y > 0) out[(y - 1) * stride + x - channels].toInt() and 0xFF else 0
            val v = when (filter) {
                0 -> cur; 1 -> cur + a; 2 -> cur + b; 3 -> cur + (a + b) / 2
                4 -> { val p = a + b - c; val pa = Math.abs(p - a); val pb = Math.abs(p - b); val pc = Math.abs(p - c)
                       cur + if (pa <= pb && pa <= pc) a else if (pb <= pc) b else c }
                else -> error("filter $filter")
            }
            out[y * stride + x] = v.toByte()
        }
    }
    val px = IntArray(w * h) { i ->
        val o = i * channels
        Raster.rgb(out[o].toInt() and 0xFF, out[o + 1].toInt() and 0xFF, out[o + 2].toInt() and 0xFF)
    }
    return Raster(w, h, px)
}

/** Stack counts read from real stash tiles, straightened, 200 px (HajinStackCountTests). */
class StackCountTests {
    @Test fun readsTheCountInTheTopRightCorner() {
        for ((name, count) in listOf("r0c0" to 1, "r0c1" to 4, "r1c2" to 8, "r2c0" to 10, "r3c2" to 9, "r4c3" to 10)) {
            assertEquals("stash_tile_$name", count, StackCount.read(testTile("stash_tile_$name")))
        }
    }
}

/** Blueprint tiles told from blue-tinted ones, on tiles from a backpack photo (HajinBlueprintTileTests). */
class BlueprintTileTests {
    @Test fun aBlueprintIsBlue() {
        assertTrue(StashGrid.blueFraction(testTile("backpack_tile_blueprint")) > 0.5)
    }

    /** A key's blue fob on a rare item's purple-blue tile was read as a blueprint */
    @Test fun aBlueTintIsNot() {
        for (name in listOf("key", "rare")) assertTrue(name, StashGrid.blueFraction(testTile("backpack_tile_$name")) < 0.25)
    }
}

/** Where a straightened tile sits back on the photo (HajinOnPhotoTests). */
class OnPhotoTests {
    @Test fun cornersMapToCorners() {
        val q = listOf(Pt(0.1, 0.2), Pt(0.9, 0.15), Pt(0.85, 0.8), Pt(0.12, 0.9))
        for ((u, v, p) in listOf(Triple(0.0, 0.0, q[0]), Triple(1.0, 0.0, q[1]), Triple(1.0, 1.0, q[2]), Triple(0.0, 1.0, q[3]))) {
            val m = StashGrid.onPhoto(q, u, v)
            assertEquals(p.x, m.x, 1e-9); assertEquals(p.y, m.y, 1e-9)
        }
    }

    @Test fun aRectangleIsEvenlySplit() {
        val q = listOf(Pt(0.2, 0.2), Pt(0.6, 0.2), Pt(0.6, 0.8), Pt(0.2, 0.8))
        val m = StashGrid.onPhoto(q, 0.25, 0.5)
        assertEquals(0.3, m.x, 1e-9); assertEquals(0.5, m.y, 1e-9)
    }
}

/** The review's highlight moved onto a tile's own outline (HajinSnapTests, HajinSnapEdgeTests). */
class SnapTests {
    @Test fun aBoxOffTheTileSnapsOntoItsOutline() {
        val w = 300; val h = 300
        val grey = IntArray(w * h) { 30 }
        for (i in 100..200) for (k in listOf(100, 200)) { grey[k * w + i] = 120; grey[i * w + k] = 120 }
        val r = StashGrid.snapped(Box(88.0, 92.0, 104.0, 104.0), grey, w, h)
        assertEquals(Box(100.0, 100.0, 100.0, 100.0), r)
    }

    @Test fun noOutlineLeavesTheBox() {
        val box = Box(88.0, 92.0, 104.0, 104.0)
        assertEquals(box, StashGrid.snapped(box, IntArray(300 * 300) { 30 }, 300, 300))
    }

    @Test fun theEdgeOfABrightPatchIsNotAnOutline() {
        val w = 300; val h = 300
        val grey = IntArray(w * h) { 30 }
        for (y in 0 until h) for (x in 190 until w) grey[y * w + x] = 220
        val box = Box(96.0, 96.0, 104.0, 104.0)
        assertEquals(box, StashGrid.snapped(box, grey, w, h))
    }
}
