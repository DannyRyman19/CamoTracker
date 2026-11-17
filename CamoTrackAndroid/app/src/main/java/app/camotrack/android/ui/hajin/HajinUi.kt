package app.camotrack.android.ui.hajin

import android.content.Context
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Assignment
import androidx.compose.material.icons.automirrored.filled.DirectionsRun
import androidx.compose.material.icons.automirrored.filled.DirectionsWalk
import androidx.compose.material.icons.filled.*
import androidx.compose.material.icons.outlined.Circle
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.painter.Painter
import app.camotrack.android.ui.Glyphs
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.camotrack.android.AppState
import app.camotrack.android.Route
import app.camotrack.android.core.hajin.HajinGuide
import app.camotrack.android.core.hajin.HajinGuideService
import app.camotrack.android.core.hajin.HajinStore
import app.camotrack.android.i18n.L
import app.camotrack.android.ui.Ink
import app.camotrack.android.ui.LocalPalette
import app.camotrack.android.ui.ModeColors
import app.camotrack.android.ui.appLocale
import app.camotrack.android.ui.borderedCard
import app.camotrack.android.ui.displayStyle
import app.camotrack.android.ui.sys
import coil.compose.AsyncImage
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import java.text.NumberFormat

/**
 * The Hajin tab's store, shared by every DMZ screen. The guide is read on
 * first use (bundled or kept download) and checked for a newer one once per
 * launch; screens read [hajin] so they redraw on every change.
 */
object Hajin {
    private lateinit var appContext: Context
    private var instance: HajinStore? = null
    private var refreshed = false

    /** Bumped on every change to My DMZ or the guide. */
    var revision by mutableIntStateOf(0)
        private set

    fun start(context: Context) { appContext = context.applicationContext }

    private val service: HajinGuideService by lazy {
        HajinGuideService(AppState.games.firstOrNull { it.isMW4 } ?: app.camotrack.android.core.GameRegistry.fallback,
            File(appContext.filesDir, "data/mw4"), app.camotrack.android.AssetSeeds(appContext))
    }

    val store: HajinStore
        get() = instance ?: HajinStore(AppState.store, service.load()) { key, args -> L(key, *args) }.also {
            it.onChange = { revision++ }
            instance = it
        }

    /** Checks the CDN once per launch for a newer guide. */
    fun refresh() {
        if (refreshed) return
        refreshed = true
        val known = store.guide?.version
        AppState.scope.launch {
            val newer = withContext(Dispatchers.IO) { runCatching { service.refresh(knownVersion = known) }.getOrNull() }
            if (newer != null) store.replaceGuide(newer)
        }
    }
}

/** The store, read so the calling composable redraws on every change. */
@Composable
fun hajin(): HajinStore {
    Hajin.revision
    return Hajin.store
}

/** Opens a DMZ screen on the Hajin tab's stack. */
fun openHajin(route: Route) = AppState.push(route)

// MARK: - Colours

object HajinColors {
    val accent = ModeColors.dmz
    val text = ModeColors.dmzText
    val printable = Color(0xFF6BCC5C)
    val short = Color(0xFFED5250)
    val pin = Color(0xFFFFD933)
    val keep = Color(0xFFF5A83D)
    val crafting = Color(0xFF5C9EFA)

    fun rarity(rarity: String?): Color = when (rarity) {
        "Uncommon" -> Color(0xFF6BCC5C)
        "Rare" -> Color(0xFF5C9EFA)
        "Epic" -> Color(0xFFA873FA)
        "Legendary" -> Color(0xFFF5A83D)
        "Ultra" -> Color(0xFFED524D)
        else -> Color(0xFF9E9E9E)
    }

    /** Threat colours, Low (green) to Extreme (deep red). */
    fun threat(level: Int): Color = when (level) {
        1 -> Color(0xFF3DD68C)
        2 -> Color(0xFFFFC43D)
        3 -> Color(0xFFF76B14)
        4 -> Color(0xFFE6474D)
        else -> Color(0xFF9E1A33)
    }
}

fun categoryTint(category: HajinGuide.Category?): Color =
    app.camotrack.android.ui.hexColor(category?.color) ?: Ink.text

