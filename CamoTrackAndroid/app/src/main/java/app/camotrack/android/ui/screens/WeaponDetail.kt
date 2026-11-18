package app.camotrack.android.ui.screens

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Undo
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.ExpandCircleDown
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.KeyboardDoubleArrowUp
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.Palette
import androidx.compose.material.icons.filled.PushPin
import androidx.compose.material.icons.filled.Remove
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.filled.Verified
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material.icons.outlined.PushPin
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.camotrack.android.AppState
import app.camotrack.android.core.ChallengeItem
import app.camotrack.android.core.CompletionistGate
import app.camotrack.android.core.GameTracker
import app.camotrack.android.core.LocalizedText
import app.camotrack.android.core.MasteryKind
import app.camotrack.android.core.PrestigeCamo
import app.camotrack.android.core.WeaponEntry
import app.camotrack.android.i18n.L
import app.camotrack.android.ui.*

private sealed interface Part {
    data object Camos : Part
    data object Completionist : Part
    data object Mastery : Part
    data class Badges(val index: Int) : Part
}

private data class CamoGroup(val title: String, val camos: List<ChallengeItem>)

private fun groups(camos: List<ChallengeItem>): List<CamoGroup> {
    val out = mutableListOf<CamoGroup>()
    for (camo in camos) {
        val title = camo.section?.resolved() ?: when (camo.group) {
            "military" -> L("mw4.ui.section.military")
            "special" -> L("mw4.ui.section.special")
            else -> L("mw4.ui.section.camos")
        }
        if (out.lastOrNull()?.title == title) out[out.size - 1] = out.last().copy(camos = out.last().camos + camo)
        else out += CamoGroup(title, listOf(camo))
    }
    return out
}

