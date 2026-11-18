package app.camotrack.android.ui.hajin

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material.icons.outlined.AddCircleOutline
import androidx.compose.material.icons.outlined.Circle
import androidx.compose.material.icons.outlined.RemoveCircleOutline
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.camotrack.android.Route
import app.camotrack.android.core.hajin.HajinGuide
import app.camotrack.android.core.hajin.HajinStore
import app.camotrack.android.core.hajin.hajinCollapseTiers
import app.camotrack.android.core.hajin.hajinGroups
import app.camotrack.android.i18n.L
import app.camotrack.android.ui.*
import coil.compose.AsyncImage

/** One table in the guide, with its own search (iOS GuideSectionView, phone layout). */
@Composable
fun GuideSectionScreen(section: HajinGuide.Section) {
    val store = hajin()
    var query by rememberSaveable(section.id) { mutableStateOf("") }
    val needle = query.lowercase()
    val rows = if (needle.isEmpty()) section.rows else section.rows.filter { it.matches(needle) }
    Column(Modifier.fillMaxSize().appBackground(HajinColors.accent)) {
        TopBar(section.title.resolved) {
            HajinReportMenu(listOf("Section: ${section.title.en ?: section.title.resolved}", "Section ID: ${section.id}"))
        }
        LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(start = readableInset(), end = readableInset(), bottom = 24.dp)) {
            item(key = "search") { HajinSearchField(query, L("mw4.ui.hajin.search_section")) { query = it } }
            when (section.id) {
                "prestige" -> {
                    prestigeTracker()
                    groupedRows(rows)
                }
                "ops" -> {
                    section.intro?.takeIf { needle.isEmpty() }?.let { intro -> item(key = "intro") { HajinIntro(intro.resolved) } }
                    ordersList(rows)
                }
                else -> {
                    section.intro?.takeIf { needle.isEmpty() }?.let { intro -> item(key = "intro") { HajinIntro(intro.resolved) } }
                    groupedRows(hajinCollapseTiers(rows, store.guide))
                    if (rows.isEmpty()) item(key = "none") { FilterEmptyRow(L("mw4.ui.hajin.no_results")) }
                }
            }
        }
    }
}

/** A section's rows, under headings when they carry a `group`. */
fun LazyListScope.groupedRows(rows: List<HajinGuide.Row>) {
    hajinGroups(rows).forEachIndexed { g, (title, group) ->
        if (title != null) item(key = "g-$g") { HajinHeading(title) }
        group.forEachIndexed { i, row -> item(key = "r-$g-$i") { GuideRowCard(row) } }
    }
}

/** A row in its card, outlined green when its item can be printed. */
@Composable
fun GuideRowCard(row: HajinGuide.Row) {
    val store = hajin()
    Box(Modifier.hajinCard(if (store.printable(row)) HajinColors.printable else null)) { GuideRowView(row) }
}

/** A guide row, drawn for what it is: an upgrade family, an item, a mission, a weapon or a plain line. */
@Composable
fun GuideRowView(row: HajinGuide.Row) {
    val store = hajin()
    val guide = store.guide
    val item = row.item?.let { guide?.item(it) }
    val tiers = item?.let { guide?.tiers(it) } ?: emptyList()
    when {
        item != null && tiers.size > 1 -> UpgradeFamilyCard(tiers)
        item != null -> ItemRow(item, row)
        row.objectives != null || row.cash != null || row.rewards != null || row.place != null -> MissionRow(row)
        row.weapon != null -> WeaponRow(row, row.weapon)
        else -> Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            PlainRow(row)
            row.links?.takeIf { it.isNotEmpty() }?.let { LinkChips(it) }
        }
    }
}