/** "$12,000" in the app's language. */
fun money(n: Int): String = "$" + NumberFormat.getIntegerInstance(appLocale).format(n)

fun number(n: Int): String = NumberFormat.getIntegerInstance(appLocale).format(n)

// MARK: - Symbols

/** The guide's SF Symbols, in Material's nearest. */
fun sfIcon(symbol: String?): ImageVector = when (symbol?.removeSuffix(".fill")) {
    "map" -> Icons.Filled.Map
    "mappin", "mappin.and.ellipse" -> Icons.Filled.Place
    "building.columns" -> Icons.Filled.AccountBalance
    "shield.lefthalf.filled", "shield" -> Icons.Filled.Shield
    "binoculars" -> Icons.Filled.Visibility
    "antenna.radiowaves.left.and.right" -> Icons.Filled.CellTower
    "key" -> Icons.Filled.Key
    "shippingbox" -> Icons.Filled.Inventory2
    "cross.case" -> Icons.Filled.MedicalServices
    "flame" -> Icons.Filled.LocalFireDepartment
    "light.beacon.max" -> Icons.Filled.LocalPolice
    "fuelpump" -> Icons.Filled.LocalGasStation
    "sailboat" -> Icons.Filled.Sailing
    "exclamationmark.shield" -> Icons.Filled.GppMaybe
    "arrow.up.circle" -> Icons.Filled.ArrowCircleUp
    "figure.walk" -> Icons.AutoMirrored.Filled.DirectionsWalk
    "lock.square", "lock" -> Icons.Filled.Lock
    "archivebox" -> Icons.Filled.Archive
    "shippingbox.circle" -> Icons.Filled.Inventory
    "bag" -> Icons.Filled.ShoppingBag
    "tray.and.arrow.down" -> Icons.Filled.MoveToInbox
    "scope" -> Icons.Filled.GpsFixed
    "exclamationmark.triangle" -> Icons.Filled.Warning
    "shower" -> Icons.Filled.Shower
    "dollarsign.circle" -> Icons.Filled.MonetizationOn
    "phone" -> Icons.Filled.Phone
    "car" -> Icons.Filled.DirectionsCar
    "cylinder" -> Icons.Filled.PropaneTank
    "flask" -> Icons.Filled.Science
    "chart.bar" -> Icons.Filled.BarChart
    "printer" -> Icons.Filled.Print
    "cube" -> Icons.Filled.ViewInAr
    "house" -> Icons.Filled.Home
    "figure.stand" -> Icons.Filled.Person
    "diamond" -> Icons.Filled.Diamond
    "shippingbox.and.arrow.backward" -> Icons.Filled.Backpack
    "airplane" -> Icons.Filled.Flight
    "checklist" -> Icons.Filled.Checklist
    "bolt" -> Icons.Filled.Bolt
    "figure.run" -> Icons.AutoMirrored.Filled.DirectionsRun
    "star" -> Icons.Filled.Star
    "brain.head.profile" -> Icons.Filled.Psychology
    "hammer" -> Icons.Filled.Construction
    "list.bullet.clipboard" -> Icons.AutoMirrored.Filled.Assignment
    "doc.text.magnifyingglass" -> Icons.Filled.FindInPage
    "arrow.left.arrow.right" -> Icons.Filled.SwapHoriz
    "building.2" -> Icons.Filled.Apartment
    "person.fill.viewfinder", "person.viewfinder" -> Icons.Filled.PersonSearch
    "sparkles" -> Icons.Filled.AutoAwesome
    else -> Icons.Filled.Place
}

// MARK: - Furniture

/** The app's card for a DMZ row: inset in the list, outlined, padded (iOS `hajinCard`). */
@Composable
fun Modifier.hajinCard(accent: Color? = null): Modifier =
    this.padding(horizontal = 12.dp, vertical = 4.dp).fillMaxWidth().borderedCard(accent = accent).padding(12.dp)

/** `hajinCard` that's one tap target, padding included. */
@Composable
fun Modifier.hajinCardButton(accent: Color? = null, onClick: () -> Unit): Modifier =
    this.padding(horizontal = 12.dp, vertical = 4.dp).fillMaxWidth().borderedCard(accent = accent).clickable(onClick = onClick).padding(12.dp)