/**
 * A weapon's page: its level and Prestige (the same in every mode), then
 * the picked mode's camos, Completionist camos and Mastery, one part at a
 * time (iOS's WeaponDetailView, phone layout).
 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
fun WeaponDetailScreen(startMode: String, weapon: WeaponEntry) {
    val t = tracker()
    var mode by rememberSaveable(weapon.weaponId) { mutableStateOf(startMode) }
    val accent = modeAccent(mode)
    val id = weapon.weaponId
    val camos = t.allCamos(id, mode)
    var showsMilitary by rememberSaveable { mutableStateOf(false) }
    val specialsFirst by Prefs.bool(Prefs.SPECIALS_FIRST, false)
    var pickedPart by remember { mutableStateOf<Part?>(null) }

    val camoGroups = groups(camos.filter { it.extra != true })
    val military = camos.filter { it.extra != true && it.group == "military" }
    val levelMilitary = military.takeIf { m -> m.isNotEmpty() && m.all { t.militaryLevel(mode, id, it) != null } }
    val listedGroups = if (levelMilitary == null) camoGroups else camoGroups.filter { g -> !g.camos.all { it.group == "military" } }
    val badgeGroups = groups(camos.filter { it.extra == true })
    val hasMastery = t.game.hasAccountMastery
    val parts: List<Pair<Part, String>> = (if (hasMastery) listOf(
        Part.Camos to L("mw4.ui.section.camos"),
        Part.Completionist to L("mw4.ui.section.completionist"),
        Part.Mastery to L("mw4.ui.section.mastery"),
    ) else listOf(
        Part.Camos to L("mw4.ui.section.camos"),
        Part.Completionist to L("mw4.ui.section.mastery"),
    )) + badgeGroups.mapIndexed { index, group -> Part.Badges(index) to group.title }
    val shownPart: Part = pickedPart?.takeIf { p -> parts.any { it.first == p } } ?: when {
        camos.any { it.extra != true && !t.isCamoComplete(mode, id, it) } -> Part.Camos
        hasMastery && t.hasLastCompletionist(mode, id) -> Part.Mastery
        else -> Part.Completionist
    }
    // Finishing the last camo moves on to what it opens, even after Camos was picked by hand
    val allDone = t.allCamosComplete(id, mode)
    LaunchedEffect(allDone) { if (allDone && pickedPart == Part.Camos) pickedPart = null }

    @Composable
    fun camoRow(camo: ChallengeItem) = CamoChallengeRow(mode, weapon, camo)

    fun LazyListScope.rowsOf(key: String, items: List<ChallengeItem>) {
        items(items, key = { "$key-${it.itemId}" }) { camo -> SurfaceRow { camoRow(camo) } }
    }

    fun LazyListScope.militarySection() {
        val list = levelMilitary ?: return
        stickyHeader(key = "h-military") { ListHeading(L("mw4.ui.section.military")) }
        item(key = "military-summary") { SurfaceRow { MilitarySummary(mode, weapon, list, showsMilitary) { showsMilitary = !showsMilitary } } }
        if (showsMilitary) rowsOf("mil", list)
    }

    Column(Modifier.fillMaxSize().appBackground(accent)) {
        TopBar(weapon.name.resolved()) {
            ReportIssueMenu(weapon, mode, camos.filter { it.extra != true }, MaterialTheme.colorScheme.primary)
            IconButton(onClick = { app.camotrack.android.ui.share.Sharing.open(app.camotrack.android.ui.share.ShareRequest.Weapon(id, mode)) }) {
                Icon(Icons.Filled.Share, L("mw4.ui.share.weapon", weapon.name.resolved()), tint = MaterialTheme.colorScheme.primary)
            }
            val pinned = t.isPinned(id)
            IconButton(onClick = { if (pinned) t.unpin(id) else t.pin(id) }) {
                Icon(
                    if (pinned) Icons.Filled.PushPin else Icons.Outlined.PushPin,
                    L(if (pinned) "mw4.ui.unpin" else "mw4.ui.pin"), tint = MaterialTheme.colorScheme.primary,
                )
            }
        }
        LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(start = readableInset(), end = readableInset(), bottom = 24.dp)) {
            item(key = "header") {
                Column(
                    Modifier.padding(horizontal = 12.dp, vertical = 6.dp).fillMaxWidth().borderedCard().padding(12.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    WeaponHeroImage(weapon.imageURL, category = t.category(weapon.weaponId))
                    Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
                        t.category(id)?.let { Text(it.name.resolved(), style = displayStyle(15.sp), color = Ink.text) }
                        AcquiredByLabel(weapon)
                    }
                    if (!t.quickTick) {
                        CardDivider()
                        CompactLevelRow(mode, weapon)
                    }
                    PrestigeCamosBlock(mode, weapon)
                }
            }
            if (camos.isEmpty()) item(key = "no-data") {
                Column(
                    Modifier.fillMaxWidth().background(LocalPalette.current.surface).padding(vertical = 12.dp, horizontal = 16.dp),
                    horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp),
                ) {
                    Icon(Icons.Filled.Palette, null, tint = Ink.muted, modifier = Modifier.size(22.dp))
                    Text(L("mw4.ui.no_camo_data", modeName(mode)), style = sys(13f), color = Ink.muted)
                }
            }
            if (t.visibleModes.size > 1) item(key = "mode-switch") {
                ModeSwitch(mode, t.visibleModes) { mode = it }
            }
            item(key = "parts") {
                SegmentTabs(shownPart, parts, accent, { pickedPart = it }, Modifier.padding(horizontal = 12.dp, vertical = 4.dp))
            }
            when (val part = shownPart) {
                Part.Camos -> {
                    if (!specialsFirst) militarySection()
                    listedGroups.forEachIndexed { index, group ->
                        stickyHeader(key = "h-g$index") { ListHeading(group.title) }
                        rowsOf("g$index", group.camos)
                    }
                    if (specialsFirst) militarySection()
                }
                is Part.Badges -> badgeGroups.getOrNull(part.index)?.let { group ->
                    stickyHeader(key = "h-badges") { ListHeading(group.title) }
                    rowsOf("b${part.index}", group.camos)
                }
                Part.Completionist -> {
                    item(key = "spacer-c") { Spacer(Modifier.height(8.dp)) }
                    items(GameTracker.COMPLETIONIST_STEP_COUNT, key = { "step$it" }) { step -> SurfaceRow { CompletionistStepRow(mode, weapon, step) } }
                    if (t.finalEnabled(mode)) item(key = "final") { SurfaceRow { FinalCamoRow(mode, weapon) } }
                }
                Part.Mastery -> {
                    item(key = "spacer-m") { Spacer(Modifier.height(8.dp)) }
                    items(3, key = { "tier$it" }) { index -> SurfaceRow { MasteryRow(mode, weapon, index + 1) } }
                }
            }
        }
    }
}

/** A row on the surface, edge to edge with a rule under it (a plain List row on iOS). */
@Composable
private fun SurfaceRow(content: @Composable () -> Unit) {
    Column(Modifier.fillMaxWidth().background(LocalPalette.current.surface)) {
        Box(Modifier.padding(horizontal = 16.dp, vertical = 4.dp)) { content() }
        Box(Modifier.fillMaxWidth().padding(start = 16.dp).height(0.5.dp).background(Ink.muted.copy(alpha = 0.2f)))
    }
}

