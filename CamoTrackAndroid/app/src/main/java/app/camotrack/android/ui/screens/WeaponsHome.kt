package app.camotrack.android.ui.screens

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.HelpOutline
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.Cancel
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Diamond
import androidx.compose.material.icons.filled.ExpandCircleDown
import androidx.compose.material.icons.filled.NorthEast
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Tune
import androidx.compose.material3.*
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.camotrack.android.AppState
import app.camotrack.android.Route
import app.camotrack.android.core.GameTracker
import app.camotrack.android.core.LiveObjective
import app.camotrack.android.core.ObjectiveCategory
import app.camotrack.android.core.Suggestion
import app.camotrack.android.core.WeaponEntry
import app.camotrack.android.core.WeaponFilter
import app.camotrack.android.i18n.L
import app.camotrack.android.i18n.Strings
import app.camotrack.android.ui.*
import kotlinx.coroutines.launch

/** A section of the Weapons tab, in the order Customise lists them by default. */
enum class HomeSection(val raw: String, val titleKey: String) {
    SUMMARY("summary", "mw4.ui.section.summary"),
    LIVE("live", "mw4.ui.section.live"),
    PINNED("pinned", "mw4.ui.section.pinned"),
    SUGGESTED("suggested", "mw4.ui.section.suggested"),
    WEAPONS("weapons", "mw4.ui.section.weapons"),
    OBJECTIVES("objectives", "mw4.ui.section.objectives");

    /** Weapons is what the tab is for, so it can move but not go. */
    val canHide: Boolean get() = this != WEAPONS
}

/** The order and visibility of the tab's sections, as two comma-separated lists (iOS's HomeLayout). */
class HomeLayout(order: String, hidden: String) {
    val order: List<HomeSection>
    val hidden: Set<HomeSection>

    init {
        val saved = order.split(",").mapNotNull { raw -> HomeSection.entries.firstOrNull { it.raw == raw } }.distinct()
        val full = saved.toMutableList()
        for (section in HomeSection.entries) {
            if (section in full) continue
            val before = HomeSection.entries.takeWhile { it != section }.lastOrNull { it in full }
            val at = before?.let { full.indexOf(it) + 1 } ?: 0
            full.add(at, section)
        }
        this.order = full
        this.hidden = hidden.split(",").mapNotNull { raw -> HomeSection.entries.firstOrNull { it.raw == raw } }.filter { it.canHide }.toSet()
    }

    val visible: List<HomeSection> get() = order.filter { it !in hidden }

    companion object {
        const val ORDER_KEY = "mw4_home_order"
        const val HIDDEN_KEY = "mw4_home_hidden"
    }
}

const val WEAPON_SORT_KEY = "mw4_weapon_sort"
const val WEAPON_FILTER_KEY = "mw4_weapon_filter"

/** The weapon list's sort choices: no Level in quick tick, where there are no levels. */
fun weaponSortOptions(t: GameTracker): List<ProgressSort> =
    ProgressSort.entries.filter { !(t.quickTick && it == ProgressSort.LEVEL) }

/** [weapons] narrowed by [filter] and put in [sort]'s order. */
fun sortedWeapons(t: GameTracker, weapons: List<WeaponEntry>, mode: String, filter: WeaponFilter, sort: ProgressSort): List<WeaponEntry> {
    val shown = weapons.filter { t.matches(filter, mode, it.weaponId) }
    fun progress(w: WeaponEntry) = t.camoProgressFraction(w.weaponId, mode)
    // Prestige first, then progress through the current stage
    fun level(w: WeaponEntry) = t.prestige(w.weaponId) + t.level(w.weaponId).toDouble() / maxOf(t.maxLevel(w), 1)
    return when (sort) {
        ProgressSort.NATURAL -> shown
        ProgressSort.ALPHABETICAL -> shown.sortedBy { it.name.resolved().lowercase(appLocale) }
        ProgressSort.PROGRESS_DESC -> shown.sortedByDescending(::progress)
        ProgressSort.PROGRESS_ASC -> shown.sortedBy(::progress)
        ProgressSort.LEVEL -> shown.sortedByDescending(::level)
    }
}

/**
 * Cards in a LazyColumn: one to a row on a phone, [columns] side by side on
 * a wide screen (`fillsRow` keeps a lone card full width).
 */
