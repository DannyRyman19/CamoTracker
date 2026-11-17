package app.camotrack.android.core

import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer

/** One Call of Duty game the app tracks, as listed in `games.json`. */
@Serializable
data class Game(
    val id: String,
    val name: LocalizedText,
    val shortName: String,
    /** Folder on the CDN under the repo root, e.g. "Data/MW4/" */
    val path: String,
    /** Bundled seed files are named `<seedPrefix><file>.json` */
    val seedPrefix: String,
    val modes: List<GameMode>,
    val countsUnlocks: Boolean? = null,
    val levelCategories: List<Int>? = null,
    val hasMastery: Boolean? = null,
    val sharedCamos: Boolean? = null,
    val theme: GameTheme? = null,
    val capstone: CapstoneCamo? = null,
    val legacyApp: String? = null,
) {
    val dataURL: String get() = DATA_BASE + path
    val dataMirrorURL: String get() = MIRROR_BASE + path

    val isMW4: Boolean get() = id == "mw4"

    /** The Hajin tab (DMZ map and guide): MW4 only. */
    val hasHajin: Boolean get() = isMW4

    /** MW4 keeps its original keys; every other game gets `ct_<name>_<id>`. */
    fun key(mw4: String, name: String): String = if (isMW4) mw4 else "ct_${name}_$id"

    val modeIds: List<String> get() = modes.map { it.id }

    /** The game has account-wide Mastery camos. */
    val hasAccountMastery: Boolean get() = hasMastery != false

    override fun equals(other: Any?): Boolean = other is Game && other.id == id
    override fun hashCode(): Int = id.hashCode()

    companion object {
        const val DATA_BASE = "https://cdn.jsdelivr.net/gh/DannyRyman19/CamoTracker@master/"
        const val MIRROR_BASE = "https://raw.githubusercontent.com/DannyRyman19/CamoTracker/master/"
    }
}

@Serializable
data class GameTheme(
    val background: String? = null,
    val surface: String? = null,
    val surface2: String? = null,
    val font: String? = null,
    val fontScale: Double? = null,
    val fontWeight: String? = null,
    val tint: String? = null,
    val mark: String? = null,
    val markWhite: Int? = null,
    val markColor: String? = null,
    val accent: String? = null,
)

/** A camo earned across the whole game (MW4's Flashpoint, BO7's Nexus Horizon). */
@Serializable
data class CapstoneCamo(
    val name: LocalizedText,
    val imageURL: String? = null,
    val colors: List<String>? = null,
)

@Serializable
data class GameMode(
    val id: String,
    val name: LocalizedText? = null,
    val symbol: String? = null,
    val accent: String? = null,
    /** The weapon classes this mode covers; absent = every class. */
    val categories: List<Int>? = null,
) {
    override fun equals(other: Any?): Boolean = other is GameMode && other.id == id
    override fun hashCode(): Int = id.hashCode()
}

/** The games the app knows. */
object GameRegistry {
    /** Where the picked game is kept. */
    const val KEY = "ct_game"

    /** MW4 as shipped, should `games.json` be missing. */
    val fallback = Game(
        id = "mw4", name = LocalizedText("Modern Warfare 4"), shortName = "MW4", path = "Data/MW4/", seedPrefix = "",
        modes = listOf(GameMode("multiplayer"), GameMode("warzone"), GameMode("dmz")),
        countsUnlocks = true, levelCategories = listOf(7, 8), sharedCamos = true,
    )

    /** `games.json`'s list, or MW4 alone when it's missing or unreadable. */
    fun parse(json: String?): List<Game> {
        val games = json?.let { runCatching { CamoJson.decodeFromString(ListSerializer(Game.serializer()), it) }.getOrNull() }
        return if (games.isNullOrEmpty()) listOf(fallback) else games
    }

    fun load(seeds: SeedSource): List<Game> = parse(seeds.read("games.json"))

    /** The game picked last time, else the first. */
    fun saved(games: List<Game>, store: KeyValueStore): Game =
        store.getString(KEY)?.let { id -> games.firstOrNull { it.id == id } } ?: games[0]
}
