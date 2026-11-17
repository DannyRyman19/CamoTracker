package app.camotrack.android.ui.hajin

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import androidx.compose.animation.core.animate
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.gestures.detectTransformGestures
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.graphics.FilterQuality
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.Shadow
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.graphics.vector.VectorPainter
import androidx.compose.ui.graphics.vector.rememberVectorPainter
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.camotrack.android.core.hajin.HajinGuide
import app.camotrack.android.core.hajin.HajinPin
import app.camotrack.android.i18n.L
import app.camotrack.android.ui.*
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min

/** What a tap on the map picked: one of the guide's markers or one of the player's own pins. */
private sealed interface MapPick {
    val id: String
    data class Marker(val marker: HajinGuide.Marker) : MapPick { override val id get() = marker.id }
    data class Pin(override val id: String) : MapPick
}

/** One thing drawn over the map: where, from what zoom (past the whole map) it shows, and what a tap on it picks. */
private class Overlay(
    val pick: MapPick,
    val x: Double, val y: Double,
    val minZoom: Float,
    val label: String? = null,
    val labelSize: Float = 0f,
    val labelWeight: FontWeight = FontWeight.Normal,
    val colour: Color = Color.White,
    val icon: String? = null,
    val number: Int? = null,
    val pin: Boolean = false,
    /** A Fortress's name under its icon: drawn, but taps go to the icon. */
    val caption: Boolean = false,
)

/** Where the map sits: zoom in screen px per map px, and how far it's scrolled (iOS's UIScrollView). */
private class Viewport {
    var zoom by mutableFloatStateOf(0f)
    var panX by mutableFloatStateOf(0f)
    var panY by mutableFloatStateOf(0f)
    var size by mutableStateOf(IntSize.Zero)
    var map = Size(1f, 1f)

    val fit: Float get() = min(size.width / map.width, size.height / map.height)
    val maxZoom: Float get() = max(fit * 4, 2f)
    private fun insetX(z: Float = zoom) = max((size.width - map.width * z) / 2, 0f)
    private fun insetY(z: Float = zoom) = max((size.height - map.height * z) / 2, 0f)

    fun toScreen(x: Double, y: Double) = Offset((x * map.width * zoom).toFloat() - panX + insetX(), (y * map.height * zoom).toFloat() - panY + insetY())
    fun toMap(p: Offset) = Offset((p.x + panX - insetX()) / (map.width * zoom), (p.y + panY - insetY()) / (map.height * zoom))
    val imageTopLeft: Offset get() = Offset(-panX + insetX(), -panY + insetY())

    fun clamp() {
        panX = panX.coerceIn(0f, max(map.width * zoom - size.width, 0f))
        panY = panY.coerceIn(0f, max(map.height * zoom - size.height, 0f))
    }

    /** Zooms by `factor` keeping `centroid` (screen px) on the same spot of the map. */
    fun zoomBy(factor: Float, centroid: Offset) {
        val anchor = toMap(centroid)
        zoom = (zoom * factor).coerceIn(fit, maxZoom)
        panX = anchor.x * map.width * zoom - centroid.x + insetX()
        panY = anchor.y * map.height * zoom - centroid.y + insetY()
        clamp()
    }

    /** The pan that puts a map point (0...1) across the middle, a third of the way down. */
    fun panFor(x: Double, y: Double, z: Float): Offset {
        val px = (x * map.width * z).toFloat() - size.width / 2f
        val py = (y * map.height * z).toFloat() - size.height * 0.3f
        return Offset(px.coerceIn(0f, max(map.width * z - size.width, 0f)), py.coerceIn(0f, max(map.height * z - size.height, 0f)))
    }

    fun set(z: Float, pan: Offset) { zoom = z; panX = pan.x; panY = pan.y; clamp() }
}

/**
 * The Tac Map on its own screen (iOS HajinMapScreen): pan and pinch-zoom a
 * large picture with the markers drawn over it at a fixed size, names that
 * only show once there's room, a tap for a marker's details, press and hold
 * to drop a pin, a filter and a search.
 */
