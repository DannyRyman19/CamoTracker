package app.camotrack.android.hajin.scan

import kotlin.math.abs
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min

/**
 * A first guess at the stash grid's corners (fractions, TL TR BR BL), for
 * the player to adjust: the tile detector's tiles fitted to a lattice, else
 * the best of three older ways from the photo's text and frame lines.
 * Null when there's too little to go on. (HajinStashGridFinder.)
 */
object GridFinder {

    /**
     * @param detections the tile detector's raw boxes on this photo
     * @param lines the photo's text (needed only when the detector finds under 8 tiles)
     */
    fun guess(image: Raster, detections: List<Detection>, lines: () -> List<TextLine>): List<Pt>? {
        fromDetector(image, TileLattice.tiles(detections))?.let { return it }
        val text = lines()
        // Squares the detector was less sure of stand in for iPhone's
        // rectangle finder (mostly empty tiles, at the bottom of a stash)
        val rects = TileLattice.tiles(detections, minConfidence = 0.2f).map {
            listOf(Pt(it.minX, it.minY), Pt(it.maxX, it.minY), Pt(it.maxX, it.maxY), Pt(it.minX, it.maxY))
        }
        val candidates = listOfNotNull(fromStraightLattice(image, text), fromHeader(image, text), fromTiles(image, rects, text))
        return candidates.maxByOrNull { frameScore(image, it) }
    }

    /** The 6-wide grid fitted to the detector's tiles (needs 8 or more). When it
     *  sees fewer than six columns, the frame lines decide which side the missing ones are on. */
    fun fromDetector(image: Raster, boxes: List<Box>): List<Pt>? {
        val fit = TileLattice.fit(boxes) ?: return null
        if (fit.cells.size < 8) return null
        // Stray boxes off the grid make lone rows and columns: keep the solid
        // block of ones with two or more tiles
        val rows = TileLattice.block(fit.cells.map { it.j }) ?: return null
        val cells = fit.cells.filter { it.j in rows }
        val cols = TileLattice.block(cells.map { it.i }) ?: return null
        val lo = cols.first; val hi = cols.last
        val columns = StashGrid.COLUMNS
        val firsts = if (hi - lo + 1 >= columns) (lo..(hi - columns + 1)).toList() else ((hi - columns + 1)..lo).toList()
        var best: Triple<List<Pt>, Int, Double>? = null
        for (first in firsts) {
            val q = TileLattice.corners(fit.h, first, rows, image.width, image.height)
            // The most tiles inside, then the strongest frame lines
            val inside = cells.count { it.i >= first && it.i < first + columns }
            val score = if (firsts.size > 1) frameScore(image, q) else 0.0
            if (best == null || inside > best.second || (inside == best.second && score > best.third)) best = Triple(q, inside, score)
        }
        return best?.first
    }

    private fun words(lines: List<TextLine>) = lines.map { it.text.uppercase().trim() to it }

