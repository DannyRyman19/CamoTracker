package app.camotrack.android.ui.hajin

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.camotrack.android.Route
import app.camotrack.android.core.hajin.HajinGuide
import app.camotrack.android.core.hajin.HajinStore
import app.camotrack.android.core.hajin.HajinVerdict
import app.camotrack.android.i18n.L
import app.camotrack.android.ui.*

// MARK: - Stash stepper

/** − count + for one stash entry; tap the number to type it. */
@Composable
fun StashStepper(id: String, big: Boolean = false) {
    val store = hajin()
    val count = store.count(id)
    var entering by remember { mutableStateOf(false) }
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        StepButton(Icons.Filled.Remove, count > 0, 24.dp, HajinColors.accent) { store.setCount(count - 1, id) }
        Text(
            "$count",
            style = if (big) displayStyle(30.sp) else sys(14f, FontWeight.Bold, mono = true),
            color = if (big) (if (count > 0) Ink.text else Ink.muted) else if (count > 0) HajinColors.text else Ink.muted,
            maxLines = 1, textAlign = androidx.compose.ui.text.style.TextAlign.Center,
            modifier = Modifier.widthIn(min = 40.dp).clickable { entering = true },
        )
        StepButton(Icons.Filled.Add, true, 24.dp, HajinColors.accent) { store.setCount(count + 1, id) }
    }
    if (entering) {
        HajinNumberDialog(store.guide?.item(id)?.name?.resolved ?: "", "0", if (count > 0) "$count" else "", { entering = false }) { n ->
            store.setCount(n ?: 0, id)
        }
    }
}

// MARK: - Tracking

/** The Hajin home card: everything tracked, how close each is with what's in the stash, and what to look out for. */
@Composable
fun TrackingCard() {
    val store = hajin()
    val guide = store.guide ?: return
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            CardSymbol(MineCard.TRACKING.painter())
            Text(L("mw4.ui.hajin.tracking"), style = displayStyle(16.sp), color = Ink.text, modifier = Modifier.weight(1f))
            Text("${store.tracked.size}/${HajinStore.MAX_TRACKED}", style = sys(12f, FontWeight.SemiBold, mono = true), color = Ink.muted)
        }
        if (store.tracked.isEmpty()) {
            Text(L("mw4.ui.hajin.tracking_empty"), style = sys(12f), color = Ink.muted)
        } else {
            for (id in store.tracked) guide.item(id)?.let { TrackedRow(it) }
            val short = store.shortfall(guide)
            if (short.isEmpty()) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                    Icon(Icons.Filled.CheckCircle, null, tint = HajinColors.printable, modifier = Modifier.size(14.dp))
                    Text(L("mw4.ui.hajin.all_ready"), style = sys(12f, FontWeight.SemiBold), color = HajinColors.printable)
                }
            } else {
                Box(Modifier.padding(top = 2.dp)) { SmallCaps(L("mw4.ui.hajin.look_out_for")) }
                LinkChips(short.map { it.first.id }, short.associate { it.first.id to it.second })
            }
        }
    }
}