/** "Mode  Multiplayer ⌄": which mode's counts and Mastery the page shows. */
@Composable
private fun ModeSwitch(mode: String, modes: List<String>, onPick: (String) -> Unit) {
    var open by remember { mutableStateOf(false) }
    Row(
        Modifier.fillMaxWidth().padding(start = 14.dp, end = 14.dp, top = 8.dp, bottom = 2.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Text(L("ct.ui.mode"), style = sys(13f, FontWeight.SemiBold), color = Ink.muted)
        Box {
            Row(
                Modifier.clip(CircleShape).clickable { open = true }.padding(horizontal = 4.dp, vertical = 4.dp),
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp),
            ) {
                Text(modeName(mode), style = sys(15f, FontWeight.Bold), color = Ink.text, maxLines = 1)
                Icon(Icons.Filled.ExpandCircleDown, null, tint = modeAccent(mode), modifier = Modifier.size(16.dp))
            }
            DropdownMenu(open, onDismissRequest = { open = false }, containerColor = LocalPalette.current.surface2) {
                for (m in modes) {
                    DropdownMenuItem(
                        text = { Text(modeName(m), color = Ink.text) },
                        leadingIcon = { if (m == mode) Icon(Icons.Filled.Check, null, tint = Ink.text) else Spacer(Modifier.size(24.dp)) },
                        trailingIcon = { Icon(modeIcon(m), null, tint = modeAccent(m)) },
                        onClick = { open = false; onPick(m) },
                    )
                }
            }
        }
    }
}

// MARK: - Camo rows

@Composable
private fun CamoChallengeRow(mode: String, weapon: WeaponEntry, camo: ChallengeItem) {
    val t = tracker()
    val id = weapon.weaponId
    val lockedReason = if (camo.group == "special" && t.specialsWaitForMilitary(mode) && !t.allMilitaryComplete(mode, id)) {
        L("mw4.ui.special_locked")
    } else camo.unlockLevel?.let { levelGateText(t, it, id, "locked") }
    // "Earned at 17 weapon unlocks." under a level-earned Military camo
    val detail = t.militaryLevel(mode, id, camo)?.let { level ->
        when {
            t.quickTick -> levelGateText(t, level, id, "reach")
            t.isCamoComplete(mode, id, camo) -> levelGateText(t, level, id, "earned")
            else -> levelGateText(t, level, id, "locked")
        }
    }
    ChallengeRow(
        item = camo, accent = modeAccent(mode),
        amount = t.camoAmount(mode, id, camo),
        isDone = t.isCamoComplete(mode, id, camo),
        isAvailable = t.isCamoAvailable(mode, id, camo),
        lockedReason = lockedReason, detail = detail,
        earnedOn = t.camoUnlockedDate(mode, id, camo),
        onToggle = { t.toggleCamo(mode, id, camo) },
        onSetAmount = { t.setCamoAmount(mode, id, camo, it) },
    )
}