    /** For a straight-on screenshot: the column lines and evenly spaced row
     *  lines found directly in the strip under the header, between "ALL" and
     *  "ITEMS"; rows are counted until the lines stop. */
    fun fromStraightLattice(image: Raster, lines: List<TextLine>): List<Pt>? {
        val W = image.width.toDouble(); val H = image.height.toDouble()
        fun px(v: Pt) = Pt(v.x * W, (1 - v.y) * H)
        val words = words(lines)
        val itemsWord = words.firstOrNull { it.first.contains("ITEMS") }?.second ?: return null
        val allWord = words.filter { it.first == "ALL" }
            .minByOrNull { abs(px(it.second.bottomLeft).y - px(itemsWord.bottomLeft).y) }?.second ?: return null
        val a = px(allWord.bottomLeft); val b = px(itemsWord.bottomRight)
        // Straight only: the header must be level
        if (abs(a.y - b.y) >= (b.x - a.x) * 0.02 || b.x - a.x <= W * 0.1) return null
        // Work on a copy about 1200 px wide
        val scale = min(1.0, 1200 / W)
        val pitch0 = (b.x - a.x) / StashGrid.COLUMNS * scale
        val x0 = max(0, (a.x * scale - pitch0).toInt()); val x1 = min((W * scale).toInt() - 1, (b.x * scale + pitch0).toInt())
        val y0 = max(0, (a.y * scale).toInt()); val y1 = (H * scale).toInt() - 1
        val w = x1 - x0; val h = y1 - y0
        if (w <= 20 || h <= 20) return null
        val small = image.resized((W * scale).toInt(), (H * scale).toInt())
        val crop = small.cropped(Box(x0.toDouble(), y0.toDouble(), w.toDouble(), h.toDouble())) ?: return null
        val p = FrameLines.profiles(crop)
        val cols = smoothed(narrow(p.cols, 20), 2)
        val rows = smoothed(narrow(p.rows, 20), 2)
        val cw = crop.width; val ch = crop.height
        // the 7 column lines
        var bestScore = -1.0; var bestX = 0.0; var bestP = 0.0
        for (pp in strideThrough(pitch0 * 0.9, pitch0 * 1.1, 0.5)) {
            for (x in strideThrough(pitch0 * 0.6, pitch0 * 1.4, 1.0)) {
                if ((x + 6 * pp).toInt() >= cw) continue
                var sc = 0.0
                for (k in 0..StashGrid.COLUMNS) sc += cols[(x + k * pp).toInt()]
                if (sc > bestScore) { bestScore = sc; bestX = x; bestP = pp }
            }
        }
        if (bestP <= 0) return null
        val pitch = bestP
        // the top row line just under the header, then rows while lines continue
        var topScore = -1.0; var topY = 0.0
        for (y in strideThrough(pitch * 0.2, pitch * 1.2, 1.0)) {
            if (y.toInt() >= ch) continue
            if (rows[y.toInt()] > topScore) { topScore = rows[y.toInt()]; topY = y }
        }
        val strengths = arrayListOf(topScore)
        var count = 0
        for (j in 1..14) {
            val y = topY + j * pitch
            if (y.toInt() + 3 >= ch) break
            val lo = max(0, y.toInt() - 3); val hi = min(ch - 1, y.toInt() + 3)
            val st = (lo..hi).maxOf { rows[it] }
            val ref = strengths.sorted()[strengths.size / 2]
            if (j > 1 && st < ref * 0.35) break
            strengths.add(st); count = j
        }
        if (count < 1) return null
        val left = (x0 + bestX) / scale; val right = (x0 + bestX + 6 * pitch) / scale
        val top = (y0 + topY) / scale; val bottom = (y0 + topY + count * pitch) / scale
        return listOf(Pt(left, top), Pt(right, top), Pt(right, bottom), Pt(left, bottom))
            .map { Pt((it.x / W).coerceIn(0.0, 1.0), (it.y / H).coerceIn(0.0, 1.0)) }
    }

