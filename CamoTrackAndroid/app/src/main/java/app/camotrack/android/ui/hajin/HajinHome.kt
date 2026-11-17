package app.camotrack.android.ui.hajin

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.camotrack.android.AppState
import app.camotrack.android.Route
import app.camotrack.android.core.hajin.HajinGuide
import app.camotrack.android.core.hajin.HajinStore
import app.camotrack.android.i18n.L
import app.camotrack.android.services.Premium
import app.camotrack.android.ui.*
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/** The Hajin tab's two halves: the player's own plan, and the reference guide. */
private const val PAGE_KEY = "mw4_hajin_page"

/**
 * The Hajin tab (iOS HajinView, phone layout): My DMZ or the guide, with a
 * search across the whole guide; DMZ Level and Cash in the title bar.
 */
@Composable
fun HajinHome() {
    val store = hajin()
    LaunchedEffect(Unit) { Hajin.refresh() }
    var query by rememberSaveable { mutableStateOf("") }
    var page by Prefs.string(PAGE_KEY, "mine")
    Column(Modifier.fillMaxSize().appBackground(HajinColors.accent)) {
        TopBar(L("mw4.ui.hajin.title"), onBack = null) { NumbersChip() }
        val guide = store.guide ?: return@Column
        // Kept while a pushed screen is up, so Back returns to the same place
        LazyColumn(Modifier.fillMaxSize(), state = homeList, contentPadding = PaddingValues(bottom = 16.dp)) {
            item(key = "search") { HajinSearchField(query, L("mw4.ui.hajin.search_guide")) { query = it } }
            if (query.isEmpty()) {
                item(key = "picker") {
                    SegmentTabs(page, listOf("mine" to L("mw4.ui.hajin.page_mine"), "guide" to L("mw4.ui.hajin.page_guide")), HajinColors.accent,
                        { page = it }, Modifier.padding(horizontal = 12.dp, vertical = 4.dp))
                }
                if (page == "mine") {
                    minePage()
                } else {
                    item(key = "hero") { MapHeroCard(guide) }
                    item(key = "tiles") { GuideTiles(guide.guide.filter { it.id !in HajinGuide.trackedSections }) }
                    item(key = "footer") { GuideFooter(guide) }
                }
            } else {
                searchResults(guide, query)
            }
        }
    }
}

private val homeList = androidx.compose.foundation.lazy.LazyListState()

/** iOS's search field: a rounded well with a magnifier and a clear button. */
@Composable
fun HajinSearchField(query: String, prompt: String, onChange: (String) -> Unit) {
    val palette = LocalPalette.current
    Row(
        Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 6.dp).clip(RoundedCornerShape(10.dp))
            .background(palette.surface2).padding(horizontal = 10.dp, vertical = 9.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Icon(Icons.Filled.Search, null, tint = Ink.muted, modifier = Modifier.size(18.dp))
        Box(Modifier.weight(1f)) {
            if (query.isEmpty()) Text(prompt, style = sys(16f), color = Ink.muted)
            BasicTextField(
                query, onChange, singleLine = true, textStyle = sys(16f).copy(color = Ink.text),
                cursorBrush = SolidColor(HajinColors.accent), modifier = Modifier.fillMaxWidth(),
            )
        }
        if (query.isNotEmpty()) {
            Icon(Icons.Filled.Cancel, null, tint = Ink.muted, modifier = Modifier.size(18.dp).clickable { onChange("") })
        }
    }
}