/** One tracked item: its name (opens it), each ingredient as have/need, and a remove button. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun TrackedRow(item: HajinGuide.Item) {
    val store = hajin()
    val cost = item.cost ?: emptyList()
    val ready = cost.isNotEmpty() && store.affords(item) && cost.all { store.count(it.item) >= it.qty }
    val haptics = LocalHapticFeedback.current
    Column(Modifier.padding(vertical = 2.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Row(Modifier.weight(1f).clickable { openHajin(Route.HajinItem(item.id)) }, verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                ItemTile(item, 32.dp)
                Column(verticalArrangement = Arrangement.spacedBy(1.dp)) {
                    Text(item.name.resolved, style = sys(15f, FontWeight.SemiBold), color = Ink.text)
                    if (ready) CanPrintTag()
                }
            }
            IconButton(onClick = { haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove); store.toggleTracked(item.id) }, modifier = Modifier.size(28.dp)) {
                Icon(Icons.Filled.Cancel, L("mw4.ui.hajin.untrack"), tint = Ink.muted)
            }
        }
        FlowRow(Modifier.padding(start = 42.dp), horizontalArrangement = Arrangement.spacedBy(10.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            for (part in cost) {
                val have = store.count(part.item)
                Row(Modifier.clickable { openHajin(Route.HajinItem(part.item)) }, verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(3.dp)) {
                    ItemTile(store.guide?.item(part.item), 22.dp)
                    Text("${minOf(have, part.qty)}/${part.qty}", style = sys(11f, FontWeight.SemiBold, mono = true),
                        color = if (have >= part.qty) HajinColors.printable else Ink.text)
                }
            }
        }
    }
}

/** Suggests the next FOB upgrades to print from what's in the stash. */
@Composable
fun BuildNextCard() {
    val store = hajin()
    val picks = store.buildNext()
    val haptics = LocalHapticFeedback.current
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            CardSymbol(MineCard.BUILD_NEXT.painter())
            Text(L("mw4.ui.hajin.build_next"), style = displayStyle(16.sp), color = Ink.text, modifier = Modifier.weight(1f))
            if (store.stash.isEmpty()) Text(L("mw4.ui.hajin.build_next_hint"), style = sys(12f), color = Ink.muted, modifier = Modifier.weight(1f, fill = false))
        }
        if (picks.isEmpty()) Text(L("mw4.ui.hajin.build_next_done"), style = sys(12f), color = Ink.muted)
        for (pick in picks) {
            val cost = pick.item.cost ?: emptyList()
            val ready = pick.missing.isEmpty() && cost.isNotEmpty() && store.affords(pick.item)
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    Row(Modifier.weight(1f).clickable { openHajin(Route.HajinItem(pick.item.id)) }, verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        ItemTile(pick.item, 32.dp)
                        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                            Text(pick.item.name.resolved, style = sys(15f, FontWeight.SemiBold), color = Ink.text)
                            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                                if (ready) CanPrintTag()
                                pick.item.cash?.let { cash ->
                                    // Red when it's more than the cash the player entered
                                    Text(money(cash), style = sys(11f, FontWeight.SemiBold, mono = true),
                                        color = if (store.cash > 0 && cash > store.cash) HajinColors.short else Ink.muted)
                                    CashShort(cash)
                                }
                            }
                        }
                    }
                    if (!store.isTracked(pick.item.id) && store.tracked.size < HajinStore.MAX_TRACKED) {
                        IconButton(onClick = { haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove); store.toggleTracked(pick.item.id) }, modifier = Modifier.size(32.dp)) {
                            Icon(Icons.Filled.AddCircleOutline, L("mw4.ui.hajin.track"), tint = HajinColors.text)
                        }
                    } else if (store.isTracked(pick.item.id)) {
                        Icon(Icons.Filled.GpsFixed, null, tint = HajinColors.text, modifier = Modifier.size(20.dp))
                    }
                }
                if (cost.isEmpty()) {
                    Box(Modifier.padding(start = 42.dp)) { SmallCaps(L("mw4.ui.hajin.cash_only"), size = 10f) }
                } else {
                    ProgressBar(pick.covered, if (ready) HajinColors.printable else HajinColors.accent)
                }
                if (pick.missing.isNotEmpty() && store.stash.isNotEmpty()) {
                    LinkChips(pick.missing.map { it.first }, pick.missing.groupBy { it.first }.mapValues { e -> e.value.sumOf { it.second } })
                }
            }
        }
    }
}

// MARK: - My stash

