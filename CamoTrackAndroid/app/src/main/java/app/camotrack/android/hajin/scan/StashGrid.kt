package app.camotrack.android.hajin.scan

import kotlin.math.abs
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min

/** One tile of a read grid. (HajinStashGrid.Tile.) */
data class Tile(
    val row: Int,
    val column: Int,
    /** An item id (or `x-<first id>` for a shared picture), `empty`, `other` or `blueprint`. */
    val id: String,
    val confidence: Float,
    val count: Int?,
    /** A blueprint: its tile as read, and the model's best guess among the
     *  blueprint items (it was trained on plain tiles, so a guess) */
    val image: Raster? = null,
    val guess: String? = null,
    val guessConfidence: Float = 0f,
    /** Where it was read, on the photo: four corners (TL, TR, BR, BL) as
     *  fractions, from the tile's own borders where they were found */
    val place: List<Pt>? = null,
)

/** Stacks of the same item added together. (HajinStashGrid.totals.) */
data class GridTotals(
    val counts: Map<String, Int>,
    /** A stack whose count couldn't be read (counted as 1), or a weak match */
    val unsure: Set<String>,
    /** How sure of each item: its least certain stack */
    val sureness: Map<String, Float>,
    val stacks: Map<String, Int>,
)

/**
 * The stash grid's pure logic, ported from the iPhone's HajinStashGrid: the
 * frame's rows, straightening, the frame lines, highlighting, blueprint
 * blue, totals. `StashGridReader` reads the tiles with the models.
 */
object StashGrid {
    /** The stash's width; a backpack is `PostMatchReader.COLUMNS`. */
    const val COLUMNS = 6
    const val CELL = 200.0

    /** A point of the unit square (u across, v down) on the photo quad `q` (TL, TR, BR, BL). */
    fun onPhoto(q: List<Pt>, u: Double, v: Double): Pt = quadPoint(q, u, v)

    /** Rows that fit the framed area, from its shape (tiles are square). */
    fun rows(corners: List<Pt>, width: Int, height: Int, columns: Int = COLUMNS): Int {
        val p = corners.map { Pt(it.x * width, it.y * height) }
        fun d(a: Pt, b: Pt) = hypot(a.x - b.x, a.y - b.y)
        val w = (d(p[0], p[1]) + d(p[3], p[2])) / 2
        val h = (d(p[0], p[3]) + d(p[1], p[2])) / 2
        if (w <= 0) return 1
        return max(1, min(20, TileLattice.round(columns * h / w).toInt()))
    }

    /** Rows in the framed area, measured: straightened, the horizontal frame
     *  lines repeat once per row, so the repeat length gives the row count.
     *  Falls back to the shape estimate. */
    fun measureRows(image: Raster, corners: List<Pt>, columns: Int = COLUMNS): Int {
        val estimate = rows(corners, image.width, image.height, columns)
        val cw = 40; val height = 640
        val flat = image.straightened(corners, cw * columns, height) ?: return estimate
        val h = flat.height
        val row = FrameLines.profiles(flat).rows
        val lines = smoothed(narrow(row, 30), 2)
        // the repeat, for 3 to 14 rows; a double-row repeat scores nearly as
        // well, so take the shortest lag that comes close to the best
        val mean = lines.sum() / h
        val scores = ArrayList<Pair<Int, Double>>()
        for (lag in (height / 14)..(height / 3)) {
            var sc = 0.0
            for (y in 0 until h - lag) sc += (lines[y] - mean) * (lines[y + lag] - mean)
            scores.add(lag to sc / (h - lag))
        }
        // local peaks only, so the slope next to a strong peak doesn't count
        val peaks = scores.indices.filter { i ->
            (i == 0 || scores[i].second >= scores[i - 1].second) && (i == scores.size - 1 || scores[i].second >= scores[i + 1].second)
        }.map { scores[it] }
        val top = peaks.maxOfOrNull { it.second } ?: return estimate
        if (top <= 0) return estimate
        val best = peaks.firstOrNull { it.second >= top * 0.8 } ?: return estimate
        val measured = TileLattice.round(height.toDouble() / best.first).toInt()
        return if (measured in 1..20) measured else estimate
    }

    /** The quad grown outward by fractions of its width and height, along
     *  its own sides (bilinear, close enough for a few percent). */
    fun expanded(c: List<Pt>, du: Double, dv: Double): List<Pt> {
        fun at(u: Double, v: Double): Pt {
            val top = Pt(c[0].x + (c[1].x - c[0].x) * u, c[0].y + (c[1].y - c[0].y) * u)
            val bottom = Pt(c[3].x + (c[2].x - c[3].x) * u, c[3].y + (c[2].y - c[3].y) * u)
            return Pt(top.x + (bottom.x - top.x) * v, top.y + (bottom.y - top.y) * v)
        }
        return listOf(at(-du, -dv), at(1 + du, -dv), at(1 + du, 1 + dv), at(-du, 1 + dv))
    }

