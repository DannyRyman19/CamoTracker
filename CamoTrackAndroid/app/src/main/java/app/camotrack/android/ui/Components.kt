package app.camotrack.android.ui

import androidx.compose.animation.animateContentSize
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.animation.core.animateFloat
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Diamond
import androidx.compose.material.icons.filled.GpsFixed
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.Palette
import androidx.compose.material.icons.filled.Remove
import androidx.compose.material.icons.filled.UnfoldMore
import androidx.compose.material.icons.outlined.Circle
import androidx.compose.material.icons.outlined.Diamond
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shadow
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.IntRect
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Popup
import androidx.compose.ui.window.PopupPositionProvider
import androidx.compose.ui.window.PopupProperties
import app.camotrack.android.AppState
import app.camotrack.android.core.ChallengeItem
import app.camotrack.android.core.LocalizedText
import app.camotrack.android.core.ModeChallenge
import app.camotrack.android.core.ObjectiveScope
import app.camotrack.android.core.UnlockDate
import app.camotrack.android.core.UnlockDuration
import app.camotrack.android.core.WeaponEntry
import app.camotrack.android.core.WeaponFilter
import app.camotrack.android.i18n.L
import coil.compose.SubcomposeAsyncImage
import kotlin.math.PI
import kotlin.math.sin

// MARK: - Page furniture

/** The page's ground: the background with the mode's accent washed in at the top (iOS's AppBackground). */
@Composable
fun Modifier.appBackground(accent: Color): Modifier {
    val ground = LocalPalette.current.background
    return this
        .background(ground)
        .background(Brush.verticalGradient(0f to accent.copy(alpha = 0.12f), 0.35f to Color.Transparent))
}

/** A pushed screen's bar: back, the title, and its buttons. */
@Composable
fun TopBar(title: String, onBack: (() -> Unit)? = { AppState.pop() }, actions: @Composable RowScope.() -> Unit = {}) {
    Row(
        Modifier.fillMaxWidth().statusBarsPadding().height(52.dp).padding(horizontal = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (onBack != null) {
            IconButton(onClick = onBack) {
                Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
            }
        } else {
            Spacer(Modifier.width(12.dp))
        }
        Text(
            title, style = displayStyle(19.sp), color = Ink.text, maxLines = 1, overflow = TextOverflow.Ellipsis,
            modifier = Modifier.weight(1f).padding(horizontal = 4.dp),
        )
        actions()
    }
}

/** A section heading in a list (iOS's ListHeading): 17 semibold, on the page's ground. */
@Composable
fun ListHeading(text: String, modifier: Modifier = Modifier) {
    Text(
        text, style = sys(17f, FontWeight.SemiBold), color = Ink.text,
        modifier = modifier.fillMaxWidth().background(LocalPalette.current.background).padding(horizontal = 16.dp, vertical = 8.dp),
    )
}

/** Centred placeholder for when a filter leaves nothing to show. */
@Composable
fun FilterEmptyRow(text: String = L("mw4.ui.filter.empty")) {
    Text(
        text, style = sys(13f), color = Ink.muted, textAlign = TextAlign.Center,
        modifier = Modifier.fillMaxWidth().padding(vertical = 20.dp, horizontal = 16.dp),
    )
}

/** How many cards sit side by side: one on a phone, two from 600dp, three from 1150dp. */
fun gridColumns(widthDp: Float): Int = if (widthDp >= 1150) 3 else if (widthDp >= 600) 2 else 1

// MARK: - Cards

/**
 * The app's card: the surface with a subtle stroke, squared off at 8. An
 * `accent` washes the fill and brightens the border; `borderGradient` draws
 * the border in an earned camo's colours instead.
 */
@Composable
fun Modifier.borderedCard(cornerRadius: Dp = 8.dp, accent: Color? = null, borderGradient: List<Color>? = null): Modifier {
    val surface = LocalPalette.current.surface
    val shape = RoundedCornerShape(cornerRadius)
    val wash = accent?.copy(alpha = 0.10f) ?: Color.Transparent
    val border = if (borderGradient != null && borderGradient.size > 1) {
        Brush.linearGradient(borderGradient.map { it.copy(alpha = 0.7f) })
    } else {
        androidx.compose.ui.graphics.SolidColor(accent?.copy(alpha = 0.55f) ?: Ink.muted.copy(alpha = 0.25f))
    }
    return this.clip(shape).background(surface).background(wash).border(1.dp, border, shape)
}

// MARK: - Images

/** A weapon's picture in a square tile, or its class's silhouette (else a scope) while it loads or when it has none. */
@Composable
fun WeaponThumbnail(url: String?, size: Dp, inset: Dp? = null, category: app.camotrack.android.core.WeaponCategory? = null) {
    val surface2 = LocalPalette.current.surface2
    Box(
        Modifier.size(size).clip(RoundedCornerShape(size * 0.2f)).background(surface2),
        contentAlignment = Alignment.Center,
    ) {
        SubcomposeAsyncImage(
            model = url, contentDescription = null, contentScale = ContentScale.Fit,
            modifier = Modifier.fillMaxSize().padding(inset ?: (size * 0.14f)),
            loading = { WeaponPlaceholder(size * 0.4f, category, size * 0.72f) }, error = { WeaponPlaceholder(size * 0.4f, category, size * 0.72f) },
        )
    }
}

@Composable
private fun WeaponPlaceholder(size: Dp, category: app.camotrack.android.core.WeaponCategory? = null, maxWidth: Dp = size * 2) {
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        val drawn = category?.let { Glyphs.weaponClass(it) }
        if (drawn != null) {
            // The class's silhouette, its own shape, held to the tile's width
            Icon(androidx.compose.ui.res.painterResource(drawn), contentDescription = null, tint = Ink.muted,
                 modifier = Modifier.widthIn(max = maxWidth).height(size * 0.75f))
        } else {
            Icon(androidx.compose.ui.res.painterResource(Glyphs.tabWeapons), contentDescription = null, tint = Ink.muted, modifier = Modifier.size(size))
        }
    }
}