fun <T> LazyListScope.cards(
    items: List<T>, columns: Int, key: (T) -> Any, fillsRow: Boolean = false, card: @Composable (T) -> Unit,
) {
    val perRow = if (fillsRow) 1 else columns
    val rows = items.chunked(perRow)
    rows.forEach { row ->
        item(key = key(row.first())) {
            Row(Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 6.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                for (i in 0 until perRow) {
                    Box(Modifier.weight(1f)) { row.getOrNull(i)?.let { card(it) } }
                }
            }
        }
    }
}

/** The Weapons tab: summary, live events, pins, suggestions, every weapon, objectives (iOS's CategoryListView). */
@OptIn(ExperimentalFoundationApi::class, ExperimentalMaterial3Api::class)
@Composable
fun WeaponsHome(mode: String) {
    val t = tracker()
    val accent = modeAccent(mode)
    val textAccent = modeTextAccent(mode)
    var query by rememberSaveable(mode) { mutableStateOf("") }
    var classId by Prefs.int("mw4_home_class", -1)
    var sortRaw by Prefs.string(WEAPON_SORT_KEY, ProgressSort.NATURAL.raw)
    var filterRaw by Prefs.string(WEAPON_FILTER_KEY, WeaponFilter.ALL.raw)
    val layoutOrder by Prefs.string(HomeLayout.ORDER_KEY, "")
    val layoutHidden by Prefs.string(HomeLayout.HIDDEN_KEY, "")
    val layout = HomeLayout(layoutOrder, layoutHidden)
    val sortOptions = weaponSortOptions(t)
    val sort = ProgressSort.from(sortRaw).takeIf { it in sortOptions } ?: ProgressSort.NATURAL
    val filter = weaponFilterFrom(filterRaw)
    var refreshing by remember { mutableStateOf(false) }
    var refreshFailed by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()

    val categories = t.categories(mode)
    val objectives = t.modes[mode]?.objectives.orEmpty()
    val allSuggestions = t.suggestions(mode)
    val suggestions = if (t.isPremium) allSuggestions else allSuggestions.take(1)
    val pinned = t.visiblePinnedWeaponIds.mapNotNull(t::weapon)
    val picked = categories.firstOrNull { it.categoryId == classId }
    val shownWeapons = sortedWeapons(t, (picked?.let { listOf(it) } ?: categories).flatMap { it.weapons }, mode, filter, sort)
    val searchResults = if (query.isEmpty()) emptyList()
    else categories.flatMap { it.weapons }.filter { it.name.resolved().contains(query, ignoreCase = true) }
    val open = { route: Route -> AppState.push(route) }

    Column(Modifier.fillMaxSize().appBackground(accent)) {
        HomeTitleBar(mode)
        BoxWithConstraints(Modifier.fillMaxSize()) {
            val columns = gridColumns(maxWidth.value)
            PullToRefreshBox(
                isRefreshing = refreshing,
                onRefresh = {
                    refreshing = true
                    scope.launch {
                        runCatching { t.refresh() }
                        refreshing = false
                        refreshFailed = t.refreshError != null
                    }
                },
            ) {
                LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(bottom = 16.dp)) {
                    item(key = "search") { SearchField(query, { query = it }) }
                    if (query.isNotEmpty()) {
                        if (searchResults.isEmpty()) {
                            item(key = "none") { FilterEmptyRow(L("ct.ui.search.none", query)) }
                        } else {
                            cards(searchResults, columns, key = { "s${it.weaponId}" }) { weapon ->
                                WeaponRow(mode, weapon) { open(Route.Weapon(weapon.weaponId)) }
                            }
                        }
                        return@LazyColumn
                    }
                    for (section in layout.visible) when (section) {
                        HomeSection.SUMMARY -> item(key = "summary") {
                            Box(Modifier.padding(horizontal = 12.dp, vertical = 6.dp)) { StatSummaryCard(summaryStats(tracker(), mode)) }
                        }
                        HomeSection.LIVE -> {
                            val live = t.liveObjectives(mode)
                            if (live.isNotEmpty()) {
                                stickyHeader(key = "h-live") { ListHeading(L("mw4.ui.section.live")) }
                                cards(live, columns, key = { "live-${it.id}" }) { entry ->
                                    LiveObjectiveRow(mode, entry, objectives.firstOrNull { it.categoryId == entry.categoryId }) {
                                        open(Route.ObjectiveItem(entry.categoryId, entry.item.itemId))
                                    }
                                }
                            }
                        }
                        HomeSection.PINNED -> if (pinned.isNotEmpty()) {
                            stickyHeader(key = "h-pinned") { ListHeading(L("mw4.ui.section.pinned")) }
                            cards(pinned, columns, key = { "pin${it.weaponId}" }, fillsRow = true) { weapon ->
                                WeaponRow(mode, weapon) { open(Route.Weapon(weapon.weaponId)) }
                            }
                        }
                        HomeSection.SUGGESTED -> if (suggestions.isNotEmpty()) {
                            stickyHeader(key = "h-suggested") { ListHeading(L("mw4.ui.section.suggested")) }
                            cards(suggestions, columns, key = { "sug${it.weaponId}" }) { suggestion ->
                                SuggestionRow(mode, suggestion) { open(Route.Weapon(suggestion.weaponId)) }
                            }
                            if (allSuggestions.size > suggestions.size) item(key = "more-suggestions") {
                                Row(
                                    Modifier.fillMaxWidth().clickable { open(Route.Premium) }.padding(vertical = 10.dp),
                                    horizontalArrangement = Arrangement.Center, verticalAlignment = Alignment.CenterVertically,
                                ) {
                                    Icon(Icons.Filled.AutoAwesome, null, tint = accent, modifier = Modifier.size(16.dp))
                                    Spacer(Modifier.width(6.dp))
                                    Text(
                                        Strings.plural("mw4.ui.premium.more_suggestions", allSuggestions.size - suggestions.size),
                                        style = sys(15f, FontWeight.SemiBold), color = accent,
                                    )
                                }
                            }
                        }
                        HomeSection.WEAPONS -> if (categories.isNotEmpty()) {
                            stickyHeader(key = "h-weapons") { ListHeading(L("mw4.ui.section.weapons")) }
                            item(key = "chips") {
                                Row(
                                    Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()).padding(horizontal = 12.dp).padding(bottom = 4.dp),
                                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                                ) {
                                    ClassChip(L("mw4.ui.filter.all"), classId == -1, accent) { classId = -1 }
                                    for (category in categories) {
                                        ClassChip(category.name.resolved(), classId == category.categoryId, accent) { classId = category.categoryId }
                                    }
                                }
                            }
                            if (picked != null) item(key = "class-stats") {
                                Box(Modifier.padding(horizontal = 12.dp, vertical = 4.dp)) { StatSummaryCard(categoryStats(tracker(), picked, mode)) }
                            }
                            item(key = "filters") {
                                Row(Modifier.padding(start = 12.dp, end = 12.dp, bottom = 6.dp, top = 4.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                    FilterSortMenu(L("mw4.ui.filter"), WeaponFilter.entries, { it.label(mode) }, filter, textAccent, { filterRaw = it.raw }, Modifier.weight(1f))
                                    FilterSortMenu(L("mw4.ui.sort"), sortOptions, { it.label }, sort, textAccent, { sortRaw = it.raw }, Modifier.weight(1f))
                                }
                            }
                            if (shownWeapons.isEmpty()) {
                                item(key = "empty") { FilterEmptyRow() }
                            } else {
                                cards(shownWeapons, columns, key = { "w${it.weaponId}" }) { weapon ->
                                    WeaponRow(mode, weapon) { open(Route.Weapon(weapon.weaponId)) }
                                }
                            }
                        }
                        HomeSection.OBJECTIVES -> if (objectives.isNotEmpty()) {
                            stickyHeader(key = "h-objectives") { ListHeading(L("mw4.ui.section.objectives")) }
                            cards(objectives, columns, key = { "obj${it.categoryId}" }) { category ->
                                ObjectiveCategoryRow(mode, category) { open(Route.ObjectiveCategory(category.categoryId)) }
                            }
                        }
                    }
                }
            }
        }
    }
    if (refreshFailed) {
        AlertDialog(
            onDismissRequest = { refreshFailed = false },
            containerColor = LocalPalette.current.surface2,
            title = { Text(L("ct.ui.refresh.failed"), color = Ink.text) },
            text = { Text(L("ct.ui.refresh.failed_message"), color = Ink.muted) },
            confirmButton = { TextButton(onClick = { refreshFailed = false }) { Text(L("mw4.ui.done")) } },
        )
    }
}