@Composable
private fun GuideFooter(guide: HajinGuide) {
    Column(Modifier.padding(horizontal = 16.dp, vertical = 10.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Text(L("mw4.ui.hajin.early_access"), style = sys(12f), color = Ink.muted)
        guide.updated?.let { Text(L("mw4.ui.hajin.updated", it), style = sys(12f), color = Ink.muted) }
        guide.map.credit?.let { Text(it, style = sys(12f), color = Ink.muted) }
    }
}

// MARK: - Search

/** Every row and marker whose text matches, grouped by where it lives; a place opens the map on it. */
private fun LazyListScope.searchResults(guide: HajinGuide, query: String) {
    val needle = query.lowercase()
    val places = guide.markers.filter { it.name.resolved.lowercase().contains(needle) || it.note?.resolved?.lowercase()?.contains(needle) == true }
        .groupBy { it.name.resolved }.mapNotNull { it.value.firstOrNull() }.sortedBy { it.name.resolved }
    val sections = guide.guide.map { it to it.rows.filter { row -> row.matches(needle) } }.filter { it.second.isNotEmpty() }
    if (places.isNotEmpty()) {
        item(key = "h-map") { HajinHeading(L("mw4.ui.hajin.map")) }
        items(places, key = { "m-${it.id}" }) { marker ->
            Box(Modifier.hajinCardButton { openHajin(Route.HajinMap(marker.id)) }) { MarkerRow(marker, guide.category(marker.cat)) }
        }
    }
    for ((section, rows) in sections) {
        item(key = "h-${section.id}") { HajinHeading(section.title.resolved) }
        items(rows.size, key = { "r-${section.id}-$it" }) { i -> GuideRowCard(rows[i]) }
    }
    if (places.isEmpty() && sections.isEmpty()) item(key = "none") { FilterEmptyRow(L("mw4.ui.hajin.no_results")) }
}

@Composable
fun MarkerRow(marker: HajinGuide.Marker, category: HajinGuide.Category?) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        MarkerGlyph(marker.symbol, category, 20.dp)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(marker.name.resolved, style = sys(16f), color = Ink.text)
            category?.let { Text(it.name.resolved, style = sys(12f), color = Ink.muted) }
        }
    }
}

/** A marker's icon in its category's colour; a numbered stop shows its number. */
@Composable
fun MarkerGlyph(symbol: String?, category: HajinGuide.Category?, size: androidx.compose.ui.unit.Dp) {
    val tint = categoryTint(category)
    val number = symbol?.substringBefore('.')?.toIntOrNull()
    Box(Modifier.width(28.dp), contentAlignment = Alignment.Center) {
        if (number != null) {
            Box(Modifier.size(size).clip(CircleShape).background(tint), contentAlignment = Alignment.Center) {
                Text("$number", style = sys(size.value * 0.55f, FontWeight.Bold), color = Color.Black)
            }
        } else {
            Icon(categoryPainter(category), null, tint = tint, modifier = Modifier.size(size))
        }
    }
}

// MARK: - Guide page

/** The Tac Map card: a shrunk copy of the map, its title, and counts of what's on it. */
@Composable
private fun MapHeroCard(guide: HajinGuide) {
    val store = hajin()
    Column(
        Modifier.padding(horizontal = 12.dp, vertical = 8.dp).fillMaxWidth().borderedCard(12.dp, accent = HajinColors.accent)
            .clickable { openHajin(Route.HajinMap()) },
    ) {
        Box(Modifier.fillMaxWidth().height(170.dp).background(LocalPalette.current.surface2)) {
            MapThumbnail(guide.map.image)
            Box(Modifier.matchParentSize().background(Brush.verticalGradient(0.5f to Color.Transparent, 1f to Color.Black.copy(alpha = 0.75f))))
            Column(Modifier.align(Alignment.BottomStart).padding(12.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(L("mw4.ui.hajin.tac_map"), style = sys(20f, FontWeight.ExtraBold), color = Color.White)
                Text(L("mw4.ui.hajin.tac_map_subtitle"), style = sys(12f), color = Color.White.copy(alpha = 0.8f))
            }
        }
        Row(Modifier.padding(horizontal = 12.dp, vertical = 10.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
            HeroStat(guide.markers.count { it.cat == "fortress" }, Icons.Filled.AccountBalance, Color(0xFFE5484D))
            HeroStat(guide.markers.count { it.cat == "uav" }, Icons.Filled.CellTower, Color(0xFF3DD68C))
            HeroStat(guide.markers.count { it.cat == "cache" }, Icons.Filled.Inventory2, Color(0xFF70B8FF))
            if (store.pins.isNotEmpty()) HeroStat(store.pins.size, Icons.Filled.Place, HajinColors.pin)
            Spacer(Modifier.weight(1f))
            Chevron()
        }
    }
}

@Composable
private fun HeroStat(count: Int, icon: ImageVector, tint: Color) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
        Icon(icon, null, tint = tint, modifier = Modifier.size(15.dp))
        Text("$count", style = sys(13f, FontWeight.SemiBold, mono = true), color = tint)
    }
}