    /** How much of a tile, its middle, is a blueprint's blue: 0.8 to 0.95 on
     *  blueprints, under 0.25 on anything else (a blue rarity's tint included). */
    fun blueFraction(tile: Raster): Double {
        val w = tile.width; val h = tile.height
        if (w <= 8 || h <= 8) return 0.0
        var blue = 0; var n = 0
        var y = h / 8
        while (y < h * 7 / 8) {
            var x = w / 8
            while (x < w * 7 / 8) {
                val i = y * w + x
                val r = tile.r(i); val g = tile.g(i); val b = tile.b(i)
                // The blueprint's blue leans to cyan (green well over red); a
                // rare item's tile is a purple-blue (green near red)
                if (b > 110 && b > r + 50 && b > g + 15 && g > r + 30) blue++
                n++
                x += 2
            }
            y += 2
        }
        return if (n > 0) blue.toDouble() / n else 0.0
    }

    /** A tile's box with each side moved onto the tile's thin light outline
     *  if one is near (an eighth of a tile either way). A side with no clear
     *  line stays put. `grey` is one byte a pixel, w x h. */
    fun snapped(r: Box, grey: IntArray, w: Int, h: Int): Box {
        if (grey.size != w * h || r.width <= 20) return r
        val reach = (r.width * 0.12).toInt()
        fun at(x: Int, y: Int) = grey[min(max(y, 0), h - 1) * w + min(max(x, 0), w - 1)].toDouble()
        // How much a thin line stands out from both sides of it: the lesser
        // of the two, so the edge of a bright patch scores nothing
        fun vertical(x: Int): Double {
            val y0 = (r.minY + r.height * 0.2).toInt(); val y1 = (r.maxY - r.height * 0.2).toInt()
            var line = 0.0; var before = 0.0; var after = 0.0
            var y = y0
            while (y < y1) { line += at(x, y); before += at(x - 3, y); after += at(x + 3, y); y += 2 }
            return min(line - before, line - after) / max((y1 - y0) / 2, 1)
        }
        fun horizontal(y: Int): Double {
            val x0 = (r.minX + r.width * 0.2).toInt(); val x1 = (r.maxX - r.width * 0.2).toInt()
            var line = 0.0; var before = 0.0; var after = 0.0
            var x = x0
            while (x < x1) { line += at(x, y); before += at(x, y - 3); after += at(x, y + 3); x += 2 }
            return min(line - before, line - after) / max((x1 - x0) / 2, 1)
        }
        fun best(from: Double, score: (Int) -> Double): Double {
            val start = from.toInt()
            val found = (start - reach..start + reach).maxByOrNull(score) ?: start
            // Only a clear line: a few levels brighter than beside it
            return if (score(found) > 12) found.toDouble() else from
        }
        val left = best(r.minX, ::vertical); val right = best(r.maxX, ::vertical)
        val top = best(r.minY, ::horizontal); val bottom = best(r.maxY, ::horizontal)
        // Still about a tile, or the snap's gone wrong: keep the box
        if (right - left <= r.width * 0.85 || right - left >= r.width * 1.15 ||
            bottom - top <= r.height * 0.85 || bottom - top >= r.height * 1.15) return r
        return Box(left, top, right - left, bottom - top)
    }

    /** Each tile's highlight moved onto the detector's tile under it (the one
     *  it overlaps most), so the review lights the tile itself. */
    fun pinned(tiles: List<Tile>, width: Int, height: Int, boxes: List<Box>): List<Tile> {
        if (boxes.isEmpty()) return tiles
        val W = width.toDouble(); val H = height.toDouble()
        return tiles.map { tile ->
            val place = tile.place ?: return@map tile
            val xs = place.map { it.x * W }; val ys = place.map { it.y * H }
            val lit = Box(xs.min(), ys.min(), xs.max() - xs.min(), ys.max() - ys.min())
            fun shared(b: Box) = b.intersection(lit)?.let { it.width * it.height } ?: 0.0
            // At least a third of the highlight on it, and about a tile's size
            val box = boxes.maxByOrNull(::shared) ?: return@map tile
            if (shared(box) <= lit.width * lit.height / 3 || box.width <= lit.width * 0.6 || box.width >= lit.width * 1.6) return@map tile
            tile.copy(place = listOf(Pt(box.minX / W, box.minY / H), Pt(box.maxX / W, box.minY / H),
                                     Pt(box.maxX / W, box.maxY / H), Pt(box.minX / W, box.maxY / H)))
        }
    }