/** The title: the game and mode, with a ▾ to change either; help and Customise beside it. */
@Composable
private fun HomeTitleBar(mode: String) {
    val t = tracker()
    val accent = modeAccent(mode)
    var open by remember { mutableStateOf(false) }
    val palette = LocalPalette.current
    Box(Modifier.fillMaxWidth().statusBarsPadding().height(52.dp)) {
        Box(Modifier.align(Alignment.Center)) {
            Row(
                Modifier.clip(RoundedCornerShape(8.dp)).clickable { open = true }.padding(horizontal = 8.dp, vertical = 4.dp),
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                Text(t.game.shortName, style = displayStyle(22.sp), color = accent, maxLines = 1)
                Text(modeName(mode), style = displayStyle(22.sp), color = Ink.text, maxLines = 1)
                Icon(Icons.Filled.ExpandCircleDown, contentDescription = L("mw4.ui.mostly_play"), tint = accent, modifier = Modifier.size(18.dp))
            }
            DropdownMenu(open, onDismissRequest = { open = false }, containerColor = palette.surface2) {
                MenuHeading(L("mw4.ui.mostly_play"))
                for (m in t.visibleModes) {
                    DropdownMenuItem(
                        text = { Text(modeName(m), color = Ink.text) },
                        leadingIcon = { if (m == mode) Icon(Icons.Filled.Check, null, tint = Ink.text) else Spacer(Modifier.size(24.dp)) },
                        trailingIcon = { Icon(modeIcon(m), null, tint = modeAccent(m)) },
                        onClick = { open = false; AppState.pickMode(m) },
                    )
                }
                HorizontalDivider(color = Ink.muted.copy(alpha = 0.2f))
                MenuHeading(L("ct.ui.game"))
                for (game in AppState.games) {
                    DropdownMenuItem(
                        text = { Text(game.name.resolved(), color = Ink.text) },
                        leadingIcon = { if (game == t.game) Icon(Icons.Filled.Check, null, tint = Ink.text) else Spacer(Modifier.size(24.dp)) },
                        onClick = { open = false; if (game != t.game) AppState.open(game) },
                    )
                }
            }
        }
        Row(Modifier.align(Alignment.CenterEnd)) {
            // Help: the walkthrough again
            IconButton(onClick = { AppState.showsOnboarding = true }) { Icon(Icons.AutoMirrored.Outlined.HelpOutline, null, tint = accent) }
            IconButton(onClick = { AppState.push(Route.Customise) }) { Icon(Icons.Filled.Tune, L("mw4.ui.customise"), tint = accent) }
        }
    }
}