/** A small, pre-shrunk copy of the map for the card, so the list never decodes the full 2660 px image. */
@Composable
private fun BoxScope.MapThumbnail(name: String) {
    val context = LocalContext.current
    var image by remember { mutableStateOf<ImageBitmap?>(thumbnailCache) }
    LaunchedEffect(name) {
        if (image != null) return@LaunchedEffect
        image = withContext(Dispatchers.IO) {
            runCatching {
                context.assets.open("$name.jpg").use { input ->
                    BitmapFactory.decodeStream(input, null, BitmapFactory.Options().apply { inSampleSize = 2; inPreferredConfig = Bitmap.Config.RGB_565 })
                }?.asImageBitmap()
            }.getOrNull()
        }?.also { thumbnailCache = it }
    }
    image?.let { Image(it, null, contentScale = ContentScale.Crop, modifier = Modifier.matchParentSize()) }
}

private var thumbnailCache: ImageBitmap? = null

/** The guide's sections as a two-column grid of tiles; an odd one out at the end takes the full width. */
@Composable
private fun GuideTiles(sections: List<HajinGuide.Section>) {
    TileGrid(sections.size) { index, wide ->
        val section = sections[index]
        SectionTile(section.title.resolved, sectionPainter(section), "${section.rows.size}", null, wide) { openHajin(Route.HajinSection(section.id)) }
    }
}

/** Tiles two a row, the last full width when there's an odd one. */
@Composable
fun TileGrid(count: Int, tile: @Composable (index: Int, wide: Boolean) -> Unit) {
    val paired = if (count % 2 == 0) count else count - 1
    Column(Modifier.padding(horizontal = 12.dp, vertical = 6.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        for (row in 0 until paired step 2) {
            Row(Modifier.height(IntrinsicSize.Min), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                Box(Modifier.weight(1f).fillMaxHeight()) { tile(row, false) }
                Box(Modifier.weight(1f).fillMaxHeight()) { tile(row + 1, false) }
            }
        }
        if (paired < count) tile(count - 1, true)
    }
}

/**
 * A guide section or a tracked one: its icon (in a ring of how much is
 * ticked when `fraction` is given), the title and the count.
 */
@Composable
fun SectionTile(title: String, icon: androidx.compose.ui.graphics.painter.Painter, count: String, fraction: Double?, wide: Boolean, ring: Boolean = false, onClick: () -> Unit) {
    val symbol: @Composable () -> Unit = {
        if (ring) {
            Box(Modifier.size(40.dp), contentAlignment = Alignment.Center) {
                if (fraction != null && fraction > 0) ProgressRing(fraction, HajinColors.accent, lineWidth = 4.dp, size = 40.dp, showsPercentage = false)
                else Box(Modifier.size(40.dp).border(4.dp, LocalPalette.current.surface2, CircleShape))
                Icon(icon, null, tint = HajinColors.text, modifier = Modifier.size(16.dp))
            }
        } else {
            Box(Modifier.size(36.dp).clip(RoundedCornerShape(8.dp)).background(HajinColors.accent.copy(alpha = 0.16f)), contentAlignment = Alignment.Center) {
                Icon(icon, null, tint = HajinColors.text, modifier = Modifier.size(18.dp))
            }
        }
    }
    val countText: @Composable () -> Unit = {
        Text(count, style = sys(12f, FontWeight.SemiBold, mono = true), color = if (fraction == 1.0) HajinColors.text else Ink.muted)
    }
    val titleText: @Composable (Modifier) -> Unit = { m ->
        Text(title, style = displayStyle(15.sp), color = Ink.text, maxLines = 2, overflow = TextOverflow.Ellipsis, modifier = m)
    }
    Box(Modifier.fillMaxSize().borderedCard().clickable(onClick = onClick).padding(12.dp)) {
        if (wide) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                symbol(); titleText(Modifier.weight(1f)); countText()
            }
        } else {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.Top) { symbol(); Spacer(Modifier.weight(1f)); countText() }
                titleText(Modifier.fillMaxWidth())
            }
        }
    }
}

// MARK: - My DMZ

/** The My DMZ page's cards, in the player's order; any can be hidden (iOS HajinMineCard). */
enum class MineCard(val raw: String) {
    SCAN("scan"), POST_MATCH("postMatch"), TRACKING("tracking"), BUILD_NEXT("buildNext"), ORDERS("orders"), UPGRADES("upgrades"),
    BLUEPRINTS("blueprints"), BOSSES("bosses"), PRESTIGE("prestige"), STASH("stash"), KEEP_SELL("keepSell"), SHOPPING("shopping");

