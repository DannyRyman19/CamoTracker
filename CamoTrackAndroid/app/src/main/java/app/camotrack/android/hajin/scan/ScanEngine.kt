package app.camotrack.android.hajin.scan

/** What a photo shows, from its text (HajinScanHost.route). */
sealed interface PhotoKind {
    /** A backpack after a match: frame it 4 wide and read with `readPostMatch`. */
    data object Backpack : PhotoKind
    /** A stash grid (or nothing readable): frame it 6 wide and read with `readStash`. */
    data object Stash : PhotoKind
    /** A 3D Printer recipe screen: its counts, read already, for the review. */
    data class Printer(val read: TextRead) : PhotoKind
}

/** Counts read from text alone (recipe screens), with the bank and level if shown. */
data class TextRead(val counts: Map<String, Int>, val cash: Int?, val level: Int?)

/** A stash photo read (HajinGridResult): the grid's ingredient counts, the
 *  resources beside it, the bank and level, and the working for a report. */
data class StashRead(
    val tiles: List<Tile>,
    val counts: Map<String, Int>,
    val unsure: Set<String>,
    val sureness: Map<String, Float>,
    val stacks: Map<String, Int>,
    val cash: Int?,
    val level: Int?,
    val report: ScanReport,
)

/**
 * The whole photo reader, given its three services: what the iPhone's
 * framing screen and scan host do with a photo, minus the UI. Every call is
 * blocking and can take a second or more: run it off the main thread.
 * `StashScanner` is the Android-ready version (Bitmaps, the bundled models).
 */
class ScanEngine(
    private val classifier: TileClassifier,
    private val detector: TileDetector?,
    private val text: TextReader,
) {
    val grid = StashGridReader(classifier, detector)

    private var lastDetected: Pair<Raster, List<Detection>>? = null
    private var lastLines: Pair<Raster, List<TextLine>>? = null

    /** The detector's boxes on this photo (kept for the next call on the same one). */
    @Synchronized fun detections(image: Raster): List<Detection> {
        lastDetected?.let { if (it.first === image) return it.second }
        val found = detector?.detect(image) ?: emptyList()
        lastDetected = image to found
        return found
    }

    /** The photo's text (kept for the next call on the same one). */
    @Synchronized fun lines(image: Raster): List<TextLine> {
        lastLines?.let { if (it.first === image) return it.second }
        val found = text.lines(image)
        lastLines = image to found
        return found
    }

    /** Backpack, stash grid, or a printer screen read straight away. `items`
     *  are the items My stash counts (resources, ingredients, valuables). */
    fun route(image: Raster, items: List<ScanItem>): PhotoKind {
        val lines = lines(image)
        if (PostMatchReader.isBackpack(lines)) return PhotoKind.Backpack
        val isStash = lines.any { val t = it.text.uppercase(); t.contains("ITEMS") || t.contains("STASH") }
        if (isStash) return PhotoKind.Stash
        val counts = RecipeReader.counts(lines, items)
        if (counts.isEmpty()) return PhotoKind.Stash
        return PhotoKind.Printer(TextRead(counts, RecipeReader.bank(lines), RecipeReader.level(lines)))
    }

    fun quality(image: Raster): List<PhotoQuality> = PhotoQuality.issues(image)

    /** The grid's corners (TL, TR, BR, BL fractions), or null when it can't be found. */
    fun guessCorners(image: Raster, backpack: Boolean = false): List<Pt>? =
        if (backpack) PostMatchReader.guess(lines(image), image.width, image.height)
        else GridFinder.guess(image, detections(image)) { lines(image) }

    /** Rows for a frame, for drawing it: measured from the lines for a stash,
     *  from the shape for a backpack. */
    fun rows(image: Raster, corners: List<Pt>, backpack: Boolean = false): Int =
        if (backpack) PostMatchReader.rows(corners, image.width, image.height)
        else StashGrid.measureRows(image, corners)

    /** Every tile of the framed grid. */
    fun readGrid(image: Raster, corners: List<Pt>, columns: Int = StashGrid.COLUMNS, rows: Int? = null,
                 blueprints: Set<String> = emptySet()): List<Tile> =
        grid.read(image, corners, rows, columns, blueprints, detected = TileLattice.tiles(detections(image)))

    /**
     * A stash photo: the framed grid's counts, the resource totals beside it
     * (`items` must include the resources, kind "Resource"), the bank, level.
     */
    fun readStash(image: Raster, corners: List<Pt>, items: List<ScanItem>, guessedCorners: List<Pt>? = null,
                  moved: Boolean = false, quality: List<PhotoQuality> = emptyList()): StashRead {
        val tiles = readGrid(image, corners)
        val totals = StashGrid.totals(tiles)
        val lines = lines(image)
        val counts = LinkedHashMap(totals.counts)
        for ((id, n) in RecipeReader.counts(lines, items.filter { it.kind == "Resource" })) counts[id] = n
        val cash = RecipeReader.bank(lines); val level = RecipeReader.level(lines)
        val report = ScanReport(image.width, image.height, quality, guessedCorners, corners, moved, tiles, counts,
                                totals.unsure, totals.sureness, cash, level)
        return StashRead(tiles, counts, totals.unsure, totals.sureness, totals.stacks, cash, level, report)
    }

    /** A backpack after a match. `guide` is every guide item (to know ids and blueprints). */
    fun readPostMatch(image: Raster, corners: List<Pt>, guide: List<ScanItem>): PostMatchResult =
        PostMatchReader.read(grid, image, corners, lines(image), guide.map { it.id }.toSet(),
                             guide.filter { it.blueprint }.map { it.id }.toSet(), TileLattice.tiles(detections(image)))

    /** Printer screens, several at once: each item's count read most often. */
    fun readText(images: List<Raster>, items: List<ScanItem>): TextRead {
        var cash: Int? = null; var level: Int? = null
        val reads = images.map { image ->
            val lines = text.lines(image)
            RecipeReader.bank(lines)?.let { cash = it }
            RecipeReader.level(lines)?.let { level = it }
            RecipeReader.counts(lines, items)
        }
        return TextRead(RecipeReader.merged(reads), cash, level)
    }
}
