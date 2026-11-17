package app.camotrack.android.hajin.scan

import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min

/** What one post-match backpack photo read. (HajinPostMatchResult.) */
data class PostMatchResult(
    val counts: Map<String, Int> = emptyMap(),
    val unsure: Set<String> = emptySet(),
    val resources: Map<String, Int> = emptyMap(),
    /** Where each item's tiles are on the photo (four corners each, as fractions) */
    val places: Map<String, List<List<Pt>>> = emptyMap(),
    /** Each item's first tile, row * 100 + column, to list them in the backpack's order */
    val order: Map<String, Int> = emptyMap(),
    val blueprints: List<Blueprint> = emptyList(),
    /** Weapon manuals read */
    val manuals: Int = 0,
    /** Tiles with something on them the reader couldn't name (a weapon, say) */
    val unread: Int = 0,
) {
    /** A blueprint tile, as read: the picture, and the model's guess at it. */
    data class Blueprint(val image: Raster, val guess: String?, /** sure enough to start ticked */ val sure: Boolean, val place: List<Pt>?)
}

/**
 * After a match: a photo of the backpack read like a stash photo, but 4
 * tiles wide, with the Secure slots under it and the resources in the SORT
 * panel beside it. (HajinBackpack.)
 */
object PostMatchReader {
    const val COLUMNS = 4

    /** Text recognisers read some of the game's capitals as Cyrillic
     *  look-alikes ("ВАСКРАСК"): back to Latin, upper case, no spaces. */
    fun normalised(text: String): String {
        val map = mapOf('А' to 'A', 'В' to 'B', 'С' to 'C', 'Е' to 'E', 'К' to 'K', 'М' to 'M', 'Н' to 'H',
                        'О' to 'O', 'Р' to 'P', 'Т' to 'T', 'Х' to 'X', 'У' to 'Y')
        return text.uppercase().filter { it != ' ' }.map { map[it] ?: it }.joinToString("")
    }

    /** The text around the grid, in fractions with the origin at the top left. */
    data class Landmarks(
        /** "MEDIUM BACKPACK" over the grid: its left edge and foot are the grid's top left */
        val header: Box? = null,
        /** "SECURE SLOTS" under the grid, over the secure row */
        val secure: Box? = null,
        /** "SORT" over the resource panel to the grid's right */
        val sort: Box? = null,
    )

    private fun topLeftBox(l: TextLine) = Box(l.box.minX, 1 - l.box.maxY, l.box.width, l.box.height)

    fun landmarks(lines: List<TextLine>) = Landmarks(
        // The longest line saying BACKPACK: the item menu's lone "BACKPACK" isn't it
        header = lines.filter { normalised(it.text).contains("BACKPACK") && normalised(it.text).length > 8 }
            .maxByOrNull { it.text.length }?.let(::topLeftBox),
        secure = lines.firstOrNull { normalised(it.text).contains("SECURESLOT") }?.let(::topLeftBox),
        sort = lines.firstOrNull { normalised(it.text) == "SORT" }?.let(::topLeftBox),
    )

    /** Whether the photo is a backpack (its header or SECURE SLOTS), from its text. */
    fun isBackpack(lines: List<TextLine>): Boolean = landmarks(lines).let { it.header != null || it.secure != null }

    /** The grid's corners (TL, TR, BR, BL, fractions) from the text round it:
     *  the header pins the top left, SORT the right, SECURE SLOTS the bottom. */
    fun guess(lines: List<TextLine>, width: Int, height: Int): List<Pt>? {
        val marks = landmarks(lines)
        val header = marks.header ?: return null
        val sort = marks.sort ?: return null
        val W = width.toDouble(); val H = height.toDouble()
        val left = header.minX * W; val top = header.maxY * H
        val sortX = sort.minX * W
        if (sortX <= left) return null
        val right = left + (sortX - left) / (1 + 0.3 / COLUMNS)
        val pitch = (right - left) / COLUMNS
        var bottom = top + pitch * 4; var bottomLeft = left
        val secure = marks.secure
        if (secure != null && secure.minY * H > top + pitch) {
            bottom = secure.minY * H - pitch * 0.1
            bottomLeft = secure.minX * W - pitch * 0.1
        }
        val shift = bottomLeft - left
        return listOf(Pt(left, top + pitch * 0.04), Pt(right, top + pitch * 0.04), Pt(right + shift, bottom), Pt(bottomLeft, bottom))
            .map { Pt((it.x / W).coerceIn(0.0, 1.0), (it.y / H).coerceIn(0.0, 1.0)) }
    }

    /** Rows in the framed backpack, from its shape: 3 to 5 rows of square tiles (2...6 allowed). */
    fun rows(corners: List<Pt>, width: Int, height: Int): Int =
        min(max(StashGrid.rows(corners, width, height, COLUMNS), 2), 6)

    /** The secure row under the grid: as wide as it, a tile tall, starting
     *  just under SECURE SLOTS (or where that usually is). */
    fun secureRow(corners: List<Pt>, lines: List<TextLine>, width: Int, height: Int): List<Pt> {
        val W = width.toDouble(); val H = height.toDouble()
        val p = corners.map { Pt(it.x * W, it.y * H) }
        val pitch = hypot(p[1].x - p[0].x, p[1].y - p[0].y) / COLUMNS
        val side = p[3] - p[0]
        val length = max(side.length(), 1.0)
        val down = Pt(side.x / length, side.y / length)
        // How far below the grid the row starts: from the label when it's
        // read and sensible, else the usual gap
        var gap = pitch * 0.39
        landmarks(lines).secure?.let { secure ->
            val g = (secure.maxY * H - p[3].y) / max(down.y, 0.1) + pitch * 0.05
            if (g > 0 && g < pitch * 1.2) gap = g
        }
        fun along(point: Pt, d: Double) = Pt((point.x + down.x * d) / W, (point.y + down.y * d) / H)
        return listOf(along(p[3], gap), along(p[2], gap), along(p[2], gap + pitch), along(p[3], gap + pitch))
    }

