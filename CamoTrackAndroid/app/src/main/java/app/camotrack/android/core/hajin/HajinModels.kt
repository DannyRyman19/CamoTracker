package app.camotrack.android.core.hajin

import app.camotrack.android.core.LocalizedText
import kotlinx.serialization.KSerializer
import kotlinx.serialization.Serializable
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.json.JsonDecoder
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonEncoder
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonPrimitive

/**
 * Text in `hajin.json`: a plain English string or, once a line is translated,
 * `{ "en": ..., "de": ... }`. Either way it resolves to the player's language
 * with English as the fallback (iOS GuideText).
 */
@Serializable(with = GuideTextSerializer::class)
data class GuideText(val values: Map<String, String>) {
    constructor(value: String) : this(mapOf("en" to value))

    val en: String? get() = values["en"]

    val resolved: String
        get() {
            for (code in LocalizedText.preferredLanguages()) values[code]?.let { return it }
            return values["en"] ?: values.values.firstOrNull() ?: ""
        }
}

object GuideTextSerializer : KSerializer<GuideText> {
    override val descriptor: SerialDescriptor = JsonElement.serializer().descriptor

    override fun deserialize(decoder: Decoder): GuideText {
        val element = (decoder as JsonDecoder).decodeJsonElement()
        return when (element) {
            is JsonPrimitive -> GuideText(element.content)
            is JsonObject -> GuideText(element.mapValues { it.value.jsonPrimitive.contentOrNull ?: "" })
            else -> GuideText(emptyMap())
        }
    }

    override fun serialize(encoder: Encoder, value: GuideText) {
        val json = encoder as JsonEncoder
        val en = value.values["en"]
        if (value.values.size == 1 && en != null) json.encodeJsonElement(JsonPrimitive(en))
        else json.encodeJsonElement(JsonObject(value.values.mapValues { JsonPrimitive(it.value) }))
    }
}

/**
 * The DMZ guide: the Hajin Tac Map's markers plus the reference tables (level
 * unlocks, recipes, stations...). Bundled as `hajin.json` and refreshed over
 * the air through the manifest's `guides` block (iOS HajinGuide).
 */