/** Gold, Platinum or Harmonic Break on this weapon: its own challenge, gated on the step before. */
@Composable
private fun CompletionistStepRow(mode: String, weapon: WeaponEntry, step: Int) {
    val t = tracker()
    val id = weapon.weaponId
    val track = t.completionist(mode)
    val camo = track.steps[step]
    val item = ChallengeItem(
        itemId = -(step + 1), name = LocalizedText(camo.name), imageURL = camo.imageURL,
        requirement = t.completionistRequirement(mode, id, step), children = emptyList(),
    )
    val before = if (step == 0) null else track.steps[step - 1].name
    val ownDone = if (step == 0) t.allCamosComplete(id, mode) else t.isCompletionistComplete(mode, id, step - 1)
    val lockedReason = if (!ownDone) {
        before?.let { L("mw4.ui.completionist.locked_previous", it) } ?: L("mw4.ui.completionist.locked_camos")
    } else when (t.completionistGate(mode, step)) {
        CompletionistGate.WEAPON -> L("mw4.ui.locked")
        CompletionistGate.CATEGORY -> t.category(id)?.let { category ->
            val p = t.completionistCategoryGateProgress(category, mode, step)
            val className = category.name.resolved()
            before?.let { L("mw4.ui.completionist.locked_class", it, p.total, className, p.done) }
                ?: L("mw4.ui.completionist.locked_class_camos", className)
        } ?: L("mw4.ui.locked")
        CompletionistGate.MODE -> {
            val p = t.completionistModeGateProgress(mode, step)
            L("mw4.ui.completionist.locked_mode", before ?: "", p.total, p.done)
        }
    }
    ChallengeRow(
        item = item, accent = camo.tint,
        amount = t.completionistAmount(mode, id, step),
        isDone = t.isCompletionistComplete(mode, id, step),
        isAvailable = t.isCompletionistAvailable(mode, id, step),
        lockedReason = lockedReason, titleGradient = camo.colors,
        earnedOn = t.completionistUnlockedDate(mode, id, step),
        took = t.completionistDuration(mode, id, step),
        onToggle = { t.toggleCompletionist(mode, id, step) },
        onSetAmount = { t.setCompletionistAmount(mode, id, step, it) },
    )
}

/** The final Completionist camo: read-only, earned by this weapon's Harmonic Break and the mode's count. */
@Composable
private fun FinalCamoRow(mode: String, weapon: WeaponEntry) {
    val t = tracker()
    val id = weapon.weaponId
    val track = t.completionist(mode)
    val camo = track.final
    val harmonic = track.steps[2].name
    val needed = t.harmonicBreaksNeeded(mode)
    val done = t.harmonicBreakCount(mode)
    val detail = if (!t.isCompletionistComplete(mode, id, 2)) {
        if (needed > 1) L("mw4.ui.completionist.final_locked_count", harmonic, needed, minOf(done, needed))
        else L("mw4.ui.completionist.locked_previous", harmonic)
    } else L("mw4.ui.completionist.final_count", minOf(done, maxOf(needed, 1)), maxOf(needed, 1), harmonic)
    StatusRow(camo.name, t.hasFinalCamo(mode, id), camo.tint, camo.colors, detail, camo.imageURL)
}