@Composable
private fun MenuHeading(text: String) {
    Text(text, style = sys(12f, FontWeight.SemiBold), color = Ink.muted, modifier = Modifier.padding(horizontal = 16.dp, vertical = 6.dp))
}

/** iOS's search field: a rounded well with a magnifier and a clear button. */
@Composable
private fun SearchField(query: String, onChange: (String) -> Unit) {
    val palette = LocalPalette.current
    Row(
        Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 6.dp).clip(RoundedCornerShape(10.dp))
            .background(palette.surface2).padding(horizontal = 10.dp, vertical = 9.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Icon(Icons.Filled.Search, null, tint = Ink.muted, modifier = Modifier.size(18.dp))
        Box(Modifier.weight(1f)) {
            if (query.isEmpty()) Text(L("mw4.ui.search_weapons"), style = sys(16f), color = Ink.muted)
            BasicTextField(
                query, onChange, singleLine = true, textStyle = sys(16f).copy(color = Ink.text),
                cursorBrush = SolidColor(MaterialTheme.colorScheme.primary), modifier = Modifier.fillMaxWidth(),
            )
        }
        if (query.isNotEmpty()) {
            Icon(Icons.Filled.Cancel, null, tint = Ink.muted, modifier = Modifier.size(18.dp).clickable { onChange("") })
        }
    }
}