@Composable
private fun PlainRow(row: HajinGuide.Row) {
    val store = hajin()
    val unconfirmed = row.subtitle?.en?.contains("not confirmed") == true
    Row(Modifier.padding(vertical = 3.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        val key = row.check
        val level = row.level
        if (key != null) {
            HajinTick(key in store.checked, row.title.resolved) { store.toggle(key) }
        } else if (level != null && store.dmzLevel > 0) {
            // Level unlocks tick themselves up to the player's level
            val open = level <= store.dmzLevel
            Box(Modifier.size(24.dp), contentAlignment = Alignment.Center) {
                Icon(if (open) Icons.Filled.CheckCircle else Icons.Filled.Lock, null,
                    tint = if (open) HajinColors.text else Ink.muted.copy(alpha = 0.6f), modifier = Modifier.size(if (open) 22.dp else 16.dp))
            }
        }
        row.image?.let { image ->
            AsyncImage(image, null, contentScale = ContentScale.Fit,
                modifier = Modifier.size(44.dp).clip(RoundedCornerShape(8.dp)).background(LocalPalette.current.surface2))
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Row(verticalAlignment = Alignment.Top) {
                Text(row.title.resolved, style = displayStyle(15.sp), color = Ink.text, modifier = Modifier.weight(1f))
                row.value?.let { Spacer(Modifier.width(8.dp)); ValueBadge(it.resolved, store.isLocked(row.requiredLevel)) }
            }
            row.subtitle?.let {
                Text(it.resolved, style = sys(15f).copy(fontStyle = if (unconfirmed) FontStyle.Italic else FontStyle.Normal),
                    color = if (unconfirmed) Ink.muted.copy(alpha = 0.7f) else Ink.muted)
            }
        }
    }
}

/** A guide row that is an item: rarity tile, name, badge and its ingredients as chips. Taps through to the item. */
@Composable
fun ItemRow(item: HajinGuide.Item, row: HajinGuide.Row) {
    val store = hajin()
    val locked = store.isLocked(item.requiredLevel ?: row.requiredLevel)
    val printable = store.canPrint(item)
    Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        row.check?.let { key ->
            Box(Modifier.padding(top = 8.dp)) { HajinTick(key in store.checked, item.name.resolved) { store.toggle(key) } }
        }
        Row(
            Modifier.weight(1f).clickable { openHajin(Route.HajinItem(item.id)) }.alpha(if (locked) 0.55f else 1f).padding(vertical = 3.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            ItemTile(item, 48.dp)
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(5.dp)) {
                Row(verticalAlignment = Alignment.Top) {
                    Text(item.name.resolved, style = displayStyle(15.sp), color = Ink.text, modifier = Modifier.weight(1f))
                    val value = row.value?.resolved
                    if (value != null && value != item.rarity && value != "Resource") {
                        Spacer(Modifier.width(6.dp)); ValueBadge(value, locked)
                    }
                }
                if (item.rarity != null || printable) {
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                        // The tag replaces the kind, which the heading already gives
                        if (item.rarity != null) RarityLine(item, 10f, showsKind = !printable)
                        if (printable) CanPrintTag()
                    }
                }
                val cost = item.cost
                when {
                    !cost.isNullOrEmpty() -> CostChips(cost, if (row.value == null) item.cash else null)
                    (item.effect ?: item.note) != null -> Text((item.effect ?: item.note)!!.resolved, style = sys(15f), color = Ink.muted, maxLines = 2, overflow = TextOverflow.Ellipsis)
                    row.subtitle?.en?.contains("not confirmed") == true ->
                        Text(row.subtitle.resolved, style = sys(15f).copy(fontStyle = FontStyle.Italic), color = Ink.muted.copy(alpha = 0.7f))
                }
            }
            Chevron(Modifier.padding(top = 2.dp), alpha = 0.6f)
        }
    }
}

/** Ingredient icons with their amounts, in one row. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun CostChips(cost: List<HajinGuide.Item.Cost>, cash: Int?) {
    val store = hajin()
    FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
        if (cash != null) {
            Text(money(cash), style = sys(12f, FontWeight.SemiBold, mono = true), color = Ink.text, modifier = Modifier.align(Alignment.CenterVertically))
            Box(Modifier.align(Alignment.CenterVertically)) { CashShort(cash) }
        }
        for (part in cost) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(3.dp)) {
                ItemTile(store.guide?.item(part.item), 22.dp)
                CostAmount(part)
            }
        }
    }
}

/**
 * One FOB upgrade family as a single card: I / II / III tabs, the picked
 * tier's cost, and its tick. Opens on the first tier not yet ticked.
 */
