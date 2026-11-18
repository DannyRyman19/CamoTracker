package app.camotrack.android.ui.hajin.scan

import android.graphics.Bitmap
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.camotrack.android.core.hajin.HajinGuide
import app.camotrack.android.core.hajin.HajinStore
import app.camotrack.android.hajin.scan.PostMatchResult
import app.camotrack.android.hajin.scan.Pt
import app.camotrack.android.hajin.scan.toBitmap
import app.camotrack.android.i18n.L
import app.camotrack.android.ui.*
import app.camotrack.android.ui.hajin.*

private class PostRow(val item: HajinGuide.Item, val count: Int, /** the spare part (suggested Sell) rather than the needed part */ val spare: Boolean) {
    val key get() = item.id + if (spare) "#spare" else "#needed"
}

/**
 * After a match: what was brought out (iOS HajinPostMatchReview). Each item
 * splits into what's still needed (Keep) and the spare (Sell), by the same
 * rules as Spare to sell; the player can switch either. Update adds what's
 * kept, the resources and the blueprints ticked off, and pays what's sold
 * into DMZ Cash.
 */
@Composable
fun PostMatchReview(result: PostMatchResult, photo: Bitmap?, onBack: () -> Unit, onDone: () -> Unit) {
    val store = hajin()
    val palette = LocalPalette.current
    val haptics = LocalHapticFeedback.current
    // What was read, with the player's swaps applied
    var counts by remember { mutableStateOf(result.counts) }
    var unsure by remember { mutableStateOf(result.unsure) }
    var places by remember { mutableStateOf(result.places) }
    var order by remember { mutableStateOf(result.order) }
    var swapped by remember { mutableStateOf(setOf<String>()) }
    var swapping by remember { mutableStateOf<HajinGuide.Item?>(null) }
    /** The item (or "bp:" and a blueprint's index) lit on the photo */
    var highlighted by remember { mutableStateOf<String?>(null) }
    var opened by remember { mutableStateOf<String?>(null) }
    /** Rows the player has switched away from the suggestion */
    var flipped by remember { mutableStateOf(setOf<String>()) }
    /** Misreads the player has taken out */
    var removed by remember { mutableStateOf(setOf<String>()) }
    var edited by remember { mutableStateOf(mapOf<String, Int>()) }
    var editing by remember { mutableStateOf<HajinGuide.Item?>(null) }
    /** Which blueprint each blueprint tile is, as picked (none: not ticked); sure guesses start ticked */
    var picked by remember {
        mutableStateOf(result.blueprints.withIndex().filter { it.value.sure && it.value.guess != null }.associate { it.index to it.value.guess!! })
    }
    val guide = store.guide

    // Stash items, split into what's still needed and the spare, in the backpack's order
    val rows = run {
        if (guide == null) return@run emptyList()
        val need = store.keepNeeds()
        val out = mutableListOf<PostRow>()
        for ((id, read) in counts) {
            if (id in removed) continue
            val item = guide.item(id)?.takeIf { HajinStore.inStash(it) && it.kind != "Resource" } ?: continue
            val count = edited[id] ?: read
            val short = maxOf(0, (need[id] ?: 0) - store.count(id))
            val keep = if ((item.value ?: 0) > 0) minOf(count, short) else count
            if (count - keep > 0) out += PostRow(item, count - keep, true)
            if (keep > 0) out += PostRow(item, keep, false)
        }
        out.sortedWith(compareBy<PostRow>({ order[it.item.id] ?: Int.MAX_VALUE }, { it.item.name.resolved }, { if (it.spare) 0 else 1 }))
    }
    // Everything else read: gear and the like. Keys are apart: which key it is can't be told.
    val gear = if (guide == null) emptyList() else counts.mapNotNull { (id, n) ->
        val item = guide.item(id)
        if (id in removed || item == null || HajinStore.inStash(item) || item.kind == "Key") null else item to (edited[id] ?: n)
    }.sortedWith(compareBy({ order[it.first.id] ?: Int.MAX_VALUE }, { it.first.name.resolved }))
    var keyCount = 0
    val keyPlaces = mutableListOf<List<Pt>>()
    for ((id, n) in counts) if (id !in removed && guide?.item(id)?.kind == "Key") { keyCount += edited[id] ?: n; keyPlaces += places[id] ?: emptyList() }

    fun sells(row: PostRow) = row.spare != (row.key in flipped)
    val sold = rows.filter(::sells)
    val total = sold.sumOf { (it.item.value ?: 0) * it.count }
    val kept = rows.filter { !sells(it) }
    val ticked = picked.values.filter { !store.hasBlueprint(it) }

    fun marks(key: String): List<List<Pt>> {
        if (photo == null) return emptyList()
        if (key == "keys") return keyPlaces
        if (key.startsWith("bp:")) return key.removePrefix("bp:").toIntOrNull()?.let { result.blueprints.getOrNull(it)?.place }?.let { listOf(it) } ?: emptyList()
        return places[key] ?: emptyList()
    }
    /** Lights a row's tiles on the photo, or puts them out. */
    fun light(key: String) {
        if (marks(key).isEmpty()) return
        haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove)
        highlighted = if (highlighted == key) null else key
        opened = null
    }
    /** Selected: its tiles lit and its fixes open in one go (tap again to let go of it). */
    fun select(key: String) {
        haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove)
        if (opened == key) { opened = null; highlighted = null } else { opened = key; highlighted = key }
    }
    /** Everything read as `id` is really `to`: its count, tiles and any edit move over. */
    fun swap(id: String, to: String) {
        haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove)
        counts = (counts - id) + (to to ((counts[to] ?: 0) + (counts[id] ?: 0)))
        places = (places - id) + (to to ((places[to] ?: emptyList()) + (places[id] ?: emptyList())))
        order[id]?.let { at -> order = (order - id) + (to to minOf(order[to] ?: Int.MAX_VALUE, at)) }
        edited[id]?.let { n -> edited = (edited - id) + (to to ((edited[to] ?: 0) + n)) }
        unsure = unsure - id
        removed = removed - to
        flipped = flipped.filter { !it.startsWith("$id#") }.toSet()
        swapped = swapped - id + to
        if (highlighted == id) highlighted = to
        if (opened == id) opened = to
    }
    fun apply() {
        haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove)
        // What's sold is paid into DMZ Cash
        if (total > 0) store.setCash(store.cash + total)
        val next = mutableMapOf<String, Int>()
        for (row in kept) next[row.item.id] = (next[row.item.id] ?: store.count(row.item.id)) + row.count
        for ((id, n) in result.resources) next[id] = store.count(id) + n
        store.applyScannedCounts(next)
        for (id in ticked.toSet()) if (!store.hasBlueprint(id)) store.toggle(HajinStore.blueprintKey(id))
        onDone()
    }

    LaunchedEffect(Unit) {
        // Start with the first item that can be found on the photo selected: lit, its fixes open
        if (photo != null) { highlighted = rows.firstOrNull { places[it.item.id] != null }?.item?.id; opened = highlighted }
    }

    Column(Modifier.fillMaxSize().background(palette.background).systemBarsPadding()) {
        Row(Modifier.fillMaxWidth().height(52.dp).padding(horizontal = 4.dp), verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.width(96.dp)) {
                TextButton(onClick = onBack) {
                    Icon(Icons.AutoMirrored.Filled.ArrowBack, null, tint = HajinColors.text, modifier = Modifier.size(18.dp))
                    Spacer(Modifier.width(4.dp))
                    Text(L("mw4.ui.hajin.back"), color = HajinColors.text, style = sys(16f))
                }
            }
            Text(L("mw4.ui.postmatch.title"), style = displayStyle(17.sp), color = Ink.text, maxLines = 1, textAlign = TextAlign.Center, modifier = Modifier.weight(1f))
            Box(Modifier.width(96.dp), contentAlignment = Alignment.CenterEnd) {
                val enabled = kept.isNotEmpty() || result.resources.isNotEmpty() || ticked.isNotEmpty() || total > 0
                TextButton(onClick = ::apply, enabled = enabled) {
                    Text(L("mw4.ui.hajin.scan_apply"), style = sys(16f, FontWeight.Bold), color = if (enabled) HajinColors.text else Ink.muted)
                }
            }
        }
        PhotoBeside(photo?.let { p -> { ZoomPhoto(p, highlighted?.let { marks(it) } ?: emptyList()) } }) {
            LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(start = readableInset(), end = readableInset(), bottom = 32.dp)) {
                item(key = "summary") { Summary(sold.sumOf { it.count }, total) }
                if (result.resources.isNotEmpty()) {
                    sectionHeader("res", L("mw4.ui.hajin.resources"))
                    item(key = "resources") {
                        Row(Modifier.reviewRow().padding(12.dp), horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                            for (id in listOf("synthetics", "electronics", "chemicals", "metals")) {
                                val n = result.resources[id] ?: continue
                                val item = guide?.item(id) ?: continue
                                Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                                    ItemTile(item, 26.dp)
                                    Text("+$n", style = sys(13f, FontWeight.SemiBold, mono = true), color = Ink.text)
                                }
                            }
                        }
                    }
                    footer("res", L("mw4.ui.postmatch.resources_footer"))
                }
                if (rows.isNotEmpty()) {
                    sectionHeader("items", L("mw4.ui.postmatch.items"))
                    for (row in rows) item(key = row.key) {
                        val id = row.item.id
                        Column(Modifier.reviewRow(highlighted == id).padding(horizontal = 12.dp, vertical = 10.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                                Row(Modifier.weight(1f).clickable { select(id) }, verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                                    FindableTile(row.item, 40.dp, marks(id).isNotEmpty(), highlighted == id)
                                    Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
                                        Text(row.item.name.resolved, style = sys(15f, FontWeight.SemiBold), color = Ink.text, maxLines = 2, overflow = TextOverflow.Ellipsis)
                                        Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                                            Text("×${row.count}", style = sys(12f, FontWeight.SemiBold, mono = true), color = Ink.muted)
                                            row.item.value?.takeIf { it > 0 }?.let { Text(money(it * row.count), style = sys(12f), color = Ink.muted) }
                                            if (id in swapped) Icon(Icons.Filled.SwapHoriz, L("mw4.ui.hajin.scan_swapped"), tint = HajinColors.text, modifier = Modifier.size(14.dp))
                                            else if (id in unsure && edited[id] == null) CheckTag()
                                        }
                                    }
                                }
                                SoldKeep(sells(row)) { flipped = if (row.key in flipped) flipped - row.key else flipped + row.key }
                            }
                            AnimatedVisibility(opened == id) {
                                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                    if (photo != null) FixButton(L("mw4.ui.hajin.scan_change"), Icons.Filled.SwapHoriz) { swapping = row.item }
                                    FixButton(L("mw4.ui.hajin.scan_edit"), Icons.Filled.Edit) { editing = row.item }
                                    FixButton(L("mw4.ui.postmatch.remove"), Icons.Filled.Delete) { removed = removed + id }
                                }
                            }
                        }
                    }
                    footer("items", L("mw4.ui.postmatch.items_footer"))
                }
                if (result.blueprints.isNotEmpty()) {
                    sectionHeader("bp", L("mw4.ui.postmatch.blueprints", result.blueprints.size))
                    result.blueprints.forEachIndexed { i, blueprint ->
                        item(key = "bp-$i") {
                            BlueprintRow(blueprint, picked[i], highlighted == "bp:$i", onLight = { light("bp:$i") }) { choice ->
                                picked = if (choice == null) picked - i else picked + (i to choice)
                            }
                        }
                    }
                    footer("bp", L("mw4.ui.postmatch.blueprints_footer"))
                }
                if (result.manuals > 0) {
                    item(key = "manuals") {
                        // Weapon manuals picked up: tick each gun in Gunsmith prices (a note here: the
                        // review is over the tabs, so it doesn't open Gunsmith as iOS's sheet does)
                        Row(
                            Modifier.padding(top = 12.dp).padding(horizontal = 12.dp).fillMaxWidth().clip(RoundedCornerShape(10.dp))
                                .background(HajinColors.accent.copy(alpha = 0.15f)).padding(12.dp),
                            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp),
                        ) {
                            CardSymbol(Icons.Filled.MenuBook)
                            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                                    Text(L("mw4.ui.postmatch.manual_found"), style = sys(15f, FontWeight.SemiBold), color = Ink.text)
                                    if (result.manuals > 1) Text("×${result.manuals}", style = sys(12f, FontWeight.SemiBold, mono = true), color = Ink.muted)
                                }
                                Text(L("mw4.ui.postmatch.manual_hint"), style = sys(12f), color = Ink.muted)
                            }
                        }
                    }
                }
                if (gear.isNotEmpty() || keyCount > 0) {
                    sectionHeader("gear", L("mw4.ui.postmatch.gear"))
                    for ((item, n) in gear) item(key = "g-${item.id}") {
                        GearRow(highlighted == item.id, { light(item.id) }, { removed = removed + item.id }) {
                            FindableTile(item, 32.dp, marks(item.id).isNotEmpty(), highlighted == item.id)
                            Text(item.name.resolved, style = sys(15f), color = Ink.text, modifier = Modifier.weight(1f))
                            Text("×$n", style = sys(12f, FontWeight.SemiBold, mono = true), color = Ink.muted)
                        }
                    }
                    if (keyCount > 0) item(key = "keys") {
                        // Every key, unnamed: a key's picture doesn't say which it is
                        GearRow(highlighted == "keys", { light("keys") }, {
                            removed = removed + counts.keys.filter { guide?.item(it)?.kind == "Key" }
                        }) {
                            CardSymbol(Icons.Filled.Key)
                            Text(L("mw4.ui.postmatch.keys"), style = sys(15f), color = Ink.text, modifier = Modifier.weight(1f))
                            Text("×$keyCount", style = sys(12f, FontWeight.SemiBold, mono = true), color = Ink.muted)
                        }
                    }
                }
                if (result.unread > 0) item(key = "unread") {
                    Row(Modifier.padding(16.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Icon(Icons.Filled.HelpCenter, null, tint = Ink.muted, modifier = Modifier.size(16.dp))
                        Text(L("mw4.ui.postmatch.unread", result.unread), style = sys(13f), color = Ink.muted)
                    }
                }
            }
        }
    }

    editing?.let { item ->
        HajinNumberDialog(item.name.resolved, "0", "${edited[item.id] ?: counts[item.id] ?: 0}", { editing = null }) { n ->
            if (n != null) edited = edited + (item.id to n)
        }
    }
    swapping?.let { item ->
        ItemPicker(item, onCancel = { swapping = null }) { to -> swap(item.id, to); swapping = null }
    }
}