/** A weapon class's silhouette (iOS ClassIcon), or nothing when the class has no drawing. */
@Composable
fun ClassIcon(category: app.camotrack.android.core.WeaponCategory, height: Dp = 16.dp, maxWidth: Dp = 52.dp, tint: androidx.compose.ui.graphics.Color = Ink.muted) {
    val drawn = Glyphs.weaponClass(category) ?: return
    Icon(androidx.compose.ui.res.painterResource(drawn), contentDescription = null, tint = tint,
         modifier = Modifier.height(height).widthIn(max = maxWidth))
}

/** The weapon detail's wide banner, sized for the art's wide shape. */
@Composable
fun WeaponHeroImage(url: String?, height: Dp = 108.dp, modifier: Modifier = Modifier, category: app.camotrack.android.core.WeaponCategory? = null) {
    val surface2 = LocalPalette.current.surface2
    Box(
        modifier.fillMaxWidth().height(height).clip(RoundedCornerShape(12.dp)).background(surface2),
        contentAlignment = Alignment.Center,
    ) {
        SubcomposeAsyncImage(
            model = url, contentDescription = null, contentScale = ContentScale.Fit,
            modifier = Modifier.fillMaxSize().padding(12.dp),
            loading = { WeaponPlaceholder(height * 0.4f, category, height * 1.6f) }, error = { WeaponPlaceholder(height * 0.4f, category, height * 1.6f) },
        )
    }
}

/** A camo swatch. Press and hold for the picture full size, with its name; a tap goes to the row around it. */
@Composable
fun CamoThumbnail(url: String?, size: Dp, name: String? = null, modifier: Modifier = Modifier, peeks: Boolean = true) {
    var shown by remember { mutableStateOf(false) }
    val surface2 = LocalPalette.current.surface2
    Box(
        modifier
            .size(size).clip(RoundedCornerShape(size * 0.25f)).background(surface2)
            .then(if (peeks) Modifier.onPressHold { shown = true } else Modifier),
        contentAlignment = Alignment.Center,
    ) {
        SubcomposeAsyncImage(
            model = url, contentDescription = name, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize(),
            loading = { SwatchPlaceholder(size) }, error = { SwatchPlaceholder(size) },
        )
        if (shown) PeekPopup(onDismiss = { shown = false }) { CamoPreview(url, name) }
    }
}

@Composable
private fun SwatchPlaceholder(size: Dp) {
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        Icon(Icons.Filled.Palette, contentDescription = null, tint = Ink.muted, modifier = Modifier.size(size * 0.4f))
    }
}

@Composable
private fun CamoPreview(url: String?, name: String?) {
    Column(Modifier.width(300.dp)) {
        SubcomposeAsyncImage(
            model = url, contentDescription = name, contentScale = ContentScale.Crop,
            modifier = Modifier.size(300.dp),
            loading = { Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { CircularProgressIndicator() } },
        )
        if (name != null) {
            Text(
                name, style = sys(17f, FontWeight.SemiBold), color = Ink.text, textAlign = TextAlign.Center,
                modifier = Modifier.fillMaxWidth().background(LocalPalette.current.surface).padding(vertical = 12.dp),
            )
        }
    }
}

// MARK: - Press and hold

/**
 * Calls [onHold] after a 0.35s press that hasn't moved; a tap or a scroll
 * still goes to whatever is underneath (the hold's own release is eaten so
 * the card around it doesn't open as well).
 */
@Composable
fun Modifier.onPressHold(onHold: () -> Unit): Modifier {
    val haptics = LocalHapticFeedback.current
    val latest by rememberUpdatedState(onHold)
    return pointerInput(Unit) {
        awaitEachGesture {
            val down = awaitFirstDown(requireUnconsumed = false)
            val released = withTimeoutOrNull(350) {
                while (true) {
                    val event = awaitPointerEvent()
                    val change = event.changes.firstOrNull { it.id == down.id } ?: return@withTimeoutOrNull true
                    if (!change.pressed || change.isConsumed) return@withTimeoutOrNull true
                    if ((change.position - down.position).getDistance() > viewConfiguration.touchSlop) return@withTimeoutOrNull true
                }
                @Suppress("UNREACHABLE_CODE") true
            }
            if (released == null) {
                haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                latest()
                while (true) {
                    val event = awaitPointerEvent()
                    event.changes.forEach { it.consume() }
                    if (event.changes.none { it.pressed }) break
                }
            }
        }
    }
}