/** A Mastery tier: this weapon's own challenge, a mode-wide challenge, or the mode-wide count. */
@Composable
internal fun MasteryRow(mode: String, weapon: WeaponEntry, tier: Int) {
    val t = tracker()
    val id = weapon.weaponId
    val tiers = t.masteryCamos(mode)
    val camo = tiers[tier - 1]
    val last = t.lastCompletionist(mode)
    val before = if (tier == 1) last else tiers[tier - 2]
    when (t.masteryKind(mode, tier)) {
        MasteryKind.COUNT -> {
            val p = t.masteryProgress(mode, tier)
            StatusRow(camo.name, t.isMasteryAchieved(mode, tier), camo.tint, camo.colors,
                L("mw4.ui.mastery.weapons_needed", p.done, p.total, last.name), camo.imageURL)
        }
        MasteryKind.MODE -> {
            val requirement = t.modeMasteryRequirement(mode, tier)
            val lockedReason = when {
                tier > 1 && !t.isMasteryAchieved(mode, tier - 1) -> L("mw4.ui.mastery.mode_locked", before.name)
                t.modeMasteryWeaponsNeeded(mode, tier) <= 1 -> L("mw4.ui.mastery.mode_locked_first", last.name)
                else -> {
                    val needed = t.modeMasteryWeaponsNeeded(mode, tier)
                    L("mw4.ui.mastery.weapons_needed", minOf(t.lastCompletionistCount(mode), needed), needed, last.name)
                }
            }
            if (t.modeMasteryCountsItself(mode, tier)) {
                val p = t.masteryProgress(mode, tier)
                val counted = t.modeMasteryCountedCamo(mode, tier) ?: t.completionist(mode).steps[2]
                StatusRow(
                    camo.name, t.isMasteryAchieved(mode, tier), camo.tint, camo.colors,
                    if (t.isModeMasteryAvailable(mode, tier)) L("mw4.ui.mastery.self_count", p.done, p.total, counted.name) else lockedReason,
                    camo.imageURL,
                )
            } else {
                ChallengeRow(
                    item = ChallengeItem(itemId = -(20 + tier), name = LocalizedText(camo.name), imageURL = camo.imageURL, requirement = requirement, children = emptyList()),
                    accent = camo.tint,
                    amount = t.modeMasteryAmount(mode, tier),
                    isDone = t.isModeMasteryComplete(mode, tier),
                    isAvailable = t.isModeMasteryAvailable(mode, tier),
                    lockedReason = lockedReason, titleGradient = camo.colors,
                    onToggle = { t.toggleModeMastery(mode, tier, id) },
                    onSetAmount = { t.setModeMasteryAmount(mode, tier, id, it) },
                )
            }
        }
        MasteryKind.CHALLENGE -> {
            val ownDone = if (tier == 1) t.hasLastCompletionist(mode, id) else t.hasTierBefore(mode, id, tier)
            val lockedReason = if (!ownDone) {
                val forTheMode = tier > 1 && t.masteryKind(mode, tier - 1) != MasteryKind.CHALLENGE
                L(if (forTheMode) "mw4.ui.mastery.mode_locked" else "mw4.ui.completionist.locked_previous", before.name)
            } else when (t.masteryGate(mode, tier)) {
                CompletionistGate.WEAPON -> L("mw4.ui.locked")
                CompletionistGate.CATEGORY -> t.category(id)?.let { category ->
                    val p = t.masteryGateProgress(mode, tier, category)
                    L("mw4.ui.completionist.locked_class", before.name, p.total, category.name.resolved(), p.done)
                } ?: L("mw4.ui.locked")
                CompletionistGate.MODE -> {
                    val p = t.masteryGateProgress(mode, tier)
                    L("mw4.ui.completionist.locked_mode", before.name, p.total, p.done)
                }
            }
            ChallengeRow(
                item = ChallengeItem(itemId = -(10 + tier), name = LocalizedText(camo.name), imageURL = camo.imageURL,
                    requirement = t.masteryRequirement(mode, id, tier), children = emptyList()),
                accent = camo.tint,
                amount = t.weaponMasteryAmount(mode, id, tier),
                isDone = t.isWeaponMasteryComplete(mode, id, tier),
                isAvailable = t.isWeaponMasteryAvailable(mode, id, tier),
                lockedReason = lockedReason, titleGradient = camo.colors,
                onToggle = { t.toggleWeaponMastery(mode, id, tier) },
                onSetAmount = { t.setWeaponMasteryAmount(mode, id, tier, it) },
            )
        }
    }
}

// MARK: - Military summary

/** The level-earned Military camos in one card: their swatches, how many are earned, what the next needs. */
@Composable
private fun MilitarySummary(mode: String, weapon: WeaponEntry, camos: List<ChallengeItem>, expanded: Boolean, onToggle: () -> Unit) {
    val t = tracker()
    val id = weapon.weaponId
    val textAccent = modeTextAccent(mode)
    val accent = modeAccent(mode)
    fun done(camo: ChallengeItem) = t.isCamoComplete(mode, id, camo)
    val earned = camos.count(::done)
    val next = camos.firstOrNull { !done(it) }
    val nextText = next?.let { t.militaryLevel(mode, id, it) }?.let { levelGateText(t, it, id, if (t.quickTick) "reach" else "locked") }
        ?: L("mw4.ui.military.all_earned")
    val turn by animateFloatAsState(if (expanded) 180f else 0f, label = "chevron")
    Column(
        Modifier.fillMaxWidth().clickable(onClick = onToggle).padding(vertical = 8.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(L("mw4.ui.military.count", earned, camos.size), style = displayStyle(15.sp), color = Ink.text, modifier = Modifier.weight(1f))
            Text(L(if (expanded) "mw4.ui.military.hide" else "mw4.ui.military.show"), style = sys(13f, FontWeight.SemiBold), color = textAccent)
            Icon(Icons.Filled.ExpandMore, null, tint = textAccent, modifier = Modifier.size(18.dp).rotate(turn))
        }
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            for (camo in camos) {
                Box {
                    CamoThumbnail(camo.imageURL, 28.dp, camo.name.resolved(), modifier = Modifier.alpha(if (done(camo)) 1f else 0.35f))
                    if (done(camo)) {
                        Icon(
                            Icons.Filled.CheckCircle, null, tint = accent,
                            modifier = Modifier.align(Alignment.BottomEnd).offset(3.dp, 3.dp).size(12.dp)
                                .clip(CircleShape).background(LocalPalette.current.surface),
                        )
                    }
                }
            }
        }
        Text(nextText, style = sys(13f), color = Ink.muted)
    }
}

