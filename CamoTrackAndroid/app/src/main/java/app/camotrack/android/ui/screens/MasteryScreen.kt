package app.camotrack.android.ui.screens

import android.icu.text.ListFormatter
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.WorkspacePremium
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import app.camotrack.android.AppState
import app.camotrack.android.core.BuiltInColors
import app.camotrack.android.core.CompletionistGate
import app.camotrack.android.core.GameTracker
import app.camotrack.android.core.HexColor
import app.camotrack.android.core.MasteryKind
import app.camotrack.android.i18n.L
import app.camotrack.android.ui.*

/**
 * Mastery, the one part of the grind that's per mode: every mode played, one
 * under the other, each with its three Mastery camos to tick and count; the
 * game's capstone under them (iOS MasteryTabView). A Black Ops game shows
 * its camos earned across the game, then each mode's Mastery camos.
 */
@Composable
fun MasteryScreen() {
    val t = tracker()
    // The mode picked in the Weapons title goes first
    val modes = t.visibleModes.let { all -> listOf(AppState.mode) + all.filter { it != AppState.mode } }
    val hasMastery = t.game.hasAccountMastery
    val capstone = t.game.capstone
    val gameAccent = hexColor(t.game.theme?.accent) ?: CamoGold
    Column(Modifier.fillMaxSize().appBackground(modeAccent(modes.first()))) {
        TopBar(L("mw4.ui.section.mastery"), onBack = null)
        LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(bottom = 24.dp)) {
            if (!hasMastery && (capstone != null || t.prestigeCamos.any { it.weaponsNeeded != null })) {
                item(key = "game-camos") {
                    // Not sparkles: across the app those mean Premium
                    SectionHeading(L("ct.ui.stats.game_camos"), Icons.Filled.WorkspacePremium, gameAccent)
                    SectionCard { GameCamoRows(t) }
                }
            }
            for (mode in modes) {
                item(key = "mode-$mode") {
                    SectionHeading(modeName(mode), modeIcon(mode), modeTextAccent(mode))
                    SectionCard {
                        if (hasMastery) {
                            for (tier in 1..3) {
                                if (tier > 1) RowRule()
                                MasteryTierRow(t, mode, tier)
                            }
                        } else {
                            TrackCamoRows(t, mode)
                        }
                    }
                }
            }
            if (hasMastery && capstone != null) {
                item(key = "global") {
                    SectionHeading(L("ct.mastery.global"), Icons.Filled.WorkspacePremium, gameAccent)
                    SectionCard {
                        val progress = t.globalMasteryProgress
                        val colors = colorsOf(HexColor.parseAll(capstone.colors))
                        val names = ListFormatter.getInstance(appLocale).format(t.modeIds.filter { t.modes[it] != null }.map(::modeName))
                        StatusRow(
                            capstone.name.resolved(), progress.total > 0 && progress.done >= progress.total,
                            colors.firstOrNull() ?: CamoGold, colors,
                            L("ct.mastery.global.detail", names, progress.done, progress.total), capstone.imageURL,
                        )
                    }
                }
            }
        }
    }
}

