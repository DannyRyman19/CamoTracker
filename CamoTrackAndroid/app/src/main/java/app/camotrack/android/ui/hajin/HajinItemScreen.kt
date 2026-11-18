package app.camotrack.android.ui.hajin

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material.icons.outlined.Image
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material.icons.outlined.TextFields
import androidx.compose.material.icons.outlined.AddCircleOutline
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.camotrack.android.Route
import app.camotrack.android.core.hajin.HajinGuide
import app.camotrack.android.core.hajin.HajinStore
import app.camotrack.android.core.hajin.HajinVerdict
import app.camotrack.android.i18n.L
import app.camotrack.android.ui.*

/**
 * An item laid out like the game's printer panel: big tile, name, rarity
 * line and effect, then its status, the recipe, what uses it, and where it
 * is (iOS HajinItemView, phone layout).
 */
@Composable
fun HajinItemScreen(id: String) {
    val store = hajin()
    // Another tier of the same upgrade, swapped in place by the tier strip
    var tierShown by rememberSaveable(id) { mutableStateOf<String?>(null) }
    val shownId = tierShown ?: id
    val guide = store.guide
    val item = guide?.item(shownId)
    Column(Modifier.fillMaxSize().appBackground(HajinColors.accent)) {
        TopBar(item?.name?.resolved ?: "") {
            if (item != null) HajinReportMenu(listOf("Item: ${item.name.en ?: item.name.resolved}", "Item ID: ${item.id}", "Kind: ${item.kind}"))
        }
        if (guide == null || item == null) {
            FilterEmptyRow(L("mw4.ui.hajin.no_results"))
            return@Column
        }
        Column(
            Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = readableInset()).padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(18.dp),
        ) {
            Header(item)
            if (HajinVerdict.applies(item)) VerdictBadge(HajinVerdict(item, guide, store.checked), have = store.count(item.id))
            if (item.blueprint == true) BlueprintStatus(item)
            if (item.kind == "FOB Upgrade") UpgradeStatus(item)
            if (HajinStore.inStash(item)) StashPanel(item)
            val tiers = guide.tiers(item)
            if (tiers.size > 1) TierStrip(item, tiers, id) { tierShown = it }
            if (!item.cost.isNullOrEmpty() || item.cash != null) Recipe(item)
            Facts(item)
            item.marker?.let { guide.marker(it) }?.let { MapButton(it) }
            Secondary(item, guide)
        }
    }
}

@Composable
private fun Header(item: HajinGuide.Item) {
    Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
        ItemTile(item, 104.dp)
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(item.name.resolved.uppercase(appLocale), style = displayStyle(26.sp), color = Ink.text)
            RarityLine(item)
            item.effect?.let { Text(it.resolved, style = sys(15f).copy(fontStyle = FontStyle.Italic), color = Ink.text.copy(alpha = 0.85f)) }
        }
    }
}

/** A section's heading, as My DMZ's. */
@Composable
private fun PanelTitle(text: String, modifier: Modifier = Modifier) {
    Text(text, style = displayStyle(18.sp), color = Ink.text, modifier = modifier.padding(top = 4.dp))
}

/** The panel, outlined in a colour when it has something to say. */
@Composable
private fun Modifier.panel(tint: Color? = null): Modifier {
    val shape = RoundedCornerShape(8.dp)
    return this.fillMaxWidth().clip(shape)
        .background(tint?.copy(alpha = 0.08f) ?: LocalPalette.current.surface.copy(alpha = 0.9f))
        .border(1.dp, tint?.copy(alpha = 0.7f) ?: Ink.muted.copy(alpha = 0.2f), shape)
}

@Composable
private fun PanelDivider(start: Dp = 0.dp) {
    Box(Modifier.padding(start = start).fillMaxWidth().height(1.dp).background(Ink.muted.copy(alpha = 0.2f)))
}