/** Every ingredient and resource with a stepper: what the player has. */
@Composable
fun StashScreen() {
    val store = hajin()
    var query by rememberSaveable { mutableStateOf("") }
    val guide = store.guide
    val groups = remember(Hajin.revision, query) {
        if (guide == null) emptyList() else {
            val needle = query.lowercase()
            val all = (guide.items ?: emptyList()).filter { HajinStore.inStash(it) && it.id != "commanders" }
                .filter { needle.isEmpty() || it.name.resolved.lowercase().contains(needle) }
            // Needed for something tracked first, then resources, then the rest
            val short = store.shortfall(guide).map { it.first.id }.toSet()
            val neededIds = store.tracked.flatMap { id -> guide.item(id)?.cost?.map { it.item } ?: emptyList() }.toSet()
            val needed = all.filter { it.id in neededIds }.sortedWith(compareBy<HajinGuide.Item> { if (it.id in short) 0 else 1 }.thenBy { it.name.resolved })
            val resources = all.filter { it.kind == "Resource" && it.id !in neededIds }.sortedBy { HajinStore.resourceRank(it.id) }
            val rest = all.filter { it.kind == "Ingredient" && it.id !in neededIds }.sortedBy { it.name.resolved }
            val valuables = all.filter { it.kind == "Valuable" && it.id !in neededIds }.sortedBy { it.name.resolved }
            listOf(L("mw4.ui.hajin.for_tracked") to needed, L("mw4.ui.hajin.resources") to resources,
                L("mw4.ui.hajin.ingredients") to rest, L("mw4.ui.hajin.valuables") to valuables).filter { it.second.isNotEmpty() }
        }
    }
    Column(Modifier.fillMaxSize().appBackground(HajinColors.accent)) {
        TopBar(L("mw4.ui.hajin.stash"))
        LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(bottom = 24.dp)) {
            item(key = "search") { HajinSearchField(query, L("mw4.ui.hajin.search_section")) { query = it } }
            if (query.isEmpty()) {
                item(key = "intro") { HajinIntro(L("mw4.ui.hajin.stash_intro")) }
                // One photo reader: the stash grid, a backpack or a 3D Printer screen
                item(key = "scan") { app.camotrack.android.ui.hajin.scan.ScanStashRow() }
            }
            for ((title, items) in groups) {
                item(key = "h-$title") { HajinHeading(title) }
                for (item in items) item(key = "${title}-${item.id}") { StashRow(item) }
            }
        }
    }
}

@Composable
private fun StashRow(item: HajinGuide.Item) {
    Row(Modifier.hajinCard(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Row(Modifier.weight(1f).clickable { openHajin(Route.HajinItem(item.id)) }, verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            ItemTile(item, 36.dp)
            Text(item.name.resolved, style = displayStyle(15.sp), color = Ink.text)
        }
        StashStepper(item.id)
    }
}

/** A tool row on My DMZ: its round icon, title, subtitle and a figure. */
@Composable
private fun ToolEntry(icon: androidx.compose.ui.graphics.painter.Painter, title: String, subtitle: String, figure: String?, figureColor: Color = Ink.muted) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        CardSymbol(icon)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(title, style = displayStyle(16.sp), color = Ink.text)
            Text(subtitle, style = sys(12f), color = Ink.muted)
        }
        figure?.let { Text(it, style = sys(12f, FontWeight.SemiBold, mono = true), color = figureColor) }
    }
}

@Composable
fun StashEntry() {
    val store = hajin()
    ToolEntry(MineCard.STASH.painter(), L("mw4.ui.hajin.stash"), L("mw4.ui.hajin.stash_subtitle"), "${store.stash.values.sum()}")
}

@Composable
fun KeepSellEntry() {
    val store = hajin()
    val spare = store.spare().second
    ToolEntry(MineCard.KEEP_SELL.painter(), L("mw4.ui.keep.title"), L("mw4.ui.keep.row_subtitle"),
        if (spare > 0) L("mw4.ui.keep.spare_short", money(spare)) else null, HajinColors.printable)
}

@Composable
fun ShoppingEntry() {
    val store = hajin()
    val scope by Prefs.string(SHOP_SCOPE_KEY, HajinStore.ShoppingScope.UPGRADES.raw)
    val missing = store.shoppingList(shopScope(scope)).sumOf { it.missing }
    ToolEntry(MineCard.SHOPPING.painter(), L("mw4.ui.hajin.shop"), L("mw4.ui.hajin.shop_subtitle"), if (missing > 0) "$missing" else null)
}

// MARK: - Undo

/** "Took 20 Reactive Metals from your stash · Undo", with a bar running down until it goes away on its own. */
@Composable
fun BoxScope.HajinUndoOverlay() {
    val store = hajin()
    val undo = store.stashUndo
    AnimatedVisibility(
        visible = undo != null,
        enter = slideInVertically { it } + fadeIn(), exit = slideOutVertically { it } + fadeOut(),
        modifier = Modifier.align(Alignment.BottomCenter).padding(bottom = 16.dp),
    ) {
        val shown = remember { mutableStateOf(undo) }
        if (undo != null) shown.value = undo
        shown.value?.let { UndoToast(it) }
    }
}