@Composable
fun HajinMapScreen(startAt: String?) {
    val store = hajin()
    val guide = store.guide ?: return
    val context = LocalContext.current
    val density = LocalDensity.current
    val haptics = LocalHapticFeedback.current
    val scope = rememberCoroutineScope()
    var image by remember { mutableStateOf<ImageBitmap?>(null) }
    var selection by remember { mutableStateOf<MapPick?>(null) }
    var newPin by remember { mutableStateOf<HajinPin?>(null) }
    var editing by remember { mutableStateOf<HajinPin?>(null) }
    var showsFilters by remember { mutableStateOf(false) }
    var showsSearch by remember { mutableStateOf(false) }
    val view = remember { Viewport() }
    var pendingFocus by remember { mutableStateOf<HajinGuide.Marker?>(startAt?.let { guide.marker(it) }) }

    LaunchedEffect(guide.map.image) {
        image = withContext(Dispatchers.IO) {
            runCatching {
                context.assets.open("${guide.map.image}.jpg").use { input ->
                    // Decoded once, off the main thread, straight to the GPU so the first pan doesn't stutter
                    BitmapFactory.decodeStream(input, null, BitmapFactory.Options().apply { inPreferredConfig = Bitmap.Config.HARDWARE })
                }?.asImageBitmap()
            }.getOrNull()
        }
    }

    fun fly(marker: HajinGuide.Marker) {
        store.reveal(marker)
        selection = MapPick.Marker(marker)
        if (view.zoom <= 0f) { pendingFocus = marker; return }
        val fromZoom = view.zoom
        val from = Offset(view.panX, view.panY)
        val toZoom = min(max(view.zoom, view.fit * 4), view.maxZoom)
        val to = view.panFor(marker.x, marker.y, toZoom)
        scope.launch {
            animate(0f, 1f, animationSpec = tween(350)) { t, _ ->
                view.set(fromZoom + (toZoom - fromZoom) * t, Offset(from.x + (to.x - from.x) * t, from.y + (to.y - from.y) * t))
            }
        }
    }

    // A start marker: its category on, picked, and flown to once there's a size
    LaunchedEffect(Unit) { pendingFocus?.let { store.reveal(it); selection = MapPick.Marker(it) } }

    val hidden = store.hiddenCategories
    val overlays = remember(guide, hidden, store.pins) { overlays(guide, hidden, store.pins) }
    val painters: Map<String, androidx.compose.ui.graphics.painter.Painter> = guide.categories.associate { it.id to categoryPainter(it) } +
        ("pin" to rememberVectorPainter(Icons.Filled.Place))
    val measurer = rememberTextMeasurer(cacheSize = 256)

    Column(Modifier.fillMaxSize().background(LocalPalette.current.background)) {
        TopBar(L("mw4.ui.hajin.tac_map")) {
            IconButton(onClick = { showsSearch = true }) { Icon(Icons.Filled.Search, L("mw4.ui.hajin.search_map"), tint = HajinColors.text) }
            IconButton(onClick = { showsFilters = true }) { Icon(Icons.Filled.FilterList, L("mw4.ui.hajin.filters"), tint = HajinColors.text) }
        }
        Box(Modifier.fillMaxSize().clipToBounds().background(Color(0xFF0B0F0D))) {
            val bitmap = image
            if (bitmap == null) {
                CircularProgressIndicator(Modifier.align(Alignment.Center), color = Color.White)
            } else {
                view.map = Size(bitmap.width.toFloat(), bitmap.height.toFloat())
                Canvas(
                    Modifier.fillMaxSize()
                        .onSizeChanged { size ->
                            val first = view.size == IntSize.Zero
                            view.size = size
                            if (first || view.zoom < view.fit) {
                                // Open a little closer than the whole map, on the city
                                val tall = size.height > size.width * 1.3f
                                val zoom = min(max(view.fit * (if (tall) 2.3f else 1.6f), size.width / view.map.width), view.maxZoom)
                                view.set(zoom, view.panFor(0.5, if (tall) 0.72 else 0.55, zoom))
                            }
                            pendingFocus?.let { marker ->
                                pendingFocus = null
                                val zoom = min(view.fit * 4, view.maxZoom)
                                view.set(zoom, view.panFor(marker.x, marker.y, zoom))
                            }
                            view.clamp()
                        }
                        .pointerInput(Unit) {
                            detectTransformGestures { centroid, pan, zoom, _ ->
                                if (zoom != 1f) view.zoomBy(zoom, centroid)
                                view.panX -= pan.x
                                view.panY -= pan.y
                                view.clamp()
                            }
                        }
                        .pointerInput(overlays) {
                            detectTapGestures(
                                onTap = { point -> selection = nearest(overlays, view, point, density.density) },
                                onDoubleTap = { point ->
                                    val from = view.zoom
                                    val to = min(view.zoom * 2, view.maxZoom)
                                    scope.launch {
                                        var last = from
                                        animate(from, to, animationSpec = tween(300)) { z, _ -> view.zoomBy(z / last, point); last = z }
                                    }
                                },
                                onLongPress = { point ->
                                    haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                                    val at = view.toMap(point)
                                    if (at.x in 0f..1f && at.y in 0f..1f) newPin = HajinPin(x = at.x.toDouble(), y = at.y.toDouble(), title = "", note = "")
                                },
                            )
                        },
                ) {
                    if (view.zoom <= 0f) return@Canvas
                    val topLeft = view.imageTopLeft
                    drawImage(
                        bitmap, srcOffset = androidx.compose.ui.unit.IntOffset.Zero, srcSize = IntSize(bitmap.width, bitmap.height),
                        dstOffset = androidx.compose.ui.unit.IntOffset(topLeft.x.toInt(), topLeft.y.toInt()),
                        dstSize = IntSize((bitmap.width * view.zoom).toInt(), (bitmap.height * view.zoom).toInt()),
                        filterQuality = FilterQuality.Medium,
                    )
                    drawOverlays(overlays, view, selection, painters, measurer, guide)
                }

                // The threat colours the area names use, top right, clear of the hint
                ThreatLegend(guide, Modifier.align(Alignment.TopEnd).padding(10.dp).padding(top = 36.dp))
                Text(
                    L("mw4.ui.hajin.long_press_hint"), style = sys(11f, FontWeight.SemiBold), color = Color.White.copy(alpha = 0.85f),
                    modifier = Modifier.align(Alignment.TopCenter).padding(top = 8.dp).clip(CircleShape).background(Color.Black.copy(alpha = 0.55f))
                        .padding(horizontal = 10.dp, vertical = 5.dp),
                )
                selection?.let { picked ->
                    SelectionCard(picked, onEdit = { editing = it }, dismiss = { selection = null },
                        modifier = Modifier.align(Alignment.BottomCenter))
                }
            }
        }
    }

    newPin?.let { pin -> PinEditor(pin, isNew = true) { saved -> saved?.let { store.addPin(it); selection = MapPick.Pin(it.id) }; newPin = null } }
    editing?.let { pin -> PinEditor(pin, isNew = false) { saved -> saved?.let(store::updatePin); editing = null } }
    if (showsFilters) FilterSheet(guide) { showsFilters = false }
    if (showsSearch) MapSearchSheet(guide, { showsSearch = false }) { marker -> showsSearch = false; fly(marker) }
}