/** Blueprints: tick once found (the "Still to find" list). */
@Composable
private fun BlueprintStatus(item: HajinGuide.Item) {
    val store = hajin()
    val found = store.hasBlueprint(item.id)
    Row(Modifier.panel().padding(12.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        HajinTick(found, item.name.resolved) { store.toggle(HajinStore.blueprintKey(item.id)) }
        Text(L(if (found) "mw4.ui.hajin.blueprint_found" else "mw4.ui.hajin.blueprint_missing"), style = sys(15f, FontWeight.SemiBold),
            color = if (found) HajinColors.text else Ink.text, modifier = Modifier.weight(1f))
        Icon(Icons.Filled.FindInPage, null, tint = if (found) HajinColors.text else Ink.muted)
    }
}

/** One status row: Printed / Ready to print / tick once printed. */
@Composable
private fun UpgradeStatus(item: HajinGuide.Item) {
    val store = hajin()
    val key = "upgrade-${item.id}"
    val done = key in store.checked
    val ready = !done && store.canPrint(item)
    Row(Modifier.panel(if (ready) HajinColors.printable else null).padding(12.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        HajinTick(done, item.name.resolved) { store.toggle(key) }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(L(when { done -> "mw4.ui.hajin.printed"; ready -> "mw4.ui.hajin.can_print_title"; else -> "mw4.ui.hajin.not_printed" }),
                style = sys(15f, FontWeight.SemiBold), color = when { done -> HajinColors.text; ready -> HajinColors.printable; else -> Ink.text })
            if (ready) Text(L("mw4.ui.hajin.ready_tick"), style = sys(12f), color = Ink.muted)
        }
        if (ready) Icon(Icons.Filled.Print, null, tint = HajinColors.printable)
    }
}

/** How many you have and what one sells for, side by side. */
@Composable
private fun StashPanel(item: HajinGuide.Item) {
    val store = hajin()
    val have = store.count(item.id)
    Row(Modifier.panel().height(IntrinsicSize.Min).padding(12.dp), horizontalArrangement = Arrangement.spacedBy(14.dp)) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text(L("mw4.ui.hajin.in_stash"), style = sys(12f, FontWeight.SemiBold), color = Ink.muted)
            StashStepper(item.id, big = true)
        }
        item.value?.let { value ->
            Box(Modifier.width(1.dp).fillMaxHeight().background(LocalPalette.current.surface2))
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(L("mw4.ui.hajin.sells_for"), style = sys(12f, FontWeight.SemiBold), color = Ink.muted)
                Text(money(value), style = displayStyle(30.sp), color = Ink.text, maxLines = 1)
                if (have > 1) Text("${money(value * have)} ×$have", style = sys(12f), color = Ink.muted)
            }
        }
    }
}

/** Every tier of the upgrade side by side, this one lit; tap another to jump to it. */
@Composable
private fun TierStrip(item: HajinGuide.Item, tiers: List<HajinGuide.Item>, openedId: String, show: (String?) -> Unit) {
    val store = hajin()
    val haptics = LocalHapticFeedback.current
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        PanelTitle(L("mw4.ui.hajin.tiers"))
        val tile: @Composable (HajinGuide.Item, Modifier) -> Unit = { tier, modifier ->
            val current = tier.id == item.id
            val done = "upgrade-${tier.id}" in store.checked
            Column(
                modifier.clip(RoundedCornerShape(8.dp)).background(if (current) HajinColors.accent else LocalPalette.current.surface)
                    .border(1.dp, Ink.muted.copy(alpha = if (current) 0f else 0.25f), RoundedCornerShape(8.dp))
                    .clickable(enabled = !current) { haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove); show(if (tier.id == openedId) null else tier.id) }
                    .padding(vertical = 8.dp),
                horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(3.dp),
            ) {
                val ink = if (current) Color.Black.copy(alpha = 0.85f) else Ink.text
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text(roman(tier.tier ?: 1), style = displayStyle(18.sp), color = ink)
                    if (done) Icon(Icons.Filled.CheckCircle, null, tint = ink, modifier = Modifier.size(12.dp))
                }
                Text(tier.cash?.let { "$" + compactNumber(it) } ?: "–", style = sys(11f, FontWeight.SemiBold, mono = true),
                    color = if (current) Color.Black.copy(alpha = 0.7f) else Ink.muted)
            }
        }
        if (tiers.size > 5) {
            Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                for (tier in tiers) tile(tier, Modifier.width(64.dp))
            }
        } else {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) { for (tier in tiers) tile(tier, Modifier.weight(1f)) }
        }
    }
}