    val title: String
        get() = when (this) {
            SCAN -> L("mw4.ui.hajin.grid_scan")
            POST_MATCH -> L("mw4.ui.postmatch.card")
            TRACKING -> L("mw4.ui.hajin.tracking")
            BUILD_NEXT -> L("mw4.ui.hajin.build_next")
            SHOPPING -> L("mw4.ui.hajin.shop")
            BLUEPRINTS -> L("mw4.ui.hajin.blueprints")
            STASH -> L("mw4.ui.hajin.stash")
            KEEP_SELL -> L("mw4.ui.keep.title")
            ORDERS -> L("mw4.ui.hajin.mine_orders")
            UPGRADES -> L("mw4.ui.hajin.mine_upgrades")
            BOSSES -> L("mw4.ui.hajin.mine_bosses")
            PRESTIGE -> L("mw4.ui.hajin.mine_prestige")
        }

    /** The guide section a tracking card opens. */
    val section: String?
        get() = when (this) {
            ORDERS -> "ops"; UPGRADES -> "upgrades"; BOSSES -> "bosses"; PRESTIGE -> "prestige"; else -> null
        }

    val icon: ImageVector
        get() = when (this) {
            SCAN -> Icons.Filled.CenterFocusStrong
            POST_MATCH -> Icons.Filled.ShoppingBag
            TRACKING -> Icons.Filled.GpsFixed
            BUILD_NEXT -> Icons.Filled.Construction
            SHOPPING -> sfIcon("list.bullet.clipboard.fill")
            BLUEPRINTS -> Icons.Filled.FindInPage
            STASH -> Icons.Filled.Inventory2
            KEEP_SELL -> Icons.Filled.SwapHoriz
            ORDERS -> Icons.Filled.Checklist
            UPGRADES -> Icons.Filled.Apartment
            BOSSES -> Icons.Filled.PersonSearch
            PRESTIGE -> Icons.Filled.Star
        }

    /** The card's drawing (iOS HajinMineCard.glyph); the photo reader keeps its camera. */
    val glyph: Int?
        get() = when (this) {
            SCAN -> null
            POST_MATCH -> app.camotrack.android.R.drawable.glyph_map_loot
            TRACKING -> app.camotrack.android.R.drawable.glyph_dmz_tracking
            BUILD_NEXT -> app.camotrack.android.R.drawable.glyph_dmz_build
            SHOPPING -> app.camotrack.android.R.drawable.glyph_dmz_shopping
            BLUEPRINTS -> app.camotrack.android.R.drawable.glyph_dmz_blueprints
            STASH -> app.camotrack.android.R.drawable.glyph_map_cache
            KEEP_SELL -> app.camotrack.android.R.drawable.glyph_dmz_keepsell
            ORDERS -> Glyphs.dmzSection["ops"]
            UPGRADES -> Glyphs.dmzSection["upgrades"]
            BOSSES -> Glyphs.dmzSection["bosses"]
            PRESTIGE -> Glyphs.dmzSection["prestige"]
        }

    @Composable
    fun painter(): androidx.compose.ui.graphics.painter.Painter = Glyphs.painter(glyph, icon)

    companion object {
        const val ORDER_KEY = "mw4_hajin_mine_order"
        const val HIDDEN_KEY = "mw4_hajin_mine_hidden"

        /** Saved order, with any card added since slotted in after the card it follows by default. */
        fun order(raw: String): List<MineCard> {
            val out = raw.split(",").mapNotNull { r -> entries.firstOrNull { it.raw == r } }.toMutableList()
            entries.forEachIndexed { i, card ->
                if (card in out) return@forEachIndexed
                val after = if (i > 0) out.indexOf(entries[i - 1]).takeIf { it >= 0 } else null
                out.add(after?.plus(1) ?: if (i == 0) 0 else out.size, card)
            }
            return out.filter { it != POST_MATCH }
        }
    }
}

/** The player's own cards in the order they chose, with a Customise button (iOS HajinMinePage). The photo reader comes later on Android. */
private fun LazyListScope.minePage() {
    item(key = "mine") { MineCards() }
}