@Composable
private fun UndoToast(undo: HajinStore.StashUndo) {
    val remaining = remember(undo.id) { Animatable(1f) }
    val haptics = LocalHapticFeedback.current
    LaunchedEffect(undo.id) {
        remaining.animateTo(0f, tween(6_000, easing = LinearEasing))
        Hajin.store.clearUndo(undo.id)
    }
    val shape = RoundedCornerShape(12.dp)
    Column(
        Modifier.padding(horizontal = 16.dp).fillMaxWidth().shadow(12.dp, shape).clip(shape).background(LocalPalette.current.surface2)
            .border(1.dp, Ink.muted.copy(alpha = 0.3f), shape).padding(14.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.Top) {
            Icon(Icons.Filled.Inventory2, null, tint = HajinColors.text, modifier = Modifier.size(18.dp))
            Text(undo.message, style = sys(15f), color = Ink.text, modifier = Modifier.weight(1f))
            Text(L("mw4.ui.hajin.undo"), style = sys(15f, FontWeight.Bold), color = HajinColors.text,
                modifier = Modifier.clickable { haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove); Hajin.store.undoStash() })
        }
        Box(Modifier.fillMaxWidth().height(3.dp).clip(CircleShape).background(Ink.muted.copy(alpha = 0.25f))) {
            Box(Modifier.fillMaxHeight().fillMaxWidth(remaining.value).clip(CircleShape).background(HajinColors.accent))
        }
    }
}

// MARK: - Keep or sell

/** Search anything you've looted and see whether to keep or sell it. */
@Composable
fun KeepSellScreen() {
    val store = hajin()
    var query by rememberSaveable { mutableStateOf("") }
    val guide = store.guide
    val groups = remember(Hajin.revision, query) {
        if (guide == null) emptyList() else {
            val needle = query.lowercase()
            val rows = (guide.items ?: emptyList()).filter { HajinVerdict.applies(it) }
                .filter { needle.isEmpty() || it.name.resolved.lowercase().contains(needle) }
                .sortedBy { it.name.resolved }
                .map { it to HajinVerdict(it, guide, store.checked) }
            listOf(HajinVerdict.Kind.KEEP, HajinVerdict.Kind.CRAFTING, HajinVerdict.Kind.SELL, HajinVerdict.Kind.USE)
                .mapNotNull { kind -> rows.filter { it.second.kind == kind }.takeIf { it.isNotEmpty() } }
        }
    }
    Column(Modifier.fillMaxSize().appBackground(HajinColors.accent)) {
        TopBar(L("mw4.ui.keep.title"))
        LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(bottom = 24.dp)) {
            item(key = "search") { HajinSearchField(query, L("mw4.ui.keep.search")) { query = it } }
            if (query.isEmpty()) {
                item(key = "intro") { HajinIntro(L("mw4.ui.keep.intro")) }
                item(key = "spare") { SpareCard() }
            }
            for (rows in groups) {
                item(key = "h-${rows.first().second.kind}") { HajinHeading(rows.first().second.title) }
                for ((item, verdict) in rows) item(key = "k-${item.id}") { Box(Modifier.hajinCard()) { KeepSellRow(item, verdict) } }
            }
        }
    }
}