    /** The SORT panel's four totals, top to bottom: synthetics, electronics, chemicals, metals. */
    fun resources(lines: List<TextLine>): Map<String, Int> {
        val sort = landmarks(lines).sort ?: return emptyMap()
        // The panel under SORT: about its width, a dozen lines deep
        val panel = Box(sort.minX - sort.width * 0.5, sort.maxY, sort.width * 2.5, sort.height * 14)
        val below = lines.map { it to topLeftBox(it) }
            .filter { panel.intersects(it.second) && it.second.minY > sort.minY }
            .sortedBy { it.second.minY }
        var cap = 999
        val values = ArrayList<Int>()
        val three = Regex("[0-9O]{3}$")
        for ((line, _) in below) {
            val text = normalised(line.text)
            if (text.startsWith("MAX")) {
                text.filter { it.isDigit() }.toIntOrNull()?.let { cap = it }
                break
            }
            if (values.size >= 4) continue
            val m = three.find(text) ?: continue
            values.add(m.value.replace("O", "0").toIntOrNull() ?: 0)
        }
        if (values.size != 4) return emptyMap()
        // A misread first digit (043 as 843) can't be over the backpack's cap
        val fixed = values.map { if (it > cap) it % 100 else it }
        return listOf("synthetics", "electronics", "chemicals", "metals").zip(fixed).filter { it.second > 0 }.toMap()
    }

    /** One tile's four corners inside a framed grid, as fractions of the photo. */
    fun quad(k: List<Pt>, row: Int, column: Int, rows: Int, columns: Int = COLUMNS): List<Pt> {
        fun at(u: Double, v: Double): Pt {
            val top = Pt(k[0].x + (k[1].x - k[0].x) * u, k[0].y + (k[1].y - k[0].y) * u)
            val bottom = Pt(k[3].x + (k[2].x - k[3].x) * u, k[3].y + (k[2].y - k[3].y) * u)
            return Pt(top.x + (bottom.x - top.x) * v, top.y + (bottom.y - top.y) * v)
        }
        val u0 = column.toDouble() / columns; val u1 = (column + 1.0) / columns
        val v0 = row.toDouble() / max(rows, 1); val v1 = (row + 1.0) / max(rows, 1)
        return listOf(at(u0, v0), at(u1, v0), at(u1, v1), at(u0, v1))
    }

    /** Never reaches the stash: armor plates, dog tags, Lieutenant tag cases. */
    fun discarded(id: String) = id == "armor-plate" || id.contains("dog-tag")

    /**
     * The backpack and secure slots as guide items and counts, the blueprints
     * picked up, and the resources. `known` is every guide item id;
     * `blueprints` the ids of blueprint items.
     */
    fun read(reader: StashGridReader, image: Raster, corners: List<Pt>, lines: List<TextLine>,
             known: Set<String>, blueprints: Set<String>, detected: List<Box>? = null): PostMatchResult {
        val gridRows = rows(corners, image.width, image.height)
        val secureCorners = secureRow(corners, lines, image.width, image.height)
        // Each tile with where it is on the photo, for the review to light up
        val tiles = reader.read(image, corners, gridRows, COLUMNS, blueprints, detected = detected)
            .map { it to (it.place ?: quad(corners, it.row, it.column, gridRows)) }.toMutableList()
        // The secure row, read where it is rather than fitted to lines: the
        // SECURE SLOTS label's box looks like another row
        val secure = reader.read(image, secureCorners, 1, COLUMNS, blueprints, fitBorders = false, detected = detected)
        // A free secure slot shows a grey shield, which a weak read takes for a Riot Shield
        tiles += secure.filter { !(it.id == "riot-shield" && it.confidence < 0.7f) }
            .map { it.copy(row = gridRows) }
            .map { it to (it.place ?: quad(secureCorners, 0, it.column, 1)) }
        val counts = LinkedHashMap<String, Int>(); val unsure = LinkedHashSet<String>()
        val places = LinkedHashMap<String, MutableList<List<Pt>>>(); val order = LinkedHashMap<String, Int>()
        val prints = ArrayList<PostMatchResult.Blueprint>()
        var manuals = 0; var unread = 0
        for ((t, place) in tiles) {
            when (t.id) {
                "empty" -> continue
                "blueprint" -> {
                    t.image?.let { prints.add(PostMatchResult.Blueprint(it, t.guess, t.guessConfidence >= 0.6f, place)) }
                    continue
                }
                "weapon-manual" -> { manuals++; continue }
            }
            // A shared picture's class is named after its first item
            val id = StashGrid.itemId(t.id)
            // Gone by the time you're back
            if (discarded(id)) continue
            // A wild guess (a weapon or gear the model doesn't know) is left out
            if (t.id == "other" || t.confidence < 0.3f || id !in known) { unread++; continue }
            counts[id] = (counts[id] ?: 0) + (t.count ?: 1)
            places.getOrPut(id) { ArrayList() }.add(place)
            order[id] = min(order[id] ?: Int.MAX_VALUE, t.row * 100 + t.column)
            if (t.count == null || t.confidence < 0.5f) unsure.add(id)
        }
        return PostMatchResult(counts, unsure, resources(lines), places, order, prints, manuals, unread)
    }
}