    /** Stacks of the same item added together. A stack whose count couldn't
     *  be read counts as 1 and is listed in `unsure`, as is a weak match.
     *  "other", "empty" and blueprints aren't counted. */
    fun totals(tiles: List<Tile>): GridTotals {
        val counts = LinkedHashMap<String, Int>(); val unsure = LinkedHashSet<String>()
        val sureness = LinkedHashMap<String, Float>(); val stacks = LinkedHashMap<String, Int>()
        for (t in tiles) {
            if (t.id == "empty" || t.id == "other" || t.id == "blueprint") continue
            counts[t.id] = (counts[t.id] ?: 0) + (t.count ?: 1)
            stacks[t.id] = (stacks[t.id] ?: 0) + 1
            sureness[t.id] = min(sureness[t.id] ?: 1f, t.confidence)
            if (t.count == null || t.confidence < 0.5f) unsure.add(t.id)
        }
        return GridTotals(counts, unsure, sureness, stacks)
    }

    /** A class name back to its item id: a shared picture's class is `x-<first id>`. */
    fun itemId(classId: String) = if (classId.startsWith("x-")) classId.substring(2) else classId
}

/**
 * Reads the stash grid from a photo: straightened from four corners (TL,
 * TR, BR, BL fractions), each tile named by the classifier and its stack
 * count read from the top-right corner. (HajinStashGrid.read.)
 */
class StashGridReader(private val classifier: TileClassifier, private val detector: TileDetector? = null) {

    /**
     * @param rows known rows, or null to measure them from the frame lines
     * @param fitBorders false reads the frame as given, nudged a little up and
     *   down, without fitting the grid to the lines (a single row, like a
     *   backpack's secure slots, has too few to fit)
     * @param detected the detector's boxes on this photo, if already found
     *   (null runs the detector, when there is one, to pin the highlights)
     */
    fun read(image: Raster, corners: List<Pt>, rows: Int? = null, columns: Int = StashGrid.COLUMNS,
             blueprints: Set<String> = emptySet(), fitBorders: Boolean = true, detected: List<Box>? = null): List<Tile> {
        val cell = StashGrid.CELL
        val rowCount = rows ?: StashGrid.measureRows(image, corners, columns)
        // Half a tile of margin all round, so a frame dragged slightly inside
        // the grid still has its borders in the picture
        val margin = StashGrid.expanded(corners, 0.5 / columns, 0.5 / rowCount)
        val flat = image.straightened(margin, (cell * (columns + 1)).toInt(), (cell * (rowCount + 1)).toInt()) ?: return emptyList()
        val lattice = if (fitBorders) GridLattice.fit(flat, columns, rowCount, cell) else GridLattice.Lattice(emptyList(), emptyList())
        fun fromFrame(row: Int, column: Int): Box? =
            if (row < rowCount) Box(cell / 2 + column * cell, cell / 2 + row * cell, cell, cell) else null
        fun fromBorders(row: Int, column: Int): Box? {
            if (row + 1 >= lattice.ys.size || column + 1 >= lattice.xs.size) return null
            return Box(lattice.xs[column], lattice.ys[row], lattice.xs[column + 1] - lattice.xs[column], lattice.ys[row + 1] - lattice.ys[row])
        }
        val flatW = flat.width.toDouble(); val flatH = flat.height.toDouble()
        val grey = flat.grey()
        fun place(r: Box): List<Pt> = listOf(r.minX to r.minY, r.maxX to r.minY, r.maxX to r.maxY, r.minX to r.maxY)
            .map { StashGrid.onPhoto(margin, it.first / flatW, it.second / flatH) }
        fun classify(r: Box, row: Int, column: Int): Tile? {
            val raw = flat.cropped(r.integral()) ?: return null
            val tile = raw.resized(cell.toInt(), cell.toInt())
            // A blueprint is the item drawn on a blue grid, which the icon
            // model has never seen as an item
            if (StashGrid.blueFraction(tile) > 0.5) {
                val guess = if (blueprints.isEmpty()) null
                    else classifier.classify(tile).firstOrNull { StashGrid.itemId(it.id) in blueprints }
                return Tile(row, column, "blueprint", 1f, null, image = tile,
                            guess = guess?.let { StashGrid.itemId(it.id) }, guessConfidence = guess?.confidence ?: 0f)
            }
            val top = classifier.classify(tile).firstOrNull() ?: return null
            val count = if (top.id == "empty" || top.id == "other") null else StackCount.read(tile)
            return Tile(row, column, top.id, top.confidence, count)
        }
        fun readTile(r: Box, row: Int, column: Int) = classify(r, row, column)?.copy(place = place(r))

        val tiles = ArrayList<Tile>()
        for (row in 0 until max(rowCount, lattice.ys.size - 1)) {
            for (column in 0 until columns) {
                val a = fromFrame(row, column); val b = fromBorders(row, column)
                var crops = listOfNotNull(a, b)
                if (!fitBorders && a != null) {
                    // Where the row really sits can be a fifth of a tile out
                    // either way, and its tiles a little bigger: try across it
                    crops = buildList {
                        for (dy in listOf(-0.1, 0.0, 0.1, 0.2, 0.3)) for (grow in listOf(1.0, 1.15)) {
                            val g = -cell * (grow - 1) / 2
                            add(a.offsetBy(0.0, cell * dy).insetBy(g, g))
                        }
                    }
                }
                if (a != null && b != null) {   // and one halfway between
                    crops = crops + Box((a.minX + b.minX) / 2, (a.minY + b.minY) / 2, (a.width + b.width) / 2, (a.height + b.height) / 2)
                }
                val reads = crops.mapNotNull { readTile(it, row, column) }
                if (reads.isEmpty()) continue
                // The item with the most confidence across the reads, then the
                // count most of its reads agree on (the frame's on a tie)
                val weight = LinkedHashMap<String, Float>()
                for (r in reads) weight[r.id] = (weight[r.id] ?: 0f) + r.confidence
                val id = weight.maxByOrNull { it.value }!!.key
                val mine = reads.filter { it.id == id }
                val counts = mine.mapNotNull { it.count }
                val votes = counts.groupingBy { it }.eachCount()
                val topVotes = votes.values.maxOrNull() ?: 0
                val count = counts.firstOrNull { votes[it] == topVotes }
                val best = mine.maxByOrNull { it.guessConfidence }
                // Lit where a read that agreed was taken: the tile's own
                // borders first, but only if they read this item too, then
                // the frame's crop, then the surest read; snapped onto the outline
                val surest = mine.maxByOrNull { it.confidence }
                val agreed = mine.mapNotNull { it.place }.toSet()
                fun agrees(r: Box?): Box? = r?.takeIf { place(it) in agreed }
                val lit = (agrees(b) ?: agrees(a))?.let { place(StashGrid.snapped(it, grey, flat.width, flat.height)) } ?: surest?.place
                tiles.add(Tile(row, column, id, weight[id]!! / reads.size, count,
                               image = best?.image, guess = best?.guess, guessConfidence = best?.guessConfidence ?: 0f, place = lit))
            }
        }
        val boxes = detected ?: detector?.let { TileLattice.tiles(it.detect(image)) } ?: emptyList()
        return StashGrid.pinned(tiles, image.width, image.height, boxes)
    }
}