@Composable
fun UpgradeFamilyCard(tiers: List<HajinGuide.Item>) {
    val store = hajin()
    var picked by remember(tiers.first().id) { mutableStateOf<String?>(null) }
    val item = tiers.firstOrNull { it.id == picked } ?: tiers.firstOrNull { "upgrade-${it.id}" !in store.checked } ?: tiers.last()
    val key = "upgrade-${item.id}"
    val haptics = LocalHapticFeedback.current
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            ItemTile(item, 40.dp)
            Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(item.family ?: item.name.resolved, style = displayStyle(15.sp), color = Ink.text)
                Text("${tiers.count { "upgrade-${it.id}" in store.checked }}/${tiers.size} " + L("mw4.ui.hajin.tiers").uppercase(appLocale),
                    style = sys(11f, FontWeight.Bold), color = Ink.muted)
            }
        }
        val label = { tier: HajinGuide.Item -> (if ("upgrade-${tier.id}" in store.checked) "✓ " else "") + roman(tier.tier ?: 1) }
        if (tiers.size > 5) {
            // Too many for the tabs (the Bank's nine): chips that scroll
            Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                for (tier in tiers) {
                    val on = tier.id == item.id
                    Text(label(tier), style = sys(15f, FontWeight.SemiBold), textAlign = androidx.compose.ui.text.style.TextAlign.Center, color = if (on) Color.Black.copy(alpha = 0.85f) else Ink.text,
                        modifier = Modifier.clip(CircleShape).background(if (on) HajinColors.accent else LocalPalette.current.surface2)
                            .clickable { haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove); picked = tier.id }
                            .widthIn(min = 54.dp).padding(horizontal = 10.dp, vertical = 6.dp))
                }
            }
        } else {
            SegmentTabs(item.id, tiers.map { it.id to label(it) }, HajinColors.accent, { picked = it })
        }
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            HajinTick(key in store.checked, item.name.resolved) {
                store.toggle(key)
                // Ticked: move on to the next tier still to print
                if (key in Hajin.store.checked) picked = null
            }
            Column(Modifier.weight(1f).clickable { openHajin(Route.HajinItem(item.id)) }, verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text(item.name.resolved, style = sys(15f, FontWeight.SemiBold), color = Ink.text, modifier = Modifier.weight(1f))
                    item.cash?.let { CashShort(it); ValueBadge(money(it)) }
                    Chevron(alpha = 0.6f)
                }
                if (store.canPrint(item) && key !in store.checked) CanPrintTag()
                val cost = item.cost
                if (!cost.isNullOrEmpty()) CostChips(cost, null)
                else item.note?.let { Text(it.resolved, style = sys(12f), color = Ink.muted) }
                item.effect?.let { Text(it.resolved, style = sys(12f).copy(fontStyle = FontStyle.Italic), color = Ink.muted) }
            }
        }
    }
}

