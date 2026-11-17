package app.camotrack.android.widgets

import android.content.Context
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import java.io.File

/**
 * What the home-screen widgets show (iOS WidgetSnapshot), written by the app
 * whenever progress changes and read as is by the widgets. Every string is
 * already in the app's language, so the widgets carry no translations of
 * their own beyond their picker names and empty states.
 */
@Serializable
data class WidgetSnapshot(
    val modes: List<Mode>,
    val pinned: Pinned? = null,
    /** Average of the played modes' fractions (Stats' overall ring). */
    val overall: Double,
    val overallLabel: String,
    val pinPrompt: String,
    val allDoneLabel: String,
    /** "Mastery", over the three Mastery bars. */
    val masteryLabel: String? = null,
    /** The game it's for ("bo7") and its short name ("BO7"). */
    val game: String? = null,
    val gameName: String? = null,
    /** The mode the app opens on: what a Mode progress widget shows until one is picked (Android only). */
    val startMode: String? = null,
) {
    @Serializable
    data class Mode(
        /** "multiplayer", "warzone", "dmz"... */
        val id: String,
        val name: String,
        /** "#RRGGBB", the mode's accent. */
        val accentHex: String,
        /** The mode's full-track completion, 0..1 (Stats' ring). */
        val fraction: Double,
        val weaponCount: Int,
        /** Weapons with each Completionist camo, in order (Gold, Platinum, Harmonic Break, then the final camo). */
        val steps: List<Step>,
        /** The three Mastery camos and how far through each is (none for a game without account Mastery). */
        val mastery: List<Step>,
    )

    @Serializable
    data class Step(val name: String, val done: Int, val total: Int, val colorHex: String)

    /** The pinned weapon, as it stands in the mode the app opens on. */
    @Serializable
    data class Pinned(
        val weaponId: Int,
        val name: String,
        val category: String,
        val mode: String,
        val modeName: String,
        val accentHex: String,
        val camosDone: Int,
        val camosTotal: Int,
        /** The next camo to earn, its challenge, and how far through it is. */
        val nextName: String? = null,
        val nextDetail: String? = null,
        val nextDone: Int = 0,
        val nextTotal: Int = 1,
    )

    /** "BO7 Multiplayer": a mode's name after its game's. */
    fun titled(name: String): String = gameName?.let { "$it $name" } ?: name

    companion object {
        private val json = Json { ignoreUnknownKeys = true }

        fun encode(snapshot: WidgetSnapshot): String = json.encodeToString(snapshot)
        fun decode(text: String): WidgetSnapshot? = runCatching { json.decodeFromString<WidgetSnapshot>(text) }.getOrNull()

        /** The current game's snapshot (null `game`), or one game's own: each game keeps its own, written while it's open. */
        fun file(context: Context, game: String? = null): File =
            File(File(context.filesDir, "widgets"), game?.let { "widget-snapshot-$it.json" } ?: "widget-snapshot.json")

        fun load(context: Context, game: String? = null): WidgetSnapshot? =
            runCatching { file(context, game).takeIf { it.exists() }?.readText() }.getOrNull()?.let(::decode)

        /** The link a widget opens: a mode tab, or one weapon in a mode, in the game the widget shows. */
        fun link(mode: String, weaponId: Int? = null, game: String? = null): String = buildString {
            append("mw4camo://mode/").append(mode)
            if (weaponId != null) append("/weapon/").append(weaponId)
            if (game != null) append("?game=").append(game)
        }
    }
}