/** A pop-up anchored to the view it's called in: below it when there's room, else above, else centred. */
@Composable
fun PeekPopup(onDismiss: () -> Unit, content: @Composable () -> Unit) {
    val provider = remember {
        object : PopupPositionProvider {
            override fun calculatePosition(anchorBounds: IntRect, windowSize: IntSize, layoutDirection: LayoutDirection, popupContentSize: IntSize): IntOffset {
                val margin = 24
                val x = (anchorBounds.center.x - popupContentSize.width / 2)
                    .coerceIn(margin, maxOf(margin, windowSize.width - popupContentSize.width - margin))
                val below = anchorBounds.bottom + 12
                val above = anchorBounds.top - 12 - popupContentSize.height
                val y = when {
                    below + popupContentSize.height <= windowSize.height - margin -> below
                    above >= margin -> above
                    else -> (windowSize.height - popupContentSize.height) / 2
                }
                return IntOffset(x, y)
            }
        }
    }
    Popup(popupPositionProvider = provider, onDismissRequest = onDismiss, properties = PopupProperties(focusable = true)) {
        Box(
            Modifier
                .shadow(16.dp, RoundedCornerShape(14.dp))
                .clip(RoundedCornerShape(14.dp))
                .background(LocalPalette.current.surface)
                .border(1.dp, Ink.muted.copy(alpha = 0.2f), RoundedCornerShape(14.dp)),
        ) { content() }
    }
}

// MARK: - Progress

@Composable
fun ProgressBar(fraction: Double, accent: Color, modifier: Modifier = Modifier) {
    val shown by animateFloatAsState(fraction.toFloat().coerceIn(0f, 1f), tween(350), label = "bar")
    val track = LocalPalette.current.surface2
    Box(modifier.fillMaxWidth().height(4.dp).clip(CircleShape).background(track)) {
        Box(Modifier.fillMaxHeight().fillMaxWidth(shown).clip(CircleShape).background(accent))
    }
}

/** A circular completion meter; at 100% a slow rotating sweep in [shimmer]. */
@Composable
fun ProgressRing(
    fraction: Double, accent: Color, lineWidth: Dp = 8.dp, size: Dp = 64.dp,
    showsPercentage: Boolean = true, shimmer: List<Color> = GoldColors,
) {
    val track = LocalPalette.current.surface2
    val complete = fraction >= 1
    val shown by animateFloatAsState(fraction.toFloat().coerceIn(0f, 1f), tween(500), label = "ring")
    val angle = if (complete) {
        val transition = rememberInfiniteTransition(label = "sweep")
        transition.animateFloat(0f, 360f, infiniteRepeatable(tween(3200, easing = LinearEasing)), label = "angle").value
    } else 0f
    Box(Modifier.size(size), contentAlignment = Alignment.Center) {
        Canvas(Modifier.fillMaxSize()) {
            val stroke = lineWidth.toPx()
            val inset = stroke / 2
            val arcSize = Size(this.size.width - stroke, this.size.height - stroke)
            drawCircle(track, radius = (this.size.minDimension - stroke) / 2, style = Stroke(stroke))
            if (complete) {
                rotate(angle) {
                    drawArc(
                        Brush.sweepGradient(shimmer + shimmer.first()), 0f, 360f, false,
                        topLeft = Offset(inset, inset), size = arcSize, style = Stroke(stroke, cap = StrokeCap.Round),
                    )
                }
            } else if (shown > 0.0015f) {
                drawArc(
                    accent, -90f, 360f * shown, false,
                    topLeft = Offset(inset, inset), size = arcSize, style = Stroke(stroke, cap = StrokeCap.Round),
                )
            }
        }
        if (showsPercentage) {
            Text(percentText(fraction), style = sys(size.value * 0.22f, FontWeight.Bold, mono = true), color = Ink.text, maxLines = 1)
        }
    }
}

/**
 * The camo pips (one per camo, filled once earned) then a diamond per
 * Completionist camo, each lit in its own colour.
 */
@Composable
fun CamoPipRow(done: List<Boolean>, filled: Color, tiers: List<Pair<Boolean, Color>>) {
    val dense = done.size > 8
    val pip = if (dense) 5.dp else 6.dp
    Row(horizontalArrangement = Arrangement.spacedBy(if (dense) 2.dp else 3.dp), verticalAlignment = Alignment.CenterVertically) {
        for (on in done) {
            Box(
                Modifier.size(pip).clip(CircleShape)
                    .then(if (on) Modifier.background(filled) else Modifier.border(1.dp, Ink.muted.copy(alpha = 0.5f), CircleShape)),
            )
        }
        tiers.forEachIndexed { index, (achieved, color) ->
            Icon(
                if (achieved) Icons.Filled.Diamond else Icons.Outlined.Diamond, contentDescription = null,
                tint = if (achieved) color else Ink.muted.copy(alpha = 0.5f),
                modifier = Modifier.padding(start = if (index == 0) 1.dp else 0.dp).size(if (dense) 9.dp else 11.dp),
            )
        }
    }
}