/** A mission, order or op: tick, where it is, its steps (each tickable), what it needs and what it pays. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun MissionRow(row: HajinGuide.Row) {
    val store = hajin()
    val key = row.check ?: "op-${row.title.resolved}"
    val done = key in store.checked
    val objectives = row.objectives ?: emptyList()
    val haptics = LocalHapticFeedback.current
    Column(Modifier.alpha(if (done) 0.75f else 1f), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            if (row.check != null) HajinTick(done, row.title.resolved) { store.toggle(key) }
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                Text(row.title.resolved, style = displayStyle(15.sp), color = Ink.text)
                if (row.place != null) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                        Icon(Icons.Filled.Place, null, tint = Ink.muted, modifier = Modifier.size(12.dp))
                        Text(row.place.resolved, style = sys(12f), color = Ink.muted)
                    }
                } else row.subtitle?.let {
                    Text(it.resolved, style = sys(12f).copy(fontStyle = FontStyle.Italic), color = Ink.muted.copy(alpha = 0.8f))
                }
            }
            if (objectives.isNotEmpty()) {
                val stepsDone = objectives.indices.count { done || "$key#$it" in store.checked }
                Text("$stepsDone/${objectives.size}", style = sys(12f, FontWeight.SemiBold, mono = true),
                    color = if (stepsDone == objectives.size) HajinColors.text else Ink.muted)
            }
        }
        val indent = Modifier.padding(start = 44.dp)
        if (objectives.isNotEmpty()) {
            Column(indent, verticalArrangement = Arrangement.spacedBy(6.dp)) {
                objectives.forEachIndexed { index, objective ->
                    val stepKey = "$key#$index"
                    val stepDone = done || stepKey in store.checked
                    Row(
                        Modifier.fillMaxWidth().clickable(enabled = !done) { haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove); store.toggle(stepKey) },
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        Icon(if (stepDone) Icons.Filled.CheckCircle else Icons.Outlined.Circle, null,
                            tint = if (stepDone) HajinColors.text else Ink.muted, modifier = Modifier.padding(top = 2.dp).size(15.dp))
                        Text(objective.resolved, style = sys(15f).copy(textDecoration = if (stepDone) TextDecoration.LineThrough else null),
                            color = if (stepDone) Ink.muted else Ink.text)
                    }
                }
            }
        }
        // An order's prints and the ingredients it wants extracted
        val needs = (row.prints ?: emptyList()) + (row.extracts ?: emptyList())
        if (needs.isNotEmpty()) {
            Column(indent, verticalArrangement = Arrangement.spacedBy(6.dp)) {
                SmallCaps(L("mw4.ui.hajin.needs"))
                LinkChips(needs.map { it.item }, needs.groupBy { it.item }.mapValues { e -> e.value.sumOf { it.qty } })
            }
        }
        row.tips?.takeIf { it.isNotEmpty() }?.let { tips ->
            Column(indent, verticalArrangement = Arrangement.spacedBy(4.dp)) {
                for (tip in tips) Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    Icon(Icons.Filled.Lightbulb, null, tint = Ink.muted, modifier = Modifier.padding(top = 1.dp).size(13.dp))
                    Text(tip.resolved, style = sys(12f), color = Ink.muted)
                }
            }
        }
        val items = row.links ?: emptyList()
        val other = row.rewards ?: emptyList()
        if (row.cash != null || items.isNotEmpty() || other.isNotEmpty()) {
            Column(indent, verticalArrangement = Arrangement.spacedBy(6.dp)) {
                SmallCaps(L("mw4.ui.hajin.rewards"))
                FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    row.cash?.let { ValueBadge(money(it)) }
                    for (reward in other) ValueBadge(reward.resolved)
                }
                if (items.isNotEmpty()) LinkChips(items)
            }
        }
    }
}

/** A Gunsmith price with the weapon's picture, linking to its camos; a tick for its Manual. */
@Composable
fun WeaponRow(row: HajinGuide.Row, weaponId: Int) {
    val store = hajin()
    val t = tracker()
    val weapon = t.weapon(weaponId)
    // Starter weapons are on sale from the start; the rest need their Manual extracted once
    val needsManual = row.subtitle?.en?.startsWith("Starter") != true
    val manualKey = "manual-$weaponId"
    val manualDone = manualKey in store.checked
    Row(
        Modifier.fillMaxWidth().then(if (weapon != null) Modifier.clickable { openHajin(Route.HajinWeapon(weaponId)) } else Modifier).padding(vertical = 2.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        if (needsManual) HajinTick(manualDone, row.title.resolved) { store.toggle(manualKey) }
        Box(Modifier.size(96.dp, 54.dp).clip(RoundedCornerShape(6.dp)).background(LocalPalette.current.surface2), contentAlignment = Alignment.Center) {
            WeaponThumbnail(weapon?.imageURL, 54.dp, inset = 4.dp, category = t.category(weaponId))
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Text(row.title.resolved, style = displayStyle(15.sp), color = Ink.text)
            if (needsManual) {
                Text(L(if (manualDone) "mw4.ui.hajin.manual_done" else "mw4.ui.hajin.manual_needed").uppercase(appLocale),
                    style = sys(11f, FontWeight.Bold), color = if (manualDone) HajinColors.text else Ink.muted)
            } else row.subtitle?.let {
                Text(it.resolved.uppercase(appLocale), style = sys(11f, FontWeight.Bold), color = Ink.muted)
            }
        }
        row.value?.let { ValueBadge(it.resolved) }
    }
}

// MARK: - Missions & Orders

private const val HIDE_DONE_KEY = "mw4_hajin_orders_hide_done"

/**
 * Missions & Orders: Story Missions, then each DMZ Orders page in the game's
 * order. A page folds away once it's all ticked, shows its progress and its
 * reward, and the first unfinished one is marked Up next.
 */
fun LazyListScope.ordersList(rows: List<HajinGuide.Row>) {
    val pages = mutableListOf<Pair<String, MutableList<HajinGuide.Row>>>()
    for (row in rows) {
        val title = row.group?.resolved ?: ""
        val last = pages.lastOrNull()
        if (last != null && last.first == title) last.second.add(row) else pages.add(title to mutableListOf(row))
    }
    item(key = "hide-done") { HideDoneToggle() }
    item(key = "pages") { OrderPages(pages) }
}

@Composable
private fun HideDoneToggle() {
    var hideDone by Prefs.bool(HIDE_DONE_KEY, false)
    Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(L("mw4.ui.hajin.hide_done"), style = sys(15f, FontWeight.SemiBold), color = Ink.text, modifier = Modifier.weight(1f))
        Switch(hideDone, { hideDone = it }, colors = SwitchDefaults.colors(checkedTrackColor = HajinColors.accent))
    }
}