// MARK: - Prestige camos

/** The Weapon Prestige camos: a one-line count, opening to their rows. Open or shut for every weapon. */
@Composable
private fun PrestigeCamosBlock(mode: String, weapon: WeaponEntry) {
    val t = tracker()
    val id = weapon.weaponId
    val count = t.prestigeCamos.size
    if (count == 0) return
    var open by Prefs.bool(Prefs.PRESTIGE_CAMOS_OPEN, false)
    val done = t.prestigeCamos.indices.count { t.isPrestigeCamoComplete(id, it) }
    val turn by animateFloatAsState(if (open) 90f else 0f, label = "chevron")
    Column(verticalArrangement = Arrangement.spacedBy(4.dp), modifier = Modifier.animated()) {
        CardDivider()
        Row(
            Modifier.fillMaxWidth().clickable { open = !open }.padding(vertical = 6.dp),
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Text(L("mw4.ui.prestige_camos"), style = sys(12f, FontWeight.SemiBold), color = Ink.muted, modifier = Modifier.weight(1f))
            Text("$done/$count", style = sys(13f, FontWeight.Bold), color = if (done == count) modeAccent(mode) else Ink.text)
            Icon(Icons.Filled.ChevronRight, null, tint = Ink.muted, modifier = Modifier.size(16.dp).rotate(turn))
        }
        if (open) {
            t.prestigeCamos.forEachIndexed { index, camo -> PrestigeCamoRow(mode, weapon, index, camo) }
        }
    }
}

/** A Weapon Prestige camo, earned by the weapon's Prestige and level in every mode at once. */
@Composable
private fun PrestigeCamoRow(mode: String, weapon: WeaponEntry, index: Int, camo: PrestigeCamo) {
    val t = tracker()
    val id = weapon.weaponId
    val stage = t.prestigeCamoStage(camo)
    val detail = when {
        stage == null -> null
        camo.weaponsNeeded != null -> {
            val needed = camo.weaponsNeeded!!
            L("ct.ui.prestige_camo.weapons", t.prestigeStages[stage - 1].name.resolved(), camo.level ?: 1, needed,
                minOf(t.prestigeCamoWeaponCount(camo), needed))
        }
        else -> t.prestigeCamoLevel(camo, id)?.let { L("mw4.ui.prestige_camo.level", t.prestigeStages[stage - 1].name.resolved(), it) }
            ?: L("mw4.ui.prestige_camo.enter", weapon.name.resolved())
    }
    ChallengeRow(
        item = ChallengeItem(itemId = -1 - index, name = t.prestigeCamoName(camo, id), imageURL = t.prestigeCamoImageURL(camo, id),
            children = emptyList(), group = "prestige"),
        accent = modeAccent(mode), amount = 0,
        isDone = t.isPrestigeCamoComplete(id, index),
        titleGradient = colorsOf(t.prestigeCamoColors(camo, index, id)),
        detail = detail,
        onToggle = { t.togglePrestigeCamo(id, index) },
        onSetAmount = {},
    )
}

// MARK: - Level and Prestige

/**
 * The level (or unlocks) stepper: −/+ to nudge, the number to type one,
 * MAX to jump to the cap, a bar under it; then the Prestige line.
 */