    /** The frame from tile-like squares (pixel quads TL TR BR BL), with the
     *  header words for the top when they're there. */
    fun fromTiles(image: Raster, rects: List<List<Pt>>, lines: List<TextLine>): List<Pt>? {
        val W = image.width.toDouble(); val H = image.height.toDouble()
        fun px(v: Pt) = Pt(v.x * W, (1 - v.y) * H)
        fun mid(a: Pt, b: Pt) = Pt((a.x + b.x) / 2, (a.y + b.y) / 2)
        class Q(val tl: Pt, val tr: Pt, val br: Pt, val bl: Pt) {
            val c get() = Pt((tl.x + br.x) / 2, (tl.y + br.y) / 2)
            val size get() = ((tr - tl).length() + (bl - tl).length()) / 2
        }
        val all = rects.map { Q(it[0], it[1], it[2], it[3]) }
        if (all.isEmpty()) return null
        val median = all.map { it.size }.sorted()[all.size / 2]
        val sized = all.filter { it.size > median * 0.7 && it.size < median * 1.4 }
        val tiles = sized.filter { q -> sized.any { o -> val d = (o.c - q.c).length(); d > median * 0.8 && d < median * 1.8 } }
        if (tiles.size < 3) return null
        // Spacing along a row and down a column, from neighbouring tiles
        val across = ArrayList<Pt>(); val down = ArrayList<Pt>()
        for (q in tiles) for (o in tiles) {
            val d = o.c - q.c
            val len = d.length()
            if (len <= median * 0.8 || len >= median * 1.8) continue
            if (d.x > 0 && abs(d.y) < len * 0.4) across.add(d)
            if (d.y > 0 && abs(d.x) < len * 0.4) down.add(d)
        }
        fun medianVector(v: List<Pt>): Pt? = if (v.isEmpty()) null else Pt(v.map { it.x }.sorted()[v.size / 2], v.map { it.y }.sorted()[v.size / 2])
        val hx = medianVector(across) ?: Pt(median * 1.25, 0.0)
        val vy = medianVector(down) ?: Pt(-hx.y, hx.x)
        val pitch = hx.length()
        // The bottom: the lowest row of tiles (measured down the columns)
        val vyLen = vy.length()
        fun depth(p: Pt) = (p.x * vy.x + p.y * vy.y) / vyLen
        val lowest = tiles.maxOf { depth(it.c) }
        val bottomRow = tiles.filter { depth(it.c) > lowest - vyLen * 0.5 }
        val bottomPoint = bottomRow.map { mid(it.bl, it.br) }.fold(Pt(0.0, 0.0)) { s, p -> Pt(s.x + p.x / bottomRow.size, s.y + p.y / bottomRow.size) }
        // The header words: "ALL" starts over the grid's left edge, "ITEMS"
        // ends over its right edge, and the grid starts just under them
        val words = lines.map { it.text.uppercase() to it }.filter { px(it.second.bottomLeft).y < bottomPoint.y - pitch }
        val itemsWord = words.firstOrNull { it.first.contains("ITEMS") }?.second
        // The header's "ALL", not the side menu's: the one level with "ITEMS"
        val allWord = words.filter { it.first.trim() == "ALL" }.minByOrNull {
            val y = itemsWord?.let { w -> px(w.bottomLeft).y } ?: 0.0
            abs(px(it.second.bottomLeft).y - y)
        }?.second
        val itemsY = itemsWord?.let { px(it.bottomLeft).y }
        val headerPts = words.filter { (t, l) ->
            (t.contains("WEAPON") || t.contains("ITEMS")) && (itemsY?.let { abs(px(l.bottomLeft).y - it) < H * 0.03 } ?: true)
        }.flatMap { listOf(px(it.second.bottomLeft), px(it.second.bottomRight)) }
        val topLeft: Pt; val topRight: Pt
        if (allWord != null && itemsWord != null && headerPts.size >= 2) {
            val mx = headerPts.sumOf { it.x } / headerPts.size; val my = headerPts.sumOf { it.y } / headerPts.size
            val num = headerPts.sumOf { (it.x - mx) * (it.y - my) }; val den = headerPts.sumOf { (it.x - mx) * (it.x - mx) }
            val slope = if (den > 1) num / den else 0.0
            fun baseline(x: Double) = my + slope * (x - mx)
            val lx = px(allWord.bottomLeft).x; val rx = px(itemsWord.bottomRight).x
            val gap = (rx - lx) / StashGrid.COLUMNS * 0.58
            topLeft = Pt(lx, baseline(lx) + gap)
            topRight = Pt(rx, baseline(rx) + gap)
        } else {
            // No header: the leftmost and rightmost tiles' columns, a few rows up
            val leftmost = tiles.minBy { it.c.x }; val rightmost = tiles.maxBy { it.c.x }
            val rows = 5.0
            topLeft = Pt(leftmost.bl.x - vy.x * rows, bottomPoint.y - vy.y * rows)
            topRight = Pt(rightmost.br.x - vy.x * rows, bottomPoint.y - vy.y * rows)
        }
        // Bottom corners: down each side (along the columns) to the bottom row
        fun meet(p: Pt, d: Pt, q: Pt, e: Pt): Pt {
            val den = d.x * e.y - d.y * e.x
            if (abs(den) <= 1e-6) return p
            val t = ((q.x - p.x) * e.y - (q.y - p.y) * e.x) / den
            return Pt(p.x + d.x * t, p.y + d.y * t)
        }
        val bottomLeft = meet(topLeft, vy, bottomPoint, hx); val bottomRight = meet(topRight, vy, bottomPoint, hx)
        val quad = listOf(topLeft, topRight, bottomRight, bottomLeft)
        if (!quad.all { it.x > -W * 0.05 && it.x < W * 1.05 && it.y > -H * 0.05 && it.y < H * 1.05 } ||
            bottomLeft.y - topLeft.y <= pitch || topRight.x - topLeft.x <= pitch * 3) return null
        val fractions = quad.map { Pt((it.x / W).coerceIn(0.0, 1.0), (it.y / H).coerceIn(0.0, 1.0)) }
        return refine(image, fractions)
    }

