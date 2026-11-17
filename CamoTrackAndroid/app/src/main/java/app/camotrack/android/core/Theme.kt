package app.camotrack.android.core

import kotlin.math.roundToInt

/** Colours are plain ARGB Ints in the core (0xFFRRGGBB); the UI wraps them in Compose's `Color`. */
object HexColor {
    /** "#RRGGBB" or "RRGGBB"; null for anything else, so a typo falls back to the built-in colour. */
    fun parse(hex: String): Int? {
        val digits = hex.trim().replace("#", "")
        if (digits.length != 6 || !digits.all { it in '0'..'9' || it in 'a'..'f' || it in 'A'..'F' }) return null
        return (0xFF000000L or digits.toLong(16)).toInt()
    }

    fun rgb(r: Double, g: Double, b: Double): Int =
        (0xFF shl 24) or ((r * 255).roundToInt() shl 16) or ((g * 255).roundToInt() shl 8) or (b * 255).roundToInt()

    fun toHex(color: Int): String = "#%06X".format(color and 0xFFFFFF)

    fun parseAll(hexes: List<String>?): List<Int> = hexes.orEmpty().mapNotNull(::parse)
}

/** The built-in colours from the iOS app's Theme.swift. */
object BuiltInColors {
    private fun rgb(r: Double, g: Double, b: Double) = HexColor.rgb(r, g, b)

    val accentMultiplayer = rgb(0.788, 0.271, 0.494)
    val accentMultiplayerText = rgb(0.878, 0.439, 0.627)
    val accentDMZText = rgb(0.918, 0.361, 0.439)

    val gold = rgb(0.831, 0.686, 0.216)
    val platinum = rgb(0.78, 0.82, 0.86)
    val harmonicBreak = rgb(0.82, 0.31, 0.30)
    val divergence = rgb(0.43, 0.61, 0.91)

    val mercurialDrift = rgb(0.878, 0.082, 0.498)
    val polyatomicReforged = rgb(0.357, 0.384, 0.878)
    val orionReforged = rgb(0.639, 0.251, 0.416)
    val parallax = rgb(0.761, 0.608, 0.769)
    val damascusReforged = rgb(0.082, 0.255, 0.776)
    val empyros = rgb(0.149, 0.627, 0.710)
    val chiral = rgb(0.757, 0.004, 0.004)
    val rippleTide = rgb(0.765, 0.584, 0.165)
    val helio = rgb(0.769, 0.141, 0.216)

    val accentWarzone = empyros
    val accentDMZ = helio

    val mercurialDriftGradient = listOf(mercurialDrift, rgb(1.00, 0.70, 0.28), rgb(1.00, 0.31, 0.64))
    val polyatomicReforgedGradient = listOf(polyatomicReforged, rgb(0.31, 0.85, 0.91), rgb(0.64, 0.36, 0.88))
    val orionReforgedGradient = listOf(orionReforged, rgb(0.89, 0.61, 0.75), rgb(0.35, 0.13, 0.25))
    val parallaxGradient = listOf(parallax, rgb(0.94, 0.87, 0.95), rgb(0.55, 0.42, 0.56))
    val damascusReforgedGradient = listOf(damascusReforged, rgb(1.00, 0.54, 0.36), rgb(0.88, 0.28, 0.62))
    val empyrosGradient = listOf(empyros, rgb(0.94, 0.42, 0.66), rgb(0.31, 0.88, 0.82))
    val chiralGradient = listOf(chiral, rgb(1.00, 0.25, 0.21), rgb(0.48, 0.0, 0.0))
    val rippleTideGradient = listOf(rippleTide, rgb(1.00, 0.83, 0.31), rgb(0.55, 0.27, 0.07))
    val helioGradient = listOf(helio, rgb(1.00, 0.42, 0.51), rgb(0.48, 0.06, 0.11))
    val goldGradient = listOf(gold, rgb(1.00, 0.93, 0.66), rgb(0.60, 0.46, 0.09))
    val platinumGradient = listOf(platinum, rgb(0.96, 0.98, 1.00), rgb(0.62, 0.68, 0.74))
    val harmonicBreakGradient = listOf(harmonicBreak, rgb(0.95, 0.61, 0.60), rgb(0.48, 0.21, 0.20))
    val divergenceGradient = listOf(divergence, rgb(0.91, 0.78, 0.29), rgb(0.90, 0.51, 0.25))