@Serializable
data class HajinGuide(
    val version: String,
    val updated: String? = null,
    val map: MapInfo,
    val threatLevels: List<GuideText>,
    val categories: List<Category>,
    val markers: List<Marker>,
    val guide: List<Section>,
    val items: List<Item>? = null,
    val traitTrees: List<TraitTree>? = null,
    val traits: List<Trait>? = null,
) {
    @Serializable
    data class Category(
        val id: String,
        val name: GuideText,
        val symbol: String,
        val color: String,
        /** Shown when the map first opens; the busy ones start hidden. */
        val visible: Boolean,
        /** What every marker in this category is, shown in its sheet. */
        val blurb: GuideText? = null,
    ) {
        /** Areas and places are drawn as names, not pins. */
        val isLabel: Boolean get() = id == "area" || id == "place"
    }

    @Serializable
    data class Marker(
        val id: String,
        val cat: String,
        val name: GuideText,
        /** 0...1 across and down the map image. */
        val x: Double,
        val y: Double,
        /** 1 (Low) to 5 (Extreme), for areas and Fortresses. */
        val threat: Int? = null,
        val note: GuideText? = null,
        val parts: List<Part>? = null,
        /** Its own symbol in place of its category's (a stop's number on a route). */
        val symbol: String? = null,
    ) {
        @Serializable
        data class Part(val name: GuideText, val threat: Int? = null)
    }

    @Serializable
    data class Row(
        val title: GuideText,
        val value: GuideText? = null,
        val subtitle: GuideText? = null,
        val level: Int? = null,
        val image: String? = null,
        val group: GuideText? = null,
        val item: String? = null,
        val links: List<String>? = null,
        val weapon: Int? = null,
        val check: String? = null,
        val place: GuideText? = null,
        val objectives: List<GuideText>? = null,
        val cash: Int? = null,
        val rewards: List<GuideText>? = null,
        val prints: List<Item.Cost>? = null,
        val extracts: List<Item.Cost>? = null,
        val tips: List<GuideText>? = null,
        val pageReward: GuideText? = null,
    ) {
        /** The DMZ level this row needs: a level-unlock row's level, or a "Lv 12" badge. */
        val requiredLevel: Int?
            get() {
                level?.let { return it }
                val text = value?.en ?: return null
                if (!text.startsWith("Lv ")) return null
                return text.drop(3).toIntOrNull()
            }

        /** Whether any of its text contains `needle` (already lowercased). */
        fun matches(needle: String): Boolean =
            listOf(title, value, subtitle).any { it?.resolved?.lowercase()?.contains(needle) == true }
    }

    @Serializable
    data class Section(
        val id: String,
        val title: GuideText,
        val symbol: String,
        val intro: GuideText? = null,
        val rows: List<Row>,
    )

    @Serializable
    data class Item(
        val id: String,
        val name: GuideText,
        /** The printer tab or kind: "Consumables", "Ingredient", "Key"... */
        val kind: String,
        val rarity: String? = null,
        val image: String? = null,
        /** SF Symbol for the base resources, which have no picture. */
        val symbol: String? = null,
        val unlock: GuideText? = null,
        val cost: List<Cost>? = null,
        /** DMZ Cash on top of `cost` (FOB upgrades). */
        val cash: Int? = null,
        val effect: GuideText? = null,
        /** Sell value in DMZ Cash. */
        val value: Int? = null,
        val note: GuideText? = null,
        val found: GuideText? = null,
        val foundPlaces: List<String>? = null,
        val grid: String? = null,
        val marker: String? = null,
        val family: String? = null,
        val tier: Int? = null,
        val blueprint: Boolean? = null,
    ) {
        @Serializable
        data class Cost(val item: String, val qty: Int)

        /** "Reach DMZ level 48" as 48. */
        val requiredLevel: Int?
            get() {
                val text = unlock?.en ?: return null
                val at = text.indexOf("level ")
                if (at < 0) return null
                return text.substring(at + 6).takeWhile { it.isDigit() }.toIntOrNull()
            }
    }

    @Serializable
    data class TraitTree(
        val id: String,
        val name: GuideText,
        val color: String,
        val shape: String,
        val rows: List<List<String?>>,
        val emblem: String? = null,
    )

    @Serializable
    data class Trait(
        val id: String,
        val name: GuideText? = null,
        val tree: String? = null,
        val effect: GuideText? = null,
        val icon: String? = null,
    )

    @Serializable
    data class MapInfo(val image: String, val credit: String? = null)

    private val itemById: Map<String, Item> by lazy { (items ?: emptyList()).associateBy { it.id } }
    private val markerById: Map<String, Marker> by lazy { markers.associateBy { it.id } }
    private val categoryById: Map<String, Category> by lazy { categories.associateBy { it.id } }

    fun trait(id: String): Trait? = traits?.firstOrNull { it.id == id }
    fun category(id: String): Category? = categoryById[id]
    fun item(id: String): Item? = itemById[id]
    fun marker(id: String): Marker? = markerById[id]
    fun section(id: String): Section? = guide.firstOrNull { it.id == id }

    /** Everything whose recipe or upgrade needs this item. */
    fun usedIn(id: String): List<Item> = (items ?: emptyList()).filter { item -> item.cost?.any { it.item == id } == true }

    /** One unticked DMZ Order's need for an item. */
    data class OrderNeed(val order: Row, val item: String, val qty: Int)

    /**
     * What the DMZ Orders not yet ticked need from the stash: each print's
     * recipe cost times how many, and the ingredients to extract.
     */
    fun orderNeeds(done: Set<String>): List<OrderNeed> {
        val orders = section("ops")?.rows?.filter { row -> row.check?.let { it !in done } ?: false } ?: emptyList()
        return orders.flatMap { order ->
            val printed = (order.prints ?: emptyList()).flatMap { print ->
                (item(print.item)?.cost ?: emptyList()).map { OrderNeed(order, it.item, it.qty * print.qty) }
            }
            printed + (order.extracts ?: emptyList()).map { OrderNeed(order, it.item, it.qty) }
        }
    }

    /** Every tier of an upgrade family, lowest first. */
    fun tiers(of: Item): List<Item> {
        val family = of.family ?: return emptyList()
        return (items ?: emptyList()).filter { it.family == family }.sortedBy { it.tier ?: 0 }
    }

    /** Guide rows that mention this item: where it drops, what rewards it. */
    fun mentions(id: String): List<Pair<Section, Row>> =
        guide.flatMap { section -> section.rows.filter { it.links?.contains(id) == true }.map { section to it } }

    fun threatName(level: Int): String? = threatLevels.getOrNull(level - 1)?.resolved

    companion object {
        /** Sections the player ticks off: they're on My DMZ, not in the guide. */
        val trackedSections = setOf("ops", "upgrades", "bosses", "gunsmith", "prestige")
    }
}

/** A pin the player drops on the map themselves. Kept on this device only (iOS HajinPin, id a UUID string). */
@Serializable
data class HajinPin(
    val id: String = java.util.UUID.randomUUID().toString().uppercase(),
    val x: Double,
    val y: Double,
    val title: String,
    val note: String,
)

/** One upgrade family collapsed to one row: later tiers live in the first tier's tabs. */
fun hajinCollapseTiers(rows: List<HajinGuide.Row>, guide: HajinGuide?): List<HajinGuide.Row> {
    val seen = mutableSetOf<String>()
    return rows.filter { row ->
        val item = row.item?.let { guide?.item(it) } ?: return@filter true
        val family = item.family ?: return@filter true
        if ((guide?.tiers(item)?.size ?: 0) <= 1) return@filter true
        seen.add(family)
    }
}

/** Consecutive rows that share a `group`, in order. */
fun hajinGroups(rows: List<HajinGuide.Row>): List<Pair<String?, List<HajinGuide.Row>>> {
    val out = mutableListOf<Pair<String?, MutableList<HajinGuide.Row>>>()
    for (row in rows) {
        val title = row.group?.resolved
        val last = out.lastOrNull()
        if (last != null && last.first == title) last.second.add(row) else out.add(title to mutableListOf(row))
    }
    return out
}