/** Every marker and pin to draw: names first so the icons sit on top of them. */
private fun overlays(guide: HajinGuide, hidden: Set<String>, pins: List<HajinPin>): List<Overlay> {
    // A Fortress named like its area already has its name on the map
    val areaNames = guide.markers.filter { it.cat == "area" }.map { it.name.resolved.lowercase() }.toSet()
    val ordered = guide.markers.sortedBy { if (guide.category(it.cat)?.isLabel == true) 0 else 1 }
    val out = mutableListOf<Overlay>()
    for (marker in ordered) {
        if (marker.cat in hidden) continue
        val category = guide.category(marker.cat) ?: continue
        val pick = MapPick.Marker(marker)
        val name = marker.name.resolved
        if (category.isLabel) {
            val area = category.id == "area"
            // Area names take their threat colour, Low green to Extreme red
            val colour = marker.threat?.let { HajinColors.threat(it) } ?: if (area) Color.White else Color(0xFFD9D9D9)
            out += Overlay(pick, marker.x, marker.y, if (area) 0f else 2.5f, label = name.uppercase(appLocale),
                labelSize = if (area) 14f else 11f, labelWeight = if (area) FontWeight.ExtraBold else FontWeight.SemiBold, colour = colour)
        } else {
            val number = marker.symbol?.substringBefore('.')?.toIntOrNull()
            out += Overlay(pick, marker.x, marker.y, 0f, colour = categoryTint(category), icon = category.id, number = number)
            val threat = marker.threat
            if (category.id == "fortress" && threat != null && name.lowercase() !in areaNames) {
                out += Overlay(pick, marker.x, marker.y, 3f, label = name.uppercase(appLocale), labelSize = 10f, labelWeight = FontWeight.Bold,
                    colour = HajinColors.threat(threat), caption = true)
            }
        }
    }
    for (pin in pins) out += Overlay(MapPick.Pin(pin.id), pin.x, pin.y, 0f, colour = HajinColors.pin, icon = "pin", pin = true)
    return out
}

