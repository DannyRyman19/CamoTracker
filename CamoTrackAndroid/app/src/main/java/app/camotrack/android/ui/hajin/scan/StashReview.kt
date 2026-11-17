package app.camotrack.android.ui.hajin.scan

import android.graphics.Bitmap
import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.VectorConverter
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.gestures.detectTransformGestures
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.*
import androidx.compose.material.icons.outlined.Circle
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.camotrack.android.core.hajin.HajinGuide
import app.camotrack.android.core.hajin.HajinStore
import app.camotrack.android.hajin.scan.Pt
import app.camotrack.android.hajin.scan.ScanReport
import app.camotrack.android.hajin.scan.StashGrid
import app.camotrack.android.i18n.L
import app.camotrack.android.ui.*
import app.camotrack.android.ui.hajin.*
import kotlinx.coroutines.launch
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

private class ReviewRow(val item: HajinGuide.Item, val now: Int, val read: Int)

/**
 * What the photos said against what the stash has (iOS
 * HajinStashScanReview); tick off anything misread, then update the stash in
 * one go (with Undo). A stash photo sits over the counts, its tiles lit for
 * the row tapped; a 3D Printer screen's counts come without one.
 */
@Composable
fun StashReview(
    found: Map<String, Int>,
    unsure: Set<String> = emptySet(),
    cash: Int? = null,
    level: Int? = null,
    sureness: Map<String, Float> = emptyMap(),
    stacks: Map<String, Int> = emptyMap(),
    report: ScanReport? = null,
    photo: Bitmap? = null,
    /** Back to the framing screen, to fix the frame and read again */
    onBack: (() -> Unit)?,
    /** After Update or Cancel: the scan is over */
    onDone: () -> Unit,
) {
    val store = hajin()
    val context = LocalContext.current
    val palette = LocalPalette.current
    val haptics = LocalHapticFeedback.current
    var skip by remember { mutableStateOf(setOf<String>()) }
    var edited by remember { mutableStateOf(mapOf<String, Int>()) }
    var editing by remember { mutableStateOf<HajinGuide.Item?>(null) }
    var skipCash by remember { mutableStateOf(false) }
    var skipLevel by remember { mutableStateOf(false) }
    /** The item whose tiles are lit on the photo */
    var highlighted by remember { mutableStateOf<String?>(null) }
    /** The row tapped open, showing its fixes */
    var opened by remember { mutableStateOf<String?>(null) }
    /** Items the player said the reader got wrong: what it read -> what it is */
    var swaps by remember { mutableStateOf(mapOf<String, String>()) }
    var swapping by remember { mutableStateOf<HajinGuide.Item?>(null) }
    var askToSend by Prefs.bool(ASK_SEND_KEY, true)
    var asking by remember { mutableStateOf<SentState?>(null) }

    // What was read, with the player's swaps applied (a swap onto an item also read adds the two together)
    val counts = HashMap<String, Int>().apply { for ((id, n) in found) { val to = swaps[id] ?: id; this[to] = (this[to] ?: 0) + n } }
    /** The id the reader actually read for a row (itself unless swapped in). */
    fun source(id: String) = if (found[id] != null) id else swaps.entries.firstOrNull { it.value == id }?.key ?: id

    fun marks(id: String): List<List<Pt>> {
        val r = report ?: return emptyList()
        if (photo == null || r.corners.size != 4) return emptyList()
        val tiles = r.tiles
        val rows = (tiles.maxOfOrNull { it.row } ?: 0) + 1
        val columns = max((tiles.maxOfOrNull { it.column } ?: 0) + 1, StashGrid.COLUMNS)
        return tiles.filter { (swaps[it.id] ?: it.id) == id }.map { t ->
            // Where the tile was really read, from its own borders
            t.place ?: run {
                val u0 = t.column.toDouble() / columns; val u1 = (t.column + 1.0) / columns
                val v0 = t.row.toDouble() / rows; val v1 = (t.row + 1.0) / rows
                listOf(quadAt(r.corners, u0, v0), quadAt(r.corners, u1, v0), quadAt(r.corners, u1, v1), quadAt(r.corners, u0, v1))
            }
        }
    }

    fun order(id0: String): Pair<Int, Int> {
        // A swapped row keeps the place of the item it was read as
        val id = source(id0)
        // A stash photo: the grid's order, A1 across then down (resources, read from the text, first)
        report?.let { r ->
            val first = r.tiles.filter { it.id == id }.minOfOrNull { it.row * 100 + it.column }
            return (first?.plus(1) ?: 0) to 0
        }
        val sure = sureness[id]?.let { (it * 100).roundToInt() } ?: 100
        if (id in unsure) return 0 to sure
        if (sure < 100) return 1 to sure
        return (if (store.count(id) == found[id]) 3 else 2) to sure
    }

    // Only what My stash tracks: resources, ingredients and valuables
    val rows = counts.mapNotNull { (id, n) ->
        store.guide?.item(id)?.takeIf { HajinStore.inStash(it) }?.let { ReviewRow(it, store.count(id), edited[id] ?: n) }
    }.sortedWith(compareBy<ReviewRow>({ order(it.item.id).first }, { order(it.item.id).second }, { it.item.name.resolved }))
    val changes = rows.filter { it.now != it.read && it.item.id !in skip }
    val cashChange = cash?.takeIf { it != store.cash && !skipCash }
    val levelChange = level?.takeIf { it != store.dmzLevel && !skipLevel }

    LaunchedEffect(Unit) {
        // Start with the first item that can be found on the photo lit
        if (highlighted == null) { highlighted = rows.firstOrNull { marks(it.item.id).isNotEmpty() }?.item?.id; opened = highlighted }
    }

    fun finish() { onDone() }

    fun apply() {
        haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove)
        // What the stash had before this update, for the report
        val had = rows.associate { it.item.id to it.now }
        store.applyScannedCounts(changes.associate { it.item.id to it.read })
        cashChange?.let { store.setCash(it) }
        levelChange?.let { store.setLevel(it) }
        // Stash photos: with everything applied, offer to send the photo
        if (askToSend && report != null) asking = SentState(had, edited, skip, swaps) else finish()
    }

    /** Everything read as `id` (or swapped onto it) is really `to`. */
    fun swap(id: String, to: String) {
        if (id == to) return
        haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove)
        val next = swaps.toMutableMap()
        for ((from, target) in swaps) if (target == id) next[from] = to
        if (found[id] != null) next[id] = to
        // Back to what it was read as: no swap at all
        next.entries.removeAll { it.key == it.value }
        swaps = next
        edited = edited - id - to
        skip = skip - to
        if (highlighted == id) highlighted = to
        if (opened == id) opened = to
    }

    Column(Modifier.fillMaxSize().background(palette.background).systemBarsPadding()) {
        Row(Modifier.fillMaxWidth().height(52.dp).padding(horizontal = 4.dp), verticalAlignment = Alignment.CenterVertically) {
            // Over the framing screen: back to it, to fix the frame and read again (Cancel there ends the scan)
            Box(Modifier.width(96.dp)) {
                if (onBack != null) {
                    TextButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, null, tint = HajinColors.text, modifier = Modifier.size(18.dp))
                        Spacer(Modifier.width(4.dp))
                        Text(L("mw4.ui.hajin.back"), color = HajinColors.text, style = sys(16f))
                    }
                } else TextButton(onClick = ::finish) { Text(L("mw4.ui.hajin.cancel"), color = HajinColors.text, style = sys(16f)) }
            }
            Text(L("mw4.ui.hajin.scan_title"), style = displayStyle(17.sp), color = Ink.text, maxLines = 1, overflow = TextOverflow.Ellipsis,
                textAlign = TextAlign.Center, modifier = Modifier.weight(1f))
            Box(Modifier.width(96.dp), contentAlignment = Alignment.CenterEnd) {
                val enabled = changes.isNotEmpty() || cashChange != null || levelChange != null
                TextButton(onClick = ::apply, enabled = enabled) {
                    Text(L("mw4.ui.hajin.scan_apply"), style = sys(16f, FontWeight.Bold), color = if (enabled) HajinColors.text else Ink.muted)
                }
            }
        }
        PhotoBeside(photo?.let { p -> { ZoomPhoto(p, highlighted?.let { marks(it) } ?: emptyList()) } }) {
            LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(bottom = 32.dp)) {
                item(key = "hint") {
                    if (rows.isEmpty() && cash == null && level == null) {
                        Text(L("mw4.ui.hajin.scan_none"), style = sys(15f), color = Ink.muted, modifier = Modifier.padding(16.dp))
                    } else {
                        Row(Modifier.padding(horizontal = 16.dp, vertical = 10.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            Icon(Icons.Filled.TouchApp, null, tint = Ink.muted, modifier = Modifier.size(16.dp))
                            Text(L("mw4.ui.hajin.scan_edit_hint"), style = sys(12f), color = Ink.muted)
                        }
                    }
                }
                // Level, cash, resources and ingredients each in their own section
                if (level != null) {
                    sectionHeader("level", L("mw4.ui.hajin.dmz_level"))
                    item(key = "level") {
                        ValueRow(Icons.Filled.BarChart, L("mw4.ui.hajin.dmz_level"), if (store.dmzLevel > 0) "${store.dmzLevel}" else "–",
                            "$level", level == store.dmzLevel, skipLevel) { skipLevel = !skipLevel }
                    }
                }
                if (cash != null) {
                    sectionHeader("cash", L("mw4.ui.hajin.cash_title"))
                    item(key = "cash") {
                        ValueRow(Icons.Filled.Payments, L("mw4.ui.hajin.cash_title"), money(store.cash), money(cash), cash == store.cash, skipCash) { skipCash = !skipCash }
                    }
                }
                val groups = listOf(
                    L("mw4.ui.hajin.resources") to rows.filter { it.item.kind == "Resource" }.sortedBy { HajinStore.resourceRank(it.item.id) },
                    L("mw4.ui.hajin.ingredients") to rows.filter { it.item.kind == "Ingredient" },
                    L("mw4.ui.hajin.valuables") to rows.filter { it.item.kind == "Valuable" },
                )
                for ((title, list) in groups) {
                    if (list.isEmpty()) continue
                    sectionHeader(title, title)
                    for (row in list) item(key = "row-${row.item.id}") {
                        val id = row.item.id
                        val same = row.now == row.read
                        val on = !same && id !in skip
                        val swapped = id in swaps.values
                        ItemRow(
                            row = row, same = same, on = on, swapped = swapped,
                            check = id in unsure && edited[id] == null,
                            sure = sureness[id]?.takeIf { !swapped }, stacks = stacks[id] ?: 1,
                            findable = marks(id).isNotEmpty(), lit = highlighted == id, open = opened == id,
                            canChange = swapped || sureness[id] != null,
                            onTap = {
                                haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                                // Selected means lit and its fixes open, in one tap
                                if (opened == id) { opened = null; highlighted = null } else { opened = id; highlighted = id }
                            },
                            onStep = { n -> edited = edited + (id to max(0, n)); skip = skip - id },
                            onEdit = { editing = row.item },
                            onToggle = { skip = if (id in skip) skip - id else skip + id },
                            onChange = { swapping = row.item },
                            onRemove = { skip = skip + id; opened = null; highlighted = null },
                        )
                    }
                }
            }
        }
    }

    editing?.let { item ->
        val current = edited[item.id] ?: counts[item.id] ?: 0
        HajinNumberDialog(item.name.resolved, "0", "$current", { editing = null }) { n ->
            if (n != null) { edited = edited + (item.id to n); skip = skip - item.id }
        }
    }
    swapping?.let { item ->
        ItemPicker(item, onCancel = { swapping = null }) { picked -> swap(item.id, picked); swapping = null }
    }
    asking?.let { sent ->
        AlertDialog(
            onDismissRequest = { asking = null; finish() },
            containerColor = palette.surface2,
            title = { Text(L("mw4.ui.hajin.send_ask_title"), color = Ink.text) },
            text = { Text(L("mw4.ui.hajin.send_ask_message"), color = Ink.muted) },
            confirmButton = {
                Column(horizontalAlignment = Alignment.End) {
                    TextButton(onClick = {
                        asking = null
                        report?.let { ScanReportMail.send(context, it, photo, sent.had, sent.edited, sent.skipped, sent.swapped) }
                        finish()
                    }) { Text(L("mw4.ui.hajin.send_ask_send"), color = HajinColors.text, fontWeight = FontWeight.Bold) }
                    TextButton(onClick = { askToSend = false; asking = null; finish() }) { Text(L("mw4.ui.hajin.send_ask_never"), color = HajinColors.text) }
                    TextButton(onClick = { asking = null; finish() }) { Text(L("mw4.ui.hajin.send_ask_later"), color = HajinColors.text) }
                }
            },
        )
    }
}

