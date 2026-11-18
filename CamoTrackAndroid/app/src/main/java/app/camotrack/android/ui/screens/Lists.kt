package app.camotrack.android.ui.screens

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.outlined.Circle
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.camotrack.android.AppState
import app.camotrack.android.Route
import app.camotrack.android.core.ChallengeItem
import app.camotrack.android.core.ObjectiveCategory
import app.camotrack.android.core.WeaponCategory
import app.camotrack.android.core.WeaponFilter
import app.camotrack.android.i18n.L
import app.camotrack.android.ui.*

/** A class's weapons (or every weapon): its rings, Filter and Sort, the cards (iOS's WeaponListView). */
@Composable
fun WeaponListScreen(mode: String, category: WeaponCategory, title: String) {
    val t = tracker()
    val accent = modeAccent(mode)
    val textAccent = modeTextAccent(mode)
    var sortRaw by Prefs.string(WEAPON_SORT_KEY, ProgressSort.NATURAL.raw)
    var filterRaw by Prefs.string(WEAPON_FILTER_KEY, WeaponFilter.ALL.raw)
    val sortOptions = weaponSortOptions(t)
    val sort = ProgressSort.from(sortRaw).takeIf { it in sortOptions } ?: ProgressSort.NATURAL
    val filter = weaponFilterFrom(filterRaw)
    val weapons = sortedWeapons(t, category.weapons, mode, filter, sort)

    Column(Modifier.fillMaxSize().appBackground(accent)) {
        TopBar(title)
        BoxWithConstraints(Modifier.fillMaxSize()) {
            val columns = gridColumns(maxWidth.value)
            LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(bottom = 16.dp)) {
                item(key = "stats") {
                    Box(Modifier.padding(horizontal = 12.dp, vertical = 6.dp)) { StatSummaryCard(categoryStats(tracker(), category, mode)) }
                }
                item(key = "filters") {
                    Row(Modifier.padding(horizontal = 12.dp, vertical = 6.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        FilterSortMenu(L("mw4.ui.filter"), WeaponFilter.entries, { it.label(mode) }, filter, textAccent, { filterRaw = it.raw }, Modifier.weight(1f))
                        FilterSortMenu(L("mw4.ui.sort"), sortOptions, { it.label }, sort, textAccent, { sortRaw = it.raw }, Modifier.weight(1f))
                    }
                }
                if (weapons.isEmpty()) {
                    item(key = "empty") { FilterEmptyRow() }
                } else {
                    cards(weapons, columns, key = { "w${it.weaponId}" }) { weapon ->
                        WeaponRow(mode, weapon, showsCamoCount = false) { AppState.push(Route.Weapon(weapon.weaponId)) }
                    }
                }
            }
        }
    }
}

