package app.camotrack.android.widgets

import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RectF
import android.net.Uri
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.datastore.preferences.core.Preferences
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.Image
import androidx.glance.ImageProvider
import androidx.glance.LocalContext
import androidx.glance.LocalSize
import androidx.glance.action.clickable
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import androidx.glance.appwidget.SizeMode
import androidx.glance.appwidget.action.actionStartActivity
import androidx.glance.appwidget.appWidgetBackground
import androidx.glance.appwidget.provideContent
import androidx.glance.background
import androidx.glance.currentState
import androidx.glance.layout.Alignment
import androidx.glance.layout.Box
import androidx.glance.layout.Column
import androidx.glance.layout.ColumnScope
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxHeight
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.height
import androidx.glance.layout.padding
import androidx.glance.layout.size
import androidx.glance.layout.width
import androidx.glance.state.GlanceStateDefinition
import androidx.glance.state.PreferencesGlanceStateDefinition
import androidx.glance.text.FontFamily
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextAlign
import androidx.glance.text.TextStyle
import androidx.glance.unit.ColorProvider
import app.camotrack.android.MainActivity
import app.camotrack.android.R
import app.camotrack.android.i18n.L
import java.util.Locale
import kotlin.math.roundToInt

// The three home-screen widgets (iOS MW4Widgets + WidgetViews): each reads the
// snapshot the app writes (WidgetSync) for its game, the one open in the app
// unless a game was picked when setting the widget up (WidgetConfigActivity).

private val Background = Color(0xFF121214)     // iOS widgetBackground (0.07, 0.07, 0.08)
private val Accent = Color(0xFFC21C08)         // iOS widgetAccent
private val Gold = Color(0xFFD4AF37)           // iOS widgetGold
private val Heavy = FontFamily("sans-serif-black")

/** Shared by the three: Exact sizes (so a 2×2 and a 4×2 lay out differently), per-widget state, the dark ground. */
abstract class CamoWidget : GlanceAppWidget() {
    override val sizeMode: SizeMode = SizeMode.Exact
    override val stateDefinition: GlanceStateDefinition<*> = PreferencesGlanceStateDefinition

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        provideContent {
            val prefs = currentState<Preferences>()
            val stamp = prefs[WidgetSync.STAMP]
            val game = prefs[WidgetSync.GAME]?.takeIf { it.isNotEmpty() }
            val snapshot = remember(stamp, game) { WidgetSnapshot.load(context, game) }
            Box(
                GlanceModifier.fillMaxSize().appWidgetBackground()
                    .background(ImageProvider(R.drawable.widget_background)),
            ) { Face(snapshot, prefs) }
        }
    }

    @Composable
    abstract fun Face(snapshot: WidgetSnapshot?, prefs: Preferences)
}

class PinnedWeaponWidget : CamoWidget() {
    @Composable
    override fun Face(snapshot: WidgetSnapshot?, prefs: Preferences) {
        val pinned = snapshot?.pinned
        if (pinned == null) {
            // Centred in the widget, not stuck to its top
            Column(
                GlanceModifier.fillMaxSize().padding(14.dp).clickable(open(null)),
                verticalAlignment = Alignment.CenterVertically, horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                Image(ImageProvider(R.drawable.widget_pin), null, GlanceModifier.size(22.dp))
                Spacer(GlanceModifier.height(8.dp))
                Text(snapshot?.pinPrompt?.takeIf { it.isNotEmpty() } ?: L("widget.pin_prompt"),
                    style = style(14.sp, Color.White.copy(alpha = 0.85f), bold = true, align = TextAlign.Center))
            }
            return
        }
        val accent = hex(pinned.accentHex) ?: Accent
        val medium = isMedium()
        val link = WidgetSnapshot.link(pinned.mode, pinned.weaponId, snapshot.game)
        Row(
            GlanceModifier.fillMaxSize().padding(14.dp).clickable(open(link)),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            if (medium) {
                val fraction = if (pinned.camosTotal > 0) pinned.camosDone.toDouble() / pinned.camosTotal else 0.0
                Ring(84.dp, 8.dp, fraction, accent) {
                    Text("${pinned.camosDone}", style = style(22.sp, Color.White, heavy = true, align = TextAlign.Center))
                    Text("/${pinned.camosTotal}", style = style(11.sp, Color.White.copy(alpha = 0.6f), bold = true, align = TextAlign.Center))
                }
                Spacer(GlanceModifier.width(14.dp))
            }
            val width = LocalSize.current.width - 28.dp - (if (medium) 98.dp else 0.dp)
            Column(GlanceModifier.defaultWeight().fillMaxHeight()) {
                Text(snapshot.titled(pinned.modeName).upper(), style = style(10.sp, accent, heavy = true), maxLines = 1)
                Spacer(GlanceModifier.height(2.dp))
                Text(pinned.name, style = style(if (medium) 19.sp else 17.sp, Color.White, heavy = true), maxLines = 1)
                Spacer(GlanceModifier.defaultWeight())
                val next = pinned.nextName
                if (next != null) {
                    Text(next, style = style(13.sp, Color.White.copy(alpha = 0.9f), bold = true), maxLines = 1)
                    val detail = pinned.nextDetail
                    if (detail != null && medium) {
                        Text(detail, style = style(11.5.sp, Color.White.copy(alpha = 0.6f)), maxLines = 2)
                    }
                    if (pinned.nextTotal > 1) {
                        Spacer(GlanceModifier.height(4.dp))
                        Bar(width, 5.dp, pinned.nextDone.toDouble() / pinned.nextTotal, accent, Color.White.copy(alpha = 0.14f))
                        Spacer(GlanceModifier.height(3.dp))
                        Text("${pinned.nextDone}/${pinned.nextTotal}",
                            style = style(11.sp, Color.White.copy(alpha = 0.6f), bold = true, mono = true))
                    }
                } else {
                    Text(snapshot.allDoneLabel, style = style(13.sp, accent, bold = true))
                }
            }
        }
    }
}

