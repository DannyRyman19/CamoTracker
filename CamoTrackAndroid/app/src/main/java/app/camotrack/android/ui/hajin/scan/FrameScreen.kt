package app.camotrack.android.ui.hajin.scan

import android.graphics.Bitmap
import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.gestures.detectTransformGestures
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.blur
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.*
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Fill
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.camotrack.android.hajin.scan.PostMatchReader
import app.camotrack.android.hajin.scan.Pt
import app.camotrack.android.hajin.scan.StashGrid
import app.camotrack.android.i18n.L
import app.camotrack.android.ui.*
import app.camotrack.android.ui.hajin.HajinColors
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt
import kotlin.math.sin

internal val Amber = Color(0xFFF5A83D)

/** A point on the quad TL, TR, BR, BL at (u, v), in the quad's own units. */
internal fun quadAt(k: List<Pt>, u: Double, v: Double): Pt {
    val top = Pt(k[0].x + (k[1].x - k[0].x) * u, k[0].y + (k[1].y - k[0].y) * u)
    val bottom = Pt(k[3].x + (k[2].x - k[3].x) * u, k[3].y + (k[2].y - k[3].y) * u)
    return Pt(top.x + (bottom.x - top.x) * v, top.y + (bottom.y - top.y) * v)
}

/** The photo's size fitted into a box. */
internal fun fitted(w: Int, h: Int, box: Size): Size {
    val s = min(box.width / max(w, 1), box.height / max(h, 1))
    return Size(w * s, h * s)
}

/**
 * The photo with four handles: drag them to the outside corners of the tile
 * grid, with a preview of the grid following them (iOS
 * HajinStashGridFrameView). Pinch to zoom in and place them exactly.
 * Stash or Backpack at the top, guessed from the photo's text; Read reads
 * it, and the review comes up over this screen.
 */
