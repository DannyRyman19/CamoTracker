package app.camotrack.android.hajin.scan

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.double
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * stash_tiles.tflite's real output on three held-out generated screens
 * (saved by the training tools: 40 x 40 x 5 floats), decoded and fitted
 * here: the grid it gives must sit on the true tiles' grid.
 */
class DetectorOutputTests {
    @Test fun theModelsMapGivesTheTrueGrid() {
        val dir = "/hajin/scan/detector"
        val ann = Json.parseToJsonElement(javaClass.getResourceAsStream("$dir/annotations.json")!!.bufferedReader().readText()).jsonArray
        for (e in ann) {
            val o = e.jsonObject
            val name = o["image"]!!.jsonPrimitive.content
            val w = o["width"]!!.jsonPrimitive.int; val h = o["height"]!!.jsonPrimitive.int
            val truth = o["annotations"]!!.jsonArray.map {
                val c = it.jsonObject["coordinates"]!!.jsonObject
                val bw = c["width"]!!.jsonPrimitive.double; val bh = c["height"]!!.jsonPrimitive.double
                Box(c["x"]!!.jsonPrimitive.double - bw / 2, c["y"]!!.jsonPrimitive.double - bh / 2, bw, bh)
            }
            val bytes = javaClass.getResourceAsStream("$dir/${name.replace(".jpg", ".bin")}")!!.readBytes()
            val floats = FloatArray(bytes.size / 4).also { ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN).asFloatBuffer().get(it) }
            val found = TileHeatmap.decode(floats, 40, 320, w, h)
            // the same boxes as the training tools' own decoding (predict_tiles.py)
            val python = o["python"]!!.jsonArray.map { b -> b.jsonArray.map { it.jsonPrimitive.double } }.sortedByDescending { it[4] }
            assertEquals(name, python.size, found.size)
            for ((p, f) in python.zip(found)) {
                assertEquals(p[0], f.box.x, 0.01); assertEquals(p[1], f.box.y, 0.01)
                assertEquals(p[2], f.box.width, 0.01); assertEquals(p[4], f.confidence.toDouble(), 1e-5)
            }
            val tiles = TileLattice.tiles(found)
            // almost nothing that isn't a tile
            val hits = tiles.count { b -> truth.any { TileLattice.overlap(it, b) > 0.5 } }
            assertTrue("$name: $hits of ${tiles.size} boxes on tiles", hits >= tiles.size - 1)
            // with most tiles found, the grid's corners where the true tiles put
            // them (the frame score only breaks ties, so a blank picture will do)
            if (hits < truth.size * 0.9) continue
            val blank = Raster.filled(w, h, Raster.rgb(20, 20, 20))
            val want = GridFinder.fromDetector(blank, truth) ?: continue
            val got = GridFinder.fromDetector(blank, tiles)!!
            val err = (0 until 4).sumOf { Pt((got[it].x - want[it].x) * w, (got[it].y - want[it].y) * h).length() } / 4 / maxOf(w, h)
            assertTrue("$name: corners off by ${err * 100}%", err < 0.02)
        }
    }
}
