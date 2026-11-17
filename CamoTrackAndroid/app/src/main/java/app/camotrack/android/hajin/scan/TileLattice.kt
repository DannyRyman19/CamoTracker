package app.camotrack.android.hajin.scan

import kotlin.math.abs
import kotlin.math.hypot
import kotlin.math.sqrt

/**
 * The stash's grid fitted to the tiles the tile detector found. Tiles are
 * squares on a lattice, so each one's column and row follow from its
 * neighbours; a perspective fit through every tile then gives the grid's
 * corners. (HajinTileLattice.)
 */
object TileLattice {
    /** A tile's half-width in lattice units: tiles are 133 px every 148. */
    const val HALF = 0.45

    data class Cell(val i: Int, val j: Int)
    class Fit(val h: DoubleArray, val cells: List<Cell>)

    /** Tile boxes (pixels) from the detector: confident ones, one per tile, tile-sized. */
    fun tiles(found: List<Detection>, minConfidence: Float = 0.5f): List<Box> {
        val sorted = found.filter { it.confidence > minConfidence }.sortedByDescending { it.confidence }.map { it.box }
        val kept = ArrayList<Box>()
        for (box in sorted) if (kept.none { overlap(it, box) > 0.35 }) kept.add(box)
        val size = median(kept.map { sqrt(it.width * it.height) })
        return kept.filter { val s = sqrt(it.width * it.height); s > size * 0.65 && s < size * 1.5 }
    }

    fun overlap(a: Box, b: Box): Double {
        val i = a.intersection(b) ?: return 0.0
        val inter = i.width * i.height
        return inter / (a.width * a.height + b.width * b.height - inter)
    }

    /** Lattice cell for each tile and the lattice-to-image homography, or
     *  null when there's too little to go on. */
    fun fit(boxes: List<Box>): Fit? {
        if (boxes.size < 4) return null
        val centers = boxes.map { Pt(it.midX, it.midY) }
        val size = median(boxes.map { sqrt(it.width * it.height) })
        val across = ArrayList<Pt>(); val down = ArrayList<Pt>()
        val neighbours = List(centers.size) { ArrayList<Int>() }
        for (a in centers.indices) for (b in centers.indices) {
            if (a == b) continue
            val d = centers[b] - centers[a]
            val len = d.length()
            if (len <= size * 0.6 || len >= size * 1.7) continue
            neighbours[a].add(b)
            if (abs(d.x) > abs(d.y)) across.add(if (d.x > 0) d else Pt(-d.x, -d.y))
            else down.add(if (d.y > 0) d else Pt(-d.x, -d.y))
        }
        if (across.isEmpty() || down.isEmpty()) return null
        val u = Pt(median(across.map { it.x }), median(across.map { it.y }))
        val v = Pt(median(down.map { it.x }), median(down.map { it.y }))
        val det = u.x * v.y - u.y * v.x
        if (abs(det) <= 1e-6) return null
        fun steps(d: Pt) = Pair((d.x * v.y - d.y * v.x) / det, (u.x * d.y - u.y * d.x) / det)
        // Walk the neighbours out from a tile near the middle
        val mid = Pt(centers.sumOf { it.x } / centers.size, centers.sumOf { it.y } / centers.size)
        val seed = centers.indices.maxWithOrNull(compareBy<Int> { neighbours[it].size }.thenBy { -(centers[it] - mid).length() })!!
        var cell = arrayOfNulls<Cell>(centers.size)
        cell[seed] = Cell(0, 0)
        val queue = ArrayDeque<Int>().apply { add(seed) }
        while (queue.isNotEmpty()) {
            val a = queue.removeFirst()
            for (b in neighbours[a]) {
                if (cell[b] != null) continue
                val (s, t) = steps(centers[b] - centers[a])
                if (abs(s - round(s)) >= 0.3 || abs(t - round(t)) >= 0.3) continue
                cell[b] = Cell(cell[a]!!.i + round(s).toInt(), cell[a]!!.j + round(t).toInt())
                queue.add(b)
            }
        }
        // Fit, then reassign every tile by the fit and fit again
        var h: DoubleArray? = null
        repeat(3) {
            val pairs = centers.indices.mapNotNull { k -> cell[k]?.let { doubleArrayOf(it.i.toDouble(), it.j.toDouble(), centers[k].x, centers[k].y) } }
            if (pairs.size < 4) return@repeat
            val fitted = homography(pairs) ?: return@repeat
            h = fitted
            val inv = invert(fitted) ?: return@repeat
            val taken = HashMap<Cell, Pair<Int, Double>>()
            val next = arrayOfNulls<Cell>(centers.size)
            for (k in centers.indices) {
                val (x, y) = apply(inv, centers[k].x, centers[k].y)
                val err = hypot(x - round(x), y - round(y))
                if (err >= 0.3) continue
                val key = Cell(round(x).toInt(), round(y).toInt())
                val other = taken[key]
                if (other != null && other.second <= err) continue
                if (other != null) next[other.first] = null
                taken[key] = k to err
                next[k] = key
            }
            cell = next
        }
        val fitted = h ?: return null
        val cells = cell.filterNotNull()
        if (cells.size < 4) return null
        return Fit(fitted, cells)
    }