@Composable
fun FrameScreen(picked: PickedPhoto) {
    val state = picked.frame
    val image = picked.bitmap
    val context = LocalContext.current
    val palette = LocalPalette.current
    val haptics = LocalHapticFeedback.current
    val scope = rememberCoroutineScope()
    val photo = remember(image) { image.asImageBitmap() }
    var cropping by remember { mutableStateOf(false) }
    var another by remember { mutableStateOf(false) }
    var zoom by remember { mutableFloatStateOf(1f) }
    var pan by remember { mutableStateOf(Offset.Zero) }
    val lockGlow = remember { Animatable(0f) }

    fun remeasure() {
        val frame = state.corners
        // A backpack is a few rows of square tiles: its shape says how many
        if (state.postMatch) { state.rowCount = PostMatchReader.rows(frame, image.width, image.height); return }
        val columns = state.columns
        scope.launch {
            val n = runCatching { ScanFlow.work(context) { it.rows(image, frame) } }.getOrNull() ?: return@launch
            if (frame == state.corners && columns == state.columns) state.rowCount = n
        }
    }

    /** Looks for the grid and frames it, with the scan sweeping meanwhile. */
    suspend fun findGrid() {
        val started = System.currentTimeMillis()
        val postMatch = state.postMatch
        val guess = runCatching { ScanFlow.work(context) { it.guessCorners(image, postMatch) } }.getOrNull()
        // Switched again while looking: that search has taken over
        if (postMatch != state.postMatch) return
        // At least one sweep, so a quick find still reads as a scan rather than a flicker
        val left = 1300 - (System.currentTimeMillis() - started)
        if (left > 0) delay(left)
        state.guess = guess
        if (guess != null && !state.moved) state.corners = guess
        state.finding = false
        if (guess != null) {
            haptics.performHapticFeedback(HapticFeedbackType.LongPress)
            scope.launch { lockGlow.snapTo(1f); delay(200); lockGlow.animateTo(0f, tween(900)) }
        }
        remeasure()
    }

    /** Stash <-> backpack: a different grid (6 or 4 wide), looked for again from scratch. */
    fun switchKind(backpack: Boolean) {
        if (backpack == state.postMatch || state.finding || state.reading) return
        state.postMatch = backpack
        state.moved = false
        state.guess = null
        state.rowCount = null
        state.finding = true
        scope.launch { findGrid() }
    }

    fun read() {
        if (state.reading || state.finding) return
        state.reading = true
        val frame = state.corners
        scope.launch {
            if (state.postMatch) {
                val guide = ScanFlow.guideItems()
                val r = runCatching { ScanFlow.work(context) { it.readPostMatch(image, frame, guide) } }.getOrNull()
                state.reading = false
                state.postMatchResult = r
                if (r == null) android.widget.Toast.makeText(context, L("ct.android.hajin.scan_read_failed"), android.widget.Toast.LENGTH_LONG).show()
            } else {
                val resources = ScanFlow.stashItems().filter { it.kind == "Resource" }
                val quality = state.quality; val guess = state.guess; val moved = state.moved
                val r = runCatching { ScanFlow.work(context) { it.readStash(image, frame, resources, guess, moved, quality) } }.getOrNull()
                state.reading = false
                state.result = r
                if (r == null) android.widget.Toast.makeText(context, L("ct.android.hajin.scan_read_failed"), android.widget.Toast.LENGTH_LONG).show()
            }
        }
    }

    LaunchedEffect(picked.id) {
        // Once per photo: the screen can be rebuilt, and must not re-guess
        if (state.guessed) return@LaunchedEffect
        state.guessed = true
        state.quality = runCatching { ScanFlow.work(context) { it.quality(image) } }.getOrDefault(emptyList())
        findGrid()
    }

    BackHandler { ScanFlow.end() }
    Column(Modifier.fillMaxSize().background(palette.background).systemBarsPadding()) {
        // Cancel | title | Read
        Row(Modifier.fillMaxWidth().height(52.dp).padding(horizontal = 4.dp), verticalAlignment = Alignment.CenterVertically) {
            TextButton(onClick = { ScanFlow.end() }) { Text(L("mw4.ui.hajin.cancel"), color = HajinColors.text, style = sys(16f)) }
            Text(L(if (state.postMatch) "mw4.ui.postmatch.title" else "mw4.ui.hajin.grid_scan"), style = displayStyle(17.sp), color = Ink.text,
                maxLines = 1, textAlign = TextAlign.Center, modifier = Modifier.weight(1f))
            Box(Modifier.width(88.dp), contentAlignment = Alignment.Center) {
                if (state.reading) CircularProgressIndicator(Modifier.size(22.dp), color = HajinColors.accent, strokeWidth = 2.5.dp)
                else TextButton(onClick = ::read, enabled = !state.finding) {
                    Text(L("mw4.ui.hajin.grid_read"), style = sys(16f, FontWeight.Bold), color = if (state.finding) Ink.muted else HajinColors.text)
                }
            }
        }
        // What's being read, as guessed from the photo: switch it if the guess is wrong
        Box(Modifier.padding(horizontal = 12.dp).padding(top = 4.dp).alpha(if (state.finding || state.reading) 0.5f else 1f)) {
            SegmentTabs(state.postMatch, listOf(false to L("mw4.ui.hajin.read_as_stash"), true to L("mw4.ui.hajin.read_as_backpack")),
                HajinColors.accent, { switchKind(it) })
        }
        val lost = !state.finding && state.guessed && state.guess == null
        if (state.quality.isNotEmpty() || lost) {
            // The photo looks poor or the grid wasn't found: say why, and offer a crop or another photo
            Row(
                Modifier.padding(horizontal = 12.dp, vertical = 8.dp).fillMaxWidth().clip(RoundedCornerShape(10.dp)).background(palette.surface).padding(12.dp),
                horizontalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                Icon(Icons.Filled.Warning, null, tint = Amber, modifier = Modifier.size(20.dp))
                Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    if (lost) Text(L("mw4.ui.hajin.grid_not_found"), style = sys(14f), color = Ink.text)
                    for (issue in state.quality) Text(L("mw4.ui.hajin.quality_${issue.key}"), style = sys(14f), color = Ink.text)
                    Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                        Row(Modifier.clickable { cropping = true }, verticalAlignment = Alignment.CenterVertically) {
                            Icon(Icons.Filled.Crop, null, tint = HajinColors.text, modifier = Modifier.size(16.dp))
                            Spacer(Modifier.width(4.dp))
                            Text(L("mw4.ui.hajin.crop_offer"), style = sys(14f, FontWeight.SemiBold), color = HajinColors.text)
                        }
                        Box {
                            Text(L("mw4.ui.hajin.quality_retake"), style = sys(14f, FontWeight.SemiBold), color = HajinColors.text,
                                modifier = Modifier.clickable { if (ScanFlow.hasCamera) another = true else { ScanFlow.replacing = true; ScanFlow.pickPhotos() } })
                            // "Choose another photo": the library, or the camera where there is one
                            DropdownMenu(another, onDismissRequest = { another = false }, containerColor = palette.surface2) {
                                DropdownMenuItem(text = { Text(L("mw4.ui.hajin.grid_choose")) }, leadingIcon = { Icon(Icons.Filled.PhotoLibrary, null) },
                                    onClick = { another = false; ScanFlow.replacing = true; ScanFlow.pickPhotos() })
                                DropdownMenuItem(text = { Text(L("mw4.ui.hajin.grid_camera")) }, leadingIcon = { Icon(Icons.Filled.PhotoCamera, null) },
                                    onClick = { another = false; ScanFlow.replacing = true; ScanFlow.takePhoto() })
                            }
                        }
                    }
                }
            }
        }
        BoxWithConstraints(Modifier.weight(1f).fillMaxWidth().padding(horizontal = 8.dp, vertical = 8.dp).clipToBounds()) {
            val density = LocalDensity.current
            val box = with(density) { Size(maxWidth.toPx(), maxHeight.toPx()) }
            val fit = fitted(image.width, image.height, box)
            fun clampPan(p: Offset, z: Float) = Offset(
                p.x.coerceIn(-max(0f, (fit.width * z - box.width) / 2), max(0f, (fit.width * z - box.width) / 2)),
                p.y.coerceIn(-max(0f, (fit.height * z - box.height) / 2), max(0f, (fit.height * z - box.height) / 2)),
            )
            Box(
                Modifier.fillMaxSize()
                    // Double-tap: back out to the whole photo
                    .pointerInput(Unit) { detectTapGestures(onDoubleTap = { zoom = 1f; pan = Offset.Zero }) }
                    // Pinch in to place the corners exactly; one finger moves the photo while zoomed
                    .pointerInput(fit) {
                        detectTransformGestures { _, panChange, zoomChange, _ ->
                            val z = (zoom * zoomChange).coerceIn(1f, 5f)
                            val scaled = pan * (z / zoom)
                            pan = clampPan(if (z > 1f) scaled + panChange else Offset.Zero, z)
                            zoom = z
                        }
                    },
                contentAlignment = Alignment.Center,
            ) {
                val wDp = with(density) { fit.width.toDp() }; val hDp = with(density) { fit.height.toDp() }
                Box(Modifier.size(wDp, hDp).graphicsLayer { scaleX = zoom; scaleY = zoom; translationX = pan.x; translationY = pan.y }) {
                    Image(photo, null, contentScale = ContentScale.FillBounds, modifier = Modifier.fillMaxSize())
                    val rows = state.rowCount ?: StashGrid.rows(state.corners, image.width, image.height, state.columns)
                    if (state.finding) GridScanning(Modifier.fillMaxSize())
                    else if (state.reading) GridReading(state.corners, state.columns, rows, Modifier.fillMaxSize())
                    // The framed quad with the column lines and estimated row lines
                    Canvas(Modifier.fillMaxSize().alpha(if (state.finding || state.reading) 0f else 1f)) {
                        drawPath(frameLines(state.corners, state.columns, rows, size), HajinColors.accent, style = Stroke(1.5.dp.toPx() / zoom))
                    }
                    // A glow round the frame as it locks on
                    if (lockGlow.value > 0f) Canvas(Modifier.fillMaxSize().blur(6.dp).alpha(lockGlow.value)) {
                        drawPath(frameLines(state.corners, state.columns, rows, size), HajinColors.accent, style = Stroke(6.dp.toPx()))
                    }
                    if (!state.finding && !state.reading) {
                        for (i in 0 until 4) {
                            val p = state.corners[i]
                            // The same size on screen however far in it's zoomed
                            val touch = 48f / zoom
                            Box(
                                Modifier
                                    .offset { IntOffset((p.x * fit.width - touch.dp.toPx() / 2).roundToInt(), (p.y * fit.height - touch.dp.toPx() / 2).roundToInt()) }
                                    .size(touch.dp)
                                    .pointerInput(i, fit) {
                                        detectDragGestures(onDragEnd = { remeasure() }) { change, drag ->
                                            change.consume()
                                            state.moved = true
                                            val c = state.corners[i]
                                            state.corners = state.corners.toMutableList().also {
                                                it[i] = Pt((c.x + drag.x / fit.width).coerceIn(0.0, 1.0), (c.y + drag.y / fit.height).coerceIn(0.0, 1.0))
                                            }
                                        }
                                    },
                                contentAlignment = Alignment.Center,
                            ) {
                                Box(Modifier.size((34f / zoom).dp).clip(CircleShape).background(HajinColors.accent.copy(alpha = 0.35f))
                                    .border((2f / zoom).dp, Color.White, CircleShape))
                            }
                        }
                    }
                }
            }
        }
        // Once the grid's been looked for: what to check, and Crop
        if (!state.finding && !state.reading) {
            Row(
                Modifier.padding(horizontal = 12.dp).padding(bottom = 8.dp).fillMaxWidth().borderedCard().padding(12.dp),
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                Box(Modifier.size(34.dp).clip(RoundedCornerShape(8.dp)).background(HajinColors.accent.copy(alpha = 0.16f)), contentAlignment = Alignment.Center) {
                    Icon(Icons.Filled.GridOn, null, tint = HajinColors.text, modifier = Modifier.size(18.dp))
                }
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text(L("mw4.ui.hajin.grid_check_title"), style = displayStyle(15.sp), color = Ink.text)
                    Text(L(if (state.postMatch) "mw4.ui.postmatch.frame" else "mw4.ui.hajin.grid_check_body"), style = sys(12f), color = Ink.muted)
                }
                Row(
                    Modifier.clip(CircleShape).background(HajinColors.accent).clickable { cropping = true }.padding(horizontal = 14.dp, vertical = 9.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Icon(Icons.Filled.Crop, null, tint = Color.Black.copy(alpha = 0.85f), modifier = Modifier.size(16.dp))
                    Spacer(Modifier.width(4.dp))
                    Text(L("mw4.ui.hajin.crop_title"), style = sys(14f, FontWeight.Bold), color = Color.Black.copy(alpha = 0.85f))
                }
            }
        } else {
            Box(Modifier.fillMaxWidth().padding(bottom = 24.dp), contentAlignment = Alignment.Center) {
                Row(
                    Modifier.clip(CircleShape).background(palette.surface2).padding(horizontal = 14.dp, vertical = 8.dp),
                    verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp),
                ) {
                    Icon(if (state.reading) Icons.Filled.GridOn else Icons.Filled.CenterFocusWeak, null, tint = Ink.text, modifier = Modifier.size(16.dp))
                    Text(L(when {
                        !state.reading -> "mw4.ui.hajin.grid_finding"
                        state.postMatch -> "mw4.ui.hajin.grid_reading_backpack"
                        else -> "mw4.ui.hajin.grid_reading"
                    }), style = sys(14f, FontWeight.SemiBold), color = Ink.text)
                }
            }
        }
    }

    if (cropping) {
        CropScreen(image, onCancel = { cropping = false }) { cut ->
            cropping = false
            ScanFlow.photo = PickedPhoto(cut, state.postMatch)
        }
    }
    state.result?.let { r ->
        BackHandler { state.result = null }
        StashReview(
            found = r.counts, unsure = r.unsure, cash = r.cash, level = r.level, sureness = r.sureness, stacks = r.stacks,
            report = r.report, photo = image, onBack = { state.result = null }, onDone = { ScanFlow.end() },
        )
    }
    state.postMatchResult?.let { r ->
        BackHandler { state.postMatchResult = null }
        PostMatchReview(r, image, onBack = { state.postMatchResult = null }, onDone = { ScanFlow.end() })
    }
}