@Composable
private fun MineCards() {
    val store = hajin()
    val orderRaw by Prefs.string(MineCard.ORDER_KEY, "")
    val hiddenRaw by Prefs.string(MineCard.HIDDEN_KEY, "")
    var customising by remember { mutableStateOf(false) }
    val hidden = hiddenRaw.split(",").filter { it.isNotEmpty() }.toSet()
    val shown = MineCard.order(orderRaw).filter { it.raw !in hidden && it != MineCard.SCAN }
    Column {
        for (card in shown.filter { it == MineCard.TRACKING || it == MineCard.BUILD_NEXT }) {
            Box(Modifier.hajinCard()) { if (card == MineCard.TRACKING) TrackingCard() else BuildNextCard() }
        }
        val progress = shown.filter { it.section != null || it == MineCard.BLUEPRINTS }
        if (progress.isNotEmpty()) {
            HajinHeading(L("mw4.ui.hajin.mine_progress"))
            TileGrid(progress.size) { index, wide -> ProgressTile(progress[index], wide) }
        }
        val tools = shown.filter { it == MineCard.STASH || it == MineCard.KEEP_SELL || it == MineCard.SHOPPING }
        if (tools.isNotEmpty()) {
            Column(Modifier.padding(horizontal = 12.dp).padding(top = 14.dp, bottom = 4.dp).fillMaxWidth().borderedCard()) {
                tools.forEachIndexed { i, card ->
                    if (i > 0) Box(Modifier.padding(start = 54.dp).fillMaxWidth().height(1.dp).background(LocalPalette.current.surface2))
                    Row(
                        Modifier.fillMaxWidth().clickable {
                            openHajin(when (card) { MineCard.STASH -> Route.HajinStash; MineCard.KEEP_SELL -> Route.HajinKeepSell; else -> Route.HajinShopping })
                        }.padding(12.dp),
                        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        Box(Modifier.weight(1f)) {
                            when (card) {
                                MineCard.STASH -> StashEntry()
                                MineCard.KEEP_SELL -> KeepSellEntry()
                                else -> ShoppingEntry()
                            }
                        }
                        Chevron()
                    }
                }
            }
        }
        // Free players: what Premium gets them, under their own cards
        if (!Premium.isPremium) {
            Row(
                Modifier.hajinCardButton(HajinColors.accent) { AppState.push(Route.Premium) },
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                CardSymbol(Icons.Filled.AutoAwesome)
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text(L("mw4.ui.premium.title"), style = displayStyle(16.sp), color = Ink.text)
                    Text(L("mw4.ui.premium.subtitle"), style = sys(12f), color = Ink.muted)
                }
                Chevron()
            }
        }
        TextButton(
            onClick = { if (Premium.isPremium) customising = true else AppState.push(Route.Premium) },
            modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp),
        ) {
            Icon(if (Premium.isPremium) Icons.Filled.Tune else Icons.Filled.Lock, null, tint = HajinColors.text, modifier = Modifier.size(16.dp))
            Spacer(Modifier.width(6.dp))
            Text(L("mw4.ui.hajin.mine_customise"), style = sys(15f, FontWeight.SemiBold), color = HajinColors.text)
        }
    }
    if (customising) MineCustomise { customising = false }
}

/** A tracked guide section as a tile: its ring, title and x/y. */
@Composable
private fun ProgressTile(card: MineCard, wide: Boolean) {
    val store = hajin()
    if (card == MineCard.BLUEPRINTS) {
        val (found, total) = store.findProgress
        SectionTile(card.title, card.painter(), "$found/$total", found.toDouble() / maxOf(total, 1), wide, ring = true) { openHajin(Route.HajinBlueprints) }
        return
    }
    val section = card.section?.let { store.guide?.section(it) } ?: return
    // A row's tick: its own, or a Gunsmith weapon's manual (starter weapons have none)
    val keys = section.rows.mapNotNull { row ->
        row.check ?: row.weapon?.takeIf { row.subtitle?.en?.startsWith("Starter") != true }?.let { "manual-$it" }
    }
    val done = keys.count { it in store.checked }
    SectionTile(
        card.title, card.painter(),
        // Prestige has no ticks: how many operators are tracked
        if (keys.isEmpty()) "${store.operators.size}" else "$done/${keys.size}",
        if (keys.isEmpty()) null else done.toDouble() / maxOf(keys.size, 1), wide, ring = true,
    ) { openHajin(Route.HajinSection(section.id)) }
}