/** iOS `mw4_hajin_ask_send_scan`: offer to send the photo after Update. */
const val ASK_SEND_KEY = "mw4_hajin_ask_send_scan"

private class SentState(val had: Map<String, Int>, val edited: Map<String, Int>, val skipped: Set<String>, val swapped: Map<String, String>)

internal fun LazyListScope.sectionHeader(key: String, title: String) {
    item(key = "h-$key") {
        Text(title.uppercase(appLocale), style = sys(12f, FontWeight.SemiBold).copy(letterSpacing = 0.5.sp), color = Ink.muted,
            modifier = Modifier.padding(start = 16.dp, end = 16.dp, top = 16.dp, bottom = 6.dp))
    }
}

/** A grouped-list row's ground, lit when its item is lit on the photo. */
@Composable
internal fun Modifier.reviewRow(lit: Boolean = false): Modifier =
    this.padding(horizontal = 12.dp, vertical = 2.dp).fillMaxWidth().clip(RoundedCornerShape(10.dp))
        .background(if (lit) HajinColors.accent.copy(alpha = 0.14f) else LocalPalette.current.surface)

/** "10 · Already right": the value, then the note. */
@Composable
private fun SameLabel(value: String) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        Text(value, style = sys(13f, FontWeight.SemiBold, mono = true), color = Ink.text)
        Text(L("mw4.ui.hajin.scan_same"), style = sys(12f), color = Ink.muted)
        Icon(Icons.Filled.Check, null, tint = HajinColors.printable, modifier = Modifier.size(14.dp))
    }
}