/** Nearest shown marker within a finger's reach of a tap, else nothing (which deselects). */
private fun nearest(overlays: List<Overlay>, view: Viewport, point: Offset, density: Float): MapPick? {
    val zoomed = view.zoom / max(view.fit, 0.0001f)
    val reach = 28 * density
    var best: Pair<MapPick, Float>? = null
    for (overlay in overlays) {
        if (overlay.caption || zoomed < overlay.minZoom) continue
        val at = view.toScreen(overlay.x, overlay.y)
        val half = if (overlay.label != null) Size(overlay.label.length * overlay.labelSize * 0.35f * density + reach / 2, overlay.labelSize * density + reach / 2)
        else Size(13 * density + reach / 2, 13 * density + reach / 2)
        if (point.x !in at.x - half.width..at.x + half.width || point.y !in at.y - half.height..at.y + half.height) continue
        val distance = hypot(at.x - point.x, at.y - point.y)
        if (best == null || distance < best.second) best = overlay.pick to distance
    }
    return best?.first
}

/** Markers keep their on-screen size whatever the zoom; small place names only appear once there's room. */
private fun DrawScope.drawOverlays(
    overlays: List<Overlay>, view: Viewport, selection: MapPick?, painters: Map<String, androidx.compose.ui.graphics.painter.Painter>,
    measurer: androidx.compose.ui.text.TextMeasurer, guide: HajinGuide,
) {
    val zoomed = view.zoom / max(view.fit, 0.0001f)
    val margin = 60.dp.toPx()
    val bounds = Rect(-margin, -margin, size.width + margin, size.height + margin)
    var selectedLast: Overlay? = null
    for (overlay in overlays) {
        if (zoomed < overlay.minZoom) continue
        val at = view.toScreen(overlay.x, overlay.y)
        if (!bounds.contains(at)) continue
        val selected = selection?.id == overlay.pick.id && !overlay.caption
        // The picked one goes on top
        if (selected && overlay.label == null) { selectedLast = overlay; continue }
        drawOverlay(overlay, at, selected, painters, measurer)
    }
    selectedLast?.let { drawOverlay(it, view.toScreen(it.x, it.y), true, painters, measurer) }
}