/** A group heading that scrolls with the cards. */
@Composable
fun HajinHeading(title: String) {
    Text(title, style = sys(20f, FontWeight.Bold), color = Ink.text, modifier = Modifier.padding(start = 16.dp, end = 16.dp, top = 18.dp, bottom = 4.dp))
}

/** A muted intro line over a list. */
@Composable
fun HajinIntro(text: String) {
    Text(text, style = sys(15f), color = Ink.muted, modifier = Modifier.padding(horizontal = 16.dp, vertical = 6.dp))
}

/** "UPPERCASE" small heading inside a card. */
@Composable
fun SmallCaps(text: String, color: Color = Ink.muted, size: Float = 11f) {
    Text(text.uppercase(appLocale), style = sys(size, FontWeight.Bold).copy(letterSpacing = 0.8.sp), color = color)
}

@Composable
fun Chevron(modifier: Modifier = Modifier, alpha: Float = 1f) {
    Icon(Icons.Filled.ChevronRight, null, tint = Ink.muted.copy(alpha = alpha), modifier = modifier.size(18.dp))
}

/** The round icon a My DMZ card leads with. */
@Composable
fun CardSymbol(icon: Painter) {
    Box(Modifier.size(30.dp).clip(CircleShape).background(HajinColors.accent), contentAlignment = Alignment.Center) {
        Icon(icon, null, tint = Color.White, modifier = Modifier.size(17.dp))
    }
}

@Composable
fun CardSymbol(icon: ImageVector) = CardSymbol(androidx.compose.ui.graphics.vector.rememberVectorPainter(icon))

// MARK: - The app's drawings (iOS Glyph.icon / Glyph.marker)

/** A guide section's drawing, else its SF Symbol in Material's nearest. */
@Composable
fun sectionPainter(section: HajinGuide.Section): Painter = Glyphs.painter(Glyphs.dmzSection[section.id], sfIcon(section.symbol))

/** A Tac Map category's drawing, else its symbol. */
@Composable
fun categoryPainter(category: HajinGuide.Category?): Painter =
    Glyphs.painter(category?.let { Glyphs.mapCategory(it.id) }, sfIcon(category?.symbol))

/** The app's tick: an empty circle, then a filled accent circle with a check. */
@Composable
fun HajinTick(done: Boolean, label: String, toggle: () -> Unit) {
    val haptics = LocalHapticFeedback.current
    Box(
        Modifier.size(32.dp).clip(CircleShape).clickable { haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove); toggle() },
        contentAlignment = Alignment.Center,
    ) {
        Icon(
            if (done) Icons.Filled.CheckCircle else Icons.Outlined.Circle, label,
            tint = if (done) HajinColors.text else Ink.muted, modifier = Modifier.size(24.dp),
        )
    }
}