    /** The frame from the header alone: top corners under "ALL" and "ITEMS",
     *  sides square to the header line, and the bottom where the frame lines
     *  stop when walking down the grid a row at a time. */
    fun fromHeader(image: Raster, lines: List<TextLine>): List<Pt>? {
        val W = image.width.toDouble(); val H = image.height.toDouble()
        fun px(v: Pt) = Pt(v.x * W, (1 - v.y) * H)
        val words = words(lines)
        val itemsWord = words.firstOrNull { it.first.contains("ITEMS") }?.second ?: return null
        val allWord = words.filter { it.first == "ALL" }
            .minByOrNull { abs(px(it.second.bottomLeft).y - px(itemsWord.bottomLeft).y) }?.second ?: return null
        if (abs(px(allWord.bottomLeft).y - px(itemsWord.bottomLeft).y) >= H * 0.06) return null
        val a = px(allWord.bottomLeft); val b = px(itemsWord.bottomRight)
        val across = b - a
        val width = across.length()
        if (width <= W * 0.2) return null
        val down = Pt(-across.y / width, across.x / width)
        val pitch = width / StashGrid.COLUMNS
        val tl = a + down * (pitch * 0.58); val tr = b + down * (pitch * 0.58)
        // Straighten from the top line down to the bottom of the photo
        val reach = min((H - tl.y) / max(down.y, 0.1), (H - tr.y) / max(down.y, 0.1)) * 0.98
        if (reach <= pitch * 1.5) return null
        val quad = listOf(tl, tr, tr + down * reach, tl + down * reach)
        val scale = 240 / width
        val outH = (reach * scale).toInt()
        val flat = image.straightened(quad.map { Pt(it.x / W, it.y / H) }, 240, outH) ?: return null
        val h = flat.height
        val row = FrameLines.profiles(flat).rows
        val lines2 = smoothed(narrow(row, 20), 2)
        // Row spacing: the repeat of the lines, around a tile's width (40 px here)
        val mean = lines2.sum() / h
        var bestScore = Double.NEGATIVE_INFINITY; var bestLag = 40
        for (lag in 26..70) {
            if (lag >= h / 2) continue
            var sc = 0.0
            for (y in 0 until h - lag) sc += (lines2[y] - mean) * (lines2[y + lag] - mean)
            sc /= (h - lag)
            if (sc > bestScore) { bestScore = sc; bestLag = lag }
        }
        // Walk down while there's a border line about a row further on
        fun peak(y: Double): Double {
            val lo = max(0, (y - bestLag * 0.2).toInt()); val hi = min(h - 1, (y + bestLag * 0.2).toInt())
            return if (lo < hi) (lo..hi).maxOf { lines2[it] } else 0.0
        }
        val strengths = ArrayList<Double>()
        var rows = 0
        for (k in 1..20) {
            val y = (k * bestLag).toDouble()
            if (y >= h - 2) break
            val p = peak(y)
            strengths.add(p)
            val first3 = strengths.take(3).sorted()
            val ref = first3[first3.size / 2]
            if (k > 1 && p < ref * 0.35) break
            rows = k
        }
        if (rows < 1) return null
        val depth = rows * bestLag / scale
        val bl = tl + down * depth; val br = tr + down * depth
        val start = listOf(tl, tr, br, bl).map { Pt((it.x / W).coerceIn(0.0, 1.0), (it.y / H).coerceIn(0.0, 1.0)) }
        // The walk already counted the rows; re-measuring can lock onto a
        // two- or three-row repeat
        return refine(image, start, rows)
    }

    /** Nudges each corner (coordinate descent on a quarter-size copy) to where
     *  the straightened grid's frame lines fall exactly on its borders. */
    fun refine(image: Raster, start: List<Pt>, rows: Int? = null): List<Pt> {
        val score = scorer(image, rows ?: StashGrid.measureRows(image, start))
        var q = start
        var best = score(q)
        for (step in listOf(0.012, 0.006, 0.003)) {
            var improved = true; var rounds = 0
            while (improved && rounds < 6) {
                improved = false; rounds++
                for (i in 0 until 4) {
                    for (d in listOf(Pt(step, 0.0), Pt(-step, 0.0), Pt(0.0, step), Pt(0.0, -step))) {
                        val t = q.toMutableList()
                        t[i] = q[i] + d
                        val sc = score(t)
                        if (sc > best) { best = sc; q = t; improved = true }
                    }
                }
            }
        }
        return q
    }

    /** How well a frame lines up with the tiles' frame lines (higher is better). */
    fun frameScore(image: Raster, q: List<Pt>): Double = scorer(image, StashGrid.measureRows(image, q))(q)

    /** Scores frames on a quarter-size copy: straightened with the given rows,
     *  the mean frame-line strength at the column and row borders. */
    fun scorer(image: Raster, rows: Int): (List<Pt>) -> Double {
        val small = image.shrunkBy(4)
        val cell = 40
        return { q ->
            val ow = cell * StashGrid.COLUMNS; val oh = cell * rows
            val g = small.straightened(q, ow, oh)
            if (g == null) 0.0 else {
                val p = FrameLines.profiles(g)
                // Frame lines sit just inside each border: look 3 px either side
                fun at(prof: DoubleArray, c: Int) = (max(0, c - 3)..min(prof.size - 1, c + 3)).maxOfOrNull { prof[it] } ?: 0.0
                var total = 0.0
                for (k in 0..StashGrid.COLUMNS) total += at(p.cols, k * cell) / g.height
                for (j in 0..rows) total += at(p.rows, j * cell) / g.width
                total / (StashGrid.COLUMNS + rows + 2)
            }
        }
    }

    /** Swift's `stride(from:through:by:)` over doubles. */
    internal fun strideThrough(from: Double, through: Double, by: Double): Sequence<Double> =
        generateSequence(0) { it + 1 }.map { from + it * by }.takeWhile { it <= through }
}