/** The small circular −/+ (ChallengeRow's nudges, the level stepper). */
@Composable
fun StepButton(icon: ImageVector, enabled: Boolean, size: Dp, accent: Color, onClick: () -> Unit) {
    val background = LocalPalette.current.background
    Box(
        Modifier.size(size).clip(CircleShape)
            .background(if (enabled) accent else Ink.muted.copy(alpha = 0.4f))
            .clickable(enabled = enabled, onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Icon(icon, contentDescription = null, tint = background, modifier = Modifier.size(size * 0.62f))
    }
}

// MARK: - Animated gradient text

/**
 * A camo name in its own shifting gradient, glowing in its first colour:
 * the "earned" look. `weight` null sets it in the game's display face.
 */
@Composable
fun AnimatedGradientText(
    text: String, colors: List<Color>, size: Float = 16f, weight: FontWeight? = null, glow: Boolean = true,
    modifier: Modifier = Modifier, textAlign: TextAlign? = null, maxLines: Int = Int.MAX_VALUE,
) {
    val transition = rememberInfiniteTransition(label = "gradient")
    val t by transition.animateFloat(0f, 1f, infiniteRepeatable(tween(3200, easing = LinearEasing)), label = "phase")
    val phase = 0.5f * sin(t * 2 * PI).toFloat()
    val list = if (colors.size > 1) colors else listOf(colors.firstOrNull() ?: CamoGold, colors.firstOrNull() ?: CamoGold)
    val count = (list.size - 1).coerceAtLeast(1)
    val stops = list.mapIndexed { index, color -> (index.toFloat() / count + phase).coerceIn(0f, 1f) to color }.toTypedArray()
    val base = if (weight != null) sys(size, weight) else displayStyle(size.sp)
    Text(
        text, modifier = modifier, textAlign = textAlign, maxLines = maxLines, overflow = TextOverflow.Ellipsis,
        style = base.copy(
            brush = Brush.horizontalGradient(*stops),
            shadow = if (glow) Shadow(list.first().copy(alpha = 0.75f), blurRadius = 12f) else null,
        ),
    )
}

// MARK: - Stat summary

data class Stat(
    val value: String,
    val label: String,
    val labelGradient: List<Color>? = null,
    val ringFraction: Double? = null,
    val ringColor: Color? = null,
    val ringGradient: List<Color>? = null,
    /** Not open yet: a lock in place of the ring, and what it waits for in place of the count. */
    val lockedHint: String? = null,
)

/** A row of rings with counts under them, split by thin rules (iOS's StatSummaryCard). */
@Composable
fun StatSummaryCard(stats: List<Stat>, bordered: Boolean = true, horizontalPadding: Dp = 12.dp, verticalPadding: Dp = 14.dp) {
    val hasLock = stats.any { it.lockedHint != null }
    // Capped at xxxLarge as on iPhone: four columns broke "PLATINUM" mid-word past it
    CapFontScale {
    BoxWithConstraints(Modifier.fillMaxWidth()) {
    // Each word whole in its column, shrinking a little to fit (iOS's minimumScaleFactor): "DIVERGENCE" broke after "DIVERGENC"
    val column = (maxWidth - horizontalPadding * 2 - 1.dp * (stats.size - 1)) / stats.size.coerceAtLeast(1)
    val labelStyle = fittedStyle(stats.flatMap { words(it.label.uppercase(appLocale)) }, sys(11f), column, minScale = 0.6f)
    val hintStyle = fittedStyle(stats.flatMap { words(it.lockedHint.orEmpty()) }, sys(10f, FontWeight.SemiBold), column, minScale = 0.6f)
    Row(
        Modifier.fillMaxWidth()
            .then(if (bordered) Modifier.borderedCard() else Modifier)
            .padding(horizontal = horizontalPadding, vertical = verticalPadding),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        stats.forEachIndexed { index, stat ->
            Column(Modifier.weight(1f), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(4.dp)) {
                if (stat.lockedHint != null) {
                    Box(Modifier.size(40.dp), contentAlignment = Alignment.Center) {
                        Canvas(Modifier.fillMaxSize()) {
                            drawCircle(Ink.muted.copy(alpha = 0.3f), radius = (size.minDimension - 4.dp.toPx()) / 2, style = Stroke(4.dp.toPx()))
                        }
                        Icon(Icons.Filled.Lock, contentDescription = null, tint = Ink.muted, modifier = Modifier.size(15.dp))
                    }
                    Text(
                        stat.lockedHint, style = hintStyle, color = Ink.muted, textAlign = TextAlign.Center,
                        // A third line past the default size, as on iPhone ("Needs 33 Harmonic Break")
                        minLines = 2, maxLines = if (LocalDensity.current.fontScale > 1f) 3 else 2, overflow = TextOverflow.Ellipsis,
                    )
                } else if (stat.ringFraction != null) {
                    ProgressRing(stat.ringFraction, stat.ringColor ?: Ink.text, lineWidth = 4.dp, size = 40.dp, shimmer = stat.ringGradient ?: GoldColors)
                    Text(
                        stat.value, style = sys(11f, FontWeight.SemiBold, mono = true), color = Ink.text, textAlign = TextAlign.Center,
                        minLines = if (hasLock) 2 else 1, maxLines = 2,
                    )
                } else {
                    Text(stat.value, style = sys(17f, FontWeight.Bold, mono = true), color = Ink.text)
                }
                if (stat.labelGradient != null) {
                    AnimatedGradientText(
                        stat.label.uppercase(appLocale), stat.labelGradient, size = labelStyle.fontSize.value, weight = FontWeight.Normal,
                        textAlign = TextAlign.Center, maxLines = 2, modifier = Modifier.heightIn(min = 28.dp),
                    )
                } else {
                    Text(
                        stat.label.uppercase(appLocale), style = labelStyle, color = Ink.muted, textAlign = TextAlign.Center,
                        minLines = 2, maxLines = 2, overflow = TextOverflow.Ellipsis,
                    )
                }
            }
            if (index < stats.size - 1) {
                Box(Modifier.width(1.dp).height(30.dp).background(Ink.muted.copy(alpha = 0.25f)))
            }
        }
    }
    }
    }
}

// MARK: - Challenge row

/**
 * One challenge, three ways to log it: tap the circle (or a tick-box row
 * anywhere) to tick it, −/+ to nudge a count, the count itself to type an
 * amount. Shared by camos, Completionist, Mastery and objectives.
 */
@Composable
fun ChallengeRow(
    item: ChallengeItem,
    accent: Color,
    amount: Int,
    isDone: Boolean,
    onToggle: () -> Unit,
    onSetAmount: (Int) -> Unit,
    mode: String? = null,
    isAvailable: Boolean = true,
    lockedReason: String? = null,
    titleGradient: List<Color>? = null,
    detail: String? = null,
    earnedOn: UnlockDate? = null,
    took: UnlockDuration? = null,
) {
    val t = tracker()
    val showLocked by Prefs.bool(Prefs.SHOW_LOCKED, false)
    val requirement = item.requirement
    val hasCounter = !t.quickTick && (requirement?.amount ?: 0) > 1
    val showsCounter = requirement != null && hasCounter && isAvailable && !isDone
    var askingAmount by remember { mutableStateOf(false) }
    val name = item.name.resolved()
    val earnedText = if (isDone && earnedOn != null) {
        val day = L("ct.ui.earned_on", earnedOn.text())
        took?.let { day + " · " + L("ct.ui.took", it.text()) } ?: day
    } else null
    // At the largest text sizes the −/+ go under the challenge, so a long
    // name keeps the row's width (as on iPhone): beside it, the name and
    // challenge were squeezed to a few letters a line
    val stacksCounter = isAccessibilityFontSize()
    val counter: @Composable () -> Unit = {
        if (showsCounter && requirement != null) {
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                StepButton(Icons.Filled.Remove, amount > 0, 22.dp, accent) { onSetAmount(maxOf(0, amount - 1)) }
                Text(
                    "$amount/${requirement.amount}", style = sys(12.5f, mono = true), color = Ink.muted, maxLines = 1, softWrap = false,
                    modifier = Modifier.clip(CircleShape).background(LocalPalette.current.surface2)
                        .clickable { askingAmount = true }.padding(horizontal = 9.dp, vertical = 5.dp),
                )
                StepButton(Icons.Filled.Add, amount < requirement.amount, 22.dp, accent) { onSetAmount(minOf(requirement.amount, amount + 1)) }
            }
        }
    }

    Row(
        Modifier.fillMaxWidth()
            .clickable(enabled = isAvailable && !hasCounter, interactionSource = remember { MutableInteractionSource() }, indication = null) { onToggle() }
            .padding(vertical = 5.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Box(
            Modifier.size(32.dp).clip(CircleShape).clickable(enabled = isAvailable, onClick = onToggle),
            contentAlignment = Alignment.Center,
        ) {
            when {
                isDone -> Icon(Icons.Filled.CheckCircle, contentDescription = null, tint = accent, modifier = Modifier.size(24.dp))
                isAvailable -> Icon(Icons.Outlined.Circle, contentDescription = null, tint = Ink.muted, modifier = Modifier.size(24.dp))
                else -> Icon(Icons.Filled.Lock, contentDescription = null, tint = Ink.muted.copy(alpha = 0.5f), modifier = Modifier.size(18.dp))
            }
        }
        if (item.imageURL != null) {
            CamoThumbnail(item.imageURL, 34.dp, name, modifier = Modifier.alpha(if (isAvailable) 1f else 0.4f))
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            if (isDone && titleGradient != null) {
                AnimatedGradientText(name, titleGradient, size = 15f)
            } else {
                Text(name, style = displayStyle(15.sp), color = if (isAvailable) Ink.text else Ink.muted)
            }
            if (requirement != null) {
                if (isAvailable || showLocked) {
                    val byMode = requirement.byMode
                    if (!byMode.isNullOrEmpty()) {
                        ModeChallengeList(requirement.lead, byMode, mode)
                    } else {
                        Text(requirement.description.resolved(), style = sys(13f), color = Ink.muted)
                    }
                }
                if (!isAvailable) {
                    val reason = lockedReason ?: L("mw4.ui.locked")
                    if (showLocked) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Icon(Icons.Filled.Lock, null, tint = Ink.muted.copy(alpha = 0.75f), modifier = Modifier.size(10.dp))
                            Spacer(Modifier.width(3.dp))
                            Text(reason, style = sys(11.5f), color = Ink.muted.copy(alpha = 0.75f))
                        }
                    } else {
                        Text(reason, style = sys(13f), color = Ink.muted)
                    }
                }
            } else {
                val line = if (isAvailable) detail else lockedReason
                if (line != null) Text(line, style = sys(13f), color = Ink.muted)
            }
            if (earnedText != null) {
                Text(earnedText, style = sys(11.5f, FontWeight.Medium), color = accent.copy(alpha = 0.85f))
            }
            if (stacksCounter) counter()
        }
        if (!stacksCounter) counter()
    }
    if (askingAmount && requirement != null) {
        NumberDialog(
            title = L("mw4.ui.set_amount.title"), message = L("mw4.ui.set_amount.message", requirement.amount),
            initial = amount, onDismiss = { askingAmount = false }, onSave = onSetAmount,
        )
    }
}

