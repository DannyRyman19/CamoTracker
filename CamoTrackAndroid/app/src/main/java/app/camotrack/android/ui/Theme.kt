package app.camotrack.android.ui

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontVariation
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.sp
import app.camotrack.android.R

/** The iPhone app's colours (Theme.swift). A game's theme in games.json can
 *  replace the ground and surfaces, and its font (BO7 and BO6 use Teko). */
object Ink {
    val text = Color(0xFFEDEFEA)
    val muted = Color(0xFF8B958D)
}

object ModeColors {
    val multiplayer = Color(0xFFC9457E)
    val multiplayerText = Color(0xFFE070A0)
    val warzone = Color(0xFF26A0B5)
    val dmz = Color(0xFFC42437)
    val dmzText = Color(0xFFEA5C70)
    val zombies = Color(0xFF8CC63F)
    val campaign = Color(0xFFC9A24B)
    val gold = Color(0xFFD4AF37)

    fun accent(mode: String): Color = when (mode) {
        "multiplayer" -> multiplayer
        "warzone" -> warzone
        "dmz" -> dmz
        "zombies" -> zombies
        "campaign" -> campaign
        else -> multiplayer
    }

    /** For small text on a card, where the accent itself is too dark to read. */
    fun text(mode: String): Color = when (mode) {
        "multiplayer" -> multiplayerText
        "dmz" -> dmzText
        else -> accent(mode)
    }
}

/** "#C9457E" or "C9457E" as a Color, or null. */
fun hexColor(hex: String?): Color? {
    val h = hex?.removePrefix("#") ?: return null
    if (h.length != 6) return null
    return h.toLongOrNull(16)?.let { Color(0xFF000000 or it) }
}

@Immutable
data class AppPalette(
    val background: Color = Color(0xFF0B0F0D),
    val surface: Color = Color(0xFF151A17),
    val surface2: Color = Color(0xFF1D2420),
    val accent: Color = ModeColors.multiplayer,
    val display: FontFamily = Fonts.hitmarker,
    val displayScale: Float = 1f,
)

object Fonts {
    @OptIn(androidx.compose.ui.text.ExperimentalTextApi::class)
    val hitmarker = FontFamily(
        Font(R.font.hitmarker, FontWeight.Bold, variationSettings = FontVariation.Settings(FontVariation.weight(700))),
    )
    @OptIn(androidx.compose.ui.text.ExperimentalTextApi::class)
    val teko = FontFamily(
        Font(R.font.teko, FontWeight.SemiBold, variationSettings = FontVariation.Settings(FontVariation.weight(600))),
    )

    fun named(name: String?): FontFamily = if (name?.startsWith("Teko") == true) teko else hitmarker
}

val LocalPalette = staticCompositionLocalOf { AppPalette() }

/** The game's display face (titles, weapon names), as `.hitmarkerFont(size)` on iPhone. */
@Composable
fun displayStyle(size: TextUnit): TextStyle {
    val palette = LocalPalette.current
    return TextStyle(fontFamily = palette.display, fontWeight = FontWeight.Bold, fontSize = size * palette.displayScale)
}

@Composable
fun CamoTheme(palette: AppPalette, content: @Composable () -> Unit) {
    androidx.compose.runtime.CompositionLocalProvider(LocalPalette provides palette) {
        MaterialTheme(
            colorScheme = darkColorScheme(
                background = palette.background, surface = palette.surface, surfaceVariant = palette.surface2,
                primary = palette.accent, onBackground = Ink.text, onSurface = Ink.text,
            ),
            content = content,
        )
    }
}

val DefaultTextSize = 15.sp
