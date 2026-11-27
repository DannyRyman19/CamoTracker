package app.camotrack.android.core.hajin

import app.camotrack.android.core.CamoJson
import app.camotrack.android.core.KeyValueStore
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.builtins.MapSerializer
import kotlinx.serialization.builtins.serializer

/**
 * The player's DMZ: the guide, their map pins, ticks (bosses, orders,
 * upgrades, blueprints, operators' Prestige), DMZ level and cash, what's
 * tracked and the stash (iOS HajinStore). Saved under the iOS UserDefaults
 * keys; lists and dictionaries as the same JSON, as strings.
 *
 * `text` formats the few messages the store itself writes (the undo line):
 * the app passes `L`; tests leave the key.
 */
class HajinStore(
    private val store: KeyValueStore,
    guide: HajinGuide?,
    private val text: (String, Array<out Any?>) -> String = { key, _ -> key },
) {
    /** Called after every change, so the screens redraw. */
    var onChange: () -> Unit = {}

    var guide: HajinGuide? = guide
        private set

    var pins: List<HajinPin> = emptyList()
        private set
    /** Ticked rows (bosses taken down, orders done, upgrades printed...). */
    var checked: Set<String> = emptySet()
        private set
    /** The player's DMZ level; 0 until they set it, which leaves nothing shown as locked. */
    var dmzLevel = 0
        private set
    /** The player's DMZ Cash, as they last entered it (0 = not set). */
    var cash = 0
        private set
    /** Recipes and upgrades being worked towards, in the order tracked. */
    var tracked: List<String> = emptyList()
        private set
    /** How many of each ingredient or resource the player has. */
    var stash: Map<String, Int> = emptyMap()
        private set
    /** The last automatic stash change, offered for undo for a few seconds. */
    var stashUndo: StashUndo? = null
        private set

    class StashUndo(val message: String, val previous: Map<String, Int>, val previousTracked: List<String>) {
        val id: Long = nextUndoId++
    }

    init {
        pins = store.getString(PINS_KEY)?.let { runCatching { CamoJson.decodeFromString(ListSerializer(HajinPin.serializer()), it) }.getOrNull() }
            ?: emptyList()
        val savedChecks = readList(CHECKED_KEY).toSet()
        checked = withoutDuplicateOperators(savedChecks)
        if (checked != savedChecks) persist()
        dmzLevel = store.getInt(LEVEL_KEY) ?: 0
        cash = store.getInt(CASH_KEY) ?: 0
        tracked = readList(TRACKED_KEY)
        stash = store.getString(STASH_KEY)?.let {
            runCatching { CamoJson.decodeFromString(MapSerializer(String.serializer(), Int.serializer()), it) }.getOrNull()
        } ?: emptyMap()
    }

    /** A newer guide came down. */
    fun replaceGuide(newer: HajinGuide) {
        guide = newer
        onChange()
    }

    private fun readList(key: String): List<String> = store.getString(key)?.let {
        runCatching { CamoJson.decodeFromString(ListSerializer(String.serializer()), it) }.getOrNull()
    } ?: emptyList()

    private fun writeList(key: String, list: List<String>) =
        store.putString(key, CamoJson.encodeToString(ListSerializer(String.serializer()), list))

    private fun persist() {
        writeList(CHECKED_KEY, checked.sorted())
        store.putInt(LEVEL_KEY, dmzLevel)
        store.putInt(CASH_KEY, cash)
        writeList(TRACKED_KEY, tracked)
        store.putString(STASH_KEY, CamoJson.encodeToString(MapSerializer(String.serializer(), Int.serializer()), stash))
    }

    private fun saved() {
        persist()
        onChange()
    }

    // MARK: Sync (the iOS flat entries: a tick is its key, plus the level, cash, tracked order and stash)

    fun syncValues(): Map<String, Int> {
        val values = HashMap<String, Int>()
        for (key in checked) values[key] = 1
        if (dmzLevel > 0) values[LEVEL_SYNC_KEY] = dmzLevel
        if (cash > 0) values[CASH_SYNC_KEY] = cash
        tracked.forEachIndexed { index, id -> values["track:$id"] = index + 1 }
        for ((id, count) in stash) if (count > 0) values["stash:$id"] = count
        return values
    }

    /** Replaces My DMZ with another device's entries and saves it. */
    fun applySynced(values: Map<String, Int>) {
        val ticks = values.keys.filter { it != LEVEL_SYNC_KEY && it != CASH_SYNC_KEY && !it.startsWith("track:") && !it.startsWith("stash:") }.toSet()
        // An operator's Prestige set on two devices before they synced: the lower one goes
        checked = withoutDuplicateOperators(ticks)
        dmzLevel = values[LEVEL_SYNC_KEY] ?: 0
        cash = values[CASH_SYNC_KEY] ?: 0
        tracked = values.filter { it.key.startsWith("track:") }.entries.sortedBy { it.value }.map { it.key.removePrefix("track:") }
        stash = values.filter { it.key.startsWith("stash:") }.mapKeys { it.key.removePrefix("stash:") }
        saved()
    }

    // MARK: Pins

    fun addPin(pin: HajinPin) { setPins(pins + pin) }
    fun updatePin(pin: HajinPin) { setPins(pins.map { if (it.id == pin.id) pin else it }) }
    fun removePin(id: String) { setPins(pins.filter { it.id != id }) }

    private fun setPins(list: List<HajinPin>) {
        pins = list
        store.putString(PINS_KEY, CamoJson.encodeToString(ListSerializer(HajinPin.serializer()), list))
        onChange()
    }

    // MARK: Tracking

    fun isTracked(id: String) = id in tracked

    /** Track or untrack; returns false when five are already tracked. */
    fun toggleTracked(id: String): Boolean {
        if (id in tracked) {
            tracked = tracked - id
        } else {
            if (tracked.size >= MAX_TRACKED) return false
            tracked = tracked + id
        }
        saved()
        return true
    }

    // MARK: Stash

    fun count(of: String): Int = stash[of] ?: 0

    fun setCount(count: Int, of: String) {
        val clamped = count.coerceIn(0, 99_999)
        stash = if (clamped == 0) stash - of else stash + (of to clamped)
        saved()
    }

    /** A photo read's counts, set in one go and offered for undo (iOS applyScannedCounts). */
    fun applyScannedCounts(counts: Map<String, Int>) {
        if (counts.isEmpty()) return
        val previous = stash
        val previousTracked = tracked
        val next = stash.toMutableMap()
        for ((id, count) in counts) {
            val n = count.coerceIn(0, 99_999)
            if (n == 0) next.remove(id) else next[id] = n
        }
        stash = next
        stashUndo = StashUndo(text("mw4.ui.hajin.scan_updated", arrayOf(counts.size)), previous, previousTracked)
        saved()
    }

    /** The recipe is unlocked and the stash covers every part of its cost (or an upgrade's). */
    fun canPrint(item: HajinGuide.Item): Boolean {
        val cost = item.cost
        if (cost.isNullOrEmpty() || stash.isEmpty() || !hasRecipe(item) || !affords(item)) return false
        return cost.all { count(it.item) >= it.qty }
    }

    /** Whether the DMZ Cash entered covers it. Something with a price never counts as affordable while cash isn't entered. */
    fun affords(item: HajinGuide.Item): Boolean {
        val price = item.cash ?: return true
        if (price <= 0) return true
        return cash >= price
    }

    /**
     * Whether the player can print it at all: a blueprint once ticked found,
     * a level one at that level (or no level set), an Uncommon or Epic
     * ingredient once that Ingredient Printing upgrade is ticked.
     */
    fun hasRecipe(item: HajinGuide.Item): Boolean {
        if (item.blueprint == true) return hasBlueprint(item.id)
        if (isLocked(item.requiredLevel)) return false
        val needs = item.effect?.en
        if (needs != null) {
            val match = Regex("""Needs (\w+) Ingredient Printing""").find(needs)
            if (match != null) {
                val upgrade = match.value.removePrefix("Needs ").lowercase().replace(" ", "-")
                return "upgrade-$upgrade" in checked
            }
        }
        return true
    }

    data class BuildPick(val item: HajinGuide.Item, val covered: Double, val missing: List<Pair<String, Int>>)

    /**
     * What to print next: the next unprinted tier of each FOB upgrade,
     * printable ones first, then by how much of the cost the stash covers,
     * cheapest first on a tie.
     */
    fun buildNext(limit: Int = 3): List<BuildPick> {
        val guide = guide ?: return emptyList()
        val families = linkedMapOf<String, MutableList<HajinGuide.Item>>()
        for (upgrade in (guide.items ?: emptyList()).filter { it.kind == "FOB Upgrade" }) {
            families.getOrPut(upgrade.family ?: upgrade.id) { mutableListOf() }.add(upgrade)
        }
        val next = families.values.mapNotNull { tiers -> tiers.sortedBy { it.tier ?: 0 }.firstOrNull { "upgrade-${it.id}" !in checked } }
        return next.map { item ->
            val cost = item.cost ?: emptyList()
            val need = cost.sumOf { it.qty }
            val have = cost.sumOf { minOf(count(it.item), it.qty) }
            val missing = cost.mapNotNull { part -> (part.qty - count(part.item)).takeIf { it > 0 }?.let { part.item to it } }
            // Cash only: nothing to gather, so it sits just under the printable ones
            BuildPick(item, if (need == 0) 0.99 else have.toDouble() / need, missing)
        }
            .sortedWith(compareByDescending<BuildPick> { it.covered }.thenBy { it.item.cash ?: 0 })
            .take(limit)
    }

    /** Whether a row's item (or the upgrade tier still to print) can be printed: its card goes green. */
    fun printable(row: HajinGuide.Row): Boolean {
        val item = row.item?.let { guide?.item(it) } ?: return false
        val next = nextToPrint(item) ?: return false
        return canPrint(next)
    }

    /** The tier of an upgrade still to print, or the item itself when it isn't an upgrade; null once every tier is done. */
    fun nextToPrint(item: HajinGuide.Item): HajinGuide.Item? {
        if (item.kind != "FOB Upgrade") return item
        val tiers = guide?.tiers(item) ?: emptyList()
        return (tiers.ifEmpty { listOf(item) }).firstOrNull { "upgrade-${it.id}" !in checked }
    }

    /** Everything still missing for the tracked items, biggest shortfall first. */
    fun shortfall(guide: HajinGuide): List<Pair<HajinGuide.Item, Int>> {
        val need = linkedMapOf<String, Int>()
        for (id in tracked) for (part in guide.item(id)?.cost ?: emptyList()) need[part.item] = (need[part.item] ?: 0) + part.qty
        return need.mapNotNull { (id, qty) ->
            val item = guide.item(id) ?: return@mapNotNull null
            val missing = qty - count(id)
            if (missing > 0) item to missing else null
        }.sortedWith { a, b -> if (a.second == b.second) a.first.name.resolved.compareTo(b.first.name.resolved) else b.second - a.second }
    }

    // MARK: Ticks

    fun toggle(key: String) {
        if (key in checked) {
            checked = checked - key
        } else {
            checked = checked + key
            // Ticking an upgrade as printed uses up what it cost
            if (key.startsWith("upgrade-")) spend(key.removePrefix("upgrade-"))
        }
        saved()
    }

    /** Takes a printed item's ingredients out of the stash (only what's there) and stops tracking it, keeping the old state for Undo. */
    private fun spend(id: String) {
        val item = guide?.item(id) ?: return
        val previous = stash
        val previousTracked = tracked
        val taken = mutableListOf<String>()
        val next = stash.toMutableMap()
        for (part in item.cost ?: emptyList()) {
            val have = next[part.item] ?: 0
            if (have <= 0) continue
            val used = minOf(have, part.qty)
            if (have - used == 0) next.remove(part.item) else next[part.item] = have - used
            taken += "$used ${guide?.item(part.item)?.name?.resolved ?: part.item}"
        }
        stash = next
        val wasTracked = id in tracked
        tracked = tracked - id
        if (taken.isEmpty() && !wasTracked) return
        val message = if (taken.isEmpty()) text("mw4.ui.hajin.untracked_printed", arrayOf(item.name.resolved))
        else text("mw4.ui.hajin.took_from_stash", arrayOf(taken.joinToString(", ")))
        stashUndo = StashUndo(message, previous, previousTracked)
    }

    /** Puts the stash (and tracking) back as it was before the last spend. */
    fun undoStash() {
        val undo = stashUndo ?: return
        stash = undo.previous
        tracked = undo.previousTracked
        stashUndo = null
        saved()
    }

    /** The undo offer timed out. */
    fun clearUndo(id: Long) {
        if (stashUndo?.id == id) {
            stashUndo = null
            onChange()
        }
    }

    fun setCash(amount: Int) {
        cash = amount.coerceIn(0, 99_999_999)
        saved()
    }

    fun setLevel(level: Int) {
        dmzLevel = level.coerceIn(0, MAX_LEVEL)
        saved()
    }

    /** Locked only once a level is set and it's below what's needed. */
    fun isLocked(required: Int?): Boolean {
        if (required == null || dmzLevel <= 0) return false
        return required > dmzLevel
    }

    // MARK: Map filter

    /**
     * Categories the player switched off on the map. Starts from each
     * category's own `visible` default until they touch a filter, and so
     * does any category added since they last did.
     */
    var hiddenCategories: Set<String>
        get() {
            val categories = guide?.categories ?: emptyList()
            if (!store.contains(HIDDEN_KEY)) return categories.filter { !it.visible }.map { it.id }.toSet()
            val saved = readList(HIDDEN_KEY)
            val seen = if (store.contains(SEEN_CATEGORIES_KEY)) readList(SEEN_CATEGORIES_KEY).toSet() else FIRST_CATEGORIES
            return saved.toSet() + categories.filter { !it.visible && it.id !in seen }.map { it.id }
        }
        set(value) {
            writeList(HIDDEN_KEY, value.sorted())
            writeList(SEEN_CATEGORIES_KEY, (guide?.categories ?: emptyList()).map { it.id })
            onChange()
        }

    /** Makes sure a marker's category is showing before flying to it. */
    fun reveal(marker: HajinGuide.Marker) {
        val hidden = hiddenCategories
        if (marker.cat in hidden) hiddenCategories = hidden - marker.cat
    }

    // MARK: Blueprints and manuals

    fun hasBlueprint(id: String) = blueprintKey(id) in checked
    /** Every recipe you find in Hajin, printer tab by printer tab. */
    val blueprints: List<HajinGuide.Item> get() = (guide?.items ?: emptyList()).filter { it.blueprint == true }

    /** The Gunsmith's weapons that need their Manual extracted (starters don't), ticked as "manual-<weaponId>". */
    val manualRows: List<HajinGuide.Row>
        get() = (guide?.section("gunsmith")?.rows ?: emptyList()).filter { it.weapon != null && it.subtitle?.en?.startsWith("Starter") != true }

    fun hasManual(row: HajinGuide.Row) = row.weapon?.let { "manual-$it" in checked } ?: false

    /** Blueprints and Manuals found, out of all of them. */
    val findProgress: Pair<Int, Int>
        get() {
            val rows = manualRows
            val prints = blueprints
            return (prints.count { hasBlueprint(it.id) } + rows.count { hasManual(it) }) to (prints.size + rows.size)
        }

    // MARK: Operator Prestige

    data class Operator(val name: String, val level: Int)

    val operators: List<Operator>
        get() = operatorLevels(checked).map { Operator(it.key, it.value) }.sortedWith(compareBy(String.CASE_INSENSITIVE_ORDER) { it.name })

    fun prestigeTraits(of: String): List<String> = checked.mapNotNull { key ->
        val parts = key.split("|")
        if (parts.size == 3 && parts[0] == "prestige-trait" && parts[1] == of) parts[2] else null
    }.sorted()

    fun addOperator(raw: String) {
        val name = raw.replace("|", " ").trim()
        if (name.isEmpty() || operators.any { it.name.equals(name, ignoreCase = true) }) return
        checked = checked + "prestige|$name|0"
        saved()
    }

    fun setPrestige(level: Int, of: String) {
        checked = checked.filter { !it.startsWith("prestige|$of|") }.toSet() + "prestige|$of|${level.coerceIn(0, 99)}"
        saved()
    }

    fun removeOperator(name: String) {
        checked = checked.filter { !it.startsWith("prestige|$name|") && !it.startsWith("prestige-trait|$name|") }.toSet()
        saved()
    }

    /** Adds or removes a Prestige trait; an operator holds three at most. */
    fun togglePrestigeTrait(trait: String, of: String) {
        val key = "prestige-trait|$of|$trait"
        if (key in checked) {
            checked = checked - key
        } else {
            if (prestigeTraits(of).size >= MAX_PRESTIGE_TRAITS) return
            checked = checked + key
        }
        saved()
    }

    // MARK: Shopping list

    enum class ShoppingScope(val raw: String) { UPGRADES("upgrades"), TRACKED("tracked") }

    data class ShoppingLine(val item: HajinGuide.Item, val need: Int, val have: Int, val users: List<Pair<HajinGuide.Item, Int>>) {
        val missing: Int get() = maxOf(0, need - have)
    }

    /** What the scope still asks for: every FOB upgrade not ticked as done, or just what's tracked. */
    fun shoppingTargets(scope: ShoppingScope): List<HajinGuide.Item> {
        val guide = guide ?: return emptyList()
        return when (scope) {
            ShoppingScope.UPGRADES -> (guide.items ?: emptyList()).filter { it.kind == "FOB Upgrade" && "upgrade-${it.id}" !in checked }
            ShoppingScope.TRACKED -> tracked.mapNotNull { guide.item(it) }
        }
    }

    /** Every ingredient the targets need, added up and set against the stash, most still to find first. */
    fun shoppingList(scope: ShoppingScope): List<ShoppingLine> {
        val guide = guide ?: return emptyList()
        val need = linkedMapOf<String, Int>()
        val users = linkedMapOf<String, MutableList<Pair<HajinGuide.Item, Int>>>()
        for (target in shoppingTargets(scope)) for (part in target.cost ?: emptyList()) {
            need[part.item] = (need[part.item] ?: 0) + part.qty
            users.getOrPut(part.item) { mutableListOf() }.add(target to part.qty)
        }
        return need.mapNotNull { (id, qty) ->
            val item = guide.item(id) ?: return@mapNotNull null
            ShoppingLine(item, qty, count(id), users[id] ?: emptyList())
        }.sortedWith(compareByDescending<ShoppingLine> { it.missing }.thenBy { it.item.name.resolved })
    }

    // MARK: Spare to sell

    data class SpareLine(val item: HajinGuide.Item, val count: Int, val worth: Int)

    /** The Spare to sell options (iOS @AppStorage), read from the store. */
    val spareKeepsTracked: Boolean get() = store.getBoolean(SPARE_TRACKED_KEY, true)
    val spareBuffer: Int get() = store.getInt(SPARE_BUFFER_KEY) ?: 0
    val spareKeepsRecipes: Boolean get() = store.getBoolean(SPARE_RECIPES_KEY, true)
    val spareKeepsOrders: Boolean get() = store.getBoolean(SPARE_ORDERS_KEY, true)

    /**
     * What the stash holds beyond what the unfinished FOB upgrades still need
     * (and, as the player chooses, one print of every recipe they have, what
     * tracked items need and a buffer of each), with its worth: most valuable first.
     */
    fun spare(): Pair<List<SpareLine>, Int> {
        val guide = guide ?: return emptyList<SpareLine>() to 0
        val need = keepNeeds()
        val lines = stash.mapNotNull { (id, have) ->
            val item = guide.item(id) ?: return@mapNotNull null
            val value = item.value ?: return@mapNotNull null
            if (value <= 0) return@mapNotNull null
            val extra = have - (need[id] ?: 0)
            if (extra > 0) SpareLine(item, extra, extra * value) else null
        }.sortedByDescending { it.worth }
        return lines to lines.sumOf { it.worth }
    }

    /** How many of each item to hold on to, by the Spare to sell options. */
    fun keepNeeds(): Map<String, Int> {
        val guide = guide ?: return emptyMap()
        val need = mutableMapOf<String, Int>()
        for (line in shoppingList(ShoppingScope.UPGRADES)) need[line.item.id] = line.need
        if (spareKeepsOrders) for (order in guide.orderNeeds(checked)) need[order.item] = (need[order.item] ?: 0) + order.qty
        val recipes = mutableSetOf<String>()
        if (spareKeepsRecipes) {
            for (item in guide.items ?: emptyList()) {
                if (item.kind != "FOB Upgrade" && !item.cost.isNullOrEmpty() && hasRecipe(item)) recipes += item.id
            }
        }
        if (spareKeepsTracked) for (id in tracked) if (guide.item(id)?.kind != "FOB Upgrade") recipes += id
        for (id in recipes) for (part in guide.item(id)?.cost ?: emptyList()) need[part.item] = (need[part.item] ?: 0) + part.qty
        val buffer = spareBuffer
        if (buffer > 0) for (item in guide.items ?: emptyList()) if (item.kind == "Ingredient") need[item.id] = (need[item.id] ?: 0) + buffer
        return need
    }

    companion object {
        private const val LEVEL_SYNC_KEY = "dmz-level"
        private const val CASH_SYNC_KEY = "dmz-cash"
        const val PINS_KEY = "mw4_hajin_pins"
        const val CHECKED_KEY = "mw4_hajin_checked"
        const val LEVEL_KEY = "mw4_hajin_dmz_level"
        const val CASH_KEY = "mw4_hajin_cash"
        const val TRACKED_KEY = "mw4_hajin_tracked"
        const val STASH_KEY = "mw4_hajin_stash"
        const val HIDDEN_KEY = "mw4_hajin_hidden_categories"
        const val SEEN_CATEGORIES_KEY = "mw4_hajin_seen_categories"
        const val SPARE_TRACKED_KEY = "mw4_hajin_spare_tracked"
        const val SPARE_BUFFER_KEY = "mw4_hajin_spare_buffer"
        const val SPARE_RECIPES_KEY = "mw4_hajin_spare_recipes"
        const val SPARE_ORDERS_KEY = "mw4_hajin_spare_orders"
        /** The game tracks five things at once; so does the app. */
        const val MAX_TRACKED = 5
        const val MAX_LEVEL = 70
        const val MAX_PRESTIGE_TRAITS = 3

        private var nextUndoId = 1L

        /** The categories before `SEEN_CATEGORIES_KEY` was saved. */
        private val FIRST_CATEGORIES = setOf("area", "place", "fortress", "compound", "lieutenant", "uav", "key",
            "cache", "clinic", "fire", "police", "gas", "marine")

        /** Resources in the game's order: the backpack's Sort column, top down. */
        val resourceOrder = listOf("synthetics", "electronics", "chemicals", "metals")
        fun resourceRank(id: String): Int = resourceOrder.indexOf(id).let { if (it < 0) resourceOrder.size else it }

        /** What My stash counts: resources, ingredients and valuables, less dog tags. */
        fun inStash(item: HajinGuide.Item): Boolean =
            item.kind in setOf("Resource", "Ingredient", "Valuable") && !item.id.contains("dog-tag")

        fun blueprintKey(id: String) = "blueprint-$id"

        /** Each operator's Prestige in `ticks`, the highest where there are two. */
        fun operatorLevels(ticks: Set<String>): Map<String, Int> {
            val levels = mutableMapOf<String, Int>()
            for (key in ticks) {
                val parts = key.split("|")
                if (parts.size != 3 || parts[0] != "prestige") continue
                val level = parts[2].toIntOrNull() ?: continue
                levels[parts[1]] = maxOf(levels[parts[1]] ?: level, level)
            }
            return levels
        }

        /** `ticks` with one Prestige per operator (two devices that each set it before syncing leave both); the highest stays. */
        fun withoutDuplicateOperators(ticks: Set<String>): Set<String> {
            val levels = operatorLevels(ticks)
            return ticks.filter { key ->
                val parts = key.split("|")
                if (parts.size != 3 || parts[0] != "prestige") return@filter true
                val level = parts[2].toIntOrNull() ?: return@filter true
                levels[parts[1]] == level
            }.toSet()
        }
    }
}

