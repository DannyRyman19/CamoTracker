package app.camotrack.android

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import java.net.URL
import java.util.Locale

/**
 * The same published data the iPhone app reads (Data/MW4 on jsDelivr), so
 * one publish feeds both apps. Only the fields this screen needs: unknown
 * keys are ignored, as the iPhone app's decoders do.
 */
object CamoData {
    private const val BASE = "https://cdn.jsdelivr.net/gh/DannyRyman19/CamoTracker@master/Data/MW4/"
    private val json = Json { ignoreUnknownKeys = true; isLenient = true }

    private suspend inline fun <reified T> load(file: String): T = withContext(Dispatchers.IO) {
        json.decodeFromString(URL(BASE + file).readText())
    }

    suspend fun mode(file: String): Tracker = coroutineScope {
        val weapons = async { load<WeaponsFile>("weapons.json") }
        val mode = async { load<ModeFile>(file) }
        Tracker(weapons.await(), mode.await())
    }
}

/** A text in each of the app's languages, read in the phone's. */
typealias Localized = Map<String, String>

fun Localized.resolved(): String =
    this[Locale.getDefault().language] ?: this["en"] ?: values.firstOrNull().orEmpty()

@Serializable
data class WeaponsFile(val version: String = "", val categories: List<Category> = emptyList())

@Serializable
data class Category(val categoryId: Int, val name: Localized, val weapons: List<Weapon> = emptyList())

@Serializable
data class Weapon(val weaponId: Int, val name: Localized, val maxLevel: Int = 0, val imageURL: String? = null)

@Serializable
data class ModeFile(val version: String = "", val mode: String = "", val weaponCamos: List<WeaponCamos> = emptyList())

@Serializable
data class WeaponCamos(val weaponId: Int, val camos: List<Camo> = emptyList())

@Serializable
data class Camo(
    val itemId: Int,
    val name: Localized,
    val imageURL: String? = null,
    val group: String? = null,
    val unlockLevel: Int? = null,
    val children: List<Camo> = emptyList(),
) {
    /** The camos to tick: a group's members, or the camo itself. */
    val leaves: List<Camo> get() = if (children.isEmpty()) listOf(this) else children.flatMap { it.leaves }
}

class Tracker(val weapons: WeaponsFile, val mode: ModeFile) {
    private val byWeapon = mode.weaponCamos.associateBy { it.weaponId }
    fun camos(weaponId: Int): List<Camo> = byWeapon[weaponId]?.camos.orEmpty().flatMap { it.leaves }
}
