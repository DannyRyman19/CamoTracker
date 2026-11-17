package app.camotrack.android.ui

import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.painter.Painter
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.vector.rememberVectorPainter
import androidx.compose.ui.res.painterResource
import app.camotrack.android.R
import app.camotrack.android.core.WeaponCategory

/**
 * The app's own drawings (iOS Glyphs.swift, Assets.xcassets/Glyphs): tab
 * icons, modes, weapon classes, the DMZ guide's sections and the Tac Map's
 * markers. Single-colour, tinted like any icon. Copied from the iOS asset
 * catalog as res/drawable-nodpi/glyph_*.png.
 */
object Glyphs {
    val tabWeapons = R.drawable.glyph_tab_weapons
    val tabMastery = R.drawable.glyph_tab_mastery
    val tabStats = R.drawable.glyph_tab_stats
    val tabMap = R.drawable.glyph_tab_map

    /** A mode's drawing, by its id. BO7's Endgame is the `campaign` mode. */
    fun mode(id: String): Int? = when (id) {
        "multiplayer" -> R.drawable.glyph_mode_multiplayer
        "warzone" -> R.drawable.glyph_mode_warzone
        "dmz" -> R.drawable.glyph_mode_dmz
        "zombies" -> R.drawable.glyph_mode_zombies
        "campaign", "endgame" -> R.drawable.glyph_mode_endgame
        else -> null
    }

    /** A weapon class's silhouette, from its English name (the same across games: "Pistols", "Handguns"). */
    fun weaponClass(category: WeaponCategory): Int? {
        val en = (category.name.values["en"] ?: "").lowercase()
        val match = listOf(
            "assault" to R.drawable.glyph_class_assault, "battle" to R.drawable.glyph_class_battle,
            "smg" to R.drawable.glyph_class_smg, "submachine" to R.drawable.glyph_class_smg,
            "shotgun" to R.drawable.glyph_class_shotgun, "lmg" to R.drawable.glyph_class_lmg,
            "light machine" to R.drawable.glyph_class_lmg, "marksman" to R.drawable.glyph_class_marksman,
            "sniper" to R.drawable.glyph_class_sniper, "pistol" to R.drawable.glyph_class_pistol,
            "handgun" to R.drawable.glyph_class_pistol, "launcher" to R.drawable.glyph_class_launcher,
            "melee" to R.drawable.glyph_class_melee, "special" to R.drawable.glyph_class_special,
        )
        return match.firstOrNull { en.contains(it.first) }?.second
    }

    /** The DMZ guide's sections, by id; several share the Tac Map's art (a boss is the same skull). */
    val dmzSection: Map<String, Int> = mapOf(
        "levels" to R.drawable.glyph_dmz_levels, "recipes" to R.drawable.glyph_dmz_recipes,
        "resources" to R.drawable.glyph_dmz_resources, "stations" to R.drawable.glyph_dmz_stations,
        "upgrades" to R.drawable.glyph_dmz_upgrades, "gunsmith" to R.drawable.glyph_dmz_gunsmith,
        "bosses" to R.drawable.glyph_map_boss, "enemies" to R.drawable.glyph_dmz_enemies, "keys" to R.drawable.glyph_map_key,
        "valuables" to R.drawable.glyph_dmz_valuables, "kits" to R.drawable.glyph_dmz_kits, "threat" to R.drawable.glyph_dmz_threat,
        "infil" to R.drawable.glyph_map_spawn, "vehicles" to R.drawable.glyph_map_vehicle, "ops" to R.drawable.glyph_dmz_ops,
        "dynamic-ops" to R.drawable.glyph_map_phone, "rules" to R.drawable.glyph_dmz_rules, "prestige" to R.drawable.glyph_dmz_prestige,
        "traits" to R.drawable.glyph_dmz_traits,
        // Sections iOS reaches through other screens
        "blueprints" to R.drawable.glyph_dmz_blueprints, "build" to R.drawable.glyph_dmz_build,
        "keepsell" to R.drawable.glyph_dmz_keepsell, "shopping" to R.drawable.glyph_dmz_shopping,
        "tracking" to R.drawable.glyph_dmz_tracking,
    )

    /** A Tac Map category's drawing ("glyph_map_fortress"), by the category's id, or null. */
    @Composable
    fun mapCategory(id: String): Int? {
        val context = androidx.compose.ui.platform.LocalContext.current
        val res = context.resources.getIdentifier("glyph_map_${id.replace('-', '_')}", "drawable", context.packageName)
        return res.takeIf { it != 0 }
    }

    /** The drawing when there is one, else the Material icon. */
    @Composable
    fun painter(drawable: Int?, fallback: ImageVector): Painter =
        if (drawable != null) painterResource(drawable) else rememberVectorPainter(fallback)
}