/** The quad's outline with its column and row lines, in a box of `size`. */
internal fun frameLines(corners: List<Pt>, columns: Int, rows: Int, size: Size): Path = Path().apply {
    fun at(u: Double, v: Double): Offset = quadAt(corners, u, v).let { Offset((it.x * size.width).toFloat(), (it.y * size.height).toFloat()) }
    for (c in 0..columns) {
        val u = c.toDouble() / columns
        at(u, 0.0).let { moveTo(it.x, it.y) }; at(u, 1.0).let { lineTo(it.x, it.y) }
    }
    val r = max(rows, 1)
    for (i in 0..r) {
        val v = i.toDouble() / r
        at(0.0, v).let { moveTo(it.x, it.y) }; at(1.0, v).let { lineTo(it.x, it.y) }
    }
}

/** Seconds since this went on screen, a frame at a time (held still with animations off). */
@Composable
private fun clock(): State<Double> {
    val still = reducedMotion()
    return produceState(0.0) {
        if (still) return@produceState
        val start = withFrameNanos { it }
        while (true) withFrameNanos { value = (it - start) / 1e9 }
    }
}

/**
 * Over the photo while the grid is being found (iOS HajinGridScanning): the
 * photo dims, a scan line sweeps down and back, crosshair marks light up as
 * it passes, and viewfinder brackets breathe at the corners.
 */