/** "$500K" rather than "$500,000", so nine tiers still read. */
fun compactNumber(n: Int): String =
    runCatching { android.icu.text.CompactDecimalFormat.getInstance(appLocale, android.icu.text.CompactDecimalFormat.CompactStyle.SHORT).format(n) }
        .getOrDefault(number(n))

/** The recipe (or an upgrade's cost), with Track, like the printer. */
@Composable
private fun Recipe(item: HajinGuide.Item) {
    val store = hajin()
    // A recipe (not an upgrade, whose status row says it) the stash covers: outlined green, a line under it
    val covered = item.kind != "FOB Upgrade" && store.canPrint(item)
    val locked = store.isLocked(item.requiredLevel)
    val cost = item.cost ?: emptyList()
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            PanelTitle(L(if (item.kind == "FOB Upgrade") "mw4.ui.hajin.cost" else "mw4.ui.hajin.recipe"), Modifier.weight(1f))
            // Tracked recipes and upgrades show on My DMZ and in My stash
            TrackButton(item.id)
        }
        Column(Modifier.panel(if (covered && !locked) HajinColors.printable else null)) {
            item.cash?.let { cash ->
                Row(Modifier.padding(horizontal = 12.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    Box(Modifier.size(40.dp), contentAlignment = Alignment.Center) { Icon(Icons.Filled.AttachMoney, null, tint = Ink.text) }
                    Text(L("mw4.ui.hajin.cash"), style = sys(15f, FontWeight.Medium), color = Ink.text, modifier = Modifier.weight(1f))
                    Column(horizontalAlignment = Alignment.End) {
                        Text(money(cash), style = sys(17f, FontWeight.SemiBold, mono = true), color = Ink.text)
                        CashShort(cash)
                    }
                }
                if (cost.isNotEmpty()) PanelDivider()
            }
            cost.forEachIndexed { index, part ->
                CostLine(part)
                if (index < cost.size - 1) PanelDivider(64.dp)
            }
        }
        if (covered) {
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                Icon(if (locked) Icons.Filled.Lock else Icons.Filled.Print, null, tint = if (locked) Ink.muted else HajinColors.printable, modifier = Modifier.size(14.dp))
                Text(if (locked) L("mw4.ui.hajin.unlocks_at", item.requiredLevel ?: 0) else "${L("mw4.ui.hajin.can_print_title")}. ${L("mw4.ui.hajin.can_print_detail")}",
                    style = sys(13f, FontWeight.SemiBold), color = if (locked) Ink.muted else HajinColors.printable)
            }
        }
        if (item.unlock != null && item.requiredLevel == null) Text(item.unlock.resolved, style = sys(13f), color = Color(0xFFDBD18C))
    }
}

/** One ingredient line on a recipe: icon, name, amount. Taps through to it. */
@Composable
private fun CostLine(part: HajinGuide.Item.Cost) {
    val store = hajin()
    val item = store.guide?.item(part.item)
    val have = store.count(part.item)
    Row(
        Modifier.fillMaxWidth().clickable { openHajin(Route.HajinItem(part.item)) }.padding(horizontal = 12.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        ItemTile(item, 40.dp)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(1.dp)) {
            Text(item?.name?.resolved ?: part.item, style = sys(15f, FontWeight.Medium), color = Ink.text)
            item?.rarity?.let { Text(it, style = sys(11f, FontWeight.SemiBold), color = HajinColors.rarity(it)) }
        }
        // With some in the stash: have/need, green once covered
        Text(if (have > 0) "$have/${part.qty}" else "×${part.qty}", style = sys(17f, FontWeight.SemiBold, mono = true),
            color = if (have >= part.qty) HajinColors.printable else Ink.text)
        Chevron(alpha = 0.6f)
    }
}