class ModeProgressWidget : CamoWidget() {
    @Composable
    override fun Face(snapshot: WidgetSnapshot?, prefs: Preferences) {
        // The picked mode, else the one the app opens on; one the player has
        // switched off isn't in the snapshot, so the first one they play shows
        val wanted = prefs[WidgetSync.MODE]?.takeIf { it.isNotEmpty() } ?: snapshot?.startMode
        val mode = snapshot?.modes?.firstOrNull { it.id == wanted } ?: snapshot?.modes?.firstOrNull()
        if (snapshot == null || mode == null) {
            Box(GlanceModifier.fillMaxSize().padding(14.dp).clickable(open(null)), contentAlignment = Alignment.Center) {
                Text(L("widget.open_app"), style = style(13.sp, Color.White.copy(alpha = 0.8f), bold = true, align = TextAlign.Center))
            }
            return
        }
        val accent = hex(mode.accentHex) ?: Accent
        val title = snapshot.titled(mode.name).upper()
        val percent = "${(mode.fraction * 100).roundToInt()}%"
        val modifier = GlanceModifier.fillMaxSize().padding(14.dp).clickable(open(WidgetSnapshot.link(mode.id, game = snapshot.game)))
        if (isMedium()) {
            Row(modifier, verticalAlignment = Alignment.CenterVertically) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Ring(80.dp, 8.dp, mode.fraction, accent) {
                        Text(percent, style = style(18.sp, Color.White, heavy = true, align = TextAlign.Center))
                    }
                    Spacer(GlanceModifier.height(6.dp))
                    Text(title, style = style(10.sp, accent, heavy = true, align = TextAlign.Center), maxLines = 1,
                        modifier = GlanceModifier.width(96.dp))
                }
                Spacer(GlanceModifier.width(16.dp))
                val width = LocalSize.current.width - 28.dp - 112.dp
                Column(GlanceModifier.defaultWeight(), verticalAlignment = Alignment.CenterVertically) {
                    mode.steps.forEach { step ->
                        Row(GlanceModifier.fillMaxWidth().padding(bottom = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                            Dot(7.dp, hex(step.colorHex) ?: Color.White)
                            Spacer(GlanceModifier.width(6.dp))
                            Text(step.name, style = style(12.sp, Color.White.copy(alpha = 0.85f), bold = true), maxLines = 1,
                                modifier = GlanceModifier.defaultWeight())
                            Spacer(GlanceModifier.width(4.dp))
                            Text("${step.done}/${step.total}", style = style(11.5.sp, Color.White, bold = true, mono = true))
                        }
                    }
                    MasteryPips(mode.mastery, snapshot.masteryLabel, width, compact = false)
                }
            }
        } else {
            Column(modifier) {
                Text(title, style = style(10.sp, accent, heavy = true), maxLines = 1)
                // Without a Mastery row (Black Ops) the track's last camo takes its place, and the block sits in the middle
                if (mode.mastery.isEmpty()) Spacer(GlanceModifier.defaultWeight()) else Spacer(GlanceModifier.height(6.dp))
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Ring(58.dp, 7.dp, mode.fraction, accent) {
                        Text(percent, style = style(16.sp, Color.White, heavy = true, align = TextAlign.Center))
                    }
                    Spacer(GlanceModifier.width(10.dp))
                    Column {
                        mode.steps.take(if (mode.mastery.isEmpty()) 4 else 3).forEach { step ->
                            Row(GlanceModifier.padding(bottom = 3.dp), verticalAlignment = Alignment.CenterVertically) {
                                Dot(6.dp, hex(step.colorHex) ?: Color.White)
                                Spacer(GlanceModifier.width(4.dp))
                                Text("${step.done}/${step.total}", style = style(10.5.sp, Color.White, bold = true, mono = true), maxLines = 1)
                            }
                        }
                    }
                }
                Spacer(GlanceModifier.defaultWeight())
                MasteryPips(mode.mastery, snapshot.masteryLabel, LocalSize.current.width - 28.dp, compact = true)
            }
        }
    }
}