/** iOS's number-pad alert: a title, a line, a field, Cancel and Save. */
@Composable
fun NumberDialog(title: String, message: String, initial: Int, onDismiss: () -> Unit, onSave: (Int) -> Unit) {
    var text by remember { mutableStateOf(initial.toString()) }
    AlertDialog(
        onDismissRequest = onDismiss,
        containerColor = LocalPalette.current.surface2,
        title = { Text(title, color = Ink.text) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Text(message, color = Ink.muted)
                OutlinedTextField(
                    value = text, onValueChange = { v -> text = v.filter(Char::isDigit).take(6) }, singleLine = true,
                    label = { Text(L("mw4.ui.set_amount.field")) },
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                )
            }
        },
        confirmButton = {
            TextButton(onClick = { text.toIntOrNull()?.let(onSave); onDismiss() }) { Text(L("mw4.ui.save")) }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text(L("mw4.ui.cancel")) } },
    )
}

/** A challenge each mode earns its own way: the lead, then a line per mode, the current one first. */
@Composable
fun ModeChallengeList(lead: LocalizedText?, challenges: List<ModeChallenge>, current: String?) {
    val t = AppState.tracker
    val order = t.modeIds
    val known = challenges.filter { it.mode in order }.sortedWith(compareBy({ it.mode != current }, { order.indexOf(it.mode) }))
    Column(verticalArrangement = Arrangement.spacedBy(5.dp)) {
        if (lead != null) Text(lead.resolved(), style = sys(12f), color = Ink.muted)
        for (challenge in known) {
            val isCurrent = challenge.mode == current
            val accent = modeAccent(challenge.mode)
            Row(
                horizontalArrangement = Arrangement.spacedBy(6.dp),
                modifier = Modifier.alpha(if (isCurrent || current == null) 1f else 0.8f),
            ) {
                Icon(modeIcon(challenge.mode), null, tint = accent, modifier = Modifier.padding(top = 2.dp).size(14.dp))
                Text(
                    buildAnnotatedString {
                        withStyle(SpanStyle(fontWeight = FontWeight.Bold, color = if (isCurrent) accent else Ink.muted)) { append(modeName(challenge.mode)) }
                        append("  ")
                        append(challenge.description.resolved())
                    },
                    style = sys(13f), color = if (isCurrent) Ink.text else Ink.muted,
                )
            }
        }
    }
}