@Composable
private fun Facts(item: HajinGuide.Item) {
    val lines = listOfNotNull(
        if (item.cost == null) item.unlock?.let { L("mw4.ui.hajin.unlock") to it.resolved } else null,
        item.grid?.let { L("mw4.ui.hajin.grid") to it },
        // In the stash card above for what My stash counts
        if (HajinStore.inStash(item)) null else item.value?.let { L("mw4.ui.hajin.sells_for") to money(it) },
        item.note?.let { L("mw4.ui.hajin.notes") to it.resolved },
    )
    if (lines.isEmpty()) return
    Column(Modifier.panel()) {
        lines.forEachIndexed { index, (title, value) ->
            Row(Modifier.padding(12.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Text(title, style = sys(12f, FontWeight.SemiBold), color = Ink.muted, modifier = Modifier.width(92.dp))
                Text(value, style = sys(15f), color = Ink.text, modifier = Modifier.weight(1f))
            }
            if (index < lines.size - 1) PanelDivider()
        }
    }
}

@Composable
private fun MapButton(marker: HajinGuide.Marker) {
    Row(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(8.dp)).background(HajinColors.accent.copy(alpha = 0.18f))
            .clickable { openHajin(Route.HajinMap(marker.id)) }.padding(vertical = 12.dp),
        horizontalArrangement = Arrangement.Center, verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(Icons.Filled.Map, null, tint = HajinColors.text, modifier = Modifier.size(16.dp))
        Spacer(Modifier.width(6.dp))
        Text(L("mw4.ui.hajin.show_on_map"), style = sys(15f, FontWeight.SemiBold), color = HajinColors.text)
    }
}

/** Where to find it, what uses it, and the levels that unlock or hand it out. */
@Composable
private fun Secondary(item: HajinGuide.Item, guide: HajinGuide) {
    val users = guide.usedIn(item.id)
    // Level rows are unlocks (recipe) or rewards; everything else is where to find it
    val mentions = guide.mentions(item.id)
    val levels = mentions.filter { it.first.id == "levels" }
    val found = mentions.filter { it.first.id != "levels" }
    val showsWhere = found.isNotEmpty() || item.found != null
    val places = (item.foundPlaces ?: emptyList()).mapNotNull { guide.marker(it) }
    // The in-game line, unless it only names a row listed under it ("Colossus" over the Colossus boss row)
    val inGame = item.found?.resolved?.let { text ->
        val lower = text.lowercase()
        val name = if (lower.endsWith("s")) lower.dropLast(1) else lower
        if (places.isEmpty() && found.any { it.second.title.resolved.lowercase().contains(name) }) null else text
    }
    if (showsWhere && item.found != null) WhereFrom(found, inGame, places)
    if (users.isNotEmpty()) UsedIn(users, item.id)
    if (showsWhere && item.found == null) WhereFrom(found, null, emptyList())
    if (levels.isNotEmpty() || item.requiredLevel != null) Unlocks(item, levels)
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun WhereFrom(mentions: List<Pair<HajinGuide.Section, HajinGuide.Row>>, inGame: String?, places: List<HajinGuide.Marker>) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        PanelTitle(L("mw4.ui.hajin.where_find"))
        Column(Modifier.panel()) {
            if (inGame != null) {
                Row(Modifier.padding(12.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    Box(Modifier.width(28.dp), contentAlignment = Alignment.Center) { Icon(Icons.Filled.Place, null, tint = HajinColors.text, modifier = Modifier.size(18.dp)) }
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        Text(inGame, style = sys(15f, FontWeight.SemiBold), color = Ink.text)
                        Text(L("mw4.ui.hajin.found_in_game"), style = sys(12f), color = Ink.muted)
                        if (places.isNotEmpty()) {
                            FlowRow(Modifier.padding(top = 6.dp), horizontalArrangement = Arrangement.spacedBy(6.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                                for (marker in places) {
                                    Row(
                                        Modifier.clip(RoundedCornerShape(6.dp)).background(HajinColors.accent.copy(alpha = 0.15f))
                                            .clickable { openHajin(Route.HajinMap(marker.id)) }.padding(horizontal = 8.dp, vertical = 5.dp),
                                        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp),
                                    ) {
                                        Icon(Icons.Filled.Map, null, tint = HajinColors.text, modifier = Modifier.size(12.dp))
                                        Text(marker.name.resolved, style = sys(12f, FontWeight.SemiBold), color = HajinColors.text, maxLines = 1)
                                    }
                                }
                            }
                        }
                    }
                }
                if (mentions.isNotEmpty()) PanelDivider()
            }
            mentions.forEachIndexed { index, (section, row) ->
                Row(Modifier.padding(12.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    Box(Modifier.width(28.dp), contentAlignment = Alignment.Center) { Icon(sectionPainter(section), null, tint = HajinColors.text, modifier = Modifier.size(18.dp)) }
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text(row.title.resolved, style = sys(15f, FontWeight.SemiBold), color = Ink.text, modifier = Modifier.weight(1f))
                            row.value?.let { ValueBadge(it.resolved) }
                        }
                        Text(section.title.resolved, style = sys(12f), color = Ink.muted)
                    }
                }
                if (index < mentions.size - 1) PanelDivider()
            }
        }
    }
}