class CompletionWidget : CamoWidget() {
    @Composable
    override fun Face(snapshot: WidgetSnapshot?, prefs: Preferences) {
        val overall = snapshot?.overall ?: 0.0
        val link = snapshot?.let { s -> s.modes.firstOrNull()?.let { WidgetSnapshot.link(s.startMode ?: it.id, game = s.game) } }
        Column(
            GlanceModifier.fillMaxSize().padding(12.dp).clickable(open(link)),
            verticalAlignment = Alignment.CenterVertically, horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Ring(92.dp, 9.dp, overall, Gold) {
                Text("${(overall * 100).roundToInt()}%", style = style(22.sp, Color.White, heavy = true, align = TextAlign.Center))
            }
            Spacer(GlanceModifier.height(8.dp))
            Text((snapshot?.let { it.titled(it.overallLabel) } ?: L("widget.completion.name")).upper(),
                style = style(9.5.sp, Color.White.copy(alpha = 0.7f), heavy = true, align = TextAlign.Center), maxLines = 1)
        }
    }
}

class PinnedWeaponReceiver : GlanceAppWidgetReceiver() { override val glanceAppWidget: GlanceAppWidget = PinnedWeaponWidget() }
class ModeProgressReceiver : GlanceAppWidgetReceiver() { override val glanceAppWidget: GlanceAppWidget = ModeProgressWidget() }
class CompletionReceiver : GlanceAppWidgetReceiver() { override val glanceAppWidget: GlanceAppWidget = CompletionWidget() }

// ── Pieces ──

/** A 4×2 (or wider) widget gets the medium layout; a 2×2 the small one. */
@Composable
private fun isMedium(): Boolean = LocalSize.current.width >= 230.dp

/** Opens the app on `link` (a mw4camo:// link), or just opens it. */
@Composable
private fun open(link: String?) = actionStartActivity(
    Intent(LocalContext.current, MainActivity::class.java).apply {
        action = Intent.ACTION_VIEW
        if (link != null) data = Uri.parse(link)
        flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
    },
)

private fun String.upper() = uppercase(Locale.getDefault())

private fun hex(text: String): Color? = app.camotrack.android.core.HexColor.parse(text)?.let { Color(it) }

private fun style(size: TextUnit, color: Color, bold: Boolean = false, heavy: Boolean = false, mono: Boolean = false, align: TextAlign = TextAlign.Start) =
    TextStyle(
        color = ColorProvider(color), fontSize = size, textAlign = align,
        fontWeight = if (bold || heavy) FontWeight.Bold else FontWeight.Normal,
        fontFamily = when { mono -> FontFamily.Monospace; heavy -> Heavy; else -> null },
    )

/** iOS WidgetRing: a faint track, the fraction from the top with round ends, a label in the middle. */
@Composable
private fun Ring(size: Dp, line: Dp, fraction: Double, color: Color, label: @Composable ColumnScope.() -> Unit) {
    val context = LocalContext.current
    val bitmap = remember(size, line, fraction, color) { Draw.ring(context, size, line, fraction, color) }
    Box(GlanceModifier.size(size), contentAlignment = Alignment.Center) {
        Image(ImageProvider(bitmap), null, GlanceModifier.size(size))
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalAlignment = Alignment.CenterVertically, content = label)
    }
}