@Composable
private fun CompactLevelRow(mode: String, weapon: WeaponEntry) {
    val t = tracker()
    val id = weapon.weaponId
    val accent = modeAccent(mode)
    val level = t.level(id)
    val maxLevel = t.maxLevel(weapon)
    val prestige = t.prestige(id)
    val stageCount = t.prestigeStages.size
    val countsUnlocks = t.countsUnlocks(id)
    val shown = if (countsUnlocks) GameTracker.unlocks(level) else level
    val shownMax = if (countsUnlocks) GameTracker.unlocks(maxLevel) else maxLevel
    val stepperName = if (prestige > 0) t.prestigeName(id)?.resolved() ?: L("mw4.ui.weapon_level")
    else L(if (countsUnlocks) "mw4.ui.weapon_unlocks" else "mw4.ui.weapon_level")
    fun setShown(value: Int) = t.setLevel(if (countsUnlocks) GameTracker.levelForUnlocks(value) else value, weapon)
    var showsHint by remember { mutableStateOf(false) }
    var entering by remember { mutableStateOf(false) }
    var prestigeCamosOpen by Prefs.bool(Prefs.PRESTIGE_CAMOS_OPEN, false)
    val bar by animateFloatAsState(if (maxLevel > 0) level.toFloat() / maxLevel else 0f, label = "level")

    Column(verticalArrangement = Arrangement.spacedBy(12.dp), modifier = Modifier.animated()) {
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                Text(stepperName, style = sys(12f, FontWeight.SemiBold), color = Ink.muted, maxLines = 1)
                if (countsUnlocks && prestige == 0) {
                    Icon(
                        if (showsHint) Icons.Filled.Info else Icons.Outlined.Info, L("mw4.ui.unlocks_hint"), tint = Ink.muted,
                        modifier = Modifier.size(16.dp).clip(CircleShape).clickable { showsHint = !showsHint },
                    )
                }
                Spacer(Modifier.weight(1f).widthIn(min = 4.dp))
                StepButton(Icons.Filled.Remove, shown > 0, 26.dp, accent) { setShown(shown - 1) }
                Text(
                    buildAnnotatedString {
                        withStyle(displayStyle(20.sp).toSpanStyle().copy(color = Ink.text)) { append("$shown") }
                        withStyle(displayStyle(12.sp).toSpanStyle().copy(color = Ink.muted)) { append("/$shownMax") }
                    },
                    maxLines = 1,
                    modifier = Modifier.widthIn(min = 56.dp).clickable { entering = true },
                    textAlign = androidx.compose.ui.text.style.TextAlign.Center,
                )
                StepButton(Icons.Filled.Add, shown < shownMax, 26.dp, accent) { setShown(shown + 1) }
                val atMax = level == maxLevel
                Text(
                    L("mw4.ui.max"), style = sys(10f, FontWeight.Bold), color = if (atMax) Ink.muted else accent, maxLines = 1,
                    modifier = Modifier.clip(CircleShape)
                        .border(1.dp, if (atMax) Ink.muted.copy(alpha = 0.3f) else accent.copy(alpha = 0.6f), CircleShape)
                        .clickable(enabled = !atMax) { t.setLevel(maxLevel, weapon) }
                        .padding(horizontal = 8.dp, vertical = 6.dp),
                )
            }
            Box(Modifier.fillMaxWidth().height(4.dp).clip(CircleShape).background(Ink.muted.copy(alpha = 0.2f))) {
                Box(Modifier.fillMaxHeight().fillMaxWidth(bar).clip(CircleShape).background(accent))
            }
        }
        if (countsUnlocks && showsHint) {
            Text(L("mw4.ui.unlocks_hint"), style = sys(11f), color = Ink.muted)
        }
        if (stageCount > 0) {
            val hint = if (countsUnlocks) L("mw4.ui.prestige.hint_unlocks", shownMax) else L("mw4.ui.prestige.hint", maxLevel)
            if (stageCount == 1) {
                when {
                    prestige > 0 -> Row(
                        Modifier.clickable { t.prestigeDown(weapon) }.padding(vertical = 4.dp),
                        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp),
                    ) {
                        Icon(Icons.AutoMirrored.Filled.Undo, null, tint = Ink.muted, modifier = Modifier.size(14.dp))
                        Text(L("mw4.ui.prestige.undo"), style = sys(12f, FontWeight.SemiBold), color = Ink.muted)
                    }
                    t.canPrestige(weapon) -> Row(
                        Modifier.fillMaxWidth().height(38.dp).clip(CircleShape).background(accent)
                            .clickable { t.prestigeUp(weapon); prestigeCamosOpen = true },
                        horizontalArrangement = Arrangement.Center, verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Icon(Icons.Filled.KeyboardDoubleArrowUp, null, tint = LocalPalette.current.background, modifier = Modifier.size(18.dp))
                        Spacer(Modifier.width(6.dp))
                        Text(L("mw4.ui.prestige"), style = sys(14f, FontWeight.Bold), color = LocalPalette.current.background)
                    }
                    else -> Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        Icon(Icons.Filled.Lock, null, tint = Ink.muted, modifier = Modifier.size(11.dp))
                        Text(hint, style = sys(12f, FontWeight.SemiBold), color = Ink.muted)
                    }
                }
            } else {
                StagedPrestigeLine(mode, weapon, hint) { prestigeCamosOpen = true }
            }
        }
    }
    if (entering) {
        NumberDialog(
            title = L(if (countsUnlocks) "mw4.ui.set_unlocks.title" else "mw4.ui.set_level.title"),
            message = L("mw4.ui.set_level.message", 0, shownMax),
            initial = shown, onDismiss = { entering = false }, onSave = { setShown(it) },
        )
    }
}