private fun DrawScope.drawOverlay(overlay: Overlay, at: Offset, selected: Boolean, painters: Map<String, androidx.compose.ui.graphics.painter.Painter>, measurer: androidx.compose.ui.text.TextMeasurer) {
    val label = overlay.label
    if (label != null) {
        val y = if (overlay.caption) at.y + 20.dp.toPx() else at.y
        // Picked names go white and glow in their own colour, so a pick never reads as another threat level
        val style = TextStyle(
            fontSize = overlay.labelSize.sp, fontWeight = overlay.labelWeight, textAlign = TextAlign.Center,
            color = if (selected) Color.White else overlay.colour,
            shadow = Shadow(if (selected) overlay.colour else Color.Black, blurRadius = if (selected) 12f else 6f),
        )
        val layout: TextLayoutResult = measurer.measure(label, style, maxLines = 2, constraints = Constraints(maxWidth = 140.dp.roundToPx()))
        drawText(layout, topLeft = Offset(at.x - layout.size.width / 2f, y - layout.size.height / 2f))
        return
    }
    val radius = (if (selected) 17 else 13).dp.toPx()
    drawCircle(Color.Black.copy(alpha = 0.45f), radius + 2.dp.toPx(), at)
    drawCircle(if (overlay.pin) Color(0xF2332903) else Color(0xEB141A17), radius, at)
    drawCircle(overlay.colour, radius, at, style = Stroke((if (selected) 2.5f else 1.5f).dp.toPx()))
    val number = overlay.number
    if (number != null) {
        val layout = measurer.measure("$number", TextStyle(fontSize = (radius * 0.75f).toSp(), fontWeight = FontWeight.Bold, color = overlay.colour))
        drawText(layout, topLeft = Offset(at.x - layout.size.width / 2f, at.y - layout.size.height / 2f))
        return
    }
    val painter = overlay.icon?.let { painters[it] } ?: return
    val side = radius * 1.12f
    translate(at.x - side / 2, at.y - side / 2) {
        with(painter) { draw(Size(side, side), colorFilter = ColorFilter.tint(overlay.colour)) }
    }
}

/** The threat colours the map's area names use, Low to Extreme. */
@Composable
private fun ThreatLegend(guide: HajinGuide, modifier: Modifier) {
    Column(modifier.clip(RoundedCornerShape(8.dp)).background(Color.Black.copy(alpha = 0.6f)).padding(8.dp), verticalArrangement = Arrangement.spacedBy(3.dp)) {
        Text(L("mw4.ui.hajin.threat_legend").uppercase(appLocale), style = sys(9f, FontWeight.ExtraBold).copy(letterSpacing = 0.8.sp), color = Color.White.copy(alpha = 0.7f))
        guide.threatLevels.forEachIndexed { index, level ->
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                Box(Modifier.size(7.dp).clip(CircleShape).background(HajinColors.threat(index + 1)))
                Text(level.resolved, style = sys(10f, FontWeight.SemiBold), color = Color.White.copy(alpha = 0.9f))
            }
        }
    }
}

/** The tapped marker or pin, in a card over the foot of the map, which stays usable behind it. */
@Composable
private fun SelectionCard(pick: MapPick, onEdit: (HajinPin) -> Unit, dismiss: () -> Unit, modifier: Modifier) {
    val store = hajin()
    val shape = RoundedCornerShape(16.dp)
    Box(
        modifier.padding(12.dp).fillMaxWidth().heightIn(max = 320.dp).clip(shape)
            .background(LocalPalette.current.surface.copy(alpha = 0.97f)).border(1.dp, Ink.muted.copy(alpha = 0.25f), shape),
    ) {
        Column(Modifier.verticalScroll(rememberScrollState()).padding(16.dp).padding(end = 24.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            when (pick) {
                is MapPick.Marker -> MarkerDetails(pick.marker)
                is MapPick.Pin -> store.pins.firstOrNull { it.id == pick.id }?.let { pin ->
                    PinDetails(pin, onEdit = { onEdit(pin) }, onDelete = { store.removePin(pin.id); dismiss() })
                }
            }
        }
        IconButton(onClick = dismiss, modifier = Modifier.align(Alignment.TopEnd)) {
            Icon(Icons.Filled.Cancel, L("mw4.ui.hajin.done"), tint = Ink.muted)
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun MarkerDetails(marker: HajinGuide.Marker) {
    val store = hajin()
    val category = store.guide?.category(marker.cat)
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        Icon(categoryPainter(category), null, tint = categoryTint(category), modifier = Modifier.size(24.dp))
        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(marker.name.resolved, style = sys(20f, FontWeight.ExtraBold), color = Ink.text)
            category?.let { Text(it.name.resolved, style = sys(15f), color = Ink.muted) }
        }
    }
    val threat = marker.threat
    val threatName = threat?.let { store.guide?.threatName(it) }
    if (threat != null && threatName != null) {
        val tint = HajinColors.threat(threat)
        Row(
            Modifier.clip(CircleShape).background(tint.copy(alpha = 0.15f)).padding(horizontal = 10.dp, vertical = 5.dp),
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp),
        ) {
            Icon(Icons.Filled.Warning, null, tint = tint, modifier = Modifier.size(13.dp))
            Text(L("mw4.ui.hajin.threat", threatName), style = sys(13f, FontWeight.Bold), color = tint)
        }
    }
    marker.note?.let { Text(it.resolved, style = sys(17f), color = Ink.text) }
    marker.parts?.takeIf { it.isNotEmpty() }?.let { parts ->
        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text(L("mw4.ui.hajin.inside").uppercase(appLocale), style = sys(12f, FontWeight.ExtraBold).copy(letterSpacing = 1.2.sp), color = Ink.muted)
            FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                for (part in parts) {
                    val tint = part.threat?.let { HajinColors.threat(it) } ?: Ink.muted
                    Row(
                        Modifier.clip(CircleShape).background(LocalPalette.current.surface2).border(1.dp, tint.copy(alpha = 0.5f), CircleShape)
                            .padding(horizontal = 8.dp, vertical = 4.dp),
                        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp),
                    ) {
                        Box(Modifier.size(7.dp).clip(CircleShape).background(tint))
                        Text(part.name.resolved, style = sys(12f, FontWeight.SemiBold), color = Ink.text)
                    }
                }
            }
        }
    }
    category?.blurb?.let { Text(it.resolved, style = sys(15f), color = Ink.muted) }
}