@Composable
private fun UsedIn(users: List<HajinGuide.Item>, shownId: String) {
    val store = hajin()
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        PanelTitle(L("mw4.ui.hajin.used_in"))
        Column(Modifier.panel()) {
            users.forEachIndexed { index, user ->
                Row(verticalAlignment = Alignment.CenterVertically) {
                    if (user.kind == "FOB Upgrade") {
                        val key = "upgrade-${user.id}"
                        Box(Modifier.padding(start = 8.dp)) { HajinTick(key in store.checked, user.name.resolved) { store.toggle(key) } }
                    }
                    Row(
                        Modifier.weight(1f).clickable { openHajin(Route.HajinItem(user.id)) }.padding(horizontal = 12.dp, vertical = 8.dp),
                        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp),
                    ) {
                        ItemTile(user, 40.dp)
                        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                            Text(user.name.resolved, style = sys(15f, FontWeight.Medium), color = Ink.text)
                            RarityLine(user, 9f)
                        }
                        user.cost?.firstOrNull { it.item == shownId }?.qty?.let {
                            Text("×$it", style = sys(15f, FontWeight.SemiBold, mono = true), color = Ink.muted)
                        }
                        Chevron(alpha = 0.6f)
                    }
                }
                if (index < users.size - 1) PanelDivider(64.dp)
            }
        }
    }
}

/** When a recipe unlocks, or which levels hand the item out. */
@Composable
private fun Unlocks(item: HajinGuide.Item, levels: List<Pair<HajinGuide.Section, HajinGuide.Row>>) {
    val store = hajin()
    // Only the recipe's own level unlocks it; any other level that names the item hands one out
    val rows = levels.mapNotNull { (_, row) ->
        val level = row.level ?: return@mapNotNull null
        level to L(if (level == item.requiredLevel) "mw4.ui.hajin.unlock_recipe" else "mw4.ui.hajin.unlock_reward")
    }.toMutableList()
    item.requiredLevel?.let { needed -> if (rows.none { it.first == needed }) rows.add(0, needed to L("mw4.ui.hajin.unlock_recipe")) }
    rows.sortBy { it.first }
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        PanelTitle(L("mw4.ui.hajin.unlocks"))
        Column(Modifier.panel()) {
            rows.forEachIndexed { index, (level, text) ->
                val locked = store.isLocked(level)
                Row(Modifier.padding(12.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    Box(Modifier.width(28.dp), contentAlignment = Alignment.Center) {
                        Icon(when { store.dmzLevel == 0 -> Icons.Filled.BarChart; locked -> Icons.Filled.Lock; else -> Icons.Filled.CheckCircle }, null,
                            tint = if (store.dmzLevel > 0 && !locked) HajinColors.text else Ink.muted, modifier = Modifier.size(17.dp))
                    }
                    Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        Text(L("mw4.ui.hajin.dmz_level_n", level), style = sys(15f, FontWeight.SemiBold), color = Ink.text)
                        Text(text, style = sys(12f), color = Ink.muted)
                    }
                }
                if (index < rows.size - 1) PanelDivider()
            }
        }
    }
}