private fun LazyListScope.footer(key: String, text: String) {
    item(key = "f-$key") { Text(text, style = sys(12f), color = Ink.muted, modifier = Modifier.padding(horizontal = 16.dp, vertical = 6.dp)) }
}

/** "Sell 6 · $41,200": the sell pile at a glance. */
@Composable
private fun Summary(sold: Int, total: Int) {
    val sell = HajinColors.printable
    Row(
        Modifier.padding(horizontal = 12.dp, vertical = 8.dp).fillMaxWidth().borderedCard(accent = if (total > 0) sell else null).padding(14.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Icon(Icons.Filled.MonetizationOn, null, tint = if (sold > 0) sell else Ink.muted, modifier = Modifier.size(30.dp))
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(if (sold > 0) L("mw4.ui.postmatch.sell_total", sold) else L("mw4.ui.postmatch.sell_none"), style = sys(17f, FontWeight.SemiBold), color = Ink.text)
            if (total > 0) Text(L("mw4.ui.postmatch.sell_cash"), style = sys(12f), color = Ink.muted)
        }
        if (total > 0) Text(money(total), style = sys(18f, FontWeight.Bold, mono = true), color = sell)
    }
}

/** Sell | Keep, the chosen one filled. */
@Composable
private fun SoldKeep(sell: Boolean, flip: () -> Unit) {
    Row(Modifier.clip(CircleShape).background(LocalPalette.current.surface2).padding(2.dp)) {
        for (option in listOf(true, false)) {
            val on = option == sell
            Text(
                L(if (option) "mw4.ui.postmatch.sold" else "mw4.ui.postmatch.keep"), style = sys(12f, FontWeight.Bold),
                color = if (on) Color.Black.copy(alpha = 0.85f) else Ink.muted, textAlign = TextAlign.Center,
                modifier = Modifier.clip(CircleShape)
                    .background(if (on) (if (option) HajinColors.printable else HajinColors.accent) else Color.Transparent)
                    .clickable(enabled = !on, onClick = flip).widthIn(min = 48.dp).padding(horizontal = 8.dp, vertical = 8.dp),
            )
        }
    }
}