/** A section's heading: the mode's symbol and name in its colour. */
@Composable
private fun SectionHeading(title: String, icon: ImageVector, color: Color) {
    Row(
        Modifier.fillMaxWidth().padding(start = 20.dp, end = 20.dp, top = 18.dp, bottom = 6.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Icon(icon, null, tint = color, modifier = Modifier.size(16.dp))
        Text(title.uppercase(appLocale), style = sys(13f, FontWeight.SemiBold), color = color)
    }
}

/** An inset grouped section's rows (an iOS List section). */
@Composable
private fun SectionCard(content: @Composable ColumnScope.() -> Unit) {
    Column(
        Modifier.padding(horizontal = 16.dp).fillMaxWidth().clip(RoundedCornerShape(10.dp))
            .background(LocalPalette.current.surface).padding(horizontal = 14.dp, vertical = 4.dp),
        content = content,
    )
}

@Composable
private fun RowRule() {
    Box(Modifier.fillMaxWidth().height(0.5.dp).background(Ink.muted.copy(alpha = 0.2f)))
}

/**
 * A mode-wide challenge to tick and count (any weapon counts; the weapon
 * only names the milestone), else the read-only status.
 */
@Composable
private fun MasteryTierRow(t: GameTracker, mode: String, tier: Int) {
    val weapon = t.weapons(mode).firstOrNull()
    if (t.masteryKind(mode, tier) == MasteryKind.MODE && weapon != null) {
        MasteryRow(mode, weapon, tier)
        return
    }
    val camo = t.masteryCamos(mode)[tier - 1]
    val progress = t.masteryProgress(mode, tier)
    val requirement = t.modeMasteryRequirement(mode, tier)
    val detail = if (t.masteryKind(mode, tier) == MasteryKind.MODE && requirement != null) {
        "${requirement.description?.resolved().orEmpty()} ${progress.done}/${progress.total}".trim()
    } else {
        L("mw4.ui.mastery.weapons_needed", progress.done, progress.total, t.lastCompletionist(mode).name)
    }
    StatusRow(camo.name, t.isMasteryAchieved(mode, tier), camo.tint, camo.colors, detail, camo.imageURL)
}

/** Cold Snap and Nexus Horizon: camos for progress across every weapon or mode. */
@Composable
private fun GameCamoRows(t: GameTracker) {
    var first = true
    t.prestigeCamos.forEachIndexed { index, camo ->
        val needed = camo.weaponsNeeded ?: return@forEachIndexed
        val done = minOf(t.prestigeCamoWeaponCount(camo), needed)
        val stage = t.prestigeCamoStage(camo)?.let { t.prestigeStages[it - 1].name.resolved() } ?: ""
        val colors = colorsOf(BuiltInColors.prestige(camo, index))
        if (!first) RowRule()
        first = false
        StatusRow(
            camo.name.resolved(), done >= needed, colors.firstOrNull() ?: CamoGold, colors,
            L("ct.ui.prestige_camo.weapons", stage, camo.level ?: 1, needed, done), camo.imageURL,
        )
    }
    t.game.capstone?.let { capstone ->
        val parts = t.capstoneModes
        val colors = colorsOf(HexColor.parseAll(capstone.colors))
        val names = ListFormatter.getInstance(appLocale).format(parts.map { t.completionist(it.first).final.name })
        if (!first) RowRule()
        StatusRow(
            capstone.name.resolved(), parts.isNotEmpty() && parts.all { it.second }, colors.firstOrNull() ?: CamoGold, colors,
            L("ct.mastery.capstone", names, parts.count { it.second }, parts.size), capstone.imageURL,
        )
    }
}

/**
 * A Black Ops mode's Mastery camos (Gold to Dark Matter): weapons with each
 * out of the launch roster, and what still holds it shut. The class camo
 * lists each class still shut under its row; 100%+ follows once the last
 * camo is on the launch roster.
 */
@Composable
private fun TrackCamoRows(t: GameTracker, mode: String) {
    val camos = t.completionistCamos(mode)
    camos.forEachIndexed { index, camo ->
        val count = if (index < GameTracker.COMPLETIONIST_STEP_COUNT) t.completionistCount(mode, index) else t.finalCamoCount(mode)
        val progress = t.launchProgress(count, mode)
        val (gate, classes) = gate(t, mode, index, if (index > 0) camos[index - 1].name else null)
        if (index > 0) RowRule()
        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            StatusRow(
                camo.name, progress.done >= progress.total, camo.tint, camo.colors,
                listOfNotNull(L("ct.mastery.weapons", progress.done, progress.total), gate).joinToString(" "), camo.imageURL,
            )
            if (classes) ClassCounts(t, mode, index)
        }
    }
    val full = t.fullRosterFinalProgress(mode)
    val roster = t.launchRoster(mode)
    val last = camos.lastOrNull()
    if (last != null && t.launchProgress(t.finalCamoCount(mode), mode).done >= roster && full.total > roster) {
        RowRule()
        StatusRow(L("mw4.ui.stats.100_plus"), full.done >= full.total, PlatinumColors[0], PlatinumColors,
            L("mw4.ui.milestone.100_plus_subtitle", last.name))
    }
}

/** What still opens this camo, if anything; and whether it opens class by class. */
private fun gate(t: GameTracker, mode: String, index: Int, before: String?): Pair<String?, Boolean> {
    if (index >= GameTracker.COMPLETIONIST_STEP_COUNT) {
        val needed = t.harmonicBreaksNeeded(mode)
        val have = minOf(t.harmonicBreakCount(mode), needed)
        return (if (have >= needed) null else L("ct.mastery.gate_weapons", before ?: "", needed, have)) to false
    }
    return when (t.completionistGate(mode, index)) {
        CompletionistGate.WEAPON -> {
            val ready = t.launchProgress(t.totalGoldWeaponCount(mode), mode).done
            L("ct.mastery.gate_camos", ready) to false
        }
        CompletionistGate.MODE -> {
            val gate = t.completionistModeGateProgress(mode, index)
            (if (gate.done >= gate.total) null else L("ct.mastery.gate_weapons", before ?: "", gate.total, minOf(gate.done, gate.total))) to false
        }
        CompletionistGate.CATEGORY -> {
            val classes = t.categories(mode)
            val open = classes.count { val p = t.completionistCategoryGateProgress(it, mode, index); p.done >= p.total }
            (if (open >= classes.size) null else L("ct.mastery.gate_class", before ?: "", open, classes.size)) to (open < classes.size)
        }
    }
}

/** The classes still shut, each with its count of the camo before, in two columns. */
@Composable
private fun ClassCounts(t: GameTracker, mode: String, step: Int) {
    val rows = t.categories(mode).map { it to t.completionistCategoryGateProgress(it, mode, step) }.filter { it.second.done < it.second.total }
    val half = (rows.size + 1) / 2
    val accent = modeAccent(mode)
    Row(Modifier.padding(start = 44.dp, bottom = 6.dp), horizontalArrangement = Arrangement.spacedBy(16.dp)) {
        for (column in listOf(rows.take(half), rows.drop(half))) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                for ((category, p) in column) {
                    val color = if (p.done >= p.total) accent else Ink.muted
                    Row {
                        Text(category.name.resolved(), style = sys(12f), color = color, maxLines = 1, modifier = Modifier.weight(1f))
                        Text("${minOf(p.done, p.total)}/${p.total}", style = sys(11f, mono = true), color = color)
                    }
                }
            }
        }
    }
}