/** Several Prestige stages: pips and the stage's name, undo, and a button named after the next stage. */
@Composable
private fun StagedPrestigeLine(mode: String, weapon: WeaponEntry, hint: String, onPrestiged: () -> Unit) {
    val t = tracker()
    val id = weapon.weaponId
    val accent = modeAccent(mode)
    val prestige = t.prestige(id)
    val stageCount = t.prestigeStages.size
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(5.dp)) {
                Text(L("mw4.ui.prestige"), style = sys(12f, FontWeight.SemiBold), color = Ink.muted)
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    if (stageCount <= 8) {
                        Row(horizontalArrangement = Arrangement.spacedBy(3.dp)) {
                            repeat(stageCount) { index ->
                                Box(Modifier.size(14.dp, 5.dp).clip(CircleShape).background(if (index < prestige) accent else Ink.muted.copy(alpha = 0.25f)))
                            }
                        }
                    } else {
                        Text("$prestige/$stageCount", style = sys(10f, FontWeight.Bold, mono = true), color = Ink.muted)
                    }
                    Text(
                        t.prestigeName(id)?.resolved() ?: L("mw4.ui.prestige.none"), style = sys(13f, FontWeight.Bold),
                        color = if (prestige > 0) accent else Ink.muted, maxLines = 1,
                    )
                }
            }
            if (prestige > 0) {
                Box(
                    Modifier.size(28.dp).clip(CircleShape).border(1.dp, Ink.muted.copy(alpha = 0.35f), CircleShape).clickable { t.prestigeDown(weapon) },
                    contentAlignment = Alignment.Center,
                ) { Icon(Icons.AutoMirrored.Filled.Undo, L("mw4.ui.prestige.undo"), tint = Ink.muted, modifier = Modifier.size(13.dp)) }
            }
            if (prestige < stageCount) {
                val ready = t.canPrestige(weapon)
                Row(
                    Modifier.height(28.dp).clip(CircleShape).background(if (ready) accent else Ink.muted.copy(alpha = 0.14f))
                        .clickable(enabled = ready) { t.prestigeUp(weapon); onPrestiged() }.padding(horizontal = 11.dp),
                    verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp),
                ) {
                    val ink = if (ready) LocalPalette.current.background else Ink.muted
                    Icon(if (ready) Icons.Filled.KeyboardDoubleArrowUp else Icons.Filled.Lock, null, tint = ink, modifier = Modifier.size(12.dp))
                    Text(t.prestigeStages[prestige].name.resolved(), style = sys(12f, FontWeight.Bold), color = ink, maxLines = 1)
                }
            } else {
                Icon(Icons.Filled.Verified, null, tint = accent, modifier = Modifier.size(20.dp))
            }
        }
        if (prestige < stageCount && t.level(id) < t.maxLevel(weapon)) {
            Text(hint, style = sys(11f), color = Ink.muted)
        }
    }
}