    /** The four Weapon Prestige camos' sets, in order. */
    val prestige: List<List<Int>> = listOf(
        listOf(rgb(0.61, 0.61, 0.59), rgb(0.85, 0.84, 0.82), rgb(0.36, 0.36, 0.33)),
        listOf(rgb(0.60, 0.58, 0.47), rgb(0.85, 0.82, 0.63), rgb(0.37, 0.35, 0.28)),
        listOf(rgb(0.61, 0.59, 0.44), rgb(0.78, 0.76, 0.49), rgb(0.43, 0.48, 0.29)),
        listOf(rgb(0.61, 0.77, 0.42), rgb(0.85, 0.94, 0.66), rgb(0.33, 0.45, 0.23)),
    )

    /** A Prestige camo's colours: the data's (two or more), else the built-in set for its place. */
    fun prestige(camo: PrestigeCamo, index: Int): List<Int> {
        val parsed = HexColor.parseAll(camo.colors)
        if (parsed.size > 1) return parsed
        return prestige[minOf(index, prestige.size - 1).coerceAtLeast(0)]
    }

    /** MW4's page/card colours, the default theme. */
    val background = rgb(0.043, 0.059, 0.051)
    val surface = rgb(0.082, 0.102, 0.090)
    val surface2 = rgb(0.114, 0.141, 0.125)
}

/**
 * One named camo with its colours: a Mastery tier or a Completionist step.
 * [nameKey] is a string resource key (the UI translates it); [nameOverride]
 * from the data wins over it.
 */
data class MasteryCamo(
    val nameKey: String,
    val color: Int,
    val gradient: List<Int>,
    val nameOverride: LocalizedText? = null,
    /** Mastery only: weapons with the final Completionist camo this tier needs, when the mode file sets it. */
    val weaponsNeeded: Int? = null,
    val imageURL: String? = null,
) {
    /** The data's name, or null when the UI should translate [nameKey]. */
    fun dataName(languages: List<String> = LocalizedText.preferredLanguages()): String? = nameOverride?.resolved(languages)

    /** This camo with a mode file's tier config laid over it: only the fields it sets change. */
    fun applying(config: MasteryTierConfig?): MasteryCamo {
        if (config == null) return this
        val camo = overriding(config.name, config.colors, config.imageURL)
        return camo.copy(weaponsNeeded = config.weaponsNeeded?.let { maxOf(1, it) } ?: weaponsNeeded)
    }

    fun overriding(name: LocalizedText?, colors: List<String>?, imageURL: String? = null): MasteryCamo {
        val parsed = HexColor.parseAll(colors)
        return copy(
            color = parsed.firstOrNull() ?: color,
            gradient = parsed.ifEmpty { gradient },
            nameOverride = name ?: nameOverride,
            imageURL = imageURL ?: this.imageURL,
        )
    }
}

/** A mode's Completionist camos: Gold, Platinum, Harmonic Break, then the final camo. */
data class CompletionistTrack(val steps: List<MasteryCamo>, val final: MasteryCamo)

/** The modes the player picked (Customise > Modes you play), stored as a comma-separated list. */
object ModeSelection {
    fun playedKey(game: Game) = game.key("mw4_played_modes", "played_modes")
    fun startKey(game: Game) = game.key("mw4_start_mode", "start_mode")

    /** The modes that get a tab, in the game's order. Never empty: none named means all. */
    fun played(raw: String, all: List<String>): List<String> {
        val picked = raw.split(",").filter { it.isNotEmpty() }.toSet()
        val modes = all.filter { it in picked }
        return modes.ifEmpty { all }
    }

    /** The picked start mode if it's still played, else the first played one. */
    fun start(raw: String, playedRaw: String, all: List<String>): String {
        val played = played(playedRaw, all)
        return if (raw in all && raw in played) raw else played[0]
    }

    /** The list after switching [mode] on or off; the last one left can't be switched off. */
    fun toggling(mode: String, raw: String, all: List<String>): String {
        val modes = played(raw, all).toMutableSet()
        if (mode in modes) {
            if (modes.size <= 1) return raw
            modes.remove(mode)
        } else {
            modes.add(mode)
        }
        return if (modes.size == all.size) "" else all.filter { it in modes }.joinToString(",")
    }
}