/** Reorder the My DMZ cards with the arrows, and switch any off. */
@Composable
private fun MineCustomise(onDismiss: () -> Unit) {
    var orderRaw by Prefs.string(MineCard.ORDER_KEY, "")
    var hiddenRaw by Prefs.string(MineCard.HIDDEN_KEY, "")
    val full = MineCard.order(orderRaw)
    // The photo reader comes later on Android: kept in the saved order, not listed
    val order = full.filter { it != MineCard.SCAN }
    val hidden = hiddenRaw.split(",").filter { it.isNotEmpty() }.toSet()
    fun save(list: List<MineCard>) {
        val withScan = list.toMutableList()
        val at = full.indexOf(MineCard.SCAN)
        if (at >= 0) withScan.add(at.coerceAtMost(withScan.size), MineCard.SCAN)
        orderRaw = withScan.joinToString(",") { it.raw }
    }
    AlertDialog(
        onDismissRequest = onDismiss,
        containerColor = LocalPalette.current.surface2,
        title = { Text(L("mw4.ui.hajin.mine_customise"), color = Ink.text) },
        text = {
            Column(Modifier.verticalScrollable()) {
                order.forEachIndexed { i, card ->
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.padding(vertical = 2.dp)) {
                        Icon(card.painter(), null, tint = HajinColors.text, modifier = Modifier.size(20.dp))
                        Text(card.title, style = sys(15f), color = Ink.text, modifier = Modifier.weight(1f))
                        IconButton(onClick = { save(order.toMutableList().apply { add(i - 1, removeAt(i)) }) }, enabled = i > 0, modifier = Modifier.size(32.dp)) {
                            Icon(Icons.Filled.KeyboardArrowUp, L("ct.android.move_up"), tint = if (i > 0) Ink.text else Ink.muted.copy(alpha = 0.4f))
                        }
                        IconButton(onClick = { save(order.toMutableList().apply { add(i + 1, removeAt(i)) }) }, enabled = i < order.size - 1, modifier = Modifier.size(32.dp)) {
                            Icon(Icons.Filled.KeyboardArrowDown, L("ct.android.move_down"), tint = if (i < order.size - 1) Ink.text else Ink.muted.copy(alpha = 0.4f))
                        }
                        Switch(
                            checked = card.raw !in hidden,
                            onCheckedChange = { on -> hiddenRaw = (if (on) hidden - card.raw else hidden + card.raw).sorted().joinToString(",") },
                            colors = SwitchDefaults.colors(checkedTrackColor = HajinColors.accent),
                        )
                    }
                }
                Text(L("ct.android.hajin.customise_hint"), style = sys(12f), color = Ink.muted, modifier = Modifier.padding(top = 8.dp))
            }
        },
        confirmButton = { TextButton(onClick = onDismiss) { Text(L("mw4.ui.hajin.done"), color = HajinColors.text) } },
        dismissButton = { TextButton(onClick = { orderRaw = ""; hiddenRaw = "" }) { Text(L("mw4.ui.hajin.mine_reset"), color = HajinColors.text) } },
    )
}

@Composable
private fun Modifier.verticalScrollable(): Modifier = this.verticalScroll(androidx.compose.foundation.rememberScrollState())

// MARK: - DMZ Level and Cash

/** "33,050 -> 33K, 1,250,000 -> 1.25M". */
fun shortCash(n: Int): String = when {
    n >= 1_000_000 -> java.text.DecimalFormat("0.##", java.text.DecimalFormatSymbols(appLocale)).format(n / 1_000_000.0) + "M"
    n >= 10_000 -> "${n / 1000}K"
    else -> number(n)
}