@Composable
private fun GridScanning(modifier: Modifier) {
    val t by clock()
    val still = reducedMotion()
    Canvas(modifier) {
        val sweep = 1.3
        val phase = (t / sweep) % 2
        val raw = if (phase < 1) phase else 2 - phase
        val y = if (still) 0.5 else (1 - cos(raw * PI)) / 2
        val down = phase < 1
        val pulse = 0.5 + 0.5 * sin(t * 4)
        drawRect(Color.Black.copy(alpha = 0.35f))
        // A field of small crosshairs that light up near the scan line
        val cols = 12
        val rows = max(6, (cols * size.height / size.width).toInt())
        for (r in 0..rows) for (c in 0..cols) {
            val px = size.width * c / cols; val py = size.height * r / rows
            val near = max(0.0, 1 - abs(py / size.height - y) * 6)
            val arm = (3 + 3 * near).dp.toPx()
            val color = HajinColors.accent.copy(alpha = (0.15 + 0.75 * near).toFloat())
            drawLine(color, Offset(px - arm, py), Offset(px + arm, py), 1.dp.toPx())
            drawLine(color, Offset(px, py - arm), Offset(px, py + arm), 1.dp.toPx())
        }
        // The bright line with a fading trail behind it
        val trail = min(90.dp.toPx(), size.height * 0.3f)
        val lineY = (size.height * y).toFloat()
        val top = if (down) lineY - trail else lineY
        drawRect(
            Brush.verticalGradient(
                if (down) listOf(HajinColors.accent.copy(alpha = 0f), HajinColors.accent.copy(alpha = 0.45f))
                else listOf(HajinColors.accent.copy(alpha = 0.45f), HajinColors.accent.copy(alpha = 0f)),
                startY = top, endY = top + trail,
            ),
            topLeft = Offset(0f, top), size = Size(size.width, trail),
        )
        drawRect(HajinColors.accent.copy(alpha = 0.5f), Offset(0f, lineY - 4.dp.toPx()), Size(size.width, 8.dp.toPx()))
        drawRect(Color.White, Offset(0f, lineY - 1.dp.toPx()), Size(size.width, 2.dp.toPx()))
        // Viewfinder corners, breathing in and out a little
        val inset = (10 + 6 * pulse).dp.toPx()
        val arm = min(size.width, size.height) * 0.12f
        val w = size.width; val h = size.height
        val brackets = Path().apply {
            for ((x, yy, dx, dy) in listOf(
                listOf(inset, inset, 1f, 1f), listOf(w - inset, inset, -1f, 1f),
                listOf(w - inset, h - inset, -1f, -1f), listOf(inset, h - inset, 1f, -1f),
            )) {
                moveTo(x, yy + arm * dy); lineTo(x, yy); lineTo(x + arm * dx, yy)
            }
        }
        drawPath(brackets, Color.White.copy(alpha = (0.6 + 0.4 * pulse).toFloat()),
            style = Stroke(3.dp.toPx(), cap = StrokeCap.Round, join = StrokeJoin.Round))
    }
}