/** A camo earned by reaching a count rather than by hand: a check once earned, a lock until then. */
@Composable
fun StatusRow(name: String, achieved: Boolean, color: Color, gradient: List<Color>, detail: String, imageURL: String? = null) {
    Row(
        Modifier.fillMaxWidth().padding(vertical = 5.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Box(Modifier.size(32.dp), contentAlignment = Alignment.Center) {
            if (achieved) Icon(Icons.Filled.CheckCircle, null, tint = color, modifier = Modifier.size(24.dp))
            else Icon(Icons.Filled.Lock, null, tint = Ink.muted.copy(alpha = 0.5f), modifier = Modifier.size(18.dp))
        }
        if (imageURL != null) CamoThumbnail(imageURL, 34.dp, name, modifier = Modifier.alpha(if (achieved) 1f else 0.4f))
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            if (achieved) AnimatedGradientText(name, gradient, size = 15f)
            else Text(name, style = displayStyle(15.sp), color = Ink.muted)
            Text(detail, style = sys(13f), color = Ink.muted)
        }
    }
}

/** "Acquired by: Level 9", "Acquired by: Battle Pass"... */
@Composable
fun AcquiredByLabel(weapon: WeaponEntry, size: Float = 12.5f, color: Color = Ink.muted) {
    val level = weapon.unlockLevel()
    val how = weapon.unlockRequirement?.resolved()
    val text = when {
        level != null -> L("mw4.ui.acquired_by_level", level)
        weapon.acquiredBy == "battlePass" -> L("mw4.ui.acquired_by_battle_pass")
        weapon.acquiredBy == "event" -> L("mw4.ui.acquired_by_event")
        weapon.acquiredBy == "armory" -> L("mw4.ui.acquired_by_armory")
        weapon.acquiredBy == "challenge" && !how.isNullOrEmpty() -> how
        else -> L("mw4.ui.acquired_by_default")
    }
    Text(text, style = sys(size), color = color, maxLines = 1, overflow = TextOverflow.Ellipsis)
}

