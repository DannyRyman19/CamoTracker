package app.camotrack.android.ui

import android.icu.text.ListFormatter
import android.icu.text.MeasureFormat
import android.icu.util.Measure
import android.icu.util.MeasureUnit
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Groups
import androidx.compose.material.icons.filled.Inventory2
import androidx.compose.material.icons.filled.Movie
import androidx.compose.material.icons.filled.Psychology
import androidx.compose.material.icons.filled.SportsEsports
import androidx.compose.material.icons.filled.TrackChanges
import androidx.compose.runtime.Composable
import androidx.compose.runtime.MutableState
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp
import app.camotrack.android.AppState
import app.camotrack.android.core.GameTracker
import app.camotrack.android.core.MasteryCamo
import app.camotrack.android.core.ObjectiveScope
import app.camotrack.android.core.UnlockDate
import app.camotrack.android.core.UnlockDuration
import app.camotrack.android.i18n.L
import app.camotrack.android.i18n.Strings
import java.text.NumberFormat
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale
import kotlin.math.floor

/**
 * The current game's tracker, read so the calling composable recomposes on
 * every progress change. Use it in each composable that reads progress
 * (strong skipping would otherwise keep a row with the same arguments as it was).
 */
@Composable
fun tracker(): GameTracker {
    AppState.revision
    return AppState.tracker
}

/** The system face at a size (`.scaledFont` on iPhone, without Dynamic Type). */
fun sys(size: Float, weight: FontWeight = FontWeight.Normal, mono: Boolean = false): TextStyle =
    TextStyle(fontSize = size.sp, fontWeight = weight, fontFamily = if (mono) FontFamily.Monospace else FontFamily.Default)

val appLocale: Locale get() = Locale(Strings.language)

// MARK: - Modes

fun modeName(mode: String): String {
    val t = AppState.tracker
    return t.modeDefinition(mode)?.name?.resolved() ?: L(t.modeNameKey(mode))
}

fun modeAccent(mode: String): Color = Color(AppState.tracker.modeAccent(mode))
fun modeTextAccent(mode: String): Color = Color(AppState.tracker.modeTextAccent(mode))

/** The mode's symbol (iOS's SF Symbols, in Material's nearest). */
fun modeIcon(mode: String): ImageVector {
    val symbol = AppState.tracker.modeDefinition(mode)?.symbol
    return when {
        symbol?.startsWith("person") == true -> Icons.Filled.Groups
        symbol?.startsWith("circle") == true -> Icons.Filled.TrackChanges
        symbol?.startsWith("shippingbox") == true -> Icons.Filled.Inventory2
        symbol?.startsWith("brain") == true -> Icons.Filled.Psychology
        symbol?.startsWith("film") == true -> Icons.Filled.Movie
        symbol != null -> Icons.Filled.SportsEsports
        mode == "multiplayer" -> Icons.Filled.Groups
        mode == "warzone" -> Icons.Filled.TrackChanges
        mode == "dmz" -> Icons.Filled.Inventory2
        mode == "zombies" -> Icons.Filled.Psychology
        mode == "campaign" -> Icons.Filled.Movie
        else -> Icons.Filled.SportsEsports
    }
}

// MARK: - Camos

/** The camo's name: the data's, else the built-in one translated. */
val MasteryCamo.name: String get() = dataName() ?: L(nameKey)
val MasteryCamo.tint: Color get() = Color(color)
val MasteryCamo.colors: List<Color> get() = gradient.map { Color(it) }

fun colorsOf(argb: List<Int>): List<Color> = argb.map { Color(it) }

val GoldColors: List<Color> = listOf(Color(0xFFD4AF37), Color(0xFFFFEDA8), Color(0xFF997517))
val PlatinumColors: List<Color> = listOf(Color(0xFFC7D1DB), Color(0xFFF5FAFF), Color(0xFF9EADBD))
val CamoGold = Color(0xFFD4AF37)

// MARK: - Text

/** A 0...1 fraction as a whole percentage in the app's language, rounded down. */
fun percentText(fraction: Double): String {
    val whole = floor((fraction * 100).coerceIn(0.0, 100.0)) / 100
    return NumberFormat.getPercentInstance(appLocale).apply { maximumFractionDigits = 0 }.format(whole)
}

