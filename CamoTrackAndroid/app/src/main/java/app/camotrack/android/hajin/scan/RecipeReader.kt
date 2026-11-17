package app.camotrack.android.hajin.scan

import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

/**
 * Reads stash counts out of the text of photos or screenshots: the 3D
 * Printer's recipe screens, where each ingredient shows as its name with
 * "have/need" under it ("Synthetics" then "607/50"), and the stash screen's
 * resource totals, bank and level. (HajinStashScanner.)
 */
object RecipeReader {

    /** Ingredient and resource counts found in the lines: a name the guide
     *  knows, then the first number of the "have/need" just below it (or on
     *  the same line). Resources may show a plain total instead. */
    fun counts(lines: List<TextLine>, items: List<ScanItem>): Map<String, Int> {
        val names = items.map { it.id to normalised(it.name) }.filter { it.second.length >= 3 }
        // The stash screen lists resources as a name over a plain total
        val resources = items.filter { it.kind == "Resource" }.map { it.id }.toSet()
        fun amount(text: String, id: String) = have(text) ?: if (id in resources) plain(text) else null
        val found = LinkedHashMap<String, Int>()
        val sorted = lines.sortedByDescending { it.box.midY }
        for ((i, line) in sorted.withIndex()) {
            val id = match(line.text, names) ?: continue
            val inLine = have(line.text)
            if (inLine != null) { found[id] = inLine; continue }
            val total = if (id in resources) plain(line.text.replace(Regex("^\\D+"), "")) else null
            if (total != null) { found[id] = total; continue }
            // The count sits just under the name, roughly left-aligned with it
            val below = sorted.drop(i + 1).take(4).firstOrNull { other ->
                val gap = line.box.minY - other.box.maxY
                // Same text size, so a big screen title never takes a count
                val scale = other.box.height / max(line.box.height, 0.0001)
                gap > -line.box.height * 0.5 && gap < line.box.height * 2.5 &&
                    scale > 0.6 && scale < 1.6 &&
                    abs(other.box.minX - line.box.minX) < max(line.box.width, 0.08) &&
                    amount(other.text, id) != null
            }
            if (below != null) amount(below.text, id)?.let { found[id] = it }
        }
        return found
    }

    /** The bank balance from the stash screen's "BANK $33,050 / $1M": the
     *  first number after BANK, on the same line. Null when there's no BANK. */
    fun bank(lines: List<TextLine>): Int? {
        val label = lines.firstOrNull { it.text.uppercase().contains("BANK") } ?: return null
        val sameLine = lines.filter { abs(it.box.midY - label.box.midY) < label.box.height * 0.8 && it.box.minX >= label.box.minX - 0.01 }
            .sortedBy { it.box.minX }
        var text = sameLine.joinToString(" ") { it.text }
        val at = text.uppercase().indexOf("BANK")
        if (at >= 0) text = text.substring(min(text.length, at + 4))
        // "33,050 / 1M": digits and separators up to the slash
        val beforeSlash = text.split("/").firstOrNull { it.isNotEmpty() } ?: text
        val m = Regex("\\d[\\d,.\\s]*").find(beforeSlash) ?: return null
        val digits = m.value.filter { it.isDigit() }
        if (digits.isEmpty() || digits.length > 9) return null
        return digits.toIntOrNull()
    }

    /** The DMZ level from the stash screen's side panel: "LVL 38", or "LVL"
     *  with the number just under it. */
    fun level(lines: List<TextLine>, maxLevel: Int = 70): Int? {
        val levels = 1..maxLevel
        for (label in lines) {
            if (!label.text.uppercase().contains("LVL")) continue
            val after = label.text.uppercase().split("LVL").last()
            after.filter { it.isDigit() }.toIntOrNull()?.let { if (it in levels) return it }
            // the number on the next line down, roughly in line with LVL
            val below = lines.filter { other ->
                val gap = label.box.minY - other.box.maxY
                gap > -label.box.height && gap < label.box.height * 2.5 && abs(other.box.minX - label.box.minX) < 0.05
            }
            for (other in below) plain(other.text)?.let { if (it in levels) return it }
        }
        return null
    }

    /** "607/50", "607 / 50" or "Synthetics 607/50" gives 607. */
    fun have(text: String): Int? {
        val cleaned = text.replace(",", "").replace("O", "0")
        val m = Regex("(\\d{1,5})\\s*/\\s*\\d{1,5}").find(cleaned) ?: return null
        return m.groupValues[1].toIntOrNull()
    }

    /** A line that is only a number: "793" or "1,240". */
    fun plain(text: String): Int? {
        val t = text.replace(",", "").trim()
        if (t.isEmpty() || t.length > 6 || !t.all { it.isDigit() }) return null
        return t.toIntOrNull()
    }

    private fun normalised(s: String) = s.lowercase().filter { it.isLetter() }

    /** The guide item the text names: exact once letters are compared, or off
     *  by a letter or two for longer names (OCR slips). */
    internal fun match(text: String, names: List<Pair<String, String>>): String? {
        val key = normalised(text.replace(Regex("\\d.*$"), ""))
        if (key.length < 3) return null
        names.firstOrNull { it.second == key }?.let { return it.first }
        // A photo that cuts off the left edge: "thetics" is Synthetics, when
        // only one name ends that way
        if (key.length >= 5) {
            val tails = names.filter { it.second.endsWith(key) }
            if (tails.size == 1) return tails[0].first
        }
        val best = names.map { Triple(it.first, distance(key, it.second), it.second.length) }.minByOrNull { it.second } ?: return null
        return if (best.second <= max(1, best.third / 8)) best.first else null
    }

    internal fun distance(a: String, b: String): Int {
        if (a.isEmpty()) return b.length
        if (b.isEmpty()) return a.length
        var prev = IntArray(b.length + 1) { it }; var cur = IntArray(b.length + 1)
        for (i in 1..a.length) {
            cur[0] = i
            for (j in 1..b.length) {
                cur[j] = if (a[i - 1] == b[j - 1]) prev[j - 1] else 1 + min(prev[j - 1], min(prev[j], cur[j - 1]))
            }
            val t = prev; prev = cur; cur = t
        }
        return prev[b.length]
    }

    /** Several photos of printer screens: for each item the count read most
     *  often, the higher one on a tie. (HajinStashScanButton's merge.) */
    fun merged(reads: List<Map<String, Int>>): Map<String, Int> {
        val seen = LinkedHashMap<String, MutableList<Int>>()
        for (r in reads) for ((id, n) in r) seen.getOrPut(id) { ArrayList() }.add(n)
        return seen.mapValues { (_, values) ->
            values.groupingBy { it }.eachCount().entries.maxWith(compareBy<Map.Entry<Int, Int>> { it.value }.thenBy { it.key }).key
        }
    }
}