/** A single value read from the photo (level, cash), now -> read, tap to skip. */
@Composable
private fun ValueRow(icon: ImageVector, title: String, now: String, read: String, same: Boolean, skipped: Boolean, toggle: () -> Unit) {
    Row(
        Modifier.reviewRow().clickable(enabled = !same, onClick = toggle).padding(12.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Icon(icon, null, tint = HajinColors.text, modifier = Modifier.size(24.dp))
        Text(title, style = sys(15f, FontWeight.SemiBold), color = Ink.text, modifier = Modifier.weight(1f))
        if (same) SameLabel(read) else {
            Text("$now → $read", style = sys(13f, FontWeight.SemiBold, mono = true).copy(textDecoration = if (skipped) TextDecoration.LineThrough else null),
                color = if (skipped) Ink.muted else Ink.text)
            Icon(if (skipped) Icons.Outlined.Circle else Icons.Filled.CheckCircle, null, tint = if (skipped) Ink.muted else HajinColors.text, modifier = Modifier.size(22.dp))
        }
    }
}

@Composable
private fun ItemRow(
    row: ReviewRow, same: Boolean, on: Boolean, swapped: Boolean, check: Boolean, sure: Float?, stacks: Int,
    findable: Boolean, lit: Boolean, open: Boolean, canChange: Boolean,
    onTap: () -> Unit, onStep: (Int) -> Unit, onEdit: () -> Unit, onToggle: () -> Unit, onChange: () -> Unit, onRemove: () -> Unit,
) {
    Column(Modifier.reviewRow(lit).padding(horizontal = 12.dp, vertical = 10.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            // Tap the item to see its tiles on the photo
            Row(Modifier.weight(1f).clickable(onClick = onTap), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                FindableTile(row.item, 32.dp, findable, lit)
                Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text(row.item.name.resolved, style = sys(15f, FontWeight.SemiBold), color = Ink.text, maxLines = 2, overflow = TextOverflow.Ellipsis)
                    Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                        if (swapped) Icon(Icons.Filled.SwapHoriz, L("mw4.ui.hajin.scan_swapped"), tint = HajinColors.text, modifier = Modifier.size(14.dp))
                        else if (check) CheckTag()
                        if (sure != null) {
                            Text(L("mw4.ui.hajin.scan_sure", stacks, (sure * 100).roundToInt()), style = sys(11f),
                                color = if (sure < 0.5f) Amber else Ink.muted)
                        }
                    }
                }
            }
            // What the stash has now, then the count it becomes
            if (!same) Text("${row.now} →", style = sys(12f, FontWeight.SemiBold, mono = true), color = Ink.muted, maxLines = 1)
            CountControl(row.read, on || same, onStep, onEdit)
            if (same) {
                Icon(Icons.Filled.Check, L("mw4.ui.hajin.scan_same"), tint = HajinColors.printable, modifier = Modifier.size(24.dp))
            } else {
                // Include or leave out this change
                Icon(if (on) Icons.Filled.CheckCircle else Icons.Outlined.Circle, null, tint = if (on) HajinColors.text else Ink.muted,
                    modifier = Modifier.size(28.dp).clip(CircleShape).clickable(onClick = onToggle).padding(2.dp))
            }
        }
        // Tapped: its fixes, sharing the row's width
        AnimatedVisibility(open) {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                // Read off the photo's tiles: wrong item? pick the right one
                if (canChange) FixButton(L("mw4.ui.hajin.scan_change"), Icons.Filled.SwapHoriz, onChange)
                FixButton(L("mw4.ui.hajin.scan_edit"), Icons.Filled.Edit, onEdit)
                // A misread to drop: the stash keeps what it has
                if (!same) FixButton(L("mw4.ui.postmatch.remove"), Icons.Filled.Delete, onRemove)
            }
        }
    }
}