/**
 * Reading the framed grid (iOS HajinGridReading): everything outside it
 * dimmed, and its tiles lit one at a time in reading order, the ones done
 * left faintly filled, round and round until the read is back.
 */
@Composable
private fun GridReading(corners: List<Pt>, columns: Int, rows: Int, modifier: Modifier) {
    val t by clock()
    val still = reducedMotion()
    Canvas(modifier) {
        if (corners.size != 4) return@Canvas
        val cells = max(columns * max(rows, 1), 1)
        val cycle = (cells + 6).toDouble()
        val at = if (still) cells.toDouble() else (t / 0.07) % cycle
        fun point(u: Double, v: Double) = quadAt(corners, u, v).let { Offset((it.x * size.width).toFloat(), (it.y * size.height).toFloat()) }
        fun cell(r: Int, c: Int, inset: Double): Path = Path().apply {
            val u0 = (c + inset) / columns; val u1 = (c + 1 - inset) / columns
            val v0 = (r + inset) / rows; val v1 = (r + 1 - inset) / rows
            point(u0, v0).let { moveTo(it.x, it.y) }; point(u1, v0).let { lineTo(it.x, it.y) }
            point(u1, v1).let { lineTo(it.x, it.y) }; point(u0, v1).let { lineTo(it.x, it.y) }; close()
        }
        val grid = Path().apply {
            point(0.0, 0.0).let { moveTo(it.x, it.y) }; point(1.0, 0.0).let { lineTo(it.x, it.y) }
            point(1.0, 1.0).let { lineTo(it.x, it.y) }; point(0.0, 1.0).let { lineTo(it.x, it.y) }; close()
        }
        // Dim all but the grid
        val outside = Path().apply { fillType = PathFillType.EvenOdd; addRect(Rect(Offset.Zero, size)); addPath(grid) }
        drawPath(outside, Color.Black.copy(alpha = 0.55f), style = Fill)
        drawPath(grid, HajinColors.accent.copy(alpha = 0.8f), style = Stroke(1.5.dp.toPx()))
        val current = at.toInt()
        for (i in 0 until cells) {
            val r = i / columns; val c = i % columns
            if (i < current) drawPath(cell(r, c, 0.08), HajinColors.accent.copy(alpha = 0.18f))
            else if (i == current) {
                val p = cell(r, c, 0.04)
                drawPath(p, HajinColors.accent.copy(alpha = 0.35f))
                drawPath(p, HajinColors.accent.copy(alpha = 0.6f), style = Stroke(6.dp.toPx()))
                drawPath(p, Color.White, style = Stroke(2.dp.toPx()))
            }
        }
    }
}