@Composable
private fun Bar(width: Dp, height: Dp, fraction: Double, color: Color, track: Color, outline: Color? = null) {
    val context = LocalContext.current
    val w = width.coerceAtLeast(8.dp)
    val bitmap = remember(w, height, fraction, color, track, outline) { Draw.bar(context, w, height, fraction, color, track, outline) }
    Image(ImageProvider(bitmap), null, GlanceModifier.width(w).height(height))
}

@Composable
private fun Dot(size: Dp, color: Color) {
    val context = LocalContext.current
    val bitmap = remember(size, color) { Draw.dot(context, size, color) }
    Image(ImageProvider(bitmap), null, GlanceModifier.size(size))
}

/** The mode's three Mastery camos under a "Mastery" label: a bar each in the camo's colour, solid once earned. */
@Composable
private fun MasteryPips(steps: List<WidgetSnapshot.Step>, label: String?, width: Dp, compact: Boolean) {
    // None for a game without account Mastery
    if (steps.isEmpty()) return
    Column {
        if (label != null) {
            Text(label.upper(), style = style(if (compact) 8.5.sp else 9.sp, Color.White.copy(alpha = 0.55f), heavy = true), maxLines = 1)
            Spacer(GlanceModifier.height(3.dp))
        }
        val each = (width - 4.dp * (steps.size - 1)) / steps.size
        Row {
            steps.forEachIndexed { index, step ->
                if (index > 0) Spacer(GlanceModifier.width(4.dp))
                val color = hex(step.colorHex) ?: Color.White
                val fraction = if (step.total > 0) minOf(step.done.toDouble() / step.total, 1.0) else 0.0
                Bar(each, if (compact) 5.dp else 6.dp, fraction, color, color.copy(alpha = 0.22f),
                    outline = if (fraction >= 1) null else color.copy(alpha = 0.6f))
            }
        }
    }
}

/** Rings, bars and dots drawn to bitmaps: Glance has no shapes of its own. */
private object Draw {
    private fun px(context: Context, dp: Dp) = (dp.value * context.resources.displayMetrics.density)

    fun ring(context: Context, size: Dp, line: Dp, fraction: Double, color: Color): Bitmap {
        val s = px(context, size).roundToInt().coerceAtLeast(1)
        val lw = px(context, line)
        val bitmap = Bitmap.createBitmap(s, s, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        val rect = RectF(lw / 2, lw / 2, s - lw / 2, s - lw / 2)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.STROKE; strokeWidth = lw }
        paint.color = Color.White.copy(alpha = 0.12f).toArgb()
        canvas.drawOval(rect, paint)
        val sweep = (fraction.coerceIn(0.0, 1.0) * 360).toFloat()
        if (sweep > 0) {
            paint.color = color.toArgb()
            paint.strokeCap = Paint.Cap.ROUND
            canvas.drawArc(rect, -90f, sweep, false, paint)
        }
        return bitmap
    }

    fun bar(context: Context, width: Dp, height: Dp, fraction: Double, color: Color, track: Color, outline: Color?): Bitmap {
        val w = px(context, width).roundToInt().coerceAtLeast(1)
        val h = px(context, height).roundToInt().coerceAtLeast(1)
        val bitmap = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        val r = h / 2f
        val paint = Paint(Paint.ANTI_ALIAS_FLAG)
        paint.color = track.toArgb()
        canvas.drawRoundRect(RectF(0f, 0f, w.toFloat(), h.toFloat()), r, r, paint)
        val filled = (w * fraction.coerceIn(0.0, 1.0)).toFloat()
        if (filled > 0) {
            paint.color = color.toArgb()
            canvas.drawRoundRect(RectF(0f, 0f, filled.coerceAtLeast(h.toFloat()).coerceAtMost(w.toFloat()), h.toFloat()), r, r, paint)
        }
        if (outline != null) {
            val stroke = px(context, 1.dp)
            paint.color = outline.toArgb(); paint.style = Paint.Style.STROKE; paint.strokeWidth = stroke
            canvas.drawRoundRect(RectF(stroke / 2, stroke / 2, w - stroke / 2, h - stroke / 2), r, r, paint)
        }
        return bitmap
    }

    fun dot(context: Context, size: Dp, color: Color): Bitmap {
        val s = px(context, size).roundToInt().coerceAtLeast(1)
        val bitmap = Bitmap.createBitmap(s, s, Bitmap.Config.ARGB_8888)
        Canvas(bitmap).drawCircle(s / 2f, s / 2f, s / 2f, Paint(Paint.ANTI_ALIAS_FLAG).apply { this.color = color.toArgb() })
        return bitmap
    }
}