@Composable
internal fun CheckTag() {
    Text(L("mw4.ui.hajin.scan_check"), style = sys(11f, FontWeight.Bold), color = Color.Black.copy(alpha = 0.85f),
        modifier = Modifier.clip(CircleShape).background(Amber).padding(horizontal = 6.dp, vertical = 1.dp))
}

/** The item's picture, with a viewfinder badge when its tiles can be lit on the photo. */
@Composable
internal fun FindableTile(item: HajinGuide.Item, size: androidx.compose.ui.unit.Dp, findable: Boolean, lit: Boolean) {
    Box {
        ItemTile(item, size)
        if (findable) {
            Box(
                Modifier.align(Alignment.BottomEnd).offset(4.dp, 4.dp).size(14.dp).clip(CircleShape)
                    .background(if (lit) HajinColors.accent else Color.Black.copy(alpha = 0.6f)),
                contentAlignment = Alignment.Center,
            ) { Icon(Icons.Filled.CenterFocusWeak, null, tint = Color.White, modifier = Modifier.size(10.dp)) }
        }
    }
}

/** A fix under the tapped row. */
@Composable
internal fun RowScope.FixButton(title: String, icon: ImageVector, onClick: () -> Unit) {
    Row(
        Modifier.weight(1f).clip(CircleShape).background(HajinColors.accent.copy(alpha = 0.14f)).clickable(onClick = onClick).padding(vertical = 8.dp),
        horizontalArrangement = Arrangement.Center, verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(icon, null, tint = HajinColors.text, modifier = Modifier.size(14.dp))
        Spacer(Modifier.width(4.dp))
        Text(title, style = sys(12f, FontWeight.SemiBold), color = HajinColors.text, maxLines = 1)
    }
}

