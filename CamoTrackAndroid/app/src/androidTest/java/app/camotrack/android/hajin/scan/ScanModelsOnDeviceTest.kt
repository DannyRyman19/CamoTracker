package app.camotrack.android.hajin.scan

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Typeface
import android.util.Log
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.double
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/**
 * The bundled models and ML Kit on a device: the classifier on the iPhone
 * repo's real tiles (Tools/stash-scan/real, copied into this test's assets),
 * agreeing with the training script's own TFLite run (so the Kotlin
 * preprocessing matches); the detector finding held-out generated stash
 * screens; ML Kit reading a printer screen. Results go to logcat, tag StashScan.
 */
@RunWith(AndroidJUnit4::class)
class ScanModelsOnDeviceTest {
    private val app = InstrumentationRegistry.getInstrumentation().targetContext
    private val test = InstrumentationRegistry.getInstrumentation().context

    private fun bitmap(path: String): Bitmap = test.assets.open(path).use { BitmapFactory.decodeStream(it) }

    @Test fun theClassifierNamesTheRealTiles() {
        val classifier = TfliteTileClassifier.fromAssets(app)
        val alias = test.assets.open("scan/stash_icons_aliases.txt").bufferedReader().readLines()
            .filter { it.contains('\t') }.associate { it.substringBefore('\t') to it.substringAfter('\t') }
        val python = test.assets.open("scan/python_icons.tsv").bufferedReader().readLines().filter { it.isNotBlank() }
            .associate { it.split('\t').let { p -> p[0] to p[1] } }
        var right = 0; var total = 0; var agree = 0
        val started = System.nanoTime()
        for (cls in test.assets.list("scan/real")!!.sorted()) {
            for (file in test.assets.list("scan/real/$cls")!!.sorted()) {
                val top = classifier.classify(bitmap("scan/real/$cls/$file").toRaster()).first()
                total++
                if (top.id == (alias[cls] ?: cls)) right++ else Log.i("StashScan", "MISS $cls/$file -> ${top.id} ${top.confidence}")
                if (python["$cls/$file"] == top.id) agree++
            }
        }
        val ms = (System.nanoTime() - started) / 1e6 / total
        Log.i("StashScan", "classifier: $right/$total real tiles right, $agree agree with Python, %.1f ms a tile".format(ms))
        classifier.close()
        // Core ML's HajinStashIcons gets 215 of these 220
        assertTrue("$right/$total", right >= 215)
        assertTrue("agree $agree/$total", agree >= total - 2)
    }

    @Test fun theDetectorFindsHeldOutStashScreens() {
        val detector = TfliteTileDetector.fromAssets(app)
        val ann = Json.parseToJsonElement(test.assets.open("scan/grids/annotations.json").bufferedReader().readText()).jsonArray
        val errors = ArrayList<Double>(); var lost = 0; var screens = 0
        var ms = 0.0
        for (e in ann) {
            val name = e.jsonObject["image"]!!.jsonPrimitive.content
            val truth = e.jsonObject["annotations"]!!.jsonArray.map {
                val c = it.jsonObject["coordinates"]!!.jsonObject
                val x = c["x"]!!.jsonPrimitive.double; val y = c["y"]!!.jsonPrimitive.double
                val w = c["width"]!!.jsonPrimitive.double; val h = c["height"]!!.jsonPrimitive.double
                Box(x - w / 2, y - h / 2, w, h)
            }
            val image = bitmap("scan/grids/$name").toRaster()
            val want = GridFinder.fromDetector(image, truth) ?: continue
            screens++
            val t0 = System.nanoTime()
            val found = detector.detect(image)
            ms += (System.nanoTime() - t0) / 1e6
            val got = GridFinder.fromDetector(image, TileLattice.tiles(found))
            if (got == null) { lost++; continue }
            val long = maxOf(image.width, image.height).toDouble()
            errors.add((0 until 4).sumOf { k -> Pt((got[k].x - want[k].x) * image.width, (got[k].y - want[k].y) * image.height).length() } / 4 / long)
        }
        detector.close()
        val mean = errors.average()
        Log.i("StashScan", "detector: $screens screens, no grid on $lost, corner error mean %.2f%%, %.0f ms a photo".format(mean * 100, ms / screens))
        assertTrue(lost <= screens / 10)
        assertTrue("mean corner error $mean", mean < 0.03)
    }

    @Test fun mlKitReadsAPrinterScreen() {
        // A printer screen drawn on a canvas: names over have/need, far apart on one line
        val bmp = Bitmap.createBitmap(1600, 900, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bmp).apply { drawColor(Color.rgb(20, 22, 25)) }
        val paint = Paint().apply { color = Color.WHITE; textSize = 44f; isAntiAlias = true; typeface = Typeface.DEFAULT_BOLD }
        canvas.drawText("Synthetics", 200f, 300f, paint); canvas.drawText("607/50", 200f, 360f, paint)
        canvas.drawText("Reactive Metals", 900f, 300f, paint); canvas.drawText("6/5", 900f, 360f, paint)
        canvas.drawText("ALL", 200f, 600f, paint); canvas.drawText("79/94 ITEMS", 1100f, 600f, paint)
        val reader = MlKitTextReader()
        val lines = reader.lines(bmp)
        reader.close()
        Log.i("StashScan", "ml kit: " + lines.joinToString(" | ") { it.text })
        val items = listOf(ScanItem("synthetics", "Synthetics", "Resource"), ScanItem("reactive-metals", "Reactive Metals", "Ingredient"))
        assertEquals(mapOf("synthetics" to 607, "reactive-metals" to 6), RecipeReader.counts(lines, items))
        // the far-apart header words come out as separate lines, as Vision gives them
        assertNotNull(lines.firstOrNull { it.text.trim() == "ALL" })
    }

    @Test fun aWholeStashReadOnTheDevice() {
        // A generated screen, read end to end through StashScanner, timed
        val scanner = StashScanner(app)
        val photo = bitmap("scan/grids/" + test.assets.list("scan/grids")!!.first { it.endsWith(".jpg") })
        val t0 = System.nanoTime()
        val corners = scanner.guessCorners(photo)
        val t1 = System.nanoTime()
        assertNotNull(corners)
        val read = scanner.readStash(photo, corners!!, emptyList())
        val t2 = System.nanoTime()
        scanner.close()
        Log.i("StashScan", "whole read: corners %.0f ms, %d tiles read in %.0f ms".format((t1 - t0) / 1e6, read.tiles.size, (t2 - t1) / 1e6))
        assertTrue(read.tiles.isNotEmpty())
    }
}