/** One item in Keep or sell: its name links to it, and what needs it shows as chips. */
@Composable
private fun KeepSellRow(item: HajinGuide.Item, verdict: HajinVerdict) {
    val store = hajin()
    val line = when (verdict.kind) {
        HajinVerdict.Kind.KEEP -> verdict.summary(store.count(item.id))
        HajinVerdict.Kind.CRAFTING -> L("mw4.ui.keep.crafting_short")
        else -> verdict.reason
    }
    Column(Modifier.padding(vertical = 2.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(Modifier.fillMaxWidth().clickable { openHajin(Route.HajinItem(item.id)) }, verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            ItemTile(item, 44.dp)
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                Text(item.name.resolved, style = displayStyle(15.sp), color = Ink.text)
                Row(horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                    Icon(verdict.icon, null, tint = verdict.color, modifier = Modifier.padding(top = 2.dp).size(12.dp))
                    Text(line, style = sys(12f), color = Ink.text.copy(alpha = 0.85f), maxLines = 2)
                }
            }
            Chevron(alpha = 0.6f)
        }
        val needs = verdict.needs
        if (needs.isNotEmpty()) {
            LinkChips(needs.map { it.first.id },
                if (verdict.kind == HajinVerdict.Kind.KEEP) needs.groupBy { it.first.id }.mapValues { e -> e.value.sumOf { it.second } } else emptyMap(),
                arrows = true, modifier = Modifier.padding(start = 56.dp))
        }
        if (verdict.kind == HajinVerdict.Kind.KEEP && verdict.orders.isNotEmpty()) OrderChips(verdict.orders, Modifier.padding(start = 56.dp))
    }
}

/** "Spare to sell": the stash's worth beyond what's still needed, and the items that make it up. */
@Composable
private fun SpareCard() {
    val store = hajin()
    var keepTracked by Prefs.bool(HajinStore.SPARE_TRACKED_KEY, true)
    var buffer by Prefs.int(HajinStore.SPARE_BUFFER_KEY, 0)
    var keepRecipes by Prefs.bool(HajinStore.SPARE_RECIPES_KEY, true)
    var keepOrders by Prefs.bool(HajinStore.SPARE_ORDERS_KEY, true)
    // Read so the card redraws when a setting changes (the store reads them from the same keys)
    val (lines, total) = remember(Hajin.revision, keepTracked, buffer, keepRecipes, keepOrders) { store.spare() }
    var options by remember { mutableStateOf(false) }
    Column(
        Modifier.padding(horizontal = 12.dp, vertical = 4.dp).fillMaxWidth().clip(RoundedCornerShape(8.dp)).background(LocalPalette.current.surface).padding(12.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            Icon(Icons.Filled.MonetizationOn, null, tint = Ink.text, modifier = Modifier.size(18.dp))
            Text(L("mw4.ui.keep.spare_title"), style = displayStyle(16.sp), color = Ink.text, modifier = Modifier.weight(1f))
            Text(money(total), style = sys(18f, FontWeight.Bold, mono = true), color = if (total > 0) HajinColors.printable else Ink.muted)
            Box {
                IconButton(onClick = { options = true }, modifier = Modifier.size(32.dp)) {
                    Icon(Icons.Filled.Tune, L("mw4.ui.keep.spare_options"), tint = HajinColors.text)
                }
                DropdownMenu(options, { options = false }, containerColor = LocalPalette.current.surface2) {
                    @Composable
                    fun toggle(title: String, on: Boolean, set: (Boolean) -> Unit) = DropdownMenuItem(
                        text = { Text(title, color = Ink.text) },
                        leadingIcon = { Icon(if (on) Icons.Filled.CheckBox else Icons.Filled.CheckBoxOutlineBlank, null, tint = if (on) HajinColors.text else Ink.muted) },
                        onClick = { set(!on); options = false; Hajin.store.onChange() },
                    )
                    toggle(L("mw4.ui.keep.spare_keep_recipes"), keepRecipes) { keepRecipes = it }
                    toggle(L("mw4.ui.keep.spare_keep_tracked"), keepTracked) { keepTracked = it }
                    toggle(L("mw4.ui.keep.spare_keep_orders"), keepOrders) { keepOrders = it }
                    HorizontalDivider(color = Ink.muted.copy(alpha = 0.2f))
                    Text(L("mw4.ui.keep.spare_buffer"), style = sys(12f, FontWeight.SemiBold), color = Ink.muted, modifier = Modifier.padding(horizontal = 16.dp, vertical = 6.dp))
                    for (n in listOf(0, 5, 10)) {
                        DropdownMenuItem(
                            text = { Text(if (n == 0) L("mw4.ui.keep.spare_buffer_none") else L("mw4.ui.keep.spare_buffer_n", n), color = Ink.text) },
                            leadingIcon = { Icon(if (buffer == n) Icons.Filled.RadioButtonChecked else Icons.Filled.RadioButtonUnchecked, null, tint = if (buffer == n) HajinColors.text else Ink.muted) },
                            onClick = { buffer = n; options = false; Hajin.store.onChange() },
                        )
                    }
                }
            }
        }
        val detail = if (store.stash.isEmpty()) L("mw4.ui.keep.spare_empty") else buildString {
            append(L("mw4.ui.keep.spare_detail"))
            if (keepTracked) append(" " + L("mw4.ui.keep.spare_detail_tracked"))
            if (keepOrders) append(" " + L("mw4.ui.keep.spare_detail_orders"))
            if (buffer > 0) append(" " + L("mw4.ui.keep.spare_detail_buffer", buffer))
        }
        Text(detail, style = sys(12f), color = Ink.muted)
        if (lines.isNotEmpty()) LinkChips(lines.take(8).map { it.item.id }, lines.associate { it.item.id to it.count })
    }
}