/** A mode's objective category (events, BlackCell seasons): Filter, Sort, then the items, ended ones under Archive. */
@OptIn(ExperimentalFoundationApi::class)
@Composable
fun ObjectiveListScreen(mode: String, category: ObjectiveCategory) {
    val t = tracker()
    val accent = modeAccent(mode)
    val textAccent = modeTextAccent(mode)
    var sortRaw by Prefs.string("mw4_item_sort", ProgressSort.NATURAL.raw)
    var filterRaw by Prefs.string("mw4_item_filter", CompletionFilter.ALL.raw)
    val sortOptions = listOf(ProgressSort.NATURAL, ProgressSort.ALPHABETICAL, ProgressSort.PROGRESS_DESC, ProgressSort.PROGRESS_ASC)
    val sort = ProgressSort.from(sortRaw).takeIf { it in sortOptions } ?: ProgressSort.NATURAL
    val filter = CompletionFilter.from(filterRaw)
    fun fraction(item: ChallengeItem) = t.objectiveProgressFraction(item, mode, category.categoryId)
    fun complete(item: ChallengeItem) = if (item.isLeaf) t.isObjectiveComplete(mode, category.categoryId, item) else fraction(item) >= 1
    val filtered = when (filter) {
        CompletionFilter.ALL -> category.items
        CompletionFilter.INCOMPLETE -> category.items.filter { !complete(it) }
        CompletionFilter.COMPLETE -> category.items.filter(::complete)
    }
    val items = when (sort) {
        ProgressSort.ALPHABETICAL -> filtered.sortedBy { it.name.resolved().lowercase(appLocale) }
        ProgressSort.PROGRESS_DESC -> filtered.sortedByDescending(::fraction)
        ProgressSort.PROGRESS_ASC -> filtered.sortedBy(::fraction)
        else -> filtered
    }
    val current = items.filter { it.window() != ChallengeItem.Window.ENDED }
    val archive = items.filter { it.window() == ChallengeItem.Window.ENDED }
    val open = { item: ChallengeItem -> AppState.push(Route.ObjectiveItem(category.categoryId, item.itemId)) }

    Column(Modifier.fillMaxSize().appBackground(accent)) {
        TopBar(category.name.resolved())
        LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(start = readableInset(), end = readableInset(), bottom = 16.dp)) {
            item(key = "filters") {
                Row(Modifier.padding(horizontal = 12.dp, vertical = 6.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    FilterSortMenu(L("mw4.ui.filter"), CompletionFilter.entries, { it.label }, filter, textAccent, { filterRaw = it.raw }, Modifier.weight(1f))
                    FilterSortMenu(L("mw4.ui.sort"), sortOptions, { it.label }, sort, textAccent, { sortRaw = it.raw }, Modifier.weight(1f))
                }
            }
            if (items.isEmpty()) {
                item(key = "empty") { FilterEmptyRow() }
            } else {
                items(current, key = { "c${it.itemId}" }) { item ->
                    Box(Modifier.padding(horizontal = 12.dp, vertical = 6.dp)) { ObjectiveItemRow(mode, category, item) { open(item) } }
                }
                if (archive.isNotEmpty()) {
                    stickyHeader(key = "h-archive") { ListHeading(L("mw4.ui.section.archive")) }
                    items(archive, key = { "a${it.itemId}" }) { item ->
                        Box(Modifier.padding(horizontal = 12.dp, vertical = 6.dp)) { ObjectiveItemRow(mode, category, item) { open(item) } }
                    }
                }
            }
        }
    }
}

@Composable
private fun ObjectiveItemRow(mode: String, category: ObjectiveCategory, item: ChallengeItem, onClick: () -> Unit) {
    val t = tracker()
    val accent = modeAccent(mode)
    val done = t.isObjectiveComplete(mode, category.categoryId, item)
    val fraction = t.objectiveProgressFraction(item, mode, category.categoryId)
    val complete = if (item.isLeaf) done else fraction >= 1
    Column(
        Modifier.fillMaxWidth().borderedCard(accent = if (complete) accent else null).clickable(onClick = onClick).padding(12.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            Eyebrow(category.name.resolved())
            t.objectiveScope(category.categoryId, item.itemId)?.let { ObjectiveScopeTag(it, accent) }
        }
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(item.name.resolved(), style = displayStyle(15.sp), color = Ink.text)
                if (!item.isLeaf) ProgressBar(fraction, accent)
            }
            if (item.isLeaf) {
                Icon(if (done) Icons.Filled.CheckCircle else Icons.Outlined.Circle, null, tint = if (done) accent else Ink.muted, modifier = Modifier.size(22.dp))
            }
        }
    }
}

/** One objective's challenges (an event's or a BlackCell season's tiers), each a ChallengeRow (iOS's ItemDetailView). */
@Composable
fun ObjectiveItemScreen(mode: String, category: ObjectiveCategory, item: ChallengeItem) {
    val accent = modeAccent(mode)
    val rows = item.children.ifEmpty { listOf(item) }
    val ordered = item.children.isEmpty() || item.ordered != false
    Column(Modifier.fillMaxSize().appBackground(accent)) {
        TopBar(item.name.resolved())
        LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(start = readableInset(), end = readableInset(), bottom = 16.dp)) {
            items(rows, key = { it.itemId }) { row ->
                val tt = tracker()
                Column(Modifier.fillMaxWidth().background(LocalPalette.current.surface).padding(horizontal = 16.dp, vertical = 4.dp)) {
                    ChallengeRow(
                        item = row, accent = accent, mode = mode,
                        amount = tt.objectiveAmount(mode, category.categoryId, row),
                        isDone = tt.isObjectiveComplete(mode, category.categoryId, row),
                        isAvailable = tt.isObjectiveAvailable(mode, category.categoryId, rows, row, ordered),
                        onToggle = { tt.toggleObjective(mode, category.categoryId, row) },
                        onSetAmount = { tt.setObjectiveAmount(mode, category.categoryId, row, it) },
                    )
                }
                Box(Modifier.fillMaxWidth().padding(start = 16.dp).height(0.5.dp).background(Ink.muted.copy(alpha = 0.2f)))
            }
        }
    }
}