/**
 * Whether a looted item is worth keeping, worked out from every recipe and
 * FOB upgrade that needs it, and the DMZ Orders that print with it, minus the
 * upgrades and orders ticked as done (iOS HajinVerdict).
 */
class HajinVerdict(item: HajinGuide.Item, guide: HajinGuide, done: Set<String>) {
    enum class Kind { KEEP, CRAFTING, SELL, USE, RESOURCE }

    val kind: Kind
    /** Unfinished upgrades that need it, with amounts. */
    val upgrades: List<Pair<HajinGuide.Item, Int>>
    /** Recipes that use it. */
    val recipes: List<Pair<HajinGuide.Item, Int>>
    /** Unticked DMZ Orders that need it, with amounts. */
    val orders: List<Pair<HajinGuide.Row, Int>>
    val value: Int? = item.value
    val itemKind: String = item.kind

    init {
        val users = guide.usedIn(item.id).map { user -> user to (user.cost?.firstOrNull { it.item == item.id }?.qty ?: 0) }
        upgrades = users.filter { it.first.kind == "FOB Upgrade" && "upgrade-${it.first.id}" !in done }
        recipes = users.filter { it.first.kind != "FOB Upgrade" }
        val orders = mutableListOf<Pair<HajinGuide.Row, Int>>()
        for (need in guide.orderNeeds(done)) {
            if (need.item != item.id) continue
            val i = orders.indexOfFirst { it.first == need.order }
            if (i >= 0) orders[i] = orders[i].first to orders[i].second + need.qty else orders += need.order to need.qty
        }
        this.orders = orders
        kind = when {
            item.kind == "Resource" -> Kind.RESOURCE
            upgrades.isNotEmpty() || orders.isNotEmpty() -> Kind.KEEP
            recipes.isNotEmpty() -> Kind.CRAFTING
            item.kind == "Key" || item.kind !in setOf("Ingredient", "Valuable") -> Kind.USE
            else -> Kind.SELL
        }
    }

    companion object {
        /** Only loot you'd weigh up selling gets a verdict: materials and valuables. */
        fun applies(item: HajinGuide.Item) = item.kind == "Ingredient" || item.kind == "Valuable"
    }
}