@Composable
private fun PinDetails(pin: HajinPin, onEdit: () -> Unit, onDelete: () -> Unit) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        Icon(Icons.Filled.Place, null, tint = HajinColors.pin, modifier = Modifier.size(24.dp))
        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(pin.title.ifEmpty { L("mw4.ui.hajin.my_pin") }, style = sys(20f, FontWeight.ExtraBold), color = Ink.text)
            Text(L("mw4.ui.hajin.my_pin"), style = sys(15f), color = Ink.muted)
        }
    }
    if (pin.note.isNotEmpty()) Text(pin.note, style = sys(17f), color = Ink.text)
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        OutlinedButton(onClick = onEdit) {
            Icon(Icons.Filled.Edit, null, tint = HajinColors.text, modifier = Modifier.size(16.dp))
            Spacer(Modifier.width(6.dp))
            Text(L("mw4.ui.hajin.edit_pin"), color = HajinColors.text)
        }
        OutlinedButton(onClick = onDelete) {
            Icon(Icons.Filled.Delete, null, tint = HajinColors.short, modifier = Modifier.size(16.dp))
            Spacer(Modifier.width(6.dp))
            Text(L("mw4.ui.hajin.delete_pin"), color = HajinColors.short)
        }
    }
}

@Composable
private fun PinEditor(start: HajinPin, isNew: Boolean, finish: (HajinPin?) -> Unit) {
    var title by remember { mutableStateOf(start.title) }
    var note by remember { mutableStateOf(start.note) }
    AlertDialog(
        onDismissRequest = { finish(null) },
        containerColor = LocalPalette.current.surface2,
        title = { Text(L(if (isNew) "mw4.ui.hajin.new_pin" else "mw4.ui.hajin.edit_pin"), color = Ink.text) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                OutlinedTextField(title, { title = it }, singleLine = true, label = { Text(L("mw4.ui.hajin.pin_name")) })
                OutlinedTextField(note, { note = it }, minLines = 3, maxLines = 8, label = { Text(L("mw4.ui.hajin.pin_note")) })
            }
        },
        confirmButton = { TextButton(onClick = { finish(start.copy(title = title, note = note)) }) { Text(L("mw4.ui.hajin.save"), color = HajinColors.text) } },
        dismissButton = { TextButton(onClick = { finish(null) }) { Text(L("mw4.ui.hajin.cancel"), color = HajinColors.text) } },
    )
}