// MARK: - Filter and sort

enum class ProgressSort(val raw: String, private val key: String) {
    NATURAL("natural", "mw4.ui.sort.default"),
    ALPHABETICAL("alphabetical", "mw4.ui.sort.alphabetical"),
    PROGRESS_DESC("progressDesc", "mw4.ui.sort.progress_desc"),
    PROGRESS_ASC("progressAsc", "mw4.ui.sort.progress_asc"),
    LEVEL("level", "mw4.ui.sort.level");

    val label: String get() = L(key)

    companion object {
        fun from(raw: String) = entries.firstOrNull { it.raw == raw } ?: NATURAL
    }
}

enum class CompletionFilter(val raw: String, private val key: String) {
    ALL("all", "mw4.ui.filter.all"), INCOMPLETE("incomplete", "mw4.ui.filter.incomplete"), COMPLETE("complete", "mw4.ui.filter.complete");

    val label: String get() = L(key)

    companion object {
        fun from(raw: String) = entries.firstOrNull { it.raw == raw } ?: ALL
    }
}

/** iOS's raw values for the weapon filter, so a saved choice reads the same. */
val WeaponFilter.raw: String
    get() = when (this) {
        WeaponFilter.ALL -> "all"
        WeaponFilter.INCOMPLETE -> "incomplete"
        WeaponFilter.COMPLETE -> "complete"
        WeaponFilter.READY -> "ready"
        WeaponFilter.ON_MILITARY -> "onMilitary"
        WeaponFilter.ON_SPECIAL -> "onSpecial"
        WeaponFilter.IN_COMPLETIONIST -> "inCompletionist"
        WeaponFilter.HAS_FINAL -> "hasFinal"
    }

fun weaponFilterFrom(raw: String): WeaponFilter = WeaponFilter.entries.firstOrNull { it.raw == raw } ?: WeaponFilter.ALL

fun WeaponFilter.label(mode: String): String = when (this) {
    WeaponFilter.ALL -> L("mw4.ui.filter.all")
    WeaponFilter.INCOMPLETE -> L("mw4.ui.filter.incomplete")
    WeaponFilter.COMPLETE -> L("mw4.ui.filter.complete")
    WeaponFilter.READY -> L("mw4.ui.filter.ready")
    WeaponFilter.ON_MILITARY -> L("mw4.ui.filter.on_military")
    WeaponFilter.ON_SPECIAL -> L("mw4.ui.filter.on_special")
    WeaponFilter.IN_COMPLETIONIST -> L("mw4.ui.filter.in_completionist")
    WeaponFilter.HAS_FINAL -> L("mw4.ui.filter.has_final", AppState.tracker.lastCompletionist(mode).name)
}

/** "Sort  Default ⇕" in a capsule, opening a menu of the choices with the current one ticked. */
@Composable
fun <T> FilterSortMenu(title: String, options: List<T>, label: (T) -> String, selection: T, accent: Color, onSelect: (T) -> Unit, modifier: Modifier = Modifier) {
    var open by remember { mutableStateOf(false) }
    val palette = LocalPalette.current
    Box(modifier) {
        Row(
            Modifier.fillMaxWidth().clip(CircleShape).background(palette.surface)
                .border(1.dp, palette.surface2, CircleShape).clickable { open = true }.padding(vertical = 9.dp, horizontal = 10.dp),
            horizontalArrangement = Arrangement.spacedBy(6.dp, Alignment.CenterHorizontally),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(title, style = sys(13f, FontWeight.SemiBold), color = Ink.muted, maxLines = 1)
            Text(label(selection), style = sys(13f, FontWeight.SemiBold), color = accent, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f, fill = false))
            Icon(Icons.Filled.UnfoldMore, null, tint = accent, modifier = Modifier.size(13.dp))
        }
        DropdownMenu(open, onDismissRequest = { open = false }, containerColor = palette.surface2) {
            for (option in options) {
                DropdownMenuItem(
                    text = { Text(label(option), color = Ink.text) },
                    leadingIcon = {
                        if (option == selection) Icon(Icons.Filled.Check, null, tint = Ink.text) else Spacer(Modifier.size(24.dp))
                    },
                    onClick = { open = false; onSelect(option) },
                )
            }
        }
    }
}