// MARK: - Shopping list

private const val SHOP_SCOPE_KEY = "mw4_hajin_shop_scope"
private fun shopScope(raw: String) = HajinStore.ShoppingScope.entries.firstOrNull { it.raw == raw } ?: HajinStore.ShoppingScope.UPGRADES

/** Everything the unfinished upgrades (or tracked items) still need, minus what's in the stash, with a stepper on each line. */
@Composable
fun ShoppingScreen() {
    val store = hajin()
    var query by rememberSaveable { mutableStateOf("") }
    var scopeRaw by Prefs.string(SHOP_SCOPE_KEY, HajinStore.ShoppingScope.UPGRADES.raw)
    val scope = shopScope(scopeRaw)
    val needle = query.lowercase()
    val all = store.shoppingList(scope).filter { needle.isEmpty() || it.item.name.resolved.lowercase().contains(needle) }
    val short = all.filter { it.missing > 0 }
    val covered = all.filter { it.missing == 0 }
    Column(Modifier.fillMaxSize().appBackground(HajinColors.accent)) {
        TopBar(L("mw4.ui.hajin.shop"))
        LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(bottom = 24.dp)) {
            item(key = "search") { HajinSearchField(query, L("mw4.ui.hajin.search_section")) { query = it } }
            item(key = "header") { ShoppingHeader(scope, short, query.isEmpty()) { scopeRaw = it.raw } }
            if (short.isNotEmpty()) {
                item(key = "h-short") { HajinHeading(L("mw4.ui.hajin.shop_still_need")) }
                for (line in short) item(key = "s-${line.item.id}") { Box(Modifier.hajinCard()) { ShoppingRow(line) } }
            }
            if (covered.isNotEmpty()) {
                item(key = "h-covered") { HajinHeading(L("mw4.ui.hajin.shop_got_enough")) }
                for (line in covered) item(key = "c-${line.item.id}") { Box(Modifier.hajinCard()) { ShoppingRow(line) } }
            }
        }
    }
}

