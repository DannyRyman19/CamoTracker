package app.camotrack.android.hajin.scan

import android.content.Context
import android.graphics.Bitmap
import java.io.Closeable

/**
 * The DMZ stash photo reader for the Hajin screens: the bundled models and
 * ML Kit behind `ScanEngine`. Make one (it loads ~4 MB of models on first
 * use), call it OFF the main thread (every call blocks for up to a few
 * seconds), and close it when the scan flow ends. Photos must be upright
 * (`AndroidImages.decodeUpright`); corners are fractions TL, TR, BR, BL.
 *
 * The flow, as on iPhone:
 *  1. `route(photo, stashItems)`: a backpack, a stash, or a printer screen
 *     (already read: straight to the review)
 *  2. `quality(photo)` and `guessCorners(photo, backpack)` for the framing
 *     screen; `rows(...)` to draw the frame's row lines as it's dragged
 *  3. `readStash(...)` or `readPostMatch(...)` with the player's corners
 */
class StashScanner(context: Context) : Closeable {
    private val app = context.applicationContext
    private val classifierLoad = lazy { TfliteTileClassifier.fromAssets(app) }
    private val detectorLoad = lazy { TfliteTileDetector.fromAssets(app) }
    private val textLoad = lazy { MlKitTextReader() }
    private val classifier by classifierLoad
    private val detector by detectorLoad
    private val text by textLoad
    private val engine by lazy { ScanEngine(classifier, detector, text) }

    // The last photo's raster, so the steps on one photo convert it once
    private var last: Pair<Bitmap, Raster>? = null

    @Synchronized private fun raster(bitmap: Bitmap): Raster {
        last?.let { if (it.first === bitmap) return it.second }
        return bitmap.toRaster().also { last = bitmap to it }
    }

    fun route(photo: Bitmap, stashItems: List<ScanItem>): PhotoKind = engine.route(raster(photo), stashItems)
    fun quality(photo: Bitmap): List<PhotoQuality> = engine.quality(raster(photo))
    fun guessCorners(photo: Bitmap, backpack: Boolean = false): List<Pt>? = engine.guessCorners(raster(photo), backpack)
    fun rows(photo: Bitmap, corners: List<Pt>, backpack: Boolean = false): Int = engine.rows(raster(photo), corners, backpack)

    /** Every tile of a framed grid (6 wide for the stash, 4 for a backpack). */
    fun readGrid(photo: Bitmap, corners: List<Pt>, columns: Int = StashGrid.COLUMNS, rows: Int? = null): List<Tile> =
        engine.readGrid(raster(photo), corners, columns, rows)

    /** A stash photo: counts for the review, plus the report for "Send this photo". */
    fun readStash(photo: Bitmap, corners: List<Pt>, items: List<ScanItem>, guessedCorners: List<Pt>? = null,
                  moved: Boolean = false, quality: List<PhotoQuality> = emptyList()): StashRead =
        engine.readStash(raster(photo), corners, items, guessedCorners, moved, quality)

    /** A backpack after a match; `guide` is every guide item. */
    fun readPostMatch(photo: Bitmap, corners: List<Pt>, guide: List<ScanItem>): PostMatchResult =
        engine.readPostMatch(raster(photo), corners, guide)

    /** 3D Printer recipe screens, one or more photos. */
    fun readText(photos: List<Bitmap>, items: List<ScanItem>): TextRead = engine.readText(photos.map { it.toRaster() }, items)

    override fun close() {
        if (classifierLoad.isInitialized()) runCatching { classifier.close() }
        if (detectorLoad.isInitialized()) runCatching { detector.close() }
        if (textLoad.isInitialized()) runCatching { text.close() }
    }
}
