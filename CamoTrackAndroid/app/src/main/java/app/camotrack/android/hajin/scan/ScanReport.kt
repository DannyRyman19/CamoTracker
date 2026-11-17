package app.camotrack.android.hajin.scan

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlin.math.roundToLong

/**
 * What one stash photo read saw, for "Send this photo": where it guessed the
 * grid, where the player put it, every tile's answer, so a misread can be
 * replayed and the player's corrections used as the right answers. The
 * same JSON as the iPhone's HajinScanReport (with "android" for "ios").
 */
data class ScanReport(
    val photoWidth: Int,
    val photoHeight: Int,
    val quality: List<PhotoQuality>,
    val guessedCorners: List<Pt>?,
    val corners: List<Pt>,
    val moved: Boolean,
    val tiles: List<Tile>,
    val found: Map<String, Int>,
    val unsure: Set<String>,
    val sureness: Map<String, Float>,
    val cash: Int?,
    val level: Int?,
) {
    /** The reader's working plus what the player had and changed in the review. */
    fun json(had: Map<String, Int>, edited: Map<String, Int>, skipped: Set<String>, swapped: Map<String, String> = emptyMap(),
             app: String = "?", android: String = "?", device: String = "?"): String {
        fun round(v: Double, k: Double) = (v * k).roundToLong() / k
        fun points(p: List<Pt>?) = p?.let { JsonArray(it.map { q -> JsonArray(listOf(JsonPrimitive(round(q.x, 10_000.0)), JsonPrimitive(round(q.y, 10_000.0)))) }) }
        fun ints(m: Map<String, Int>) = JsonObject(m.toSortedMap().mapValues { JsonPrimitive(it.value) })
        fun strings(s: Collection<String>) = JsonArray(s.sorted().map(::JsonPrimitive))
        val report = sortedMapOf<String, JsonElement?>(
            "app" to JsonPrimitive(app),
            "android" to JsonPrimitive(android),
            "device" to JsonPrimitive(device),
            "photo" to JsonArray(listOf(JsonPrimitive(photoWidth), JsonPrimitive(photoHeight))),
            "quality" to JsonArray(quality.map { JsonPrimitive(it.key) }),
            "guessedCorners" to points(guessedCorners),
            "corners" to points(corners),
            "movedByPlayer" to JsonPrimitive(moved),
            "tiles" to JsonArray(tiles.map { t ->
                val d = sortedMapOf<String, JsonElement>("r" to JsonPrimitive(t.row), "c" to JsonPrimitive(t.column), "id" to JsonPrimitive(t.id),
                                                       "conf" to JsonPrimitive(round(t.confidence.toDouble(), 1000.0)))
                t.count?.let { d["count"] = JsonPrimitive(it) }
                JsonObject(d)
            }),
            "found" to ints(found),
            "unsure" to strings(unsure),
            "sureness" to JsonObject(sureness.toSortedMap().mapValues { JsonPrimitive(round(it.value.toDouble(), 1000.0)) }),
            "cash" to cash?.let(::JsonPrimitive),
            "level" to level?.let(::JsonPrimitive),
            "had" to ints(had),
            "editedByPlayer" to ints(edited),
            "skippedByPlayer" to strings(skipped),
            // Read as -> really is: the player's labels for misread tiles
            "swappedByPlayer" to JsonObject(swapped.toSortedMap().mapValues { JsonPrimitive(it.value) }),
        )
        @Suppress("UNCHECKED_CAST")
        val present = report.filterValues { it != null } as Map<String, JsonElement>
        return pretty.encodeToString(JsonObject.serializer(), JsonObject(present))
    }

    private companion object {
        val pretty = Json { prettyPrint = true }
    }
}