/** All, then each class: tap one to narrow the list to it. */
@Composable
private fun ClassChip(title: String, on: Boolean, accent: Color, onClick: () -> Unit) {
    val palette = LocalPalette.current
    Text(
        title, style = displayStyle(14.sp), color = if (on) Ink.text else Ink.muted, maxLines = 1,
        modifier = Modifier.clip(CircleShape)
            .background(if (on) accent.copy(alpha = 0.18f) else palette.surface)
            .border(1.dp, if (on) accent.copy(alpha = 0.7f) else palette.surface2, CircleShape)
            .clickable(onClick = onClick)
            .padding(horizontal = 13.dp, vertical = 7.dp),
    )
}

/** "Grind this next": the weapon, the camo it's on, and how far toward it. */
@Composable
private fun SuggestionRow(mode: String, suggestion: Suggestion, onClick: () -> Unit) {
    val accent = modeAccent(mode)
    val camo = suggestion.nextCamo
    val gradient = camo?.colors?.takeIf { it.size > 1 }
    val badge = when {
        gradient != null -> Brush.linearGradient(gradient)
        camo != null -> SolidColor(camo.tint)
        else -> SolidColor(accent)
    }
    val subtitle = camo?.let { L("mw4.ui.suggestion.next_camo", it.name) } ?: Strings.plural("ct.ui.suggestion.camos_left", suggestion.camosLeft)
    Row(
        Modifier.fillMaxWidth().borderedCard().clickable(onClick = onClick).padding(12.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Box(Modifier.size(30.dp).clip(CircleShape).background(badge), contentAlignment = Alignment.Center) {
            Icon(if (camo != null) Icons.Filled.Diamond else Icons.Filled.NorthEast, null, tint = LocalPalette.current.background, modifier = Modifier.size(15.dp))
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(suggestion.weaponName.resolved(), style = sys(15f, FontWeight.SemiBold), color = Ink.text, maxLines = 1, overflow = TextOverflow.Ellipsis)
            if (gradient != null) {
                Text(subtitle, style = sys(12.5f, FontWeight.SemiBold).copy(brush = Brush.horizontalGradient(gradient)))
            } else {
                Text(subtitle, style = sys(12.5f), color = Ink.muted)
            }
            ProgressBar(suggestion.progress, accent)
        }
        Spacer(Modifier.width(8.dp))
        Text(percentText(suggestion.progress), style = sys(13f, FontWeight.SemiBold, mono = true), color = modeTextAccent(mode))
    }
}

/** A live season or event: what it is, when it ends and how far along it is. */
@Composable
private fun LiveObjectiveRow(mode: String, entry: LiveObjective, category: ObjectiveCategory?, onClick: () -> Unit) {
    val t = tracker()
    val accent = modeAccent(mode)
    val fraction = t.objectiveProgressFraction(entry.item, mode, entry.categoryId)
    Column(
        Modifier.fillMaxWidth().borderedCard(accent = if (fraction >= 1) accent else null).clickable(onClick = onClick).padding(12.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            Eyebrow(category?.name?.resolved() ?: "")
            t.objectiveScope(entry.categoryId, entry.item.itemId)?.let { ObjectiveScopeTag(it, accent) }
            Spacer(Modifier.weight(1f))
            entry.item.endDate?.let {
                Text(L("mw4.ui.objective.ends", shortDayText(it)), style = sys(11f, FontWeight.SemiBold), color = Ink.muted)
            }
        }
        Text(entry.item.name.resolved(), style = displayStyle(16.sp), color = Ink.text)
        ProgressBar(fraction, accent)
    }
}

@Composable
private fun ObjectiveCategoryRow(mode: String, category: ObjectiveCategory, onClick: () -> Unit) {
    val t = tracker()
    val accent = modeAccent(mode)
    val fraction = t.objectiveProgressFraction(category, mode)
    val complete = fraction >= 1 && category.items.isNotEmpty()
    Column(
        Modifier.fillMaxWidth().borderedCard(accent = if (complete) accent else null).clickable(onClick = onClick).padding(12.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Eyebrow("${category.items.size} ${L("mw4.ui.section.objectives")}")
        Text(category.name.resolved(), style = displayStyle(16.sp), color = Ink.text)
        ProgressBar(fraction, accent)
    }
}