@Composable
private fun OrderPages(pages: List<Pair<String, List<HajinGuide.Row>>>) {
    val store = hajin()
    val hideDone by Prefs.bool(HIDE_DONE_KEY, false)
    /** Pages opened or closed against their default (open until finished). */
    var flipped by rememberSaveable { mutableStateOf(setOf<String>()) }
    val haptics = LocalHapticFeedback.current
    fun isDone(row: HajinGuide.Row) = row.check?.let { it in store.checked } ?: false
    val upNext = pages.firstOrNull { it.first.startsWith("DMZ Orders") && !it.second.all(::isDone) }?.first
    Column {
        for ((title, rows) in pages) {
            val done = rows.count(::isDone)
            val finished = done == rows.size
            val open = if (finished) title in flipped else title !in flipped
            if (hideDone && finished) continue
            val reward = rows.firstNotNullOfOrNull { it.pageReward }?.resolved
            Column(
                Modifier.fillMaxWidth().clickable {
                    haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                    flipped = if (title in flipped) flipped - title else flipped + title
                }.padding(start = 16.dp, end = 16.dp, top = 14.dp, bottom = 4.dp),
                verticalArrangement = Arrangement.spacedBy(4.dp),
            ) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Icon(Icons.Filled.ChevronRight, null, tint = Ink.muted, modifier = Modifier.size(16.dp).rotate(if (open) 90f else 0f))
                    Text(title.removePrefix("DMZ Orders: "), style = sys(20f, FontWeight.Bold), color = Ink.text, modifier = Modifier.weight(1f, fill = false))
                    if (title == upNext) {
                        Text(L("mw4.ui.hajin.up_next").uppercase(appLocale), style = sys(10f, FontWeight.ExtraBold), color = Color.White,
                            modifier = Modifier.clip(CircleShape).background(HajinColors.accent).padding(horizontal = 6.dp, vertical = 2.dp))
                    }
                    Spacer(Modifier.weight(1f))
                    Text("$done/${rows.size}", style = sys(13f, FontWeight.SemiBold, mono = true), color = if (finished) HajinColors.text else Ink.muted)
                }
                reward?.let {
                    Row(Modifier.padding(start = 24.dp), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        Icon(Icons.Filled.CardGiftcard, null, tint = Ink.muted, modifier = Modifier.padding(top = 1.dp).size(13.dp))
                        Text(it, style = sys(12f), color = Ink.muted)
                    }
                }
            }
            if (open) for (row in rows) {
                if (hideDone && isDone(row)) continue
                Box(Modifier.hajinCard()) { GuideRowView(row) }
            }
        }
    }
}

// MARK: - Operator Prestige