/** Each category's switch and count, with Show all and Hide all. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun FilterSheet(guide: HajinGuide, dismiss: () -> Unit) {
    val store = hajin()
    var menu by remember { mutableStateOf(false) }
    ModalBottomSheet(onDismissRequest = dismiss, containerColor = LocalPalette.current.surface2) {
        Row(Modifier.fillMaxWidth().padding(horizontal = 8.dp), verticalAlignment = Alignment.CenterVertically) {
            Box {
                TextButton(onClick = { menu = true }) { Text(L("mw4.ui.hajin.show"), color = HajinColors.text) }
                DropdownMenu(menu, { menu = false }, containerColor = LocalPalette.current.surface) {
                    DropdownMenuItem(text = { Text(L("mw4.ui.hajin.show_all"), color = Ink.text) }, onClick = { store.hiddenCategories = emptySet(); menu = false })
                    DropdownMenuItem(text = { Text(L("mw4.ui.hajin.hide_all"), color = Ink.text) }, onClick = {
                        store.hiddenCategories = guide.categories.filter { !it.isLabel }.map { it.id }.toSet(); menu = false
                    })
                }
            }
            Text(L("mw4.ui.hajin.filters"), style = sys(17f, FontWeight.SemiBold), color = Ink.text, textAlign = TextAlign.Center, modifier = Modifier.weight(1f))
            TextButton(onClick = dismiss) { Text(L("mw4.ui.hajin.done"), color = HajinColors.text, fontWeight = FontWeight.SemiBold) }
        }
        val hidden = store.hiddenCategories
        LazyColumn(contentPadding = PaddingValues(bottom = 24.dp)) {
            items(guide.categories, key = { it.id }) { category ->
                val on = category.id !in hidden
                val count = guide.markers.count { it.cat == category.id }
                Row(
                    Modifier.fillMaxWidth().clickable { store.hiddenCategories = if (on) hidden + category.id else hidden - category.id }
                        .padding(horizontal = 20.dp, vertical = 6.dp),
                    verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp),
                ) {
                    Icon(categoryPainter(category), null, tint = categoryTint(category), modifier = Modifier.size(22.dp))
                    Text(category.name.resolved, style = sys(16f), color = Ink.text, modifier = Modifier.weight(1f))
                    Text("$count", style = sys(15f, mono = true), color = Ink.muted)
                    Switch(on, { store.hiddenCategories = if (it) hidden - category.id else hidden + category.id },
                        colors = SwitchDefaults.colors(checkedTrackColor = HajinColors.accent))
                }
            }
        }
    }
}

/** Named places only: "UAV Tower" ×14 says nothing on its own. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun MapSearchSheet(guide: HajinGuide, dismiss: () -> Unit, pick: (HajinGuide.Marker) -> Unit) {
    var query by remember { mutableStateOf("") }
    val needle = query.lowercase()
    val results = guide.markers.filter { it.cat in setOf("area", "place", "fortress", "compound", "key") }
        .filter { needle.isEmpty() || it.name.resolved.lowercase().contains(needle) }
        .sortedBy { it.name.resolved }
    ModalBottomSheet(onDismissRequest = dismiss, containerColor = LocalPalette.current.surface2, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)) {
        Row(Modifier.fillMaxWidth().padding(horizontal = 8.dp), verticalAlignment = Alignment.CenterVertically) {
            TextButton(onClick = dismiss) { Text(L("mw4.ui.hajin.cancel"), color = HajinColors.text) }
            Text(L("mw4.ui.hajin.search_map"), style = sys(17f, FontWeight.SemiBold), color = Ink.text, textAlign = TextAlign.Center, modifier = Modifier.weight(1f))
            Spacer(Modifier.width(72.dp))
        }
        HajinSearchField(query, L("mw4.ui.hajin.search_map")) { query = it }
        LazyColumn(Modifier.fillMaxHeight(0.8f), contentPadding = PaddingValues(bottom = 24.dp)) {
            items(results, key = { it.id }) { marker ->
                Box(Modifier.fillMaxWidth().clickable { pick(marker) }.padding(horizontal = 16.dp, vertical = 10.dp)) {
                    MarkerRow(marker, guide.category(marker.cat))
                }
            }
        }
    }
}