@Composable
private fun GearRow(lit: Boolean, onTap: () -> Unit, onRemove: () -> Unit, content: @Composable RowScope.() -> Unit) {
    var menu by remember { mutableStateOf(false) }
    Box {
        Row(
            Modifier.reviewRow(lit).clickable(onClick = onTap).padding(horizontal = 12.dp, vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            content()
            // iOS swipes to remove: a menu here
            Icon(Icons.Filled.MoreVert, null, tint = Ink.muted, modifier = Modifier.size(22.dp).clip(CircleShape).clickable { menu = true })
        }
        DropdownMenu(menu, onDismissRequest = { menu = false }, containerColor = LocalPalette.current.surface2) {
            DropdownMenuItem(text = { Text(L("mw4.ui.postmatch.remove"), color = HajinColors.short) },
                leadingIcon = { Icon(Icons.Filled.Delete, null, tint = HajinColors.short) }, onClick = { menu = false; onRemove() })
        }
    }
}

/**
 * A blueprint tile as it was in the photo, and which blueprint it is: the
 * guess, or one picked from those still to find. Picked = ticked off.
 */
@Composable
private fun BlueprintRow(blueprint: PostMatchResult.Blueprint, choice: String?, lit: Boolean, onLight: () -> Unit, onPick: (String?) -> Unit) {
    val store = hajin()
    val tile = remember(blueprint) { blueprint.image.toBitmap().asImageBitmap() }
    val item = choice?.let { store.guide?.item(it) }
    val guessed = blueprint.guess?.let { store.guide?.item(it) }
    var menu by remember { mutableStateOf(false) }
    val candidates = store.blueprints.filter { !store.hasBlueprint(it.id) }.sortedBy { it.name.resolved }
    Row(
        Modifier.reviewRow().padding(horizontal = 12.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        val shape = RoundedCornerShape(6.dp)
        Image(tile, null, contentScale = ContentScale.FillBounds,
            modifier = Modifier.size(44.dp).clip(shape).then(if (lit) Modifier.border(2.dp, HajinColors.accent, shape) else Modifier).clickable(onClick = onLight))
        Box(Modifier.weight(1f)) {
            Row(Modifier.clickable { menu = true }, verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text(item?.name?.resolved ?: L("mw4.ui.postmatch.blueprint_pick"), style = sys(15f, FontWeight.SemiBold),
                        color = if (item == null) HajinColors.text else Ink.text)
                    if (choice != null && store.hasBlueprint(choice)) Text(L("mw4.ui.postmatch.blueprint_had"), style = sys(11f), color = Ink.muted)
                    else if (choice == null && guessed != null) Text(L("mw4.ui.postmatch.blueprint_guess", guessed.name.resolved), style = sys(11f), color = Ink.muted)
                }
                Icon(Icons.Filled.UnfoldMore, null, tint = Ink.muted, modifier = Modifier.size(14.dp))
            }
            DropdownMenu(menu, onDismissRequest = { menu = false }, containerColor = LocalPalette.current.surface2, modifier = Modifier.heightIn(max = 420.dp)) {
                if (guessed != null) {
                    DropdownMenuItem(text = { Text(guessed.name.resolved) }, leadingIcon = { Icon(Icons.Filled.AutoAwesome, null) },
                        onClick = { menu = false; onPick(guessed.id) })
                    HorizontalDivider()
                }
                for (candidate in candidates) DropdownMenuItem(text = { Text(candidate.name.resolved) }, onClick = { menu = false; onPick(candidate.id) })
                if (choice != null) {
                    HorizontalDivider()
                    DropdownMenuItem(text = { Text(L("mw4.ui.postmatch.blueprint_clear"), color = HajinColors.short) }, onClick = { menu = false; onPick(null) })
                }
            }
        }
        Icon(if (item == null) Icons.Outlined.Circle else Icons.Filled.CheckCircle, null, tint = if (item == null) Ink.muted else HajinColors.text, modifier = Modifier.size(24.dp))
    }
}