/** "Needs 17 weapon unlocks." / "Unlocks at weapon level 12." (`kind`: locked, earned, reach). */
fun levelGateText(t: GameTracker, level: Int, weaponId: Int, kind: String): String {
    val gate = t.levelGate(level, weaponId)
    return if (gate.countsUnlocks) L("mw4.ui.camo_unlocks_$kind", gate.value) else L("mw4.ui.camo_level_$kind", gate.value)
}

/** "12 Nov", or "12 Nov 2025" outside this year, in the reader's own order. */
fun earnedDayText(instant: Instant): String {
    val zone = ZoneId.systemDefault()
    val date = instant.atZone(zone).toLocalDate()
    val sameYear = date.year == java.time.LocalDate.now(zone).year
    val pattern = android.text.format.DateFormat.getBestDateTimePattern(appLocale, if (sameYear) "dMMM" else "dMMMyyyy")
    return DateTimeFormatter.ofPattern(pattern, appLocale).format(date)
}

/** "Ends 12 Nov" style day for an objective's end. */
fun shortDayText(instant: Instant): String {
    val pattern = android.text.format.DateFormat.getBestDateTimePattern(appLocale, "dMMM")
    return DateTimeFormatter.ofPattern(pattern, appLocale).format(instant.atZone(ZoneId.of("UTC")).toLocalDate())
}

fun UnlockDate.text(): String {
    val day = earnedDayText(Instant.ofEpochMilli((epochSeconds * 1000).toLong()))
    return when (kind) {
        UnlockDate.Kind.EXACT -> day
        UnlockDate.Kind.ESTIMATE -> "~$day"
        UnlockDate.Kind.ON_OR_BEFORE -> L("ct.ui.by_date", day)
    }
}

/** "6 days" or "5 hours", or "~6 days" from an estimate. */
fun UnlockDuration.text(): String {
    val format = MeasureFormat.getInstance(appLocale, MeasureFormat.FormatWidth.WIDE)
    val measure = if (seconds >= 86_400) Measure((seconds / 86_400).toInt(), MeasureUnit.DAY)
    else Measure((seconds / 3_600).toInt(), MeasureUnit.HOUR)
    val text = format.format(measure)
    return if (estimate) "~$text" else text
}

/** "All modes", "Warzone only", "Multiplayer and Warzone only". */
fun ObjectiveScope.label(): String = when (this) {
    ObjectiveScope.AllModes -> L("ct.objective.all_modes")
    is ObjectiveScope.Only -> L("ct.objective.only_in", ListFormatter.getInstance(appLocale).format(modes.map(::modeName)))
}

// MARK: - Settings shared between screens (iOS's @AppStorage)

/** One value per key, shared by every screen that reads it and kept in the app's store. */
object Prefs {
    private val strings = HashMap<String, MutableState<String>>()
    private val ints = HashMap<String, MutableState<Int>>()
    private val bools = HashMap<String, MutableState<Boolean>>()

    fun string(key: String, default: String): MutableState<String> = strings.getOrPut(key) {
        Stored(AppState.store.getString(key) ?: default) { AppState.store.putString(key, it) }
    }

    fun int(key: String, default: Int): MutableState<Int> = ints.getOrPut(key) {
        Stored(AppState.store.getInt(key) ?: default) { AppState.store.putInt(key, it) }
    }

    fun bool(key: String, default: Boolean): MutableState<Boolean> = bools.getOrPut(key) {
        Stored(AppState.store.getBoolean(key, default)) { AppState.store.putBoolean(key, it) }
    }

    private class Stored<T>(initial: T, private val save: (T) -> Unit) : MutableState<T> {
        private val state = mutableStateOf(initial)
        override var value: T
            get() = state.value
            set(v) { state.value = v; save(v) }
        override fun component1(): T = value
        override fun component2(): (T) -> Unit = { value = it }
    }

    const val SHOW_LOCKED = "mw4_show_locked_challenges"
    const val SPECIALS_FIRST = "mw4_specials_first"
    const val CARD_OUTLINE = "mw4_card_outline"
    const val PRESTIGE_CAMOS_OPEN = "mw4.prestigeCamosOpen"
}