/** − count +: steps the count read from the photo, or tap the number to type it. */
@Composable
private fun CountControl(read: Int, on: Boolean, onStep: (Int) -> Unit, onEdit: () -> Unit) {
    Row(Modifier.clip(CircleShape).background(LocalPalette.current.surface2), verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.size(30.dp).clickable(enabled = read > 0) { onStep(read - 1) }, contentAlignment = Alignment.Center) {
            Icon(Icons.Filled.Remove, null, tint = if (read > 0) HajinColors.text else Ink.muted, modifier = Modifier.size(16.dp))
        }
        Text("$read", style = sys(14f, FontWeight.SemiBold, mono = true).copy(textDecoration = if (on) null else TextDecoration.LineThrough),
            color = if (on) Ink.text else Ink.muted, textAlign = TextAlign.Center, maxLines = 1,
            modifier = Modifier.widthIn(min = 30.dp).clickable(onClick = onEdit).padding(vertical = 6.dp))
        Box(Modifier.size(30.dp).clickable { onStep(read + 1) }, contentAlignment = Alignment.Center) {
            Icon(Icons.Filled.Add, null, tint = HajinColors.text, modifier = Modifier.size(16.dp))
        }
    }
}

/**
 * The review's photo: on top of the counts, or to their left when the
 * screen is wide and held sideways (iOS HajinPhotoBeside).
 */