/** Track button for a recipe or upgrade's screen: a small pill, up to five at once. */
@Composable
fun TrackButton(id: String) {
    val store = hajin()
    val on = store.isTracked(id)
    val full = !on && store.tracked.size >= HajinStore.MAX_TRACKED
    val haptics = LocalHapticFeedback.current
    Row(
        Modifier.clip(CircleShape).background(if (on) HajinColors.accent else Color.Transparent)
            .border(1.dp, if (on) Color.Transparent else HajinColors.accent.copy(alpha = if (full) 0.3f else 0.7f), CircleShape)
            .clickable(enabled = !full) { haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove); store.toggleTracked(id) }
            .padding(horizontal = 12.dp, vertical = 6.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp),
    ) {
        val ink = when { on -> Color.Black.copy(alpha = 0.85f); full -> Ink.muted; else -> HajinColors.text }
        Icon(if (on) Icons.Filled.Check else Icons.Filled.Add, null, tint = ink, modifier = Modifier.size(14.dp))
        Text(when { on -> L("mw4.ui.hajin.tracking"); full -> L("mw4.ui.hajin.track_full", HajinStore.MAX_TRACKED); else -> L("mw4.ui.hajin.track") },
            style = sys(13f, FontWeight.SemiBold), color = ink)
    }
}

// MARK: - Keep or sell verdict

val HajinVerdict.title: String
    get() = L(when (kind) {
        HajinVerdict.Kind.KEEP -> "mw4.ui.keep.keep"
        HajinVerdict.Kind.CRAFTING -> "mw4.ui.keep.crafting"
        HajinVerdict.Kind.SELL -> "mw4.ui.keep.sell"
        HajinVerdict.Kind.USE -> "mw4.ui.keep.use"
        HajinVerdict.Kind.RESOURCE -> "mw4.ui.keep.resource"
    })

val HajinVerdict.color: Color
    get() = when (kind) {
        HajinVerdict.Kind.KEEP -> HajinColors.keep
        HajinVerdict.Kind.CRAFTING -> HajinColors.crafting
        HajinVerdict.Kind.SELL -> HajinColors.printable
        else -> Color(0xFFB3B3B3)
    }

val HajinVerdict.icon: ImageVector
    get() = when (kind) {
        HajinVerdict.Kind.KEEP -> Icons.Filled.Lock
        HajinVerdict.Kind.CRAFTING -> Icons.Filled.Print
        HajinVerdict.Kind.SELL -> Icons.Filled.MonetizationOn
        HajinVerdict.Kind.USE -> Icons.Filled.TouchApp
        HajinVerdict.Kind.RESOURCE -> Icons.Filled.Recycling
    }

/** One line on why: what needs it, or what it sells for. */
val HajinVerdict.reason: String
    get() = when (kind) {
        HajinVerdict.Kind.KEEP -> buildList {
            if (upgrades.isNotEmpty()) add(L("mw4.ui.keep.keep_reason", upgrades.sumOf { it.second }, upgrades.joinToString(", ") { "${it.first.name.resolved} ×${it.second}" }))
            if (orders.isNotEmpty()) add(L("mw4.ui.keep.orders_reason", orders.sumOf { it.second }, orders.joinToString(", ") { "${it.first.title.resolved} ×${it.second}" }))
        }.joinToString(" ")
        HajinVerdict.Kind.CRAFTING -> L("mw4.ui.keep.crafting_reason", recipes.joinToString(", ") { it.first.name.resolved })
        HajinVerdict.Kind.SELL -> value?.let { L("mw4.ui.keep.sell_reason", money(it)) } ?: L("mw4.ui.keep.sell_reason_novalue")
        HajinVerdict.Kind.USE -> when (itemKind) {
            "Key" -> L("mw4.ui.keep.use_key")
            "Consumables" -> L("mw4.ui.keep.use_consumable")
            else -> L("mw4.ui.keep.use_reason")
        }
        HajinVerdict.Kind.RESOURCE -> L("mw4.ui.keep.resource_reason")
    }

/** The banner's line: for a Keep, how many are needed against how many the stash has. */
fun HajinVerdict.summary(have: Int): String = when (kind) {
    HajinVerdict.Kind.KEEP -> {
        val total = upgrades.sumOf { it.second } + orders.sumOf { it.second }
        if (have >= total) L("mw4.ui.keep.keep_covered", total, have) else L("mw4.ui.keep.keep_left", total, have, total - have)
    }
    HajinVerdict.Kind.CRAFTING -> L("mw4.ui.keep.crafting_short")
    else -> reason
}