/** A row's figure (price, level, grid square), in one neutral style. */
@Composable
fun ValueBadge(text: String, locked: Boolean = false) {
    val surface2 = LocalPalette.current.surface2
    Row(
        Modifier.clip(RoundedCornerShape(4.dp)).background(surface2)
            .border(1.dp, Ink.muted.copy(alpha = 0.3f), RoundedCornerShape(4.dp)).padding(horizontal = 7.dp, vertical = 3.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        if (locked) Icon(Icons.Filled.Lock, null, tint = Ink.muted, modifier = Modifier.size(10.dp))
        Text(text, style = sys(11f, FontWeight.SemiBold, mono = true), color = if (locked) Ink.muted else Ink.text.copy(alpha = 0.9f))
    }
}

/** "Can print": the stash covers this recipe. */
@Composable
fun CanPrintTag() {
    Row(
        Modifier.clip(RoundedCornerShape(4.dp)).background(HajinColors.printable).padding(horizontal = 7.dp, vertical = 3.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Icon(Icons.Filled.Print, null, tint = Color.Black.copy(alpha = 0.85f), modifier = Modifier.size(10.dp))
        Text(L("mw4.ui.hajin.can_print").uppercase(appLocale), style = sys(10f, FontWeight.ExtraBold).copy(letterSpacing = 0.5.sp),
            color = Color.Black.copy(alpha = 0.85f), maxLines = 1)
    }
}

/** "$12,000 short" in red beside a price the cash entered doesn't cover. */
@Composable
fun CashShort(price: Int, size: Float = 11f) {
    val store = hajin()
    if (store.cash > 0 && price > store.cash) {
        Text(L("mw4.ui.hajin.short", money(price - store.cash)), style = sys(size, FontWeight.SemiBold), color = HajinColors.short, maxLines = 1)
    }
}

/** An ingredient's amount on a recipe: "4/16", green once covered; just "16" with no stash. */
@Composable
fun CostAmount(part: HajinGuide.Item.Cost) {
    val store = hajin()
    val have = store.count(part.item)
    Text(
        if (store.stash.isEmpty()) "${part.qty}" else "$have/${part.qty}",
        style = sys(12f, FontWeight.SemiBold, mono = true),
        color = if (store.stash.isNotEmpty() && have >= part.qty) HajinColors.printable else Ink.text,
    )
}

/** "◆ EPIC  CONSUMABLES", the game's rarity line. */
@Composable
fun RarityLine(item: HajinGuide.Item, size: Float = 12f, showsKind: Boolean = true) {
    Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
        item.rarity?.let { rarity ->
            Icon(Icons.Filled.Diamond, null, tint = HajinColors.rarity(rarity), modifier = Modifier.size((size * 0.9f).dp))
            Text(rarity.uppercase(appLocale), style = sys(size, FontWeight.ExtraBold).copy(letterSpacing = 0.6.sp), color = HajinColors.rarity(rarity), maxLines = 1)
        }
        if (showsKind) {
            Text(item.kind.uppercase(appLocale), style = sys(size, FontWeight.SemiBold).copy(letterSpacing = 0.6.sp), color = Ink.muted,
                maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
    }
}

/** An item's picture in a dark tile with a rarity stripe across the top, like the printer's icons. */
@Composable
fun ItemTile(item: HajinGuide.Item?, size: Dp = 44.dp, blueprint: Boolean = false) {
    val tint = HajinColors.rarity(item?.rarity)
    val shape = RoundedCornerShape(4.dp)
    Box(
        Modifier.size(size).clip(shape)
            .then(if (blueprint) Modifier else Modifier.background(Brush.verticalGradient(listOf(Color.Black.copy(alpha = 0.55f), tint.copy(alpha = 0.22f)))))
            .border(1.dp, if (blueprint) Color(0xFF8CC7FF).copy(alpha = 0.5f) else tint.copy(alpha = 0.45f), shape),
        contentAlignment = Alignment.Center,
    ) {
        if (blueprint) BlueprintPaper(size)
        val image = item?.image
        when {
            image != null -> AsyncImage(image, null, contentScale = ContentScale.Fit, modifier = Modifier.fillMaxSize().padding(size * 0.08f))
            item?.symbol != null -> Icon(sfIcon(item.symbol), null, tint = if (item.rarity == null) Ink.text else tint, modifier = Modifier.size(size * 0.45f))
            else -> Icon(Icons.Filled.Inventory2, null, tint = Ink.muted.copy(alpha = 0.6f), modifier = Modifier.size(size * 0.4f))
        }
        if (!blueprint) Box(Modifier.align(Alignment.TopCenter).fillMaxWidth().height(maxOf(2.dp, size / 22)).background(tint))
    }
}

/** A blueprint as the game draws it: royal blue, pale rings, an inset square and a white card badge. */
@Composable
fun BlueprintPaper(size: Dp) {
    Canvas(Modifier.size(size)) {
        val w = this.size.width
        val h = this.size.height
        drawRect(Brush.linearGradient(listOf(Color(0xFF2670F0), Color(0xFF1247CC)), Offset.Zero, Offset(w, h)))
        val centre = Offset(w / 2, h / 2)
        val ring = Color(0xFF8CC7FF).copy(alpha = 0.35f)
        for (r in listOf(0.17f, 0.31f, 0.47f)) drawCircle(ring, w * r, centre, style = Stroke(maxOf(0.6f, w / 70)))
        val inset = w * 0.07f
        drawRect(Color(0xFF9ED1FF).copy(alpha = 0.75f), Offset(inset, inset), Size(w - inset * 2, h - inset * 2), style = Stroke(maxOf(0.8f, w / 55)))
        if (size >= 28.dp) {
            val bx = w * 0.03f
            val by = h * 0.74f
            val bw = w * 0.24f
            val bh = w * 0.14f
            drawRoundRect(Color.White.copy(alpha = 0.92f), Offset(bx, by), Size(bw, bh), CornerRadius(w * 0.02f))
            for (dy in listOf(0.35f, 0.65f)) {
                val y = by + bh * dy
                drawLine(Color(0xFF737373), Offset(bx + bw * 0.18f, y), Offset(bx + bw * 0.82f, y), maxOf(0.6f, w / 90))
            }
        }
    }
}

/** A chip naming an item: its tile, name and an amount; opens the item. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun LinkChips(ids: List<String>, amounts: Map<String, Int> = emptyMap(), arrows: Boolean = false, modifier: Modifier = Modifier) {
    val store = hajin()
    val surface2 = LocalPalette.current.surface2
    FlowRow(modifier, horizontalArrangement = Arrangement.spacedBy(6.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        for (id in ids.distinct()) {
            val item = store.guide?.item(id) ?: continue
            Row(
                Modifier.clip(RoundedCornerShape(6.dp)).background(surface2)
                    .border(1.dp, HajinColors.rarity(item.rarity).copy(alpha = 0.5f), RoundedCornerShape(6.dp))
                    .clickable { openHajin(Route.HajinItem(id)) }.padding(3.dp).padding(end = 6.dp),
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                ItemTile(item, 22.dp)
                Text(item.name.resolved, style = sys(12f, FontWeight.SemiBold), color = Ink.text, maxLines = 1, overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f, fill = false))
                amounts[id]?.let { Text("×$it", style = sys(12f, FontWeight.Bold, mono = true), color = Ink.muted) }
                if (arrows) Icon(Icons.Filled.ChevronRight, null, tint = Ink.muted, modifier = Modifier.size(12.dp))
            }
        }
    }
}

/** DMZ Orders as chips, each opening its card: what needs an item. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun OrderChips(orders: List<Pair<HajinGuide.Row, Int>>, modifier: Modifier = Modifier) {
    val surface2 = LocalPalette.current.surface2
    FlowRow(modifier, horizontalArrangement = Arrangement.spacedBy(6.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        for ((order, qty) in orders) {
            val check = order.check ?: continue
            Row(
                Modifier.clip(RoundedCornerShape(6.dp)).background(surface2)
                    .border(1.dp, HajinColors.accent.copy(alpha = 0.5f), RoundedCornerShape(6.dp))
                    .clickable { openHajin(Route.HajinOrder(check)) }.padding(3.dp).padding(end = 6.dp),
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                Box(Modifier.size(22.dp).clip(RoundedCornerShape(4.dp)).background(HajinColors.accent.copy(alpha = 0.15f)), contentAlignment = Alignment.Center) {
                    Icon(Icons.Filled.Checklist, null, tint = HajinColors.text, modifier = Modifier.size(13.dp))
                }
                Text(order.title.resolved, style = sys(12f, FontWeight.SemiBold), color = Ink.text, maxLines = 1, overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f, fill = false))
                orderPage(order)?.let { Text(it, style = sys(12f), color = Ink.muted, maxLines = 1) }
                Text("×$qty", style = sys(12f, FontWeight.Bold, mono = true), color = Ink.muted)
                Icon(Icons.Filled.ChevronRight, null, tint = Ink.muted, modifier = Modifier.size(12.dp))
            }
        }
    }
}

/** "Page 10" from "DMZ Orders: Page 10": where the order sits. */
fun orderPage(row: HajinGuide.Row): String? {
    val group = row.group?.resolved ?: return null
    return if (group.startsWith("DMZ Orders: ")) group.removePrefix("DMZ Orders: ") else null
}

/** A tool row's dimming when it can't be used. */
fun Modifier.dimmed(on: Boolean): Modifier = if (on) this.alpha(0.55f) else this

/** I, II, III... for an upgrade's tiers. */
fun roman(n: Int): String = listOf("I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX").getOrNull(n - 1) ?: "$n"

/** The title-bar figure for a screen pushed on the Hajin tab. */
@Composable
fun hajinTitleStyle() = displayStyle(19.sp)