@Composable
internal fun PhotoBeside(photo: (@Composable () -> Unit)?, content: @Composable () -> Unit) {
    if (photo == null) { Box(Modifier.fillMaxSize()) { content() }; return }
    BoxWithConstraints(Modifier.fillMaxSize()) {
        val line = LocalPalette.current.surface2
        val w = maxWidth; val h = maxHeight
        if (w >= 700.dp && w > h) {
            Row(Modifier.fillMaxSize()) {
                Box(Modifier.fillMaxHeight().width(w * 0.55f)) { photo() }
                Box(Modifier.fillMaxHeight().width(1.dp).background(line))
                Box(Modifier.weight(1f)) { content() }
            }
        } else {
            Column(Modifier.fillMaxSize()) {
                Box(Modifier.fillMaxWidth().height(h * 0.45f)) { photo() }
                Box(Modifier.fillMaxWidth().height(1.dp).background(line))
                Box(Modifier.weight(1f)) { content() }
            }
        }
    }
}

/**
 * A photo to pinch and drag (iOS HajinZoomPhoto): double-tap zooms in
 * there or back out, and lit tiles (each four corners as fractions) are
 * outlined and zoomed to.
 */
@Composable
fun ZoomPhoto(image: Bitmap, marks: List<List<Pt>>) {
    val photo = remember(image) { image.asImageBitmap() }
    val scope = rememberCoroutineScope()
    BoxWithConstraints(Modifier.fillMaxSize().background(Color.Black).clipToBounds()) {
        val density = LocalDensity.current
        val box = with(density) { Size(maxWidth.toPx(), maxHeight.toPx()) }
        val fit = fitted(image.width, image.height, box)
        val zoom = remember { Animatable(1f) }
        val pan = remember { Animatable(Offset.Zero, Offset.VectorConverter) }
        fun clamp(p: Offset, z: Float) = Offset(
            p.x.coerceIn(-max(0f, (fit.width * z - box.width) / 2), max(0f, (fit.width * z - box.width) / 2)),
            p.y.coerceIn(-max(0f, (fit.height * z - box.height) / 2), max(0f, (fit.height * z - box.height) / 2)),
        )
        /** Zooms so `rect` (in the fitted photo's pixels) fills the view, centred. */
        fun zoomTo(cx: Float, cy: Float, side: Float) {
            val z = min(box.width / side, box.height / side).coerceIn(1f, 6f)
            val target = clamp(Offset(-(cx - fit.width / 2) * z, -(cy - fit.height / 2) * z), z)
            scope.launch { zoom.animateTo(z, tween(350)) }
            scope.launch { pan.animateTo(target, tween(350)) }
        }
        // Draws the lit tiles and zooms to fit them (or back out with none)
        LaunchedEffect(marks, fit) {
            val points = marks.flatten()
            if (points.isEmpty()) {
                launch { zoom.animateTo(1f, tween(350)) }; launch { pan.animateTo(Offset.Zero, tween(350)) }
                return@LaunchedEffect
            }
            val minX = points.minOf { it.x } * fit.width; val maxX = points.maxOf { it.x } * fit.width
            val minY = points.minOf { it.y } * fit.height; val maxY = points.maxOf { it.y } * fit.height
            // Room round the tiles, and no closer than 4x
            val side = max(max(maxX - minX, maxY - minY), min(fit.width, fit.height) / 4.0) * 1.6
            zoomTo(((minX + maxX) / 2).toFloat(), ((minY + maxY) / 2).toFloat(), side.toFloat())
        }
        Box(
            Modifier.fillMaxSize()
                .pointerInput(fit) {
                    detectTapGestures(onDoubleTap = { at ->
                        if (zoom.value > 1.01f) {
                            scope.launch { zoom.animateTo(1f, tween(300)) }; scope.launch { pan.animateTo(Offset.Zero, tween(300)) }
                        } else {
                            // The tapped point in the fitted photo's pixels
                            val x = (at.x - box.width / 2) + fit.width / 2; val y = (at.y - box.height / 2) + fit.height / 2
                            zoomTo(x, y, min(fit.width, fit.height) / 3)
                        }
                    })
                }
                .pointerInput(fit) {
                    detectTransformGestures { _, panChange, zoomChange, _ ->
                        val z = (zoom.value * zoomChange).coerceIn(1f, 6f)
                        val p = clamp(pan.value * (z / zoom.value) + panChange, z)
                        scope.launch { zoom.snapTo(z); pan.snapTo(p) }
                    }
                },
            contentAlignment = Alignment.Center,
        ) {
            Box(
                Modifier.size(with(density) { fit.width.toDp() }, with(density) { fit.height.toDp() })
                    .graphicsLayer { scaleX = zoom.value; scaleY = zoom.value; translationX = pan.value.x; translationY = pan.value.y },
            ) {
                Image(photo, null, contentScale = ContentScale.FillBounds, modifier = Modifier.fillMaxSize())
                Canvas(Modifier.fillMaxSize()) {
                    for (quad in marks) {
                        if (quad.size != 4) continue
                        val path = Path().apply {
                            moveTo((quad[0].x * size.width).toFloat(), (quad[0].y * size.height).toFloat())
                            for (p in quad.drop(1)) lineTo((p.x * size.width).toFloat(), (p.y * size.height).toFloat())
                            close()
                        }
                        drawPath(path, HajinColors.accent.copy(alpha = 0.25f))
                        // Lines the same width on screen at any zoom
                        drawPath(path, HajinColors.accent, style = Stroke(2.5.dp.toPx() / zoom.value))
                    }
                }
            }
        }
        if (zoom.value <= 1.01f) {
            Row(
                Modifier.align(Alignment.BottomEnd).padding(8.dp).clip(CircleShape).background(Color.Black.copy(alpha = 0.55f))
                    .padding(horizontal = 8.dp, vertical = 4.dp),
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp),
            ) {
                Icon(Icons.Filled.OpenInFull, null, tint = Color.White.copy(alpha = 0.85f), modifier = Modifier.size(12.dp))
                Text(L("mw4.ui.hajin.zoom_hint"), style = sys(11f, FontWeight.SemiBold), color = Color.White.copy(alpha = 0.85f))
            }
        }
    }
}