/** What a Keep or Crafting verdict links to. */
val HajinVerdict.needs: List<Pair<HajinGuide.Item, Int>>
    get() = when (kind) { HajinVerdict.Kind.KEEP -> upgrades; HajinVerdict.Kind.CRAFTING -> recipes; else -> emptyList() }

/** The verdict as a coloured banner on the item screen, linking to what needs the item. */
@Composable
fun VerdictBadge(verdict: HajinVerdict, have: Int) {
    val shape = RoundedCornerShape(8.dp)
    Column(
        Modifier.fillMaxWidth().clip(shape).background(verdict.color.copy(alpha = 0.12f)).border(1.dp, verdict.color.copy(alpha = 0.4f), shape).padding(12.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Icon(verdict.icon, null, tint = verdict.color, modifier = Modifier.size(22.dp))
            Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(verdict.title.uppercase(appLocale), style = sys(14f, FontWeight.ExtraBold).copy(letterSpacing = 0.8.sp), color = verdict.color)
                Text(verdict.summary(have), style = sys(15f), color = Ink.text.copy(alpha = 0.85f))
            }
        }
        val needs = verdict.needs
        if (needs.isNotEmpty()) {
            LinkChips(needs.map { it.first.id }, if (verdict.kind == HajinVerdict.Kind.KEEP) needs.groupBy { it.first.id }.mapValues { e -> e.value.sumOf { it.second } } else emptyMap(), arrows = true)
        }
        if (verdict.kind == HajinVerdict.Kind.KEEP && verdict.orders.isNotEmpty()) OrderChips(verdict.orders)
    }
}

// MARK: - An order on its own

/** One mission or DMZ Order's card on its own, from a link. */
@Composable
fun HajinOrderScreen(check: String) {
    val store = hajin()
    val row = store.guide?.section("ops")?.rows?.firstOrNull { it.check == check }
    Column(Modifier.fillMaxSize().appBackground(HajinColors.accent)) {
        TopBar(row?.title?.resolved ?: "")
        if (row == null) return@Column
        LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(horizontal = readableInset(), vertical = 8.dp)) {
            row.group?.let { group -> item { Box(Modifier.padding(horizontal = 16.dp, vertical = 6.dp)) { SmallCaps(group.resolved) } } }
            item { Box(Modifier.hajinCard()) { MissionRow(row) } }
        }
    }
}

// MARK: - Report a data issue

/** "Report a data issue" on a DMZ item or guide section, with the kinds that fit guide data. */
@Composable
fun HajinReportMenu(lines: List<String>) {
    val context = LocalContext.current
    val store = hajin()
    var open by remember { mutableStateOf(false) }
    val kinds = listOf(
        Triple("Wrong info", "mw4.ui.report.dmz_info", Icons.Outlined.Info),
        Triple("Something missing", "mw4.ui.report.dmz_missing", Icons.Outlined.AddCircleOutline),
        Triple("Missing or wrong image", "mw4.ui.report.image", Icons.Outlined.Image),
        Triple("Wrong name", "mw4.ui.report.name", Icons.Outlined.TextFields),
        Triple("Something else", "mw4.ui.report.other", Icons.Filled.MoreHoriz),
    )
    Box {
        IconButton(onClick = { open = true }) {
            Icon(Icons.Filled.Feedback, L("mw4.ui.report.title"), tint = HajinColors.text)
        }
        DropdownMenu(open, { open = false }, containerColor = LocalPalette.current.surface2) {
            Text(L("mw4.ui.report.title"), style = sys(12f, FontWeight.SemiBold), color = Ink.muted, modifier = Modifier.padding(horizontal = 16.dp, vertical = 6.dp))
            for ((mail, key, icon) in kinds) {
                DropdownMenuItem(
                    text = { Text(L(key), color = Ink.text) },
                    leadingIcon = { Icon(icon, null, tint = Ink.muted) },
                    onClick = { open = false; SupportMail.dmz(context, mail, lines, store.guide?.version) },
                )
            }
        }
    }
}