/** Whether a photo is good enough to read: sharp, lit, without glare, and
 *  big enough. (HajinPhotoQuality.) */
enum class PhotoQuality {
    BLURRY, DARK, GLARE, SMALL;

    /** As the iPhone names it ("blurry"), for reports and string keys. */
    val key get() = name.lowercase()

    companion object {
        fun issues(image: Raster): List<PhotoQuality> {
            val out = ArrayList<PhotoQuality>()
            if (min(image.width, image.height) < 900) out.add(SMALL)
            // A greyscale copy, at most 800 px, middle of the photo only
            val scale = min(1.0, 800.0 / max(image.width, image.height))
            val w = (image.width * scale).toInt(); val h = (image.height * scale).toInt()
            if (w <= 10 || h <= 10) return out
            val px = image.resized(w, h).grey()
            val x0 = (w * 0.15).toInt(); val x1 = (w * 0.85).toInt(); val y0 = (h * 0.15).toInt(); val y1 = (h * 0.8).toInt()
            var sum = 0.0; var sumSq = 0.0; var n = 0.0; var total = 0.0; var bright = 0.0
            for (y in max(1, y0) until min(h - 1, y1)) for (x in max(1, x0) until min(w - 1, x1)) {
                val c = px[y * w + x].toDouble()
                // Laplacian: how sharply each pixel differs from its neighbours
                val lap = px[(y - 1) * w + x] + px[(y + 1) * w + x] + px[y * w + x - 1] + px[y * w + x + 1] - 4 * c
                sum += lap; sumSq += lap * lap; n += 1
                total += c
                if (c >= 245) bright += 1
            }
            if (n <= 0) return out
            val variance = sumSq / n - (sum / n) * (sum / n)
            if (variance < 250) out.add(BLURRY)
            if (total / n < 45) out.add(DARK)
            if (bright / n > 0.08) out.add(GLARE)
            return out
        }
    }
}