/**
 * "Not this item?" (iOS HajinItemPicker): every item My stash counts, the
 * same kind as the misread one first, to pick the one it really is.
 */
@Composable
fun ItemPicker(current: HajinGuide.Item, onCancel: () -> Unit, onPick: (String) -> Unit) {
    val store = hajin()
    val palette = LocalPalette.current
    var query by remember { mutableStateOf("") }
    val needle = query.lowercase()
    val all = (store.guide?.items ?: emptyList())
        .filter { HajinStore.inStash(it) && it.kind != "Resource" && it.id != current.id }
        .filter { needle.isEmpty() || it.name.resolved.lowercase().contains(needle) }
        .sortedBy { it.name.resolved }
    val alike = all.filter { it.kind == current.kind }
    val rest = all.filter { it.kind != current.kind }
    val valuable = current.kind == "Valuable"
    BackHandler(onBack = onCancel)
    Column(Modifier.fillMaxSize().background(palette.background).systemBarsPadding()) {
        Row(Modifier.fillMaxWidth().height(52.dp).padding(horizontal = 4.dp), verticalAlignment = Alignment.CenterVertically) {
            TextButton(onClick = onCancel) { Text(L("mw4.ui.hajin.cancel"), color = HajinColors.text, style = sys(16f)) }
            Text(L("mw4.ui.hajin.scan_swap_title"), style = displayStyle(17.sp), color = Ink.text, textAlign = TextAlign.Center, modifier = Modifier.weight(1f))
            Spacer(Modifier.width(88.dp))
        }
        HajinSearchField(query, L("mw4.ui.hajin.search_guide")) { query = it }
        LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(bottom = 24.dp)) {
            for ((title, list) in listOf(
                L(if (valuable) "mw4.ui.hajin.valuables" else "mw4.ui.hajin.ingredients") to alike,
                L(if (valuable) "mw4.ui.hajin.ingredients" else "mw4.ui.hajin.valuables") to rest,
            )) {
                if (list.isEmpty()) continue
                sectionHeader(title, title)
                for (item in list) item(key = "p-${item.id}") {
                    Row(
                        Modifier.reviewRow().clickable { onPick(item.id) }.padding(horizontal = 12.dp, vertical = 8.dp),
                        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp),
                    ) {
                        ItemTile(item, 36.dp)
                        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                            Text(item.name.resolved, style = sys(15f, FontWeight.SemiBold), color = Ink.text)
                            item.rarity?.let { Text(it, style = sys(12f), color = HajinColors.rarity(it)) }
                        }
                    }
                }
            }
        }
    }
}