/** Scope picker, a line on what's counted, and the totals. */
@Composable
private fun ShoppingHeader(scope: HajinStore.ShoppingScope, short: List<HajinStore.ShoppingLine>, unfiltered: Boolean, pick: (HajinStore.ShoppingScope) -> Unit) {
    val store = hajin()
    val targets = store.shoppingTargets(scope)
    val cash = targets.sumOf { it.cash ?: 0 }
    Column(Modifier.padding(horizontal = 16.dp, vertical = 4.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        SegmentTabs(scope, listOf(HajinStore.ShoppingScope.UPGRADES to L("mw4.ui.hajin.shop_all"), HajinStore.ShoppingScope.TRACKED to L("mw4.ui.hajin.shop_tracked")),
            HajinColors.accent, pick)
        Text(L(if (scope == HajinStore.ShoppingScope.UPGRADES) "mw4.ui.hajin.shop_intro" else "mw4.ui.hajin.shop_intro_tracked"), style = sys(15f), color = Ink.muted)
        if (targets.isEmpty()) {
            Text(L(if (scope == HajinStore.ShoppingScope.TRACKED) "mw4.ui.hajin.shop_empty_tracked" else "mw4.ui.hajin.build_next_done"), style = sys(15f, FontWeight.SemiBold), color = Ink.text)
        } else {
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                ShopStat(L("mw4.ui.hajin.shop_to_find"), "${short.sumOf { it.missing }}")
                ShopStat(L("mw4.ui.hajin.shop_for"), "${targets.size}")
                ShopStat(L("mw4.ui.hajin.shop_cash"), money(cash))
            }
            // Cash against the balance the player entered
            if (store.cash > 0 && cash > 0) {
                val gap = cash - store.cash
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                    Icon(if (gap > 0) Icons.Filled.Payments else Icons.Filled.CheckCircle, null, tint = if (gap > 0) Ink.muted else HajinColors.printable, modifier = Modifier.size(14.dp))
                    Text(if (gap > 0) L("mw4.ui.hajin.cash_short", money(store.cash), money(gap)) else L("mw4.ui.hajin.cash_covered", money(store.cash)),
                        style = sys(12f, FontWeight.SemiBold), color = if (gap > 0) Ink.muted else HajinColors.printable)
                }
            }
            if (short.isEmpty() && unfiltered) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                    Icon(Icons.Filled.CheckCircle, null, tint = HajinColors.printable, modifier = Modifier.size(14.dp))
                    Text(L("mw4.ui.hajin.shop_done"), style = sys(12f, FontWeight.SemiBold), color = HajinColors.printable)
                }
            }
        }
    }
}

@Composable
private fun RowScope.ShopStat(title: String, value: String) {
    Column(Modifier.weight(1f).clip(RoundedCornerShape(8.dp)).background(LocalPalette.current.surface).padding(10.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
        // Shrinks to fit, as iOS's minimumScaleFactor
        Text(value, style = sys(18f * minOf(1f, maxOf(0.6f, 8f / value.length)), FontWeight.Bold, mono = true), color = Ink.text, maxLines = 1)
        Text(title.uppercase(appLocale), style = sys(10f, FontWeight.Bold), color = Ink.muted, maxLines = 1)
    }
}

/** One shopping line: the ingredient (opens it), have/need with a bar, a stash stepper, and the upgrades that want it. */
@Composable
private fun ShoppingRow(line: HajinStore.ShoppingLine) {
    val done = line.missing == 0
    Column(Modifier.padding(vertical = 2.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Row(Modifier.weight(1f).clickable { openHajin(Route.HajinItem(line.item.id)) }, verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                ItemTile(line.item, 36.dp)
                Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
                    Text(line.item.name.resolved, style = displayStyle(15.sp), color = Ink.text)
                    Text(if (done) L("mw4.ui.hajin.shop_have", line.have, line.need) else L("mw4.ui.hajin.shop_missing", line.missing, line.need),
                        style = sys(12f, FontWeight.SemiBold), color = if (done) HajinColors.printable else HajinColors.text)
                }
            }
            StashStepper(line.item.id)
        }
        ProgressBar(if (line.need == 0) 1.0 else minOf(1.0, line.have.toDouble() / line.need), if (done) HajinColors.printable else HajinColors.accent,
            Modifier.padding(start = 48.dp))
        LinkChips(line.users.map { it.first.id }, line.users.groupBy { it.first.id }.mapValues { e -> e.value.sumOf { it.second } }, modifier = Modifier.padding(start = 48.dp))
    }
}

// MARK: - Recipes & Manuals

private const val HIDE_FOUND_KEY = "mw4_hajin_blueprints_hide_found"

