package app.camotrack.android.hajin.scan

import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/**
 * The tiles' frame lines, counted along each column and row of a
 * straightened grid. A frame pixel is unsaturated and either bright (a
 * photo of a TV) or a thin ridge clearly brighter than the pixels a little
 * either side of it (a console screenshot, where the lines are a dim grey
 * on near black). (HajinFrameLines.)
 */
object FrameLines {
    class Profiles(val cols: DoubleArray, val rows: DoubleArray)

    fun profiles(img: Raster): Profiles {
        val w = img.width; val h = img.height
        val r = if (w > 600) 4 else 2
        val cols = DoubleArray(w); val rows = DoubleArray(h)
        val lum = IntArray(w * h) { (img.r(it) + img.g(it) + img.b(it)) / 3 }
        for (y in 0 until h) {
            for (x in 0 until w) {
                val i = y * w + x
                val rr = img.r(i); val gg = img.g(i); val bb = img.b(i)
                val lo = min(rr, min(gg, bb)); val hi = max(rr, max(gg, bb))
                if (hi - lo >= 45) continue
                if (lo > 110) { cols[x] += 1.0; rows[y] += 1.0; continue }
                val l = lum[i]
                if (l < 40) continue
                // a horizontal line: brighter than above and below it
                if (y >= r && y < h - r && l - max(lum[i - r * w], lum[i + r * w]) > 15) rows[y] += 1.0
                // a vertical line: brighter than left and right of it
                if (x >= r && x < w - r && l - max(lum[i - r], lum[i + r]) > 15) cols[x] += 1.0
            }
        }
        return Profiles(cols, rows)
    }
}

/**
 * Finds where the tile borders really are in a straightened stash grid (with
 * half a tile of margin), so a roughly framed photo still cuts cleanly.
 * (HajinGridLattice.)
 */
object GridLattice {
    class Lattice(val xs: List<Double>, val ys: List<Double>)

    fun fit(image: Raster, columns: Int, rows: Int, cell: Double): Lattice {
        val fallbackXs = (0..columns).map { cell / 2 + it * cell }
        val fallbackYs = (0..rows).map { cell / 2 + it * cell }
        val p = FrameLines.profiles(image)
        // White icons add broad humps; keep only the narrow frame lines by
        // taking away the local average first. Each gap has a frame line
        // either side; smoothing turns the pair into one peak on the gap.
        val colProfile = smoothed(smoothed(narrow(p.cols, 40), 6), 6)
        val rowProfile = smoothed(smoothed(narrow(p.rows, 40), 6), 6)
        val xs = lines(colProfile, columns, cell) ?: fallbackXs
        // Rows: the count from the frame's shape could be one off either way;
        // take whichever fits the borders best for its size
        var best: Pair<Double, List<Double>>? = null
        for (n in listOf(rows, rows - 1, rows + 1)) {
            if (n < 1) continue
            val ys = lines(rowProfile, n, cell) ?: continue
            val sc = score(rowProfile, ys) ?: continue
            val perLine = sc / ys.size
            if (best == null || perLine > best.first) best = perLine to ys
        }
        return Lattice(xs, best?.second ?: fallbackYs)
    }

    /** The strongest set of count+1 evenly spaced border lines. */
    private fun lines(profile: DoubleArray, count: Int, cell: Double): List<Double>? {
        val n = profile.size
        var best: Triple<Double, Double, Double>? = null   // score, offset, pitch
        var pitch = cell * 0.92
        while (pitch <= cell * 1.08 + 1e-9) {
            val span = pitch * count
            if (span < n) {
                // The frame puts the first border half a tile in; trust it to
                // within 0.4 of a tile so the fit can't jump a whole row
                var offset = cell * 0.1
                val end = min(cell * 0.9, n - span - 1)
                while (offset <= end + 1e-9) {
                    val ys = (0..count).map { offset + it * pitch }
                    val s = score(profile, ys)
                    if (s != null && (best == null || s > best.first)) best = Triple(s, offset, pitch)
                    offset += 1.0
                }
            }
            pitch += 1.0
        }
        val b = best ?: return null
        return (0..count).map { b.second + it * b.third }
    }

    private fun score(profile: DoubleArray, at: List<Double>): Double? {
        var total = 0.0
        for (a in at) {
            val c = a.roundToInt()
            if (c < 0 || c >= profile.size) return null
            total += profile[c]
        }
        return total
    }
}