    /** The grid's corners (fractions, TL TR BR BL) for `columns` columns
     *  starting at `first` and the rows the tiles cover. */
    fun corners(h: DoubleArray, first: Int, rows: IntRange, width: Int, height: Int, columns: Int = StashGrid.COLUMNS): List<Pt> {
        val l = first - HALF; val r = first + columns - 1 + HALF
        val t = rows.first - HALF; val b = rows.last + HALF
        return listOf(l to t, r to t, r to b, l to b).map { (x, y) ->
            val (px, py) = apply(h, x, y)
            Pt(px / width, py / height)
        }
    }

    /** The longest run of neighbouring indices that each hold two or more tiles. */
    fun block(indices: List<Int>): IntRange? {
        val count = indices.groupingBy { it }.eachCount()
        val good = count.filter { it.value >= 2 }.keys.sorted()
        if (good.isEmpty()) return null
        val runs = ArrayList<IntRange>()
        var start = good[0]; var last = start
        for (k in good.drop(1)) {
            if (k != last + 1) { runs.add(start..last); start = k }
            last = k
        }
        runs.add(start..last)
        // Swift's max(by:) keeps the first of equals; so does this
        var best = runs[0]
        for (run in runs.drop(1)) if (run.sumOf { count[it]!! } > best.sumOf { count[it]!! }) best = run
        return best
    }

    // Small linear algebra

    fun median(v: List<Double>): Double {
        val s = v.sorted(); return if (s.isEmpty()) 0.0 else s[s.size / 2]
    }

    fun apply(h: DoubleArray, x: Double, y: Double): Pair<Double, Double> {
        val w = h[6] * x + h[7] * y + h[8]
        return Pair((h[0] * x + h[1] * y + h[2]) / w, (h[3] * x + h[4] * y + h[5]) / w)
    }

    /** Least-squares homography from (x, y) to (u, v), h[8] = 1. */
    fun homography(pairs: List<DoubleArray>): DoubleArray? {
        val ata = Array(8) { DoubleArray(8) }; val atb = DoubleArray(8)
        for (p in pairs) {
            val (x, y, u, v) = p.toList()
            for ((row, rhs) in listOf(doubleArrayOf(x, y, 1.0, 0.0, 0.0, 0.0, -u * x, -u * y) to u,
                                      doubleArrayOf(0.0, 0.0, 0.0, x, y, 1.0, -v * x, -v * y) to v)) {
                for (i in 0 until 8) {
                    atb[i] += row[i] * rhs
                    for (j in 0 until 8) ata[i][j] += row[i] * row[j]
                }
            }
        }
        val s = solve(ata, atb) ?: return null
        return s + 1.0
    }

    fun invert(a: DoubleArray): DoubleArray? {
        val det = a[0] * (a[4] * a[8] - a[5] * a[7]) - a[1] * (a[3] * a[8] - a[5] * a[6]) + a[2] * (a[3] * a[7] - a[4] * a[6])
        if (abs(det) <= 1e-12) return null
        return doubleArrayOf(
            (a[4] * a[8] - a[5] * a[7]) / det, (a[2] * a[7] - a[1] * a[8]) / det, (a[1] * a[5] - a[2] * a[4]) / det,
            (a[5] * a[6] - a[3] * a[8]) / det, (a[0] * a[8] - a[2] * a[6]) / det, (a[2] * a[3] - a[0] * a[5]) / det,
            (a[3] * a[7] - a[4] * a[6]) / det, (a[1] * a[6] - a[0] * a[7]) / det, (a[0] * a[4] - a[1] * a[3]) / det)
    }

    private fun solve(a: Array<DoubleArray>, b: DoubleArray): DoubleArray? {
        val n = b.size
        val m = Array(n) { a[it] + b[it] }
        for (i in 0 until n) {
            val p = (i until n).maxByOrNull { abs(m[it][i]) }!!
            if (abs(m[p][i]) <= 1e-12) return null
            val t = m[i]; m[i] = m[p]; m[p] = t
            for (r in 0 until n) {
                if (r == i) continue
                val f = m[r][i] / m[i][i]
                for (c in i..n) m[r][c] -= f * m[i][c]
            }
        }
        return DoubleArray(n) { m[it][n] / m[it][it] }
    }

    /** Swift's `rounded()`: half away from zero. */
    internal fun round(v: Double): Double = if (v >= 0) (v + 0.5).toLong().toDouble() else -((-v + 0.5).toLong().toDouble())
}