/** "Still to find": every blueprint and Weapon Manual, to tick off as found; found ones drop to the bottom of their tab. */
@Composable
fun BlueprintsScreen() {
    val store = hajin()
    var query by rememberSaveable { mutableStateOf("") }
    var hideFound by Prefs.bool(HIDE_FOUND_KEY, false)
    val needle = query.lowercase()
    val (found, total) = store.findProgress
    val all = store.blueprints.filter { needle.isEmpty() || it.name.resolved.lowercase().contains(needle) }.filter { !hideFound || !store.hasBlueprint(it.id) }
    val kinds = all.map { it.kind }.distinct()
    val groups = kinds.map { kind ->
        kind to all.filter { it.kind == kind }.sortedWith(compareBy<HajinGuide.Item> { if (store.hasBlueprint(it.id)) 1 else 0 }.thenBy { it.name.resolved })
    }
    val manuals = store.manualRows.filter { needle.isEmpty() || it.title.resolved.lowercase().contains(needle) }
        .filter { !hideFound || !store.hasManual(it) }
        .sortedWith(compareBy<HajinGuide.Row> { if (store.hasManual(it)) 1 else 0 }.thenBy { it.title.resolved })
    Column(Modifier.fillMaxSize().appBackground(HajinColors.accent)) {
        TopBar(L("mw4.ui.hajin.blueprints"))
        LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(bottom = 24.dp)) {
            item(key = "search") { HajinSearchField(query, L("mw4.ui.hajin.search_section")) { query = it } }
            item(key = "head") {
                Column(Modifier.padding(horizontal = 16.dp, vertical = 6.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Text(L("mw4.ui.hajin.blueprints_intro"), style = sys(15f), color = Ink.muted)
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(L("mw4.ui.hajin.blueprints_progress", found, total), style = sys(15f, FontWeight.SemiBold), color = Ink.text, modifier = Modifier.weight(1f))
                        FilterChip(hideFound, { hideFound = !hideFound }, label = { Text(L("mw4.ui.hajin.blueprints_hide"), style = sys(12f, FontWeight.SemiBold)) },
                            colors = FilterChipDefaults.filterChipColors(selectedContainerColor = HajinColors.accent.copy(alpha = 0.3f), labelColor = HajinColors.text, selectedLabelColor = Ink.text))
                    }
                    ProgressBar(if (total == 0) 0.0 else found.toDouble() / total, HajinColors.accent)
                }
            }
            for ((kind, items) in groups) {
                // Out of the whole tab, not just the rows shown
                item(key = "h-$kind") {
                    val tab = Hajin.store.blueprints.filter { it.kind == kind }
                    HajinHeading("$kind  ${tab.count { Hajin.store.hasBlueprint(it.id) }}/${tab.size}")
                }
                for (item in items) item(key = "b-${item.id}") { Box(Modifier.hajinCard()) { BlueprintRow(item) } }
            }
            if (manuals.isNotEmpty()) {
                item(key = "h-manuals") {
                    val rows = Hajin.store.manualRows
                    HajinHeading("${L("mw4.ui.hajin.weapon_manuals")}  ${rows.count { Hajin.store.hasManual(it) }}/${rows.size}")
                }
                for (row in manuals) row.weapon?.let { weapon -> item(key = "w-$weapon") { Box(Modifier.hajinCard()) { WeaponRow(row, weapon) } } }
            }
            if (groups.isEmpty() && manuals.isEmpty() && hideFound && found == total && total > 0) {
                item(key = "all") {
                    Row(Modifier.padding(16.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        Icon(Icons.Filled.Verified, null, tint = HajinColors.printable, modifier = Modifier.size(18.dp))
                        Text(L("mw4.ui.hajin.blueprints_all"), style = sys(15f, FontWeight.SemiBold), color = HajinColors.printable)
                    }
                }
            }
        }
    }
}

/** One blueprint: a tick, its picture and name (opens it), and its rarity. */
@Composable
private fun BlueprintRow(item: HajinGuide.Item) {
    val store = hajin()
    val done = store.hasBlueprint(item.id)
    Row(Modifier.padding(vertical = 2.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        HajinTick(done, item.name.resolved) { store.toggle(HajinStore.blueprintKey(item.id)) }
        Row(Modifier.weight(1f).clickable { openHajin(Route.HajinItem(item.id)) }, verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Box(Modifier.alpha(if (done) 0.55f else 1f)) { ItemTile(item, 40.dp, blueprint = true) }
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                Text(item.name.resolved, style = displayStyle(15.sp).copy(textDecoration = if (done) TextDecoration.LineThrough else null),
                    color = if (done) Ink.muted else Ink.text)
                item.rarity?.let { Text(it, style = sys(12f), color = HajinColors.rarity(it)) }
            }
            Chevron(alpha = 0.6f)
        }
    }
}