/**
 * From the framing screen (iOS HajinCropView): drag the box's corners in to
 * just the stash (or the backpack), or drag inside it to move it, so the
 * grid finder sees nothing else and the tiles fill more of the photo.
 */
@Composable
private fun CropScreen(image: Bitmap, onCancel: () -> Unit, onDone: (Bitmap) -> Unit) {
    val palette = LocalPalette.current
    val photo = remember(image) { image.asImageBitmap() }
    // The box, as fractions of the photo: left, top, right, bottom
    var box by remember { mutableStateOf(Rect(0f, 0f, 1f, 1f)) }
    val minSide = 0.1f
    val untouched = box == Rect(0f, 0f, 1f, 1f)
    BackHandler(onBack = onCancel)
    Column(Modifier.fillMaxSize().background(palette.background).systemBarsPadding()) {
        Row(Modifier.fillMaxWidth().height(52.dp).padding(horizontal = 4.dp), verticalAlignment = Alignment.CenterVertically) {
            TextButton(onClick = onCancel) { Text(L("mw4.ui.hajin.cancel"), color = HajinColors.text, style = sys(16f)) }
            Text(L("mw4.ui.hajin.crop_title"), style = displayStyle(17.sp), color = Ink.text, textAlign = TextAlign.Center, modifier = Modifier.weight(1f))
            TextButton(enabled = !untouched, onClick = {
                val x = (box.left * image.width).roundToInt().coerceIn(0, image.width - 1)
                val y = (box.top * image.height).roundToInt().coerceIn(0, image.height - 1)
                val w = (box.width * image.width).roundToInt().coerceIn(1, image.width - x)
                val h = (box.height * image.height).roundToInt().coerceIn(1, image.height - y)
                onDone(Bitmap.createBitmap(image, x, y, w, h))
            }) { Text(L("mw4.ui.hajin.crop_done"), style = sys(16f, FontWeight.Bold), color = if (untouched) Ink.muted else HajinColors.text) }
        }
        Text(L("mw4.ui.hajin.crop_hint"), style = sys(14f), color = Ink.muted, modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp))
        BoxWithConstraints(Modifier.weight(1f).fillMaxWidth().padding(12.dp), contentAlignment = Alignment.Center) {
            val density = LocalDensity.current
            val fit = fitted(image.width, image.height, with(density) { Size(maxWidth.toPx(), maxHeight.toPx()) })
            Box(Modifier.size(with(density) { fit.width.toDp() }, with(density) { fit.height.toDp() })) {
                Image(photo, null, contentScale = ContentScale.FillBounds, modifier = Modifier.fillMaxSize())
                val r = Rect(box.left * fit.width, box.top * fit.height, box.right * fit.width, box.bottom * fit.height)
                Canvas(Modifier.fillMaxSize()
                    // Drag inside to move the box
                    .pointerInput(fit) {
                        detectDragGestures { change, drag ->
                            change.consume()
                            val b = box
                            val dx = (drag.x / fit.width).coerceIn(-b.left, 1 - b.right)
                            val dy = (drag.y / fit.height).coerceIn(-b.top, 1 - b.bottom)
                            box = b.translate(dx, dy)
                        }
                    }) {
                    // Dim what's cut away
                    val outside = Path().apply { fillType = PathFillType.EvenOdd; addRect(Rect(Offset.Zero, size)); addRect(r) }
                    drawPath(outside, Color.Black.copy(alpha = 0.6f))
                    drawRect(HajinColors.accent, r.topLeft, r.size, style = Stroke(2.dp.toPx()))
                }
                for (i in 0 until 4) {
                    val x = if (i == 0 || i == 3) r.left else r.right
                    val y = if (i < 2) r.top else r.bottom
                    Box(
                        Modifier.offset { IntOffset((x - 24.dp.toPx()).roundToInt(), (y - 24.dp.toPx()).roundToInt()) }.size(48.dp)
                            .pointerInput(i, fit) {
                                detectDragGestures { change, drag ->
                                    change.consume()
                                    val b = box
                                    val dx = drag.x / fit.width; val dy = drag.y / fit.height
                                    var l = b.left; var t = b.top; var rr = b.right; var bb = b.bottom
                                    if (i == 0 || i == 3) l = (l + dx).coerceIn(0f, rr - minSide) else rr = (rr + dx).coerceIn(l + minSide, 1f)
                                    if (i < 2) t = (t + dy).coerceIn(0f, bb - minSide) else bb = (bb + dy).coerceIn(t + minSide, 1f)
                                    box = Rect(l, t, rr, bb)
                                }
                            },
                        contentAlignment = Alignment.Center,
                    ) {
                        Box(Modifier.size(26.dp).clip(CircleShape).background(HajinColors.accent).border(2.dp, Color.White, CircleShape))
                    }
                }
            }
        }
    }
}