// MARK: - Readable width

/** The widest a single column of cards and rows gets on a tablet or an unfolded phone. */
val ReadableWidth = 720.dp

/**
 * The side inset that centres a single-column screen at [ReadableWidth] on a
 * wide screen, for a list's content padding: the list itself stays full
 * width, so it scrolls from anywhere. Nothing on a phone.
 */
@Composable
fun readableInset(): Dp {
    val width = androidx.compose.ui.platform.LocalConfiguration.current.screenWidthDp.dp
    return ((width - ReadableWidth) / 2).coerceAtLeast(0.dp)
}

// MARK: - Fitting text

/**
 * [style] shrunk, down to [minScale], until each of [texts] fits [width] on
 * one line: iOS's `minimumScaleFactor`, one size for all of them. For words
 * that would otherwise break mid-word, pass the words.
 */
@Composable
fun fittedStyle(texts: List<String>, style: TextStyle, width: Dp, minScale: Float = 0.5f): TextStyle {
    val measurer = androidx.compose.ui.text.rememberTextMeasurer()
    val px = with(LocalDensity.current) { width.toPx() }
    // As Text sets it: merged over the theme's body style (its letter spacing widens every word)
    val merged = androidx.compose.material3.LocalTextStyle.current.merge(style)
    val widest = texts.maxOfOrNull { measurer.measure(it, merged, maxLines = 1, softWrap = false).size.width } ?: 0
    return if (widest <= px || widest == 0 || px <= 0f) style
    else style.copy(fontSize = style.fontSize * (px / widest * 0.97f).coerceAtLeast(minScale))
}

/** Words of [text]: for [fittedStyle], so a label wraps between words rather than inside one. */
fun words(text: String): List<String> = text.split(' ', '\n').filter { it.isNotEmpty() }

// MARK: - Tabs

/** The app's tab switcher: the picked tab lit in the accent, with a bar along its foot. */
@Composable
fun <T> SegmentTabs(selection: T, items: List<Pair<T, String>>, accent: Color, onSelect: (T) -> Unit, modifier: Modifier = Modifier) {
    val palette = LocalPalette.current
    // Every title at one size, the largest at which they all fit whole
    // (iOS's ViewThatFits), rather than "Completionist" cut to "Comple…"
    BoxWithConstraints(modifier.fillMaxWidth()) {
        val slot = (maxWidth - 8.dp - 4.dp * (items.size - 1)) / items.size.coerceAtLeast(1) - 8.dp
        val style = fittedStyle(items.map { it.second }, displayStyle(15.sp), slot)
    Row(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(9.dp)).background(palette.surface)
            .border(1.dp, palette.surface2, RoundedCornerShape(9.dp)).padding(4.dp),
        horizontalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        for ((value, title) in items) {
            val on = value == selection
            Box(
                Modifier.weight(1f).heightIn(min = 40.dp).clip(RoundedCornerShape(6.dp))
                    .then(
                        if (on) Modifier.background(accent.copy(alpha = 0.18f)).border(1.dp, accent.copy(alpha = 0.45f), RoundedCornerShape(6.dp))
                            .drawBehind {
                                val inset = 14.dp.toPx()
                                val h = 2.5.dp.toPx()
                                drawRoundRect(accent, Offset(inset, size.height - h), Size(size.width - 2 * inset, h),
                                    androidx.compose.ui.geometry.CornerRadius(h / 2))
                            }
                        else Modifier,
                    )
                    .clickable { if (!on) onSelect(value) }
                    .padding(vertical = 9.dp, horizontal = 4.dp),
                contentAlignment = Alignment.Center,
            ) {
                Text(title, style = style, color = if (on) Ink.text else Ink.muted, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
        }
    }
    }
}

// MARK: - Objectives

/** Where an objective can be earned: muted for "All modes", the accent when only some. */
@Composable
fun ObjectiveScopeTag(scope: ObjectiveScope, accent: Color) {
    val tint = if (scope == ObjectiveScope.AllModes) Ink.muted else accent
    Text(
        scope.label().uppercase(appLocale), style = sys(10f, FontWeight.Bold), color = tint, maxLines = 1,
        modifier = Modifier.border(1.dp, tint.copy(alpha = 0.5f), CircleShape).padding(horizontal = 6.dp, vertical = 2.dp),
    )
}

/** A small uppercase eyebrow over a card's title. */
@Composable
fun Eyebrow(text: String, color: Color = Ink.muted) {
    Text(text.uppercase(appLocale), style = sys(11f, FontWeight.Bold), color = color, maxLines = 1, overflow = TextOverflow.Ellipsis)
}

/** A thin rule inside a card. */
@Composable
fun CardDivider() {
    Box(Modifier.fillMaxWidth().height(1.dp).background(Ink.muted.copy(alpha = 0.2f)))
}

/** Grows and shrinks with its content (the iOS `.snappy` animations). */
fun Modifier.animated(): Modifier = this.animateContentSize()