/** DMZ Level and Cash in the title bar: tap for the card that sets them. */
@Composable
fun NumbersChip() {
    val store = hajin()
    var open by remember { mutableStateOf(false) }
    val palette = LocalPalette.current
    Row(
        Modifier.padding(end = 8.dp).clip(CircleShape).background(palette.surface).border(1.dp, palette.surface2, CircleShape)
            .clickable { open = true }.padding(horizontal = 12.dp, vertical = 7.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Text(buildAnnotatedString {
            withStyle(SpanStyle(fontSize = 11.sp, color = Ink.muted)) { append(L("ct.ui.level_abbrev") + " ") }
            append(if (store.dmzLevel > 0) "${store.dmzLevel}" else "–")
        }, style = displayStyle(15.sp), color = Ink.text)
        Box(Modifier.width(1.dp).height(14.dp).background(Ink.muted.copy(alpha = 0.4f)))
        Text(if (store.cash > 0) "$" + shortCash(store.cash) else "$–", style = displayStyle(15.sp), color = HajinColors.text)
    }
    if (open) {
        AlertDialog(
            onDismissRequest = { open = false },
            containerColor = palette.surface2,
            text = { NumbersCard() },
            confirmButton = { TextButton(onClick = { open = false }) { Text(L("mw4.ui.hajin.done"), color = HajinColors.text) } },
        )
    }
}

/** DMZ Level and DMZ Cash side by side: tap either to type it in. */
@Composable
fun NumbersCard() {
    val store = hajin()
    var editing by remember { mutableStateOf<String?>(null) }
    val level = store.dmzLevel
    Row(Modifier.height(IntrinsicSize.Min), horizontalArrangement = Arrangement.spacedBy(14.dp)) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(L("mw4.ui.hajin.dmz_level"), style = sys(12f, FontWeight.SemiBold), color = Ink.muted)
            Row(verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.clickable { editing = "level" }) {
                    if (level > 0) {
                        Text(buildAnnotatedString {
                            append("$level")
                            withStyle(SpanStyle(fontSize = 15.sp, color = Ink.muted)) { append(" /${HajinStore.MAX_LEVEL}") }
                        }, style = displayStyle(30.sp), color = Ink.text)
                    } else {
                        Text(L("mw4.ui.hajin.dmz_level_button"), style = displayStyle(18.sp), color = HajinColors.text)
                    }
                }
                Spacer(Modifier.weight(1f))
                if (level > 0) {
                    Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        StepButton(Icons.Filled.Remove, true, 24.dp, HajinColors.accent) { store.setLevel(level - 1) }
                        StepButton(Icons.Filled.Add, level < HajinStore.MAX_LEVEL, 24.dp, HajinColors.accent) { store.setLevel(level + 1) }
                    }
                }
            }
            ProgressBar(level.toDouble() / HajinStore.MAX_LEVEL, HajinColors.accent)
        }
        Box(Modifier.width(1.dp).fillMaxHeight().background(LocalPalette.current.surface))
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(L("mw4.ui.hajin.cash_title"), style = sys(12f, FontWeight.SemiBold), color = Ink.muted)
            Text(
                if (store.cash > 0) money(store.cash) else L("mw4.ui.hajin.cash_add"),
                style = displayStyle(if (store.cash > 0) 24.sp else 18.sp), color = if (store.cash > 0) Ink.text else HajinColors.text,
                maxLines = 1, modifier = Modifier.clickable { editing = "cash" },
            )
            Text(L(if (store.cash > 0) "mw4.ui.hajin.cash_set" else "mw4.ui.hajin.cash_hint"), style = sys(11f), color = Ink.muted, maxLines = 2)
        }
    }
    when (editing) {
        "level" -> HajinNumberDialog(L("mw4.ui.hajin.dmz_level"), "1–${HajinStore.MAX_LEVEL}", if (level > 0) "$level" else "", { editing = null }) { n ->
            n?.let { store.setLevel(it) }
        }
        "cash" -> HajinNumberDialog(L("mw4.ui.hajin.cash_title"), "0", if (store.cash > 0) "${store.cash}" else "", { editing = null }) { n ->
            store.setCash(n ?: 0)
        }
    }
}

/** iOS's number-pad alert: a title, a field, Cancel and Save. Save passes null for a blank field. */
@Composable
fun HajinNumberDialog(title: String, placeholder: String, initial: String, onDismiss: () -> Unit, onSave: (Int?) -> Unit) {
    var text by remember { mutableStateOf(initial) }
    AlertDialog(
        onDismissRequest = onDismiss,
        containerColor = LocalPalette.current.surface2,
        title = { Text(title, color = Ink.text) },
        text = {
            OutlinedTextField(
                value = text, onValueChange = { v -> text = v.filter(Char::isDigit).take(8) }, singleLine = true,
                placeholder = { Text(placeholder) },
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
            )
        },
        confirmButton = { TextButton(onClick = { onSave(text.toIntOrNull()); onDismiss() }) { Text(L("mw4.ui.hajin.save"), color = HajinColors.text) } },
        dismissButton = { TextButton(onClick = onDismiss) { Text(L("mw4.ui.hajin.cancel"), color = HajinColors.text) } },
    )
}