/** The player's operators: each one's Prestige, what the next costs and the Prestige traits it holds. */
fun LazyListScope.prestigeTracker() {
    item(key = "ops-heading") { HajinHeading(L("mw4.ui.opprestige.operators")) }
    item(key = "operators") { Operators() }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun Operators() {
    val store = hajin()
    var newName by rememberSaveable { mutableStateOf("") }
    var removing by remember { mutableStateOf<String?>(null) }
    val haptics = LocalHapticFeedback.current
    fun add() {
        haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove)
        store.addOperator(newName)
        newName = ""
    }
    Column {
        for (op in store.operators) {
            Box(Modifier.padding(horizontal = 12.dp, vertical = 4.dp).fillMaxWidth().borderedCard()
                .combinedClickable(onClick = {}, onLongClick = { removing = op.name }).padding(12.dp)) {
                OperatorCard(op.name, op.level)
            }
        }
        Row(Modifier.hajinCard(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            OutlinedTextField(
                newName, { newName = it }, singleLine = true, modifier = Modifier.weight(1f),
                placeholder = { Text(L("mw4.ui.opprestige.name")) },
                keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Words, autoCorrectEnabled = false, imeAction = androidx.compose.ui.text.input.ImeAction.Done),
                keyboardActions = KeyboardActions(onDone = { add() }),
            )
            TextButton(onClick = ::add, enabled = newName.isNotBlank()) {
                Text(L("mw4.ui.opprestige.add"), style = sys(15f, FontWeight.SemiBold), color = if (newName.isNotBlank()) HajinColors.text else Ink.muted)
            }
        }
    }
    removing?.let { name ->
        AlertDialog(
            onDismissRequest = { removing = null },
            containerColor = LocalPalette.current.surface2,
            title = { Text(name, color = Ink.text) },
            confirmButton = { TextButton(onClick = { store.removeOperator(name); removing = null }) { Text(L("mw4.ui.opprestige.remove"), color = HajinColors.short) } },
            dismissButton = { TextButton(onClick = { removing = null }) { Text(L("mw4.ui.hajin.cancel"), color = HajinColors.text) } },
        )
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun OperatorCard(name: String, level: Int) {
    val store = hajin()
    val guide = store.guide
    val tiers = guide?.section("prestige")?.rows?.filter { it.title.resolved.startsWith("Prestige ") } ?: emptyList()
    val proTraits = guide?.section("traits")?.rows?.filter { it.group?.resolved == "Prestige traits" } ?: emptyList()
    val next = if (tiers.isEmpty()) null else tiers[minOf(level, tiers.size - 1)]
    val held = store.prestigeTraits(name)
    val haptics = LocalHapticFeedback.current
    var picking by remember { mutableStateOf(false) }
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Text(name, style = displayStyle(16.sp), color = Ink.text, modifier = Modifier.weight(1f))
            IconButton(onClick = { haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove); store.setPrestige(level - 1, name) }, enabled = level > 0, modifier = Modifier.size(30.dp)) {
                Icon(Icons.Outlined.RemoveCircleOutline, null, tint = if (level > 0) HajinColors.text else Ink.muted.copy(alpha = 0.4f))
            }
            Text(L("mw4.ui.opprestige.level", level), style = sys(13f, FontWeight.SemiBold, mono = true), color = if (level > 0) HajinColors.text else Ink.muted)
            IconButton(onClick = { haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove); store.setPrestige(level + 1, name) }, modifier = Modifier.size(30.dp)) {
                Icon(Icons.Outlined.AddCircleOutline, null, tint = HajinColors.text)
            }
        }
        if (next != null) {
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    SmallCaps(L("mw4.ui.opprestige.next", level + 1))
                    next.value?.resolved?.let { cost ->
                        val needed = cost.filter { it.isDigit() }.toIntOrNull() ?: 0
                        ValueBadge(cost)
                        if (store.cash > 0 && needed > 0) {
                            if (store.cash >= needed) Icon(Icons.Filled.CheckCircle, null, tint = HajinColors.printable, modifier = Modifier.size(14.dp))
                            else CashShort(needed)
                        }
                    }
                }
                next.subtitle?.let { Text(it.resolved, style = sys(12f), color = Ink.muted) }
            }
        }
        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            SmallCaps(L("mw4.ui.opprestige.traits") + " ${held.size}/${HajinStore.MAX_PRESTIGE_TRAITS}")
            FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                for (trait in held) {
                    Row(
                        Modifier.clip(RoundedCornerShape(6.dp)).background(HajinColors.accent.copy(alpha = 0.18f))
                            .clickable { store.togglePrestigeTrait(trait, name) }.padding(horizontal = 8.dp, vertical = 5.dp),
                        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp),
                    ) {
                        Text(trait, style = sys(12f, FontWeight.SemiBold), color = Ink.text)
                        Icon(Icons.Filled.Close, null, tint = Ink.muted, modifier = Modifier.size(10.dp))
                    }
                }
                if (held.size < HajinStore.MAX_PRESTIGE_TRAITS) {
                    Box {
                        Row(
                            Modifier.clip(RoundedCornerShape(6.dp)).border(1.dp, HajinColors.accent.copy(alpha = 0.5f), RoundedCornerShape(6.dp))
                                .clickable { picking = true }.padding(horizontal = 8.dp, vertical = 5.dp),
                            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp),
                        ) {
                            Icon(Icons.Filled.Add, null, tint = HajinColors.text, modifier = Modifier.size(12.dp))
                            Text(L("mw4.ui.opprestige.add_trait"), style = sys(12f, FontWeight.SemiBold), color = HajinColors.text)
                        }
                        DropdownMenu(picking, { picking = false }, containerColor = LocalPalette.current.surface2) {
                            for (row in proTraits.filter { it.title.resolved !in held }) {
                                DropdownMenuItem(text = { Text(row.title.resolved, color = Ink.text) }, onClick = {
                                    store.togglePrestigeTrait(row.title.resolved, name); picking = false
                                })
                            }
                        }
                    }
                }
            }
        }
    }
}
