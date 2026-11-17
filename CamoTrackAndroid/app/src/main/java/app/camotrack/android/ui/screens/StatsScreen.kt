package app.camotrack.android.ui.screens

import androidx.compose.animation.animateContentSize
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material.icons.filled.GpsFixed
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.filled.WorkspacePremium
import androidx.compose.material.icons.outlined.Email
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.camotrack.android.core.GameTracker
import app.camotrack.android.core.HexColor
import app.camotrack.android.i18n.L
import app.camotrack.android.ui.*
import app.camotrack.android.ui.share.ShareRequest
import app.camotrack.android.ui.share.Sharing

/**
 * The Stats tab (iOS StatsView): an overall ring, then a weapons card (one
 * where camos count in every mode, else one per mode), each mode's Mastery,
 * the game's own camos, and the support address at the foot. The share
 * button makes the progress card.
 */
@Composable
fun StatsScreen() {
    val t = tracker()
    val modes = t.visibleModes
    val hasMastery = t.game.hasAccountMastery
    // Something on the card besides 0%: a brand-new player has nothing to share yet
    val hasProgress = modes.any { t.trueCompletionFraction(it) >= 0.01 }
    Column(Modifier.fillMaxSize().appBackground(ModeColors.multiplayer)) {
        TopBar(L("mw4.ui.tab.stats"), onBack = null) {
            if (hasProgress) IconButton(onClick = { Sharing.open(ShareRequest.Progress) }) {
                Icon(Icons.Filled.Share, L("mw4.ui.share.title"), tint = MaterialTheme.colorScheme.primary)
            }
        }
        BoxWithConstraints(Modifier.fillMaxSize()) {
            val wide = maxWidth >= 600.dp
            LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(horizontal = 12.dp, vertical = 6.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                item(key = "hero") { OverallStatsHero(t) }
                // One weapons card where camos count in every mode (MW4), else one per mode
                val weaponModes = if (t.game.sharedCamos == true) modes.take(1) else modes
                for (mode in weaponModes) item(key = "w-$mode") { ModeStatsCard(t, mode, weapons = true) }
                if (hasMastery) {
                    if (wide) item(key = "mastery-row") {
                        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                            for (mode in modes) Box(Modifier.weight(1f)) { ModeStatsCard(t, mode, weapons = false) }
                        }
                    } else {
                        for (mode in modes) item(key = "m-$mode") { ModeStatsCard(t, mode, weapons = false) }
                    }
                }
                if (t.gameCamoProgress.isNotEmpty()) item(key = "game-camos") { GameCamosStatsCard(t) }
                if (hasMastery && t.game.capstone != null) item(key = "global") { GlobalMasteryStatsCard(t) }
                item(key = "support") { SupportRow() }
            }
        }
    }
}

/** One big ring (the average of every mode's own completion) and each mode's figure under it. */
@Composable
private fun OverallStatsHero(t: GameTracker) {
    val perMode = t.visibleModes.map { it to t.trueCompletionFraction(it) }
    val overall = if (perMode.isEmpty()) 0.0 else perMode.sumOf { it.second } / perMode.size
    Column(
        Modifier.fillMaxWidth().borderedCard().padding(vertical = 20.dp),
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        ProgressRing(overall, CamoGold, lineWidth = 10.dp, size = 110.dp)
        Text(L("mw4.ui.stats.overall").uppercase(appLocale), style = sys(12f, FontWeight.Bold), color = Ink.muted)
        Row(Modifier.fillMaxWidth()) {
            for ((mode, fraction) in perMode) {
                Column(Modifier.weight(1f), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Icon(modeIcon(mode), null, tint = modeAccent(mode), modifier = Modifier.size(15.dp))
                    Text(percentText(fraction), style = sys(14f, FontWeight.Bold, mono = true), color = Ink.text)
                    Text(modeName(mode), style = sys(10f), color = Ink.muted, maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
            }
        }
    }
}

/** A stop on a track: a camo, whether it's earned, and its count. */
data class TrackNode(val name: String, val color: Color, val gradient: List<Color>, val achieved: Boolean, val detail: String)

/** Circles joined by a line, each lit once earned, with the name and count under it (iOS MasteryTrack). */
@Composable
fun MasteryTrack(nodes: List<TrackNode>) {
    val surface2 = LocalPalette.current.surface2
    val ground = LocalPalette.current.background
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            nodes.forEachIndexed { index, node ->
                // Each circle sits in the middle of its label's column
                Box(Modifier.weight(1f), contentAlignment = Alignment.Center) {
                    if (index > 0) Box(Modifier.align(Alignment.CenterStart).fillMaxWidth(0.5f).height(2.dp)
                        .background(if (nodes[index - 1].achieved) nodes[index - 1].color.copy(alpha = 0.6f) else Ink.muted.copy(alpha = 0.25f)))
                    if (index < nodes.size - 1) Box(Modifier.align(Alignment.CenterEnd).fillMaxWidth(0.5f).height(2.dp)
                        .background(if (node.achieved) node.color.copy(alpha = 0.6f) else Ink.muted.copy(alpha = 0.25f)))
                    Box(
                        Modifier.size(20.dp).clip(CircleShape).background(if (node.achieved) node.color else surface2)
                            .then(if (node.achieved) Modifier else Modifier.border(1.5.dp, node.color, CircleShape)),
                        contentAlignment = Alignment.Center,
                    ) {
                        if (node.achieved) Icon(Icons.Filled.Check, null, tint = ground, modifier = Modifier.size(12.dp))
                    }
                }
            }
        }
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.Top) {
            for (node in nodes) {
                Column(Modifier.weight(1f), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    if (node.achieved) {
                        AnimatedGradientText(node.name, node.gradient, size = 10.5f, weight = FontWeight.SemiBold, textAlign = TextAlign.Center, maxLines = 2)
                    } else {
                        Text(node.name, style = sys(10.5f, FontWeight.SemiBold), color = Ink.text, textAlign = TextAlign.Center, maxLines = 2)
                    }
                    Text(node.detail, style = sys(9.5f, mono = true), color = Ink.muted, textAlign = TextAlign.Center, maxLines = 1)
                }
            }
        }
    }
}

/**
 * A mode's card: the weapons (Completionist, 100%+, badges and each class)
 * or its Mastery (the three tiers and its objectives), with its completion
 * ring and a breakdown to fold away.
 */
@Composable
private fun ModeStatsCard(t: GameTracker, mode: String, weapons: Boolean) {
    var expanded by rememberSaveable(mode, weapons) { mutableStateOf(true) }
    val accent = modeAccent(mode)
    val completion = t.trueCompletionFraction(mode)
    val categories = t.categories(mode)
    val objectives = t.modes[mode]?.objectives.orEmpty()
    // Black Ops has a card per mode, each with every class: two columns keep them short
    val twoColumns = !t.game.hasAccountMastery
    val ownGrind = weapons && t.game.sharedCamos != true

    Column(
        Modifier.fillMaxWidth().borderedCard(accent = accent).padding(14.dp).animateContentSize(),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Icon(if (weapons && !ownGrind) app.camotrack.android.ui.Glyphs.painter(app.camotrack.android.ui.Glyphs.tabWeapons, Icons.Filled.GpsFixed) else modeIcon(mode), null, tint = accent, modifier = Modifier.size(17.dp))
            Text(
                when {
                    ownGrind -> modeName(mode)
                    weapons -> L("mw4.ui.section.weapons")
                    else -> "${modeName(mode)} ${L("mw4.ui.section.mastery")}"
                },
                style = displayStyle(17.sp), color = Ink.text, modifier = Modifier.weight(1f), maxLines = 2,
            )
            Box(contentAlignment = Alignment.Center) {
                ProgressRing(completion, accent, lineWidth = 5.dp, size = 42.dp, showsPercentage = false, shimmer = t.masteryCamos(mode)[2].colors)
                Text(percentText(completion), style = sys(11f, FontWeight.Bold, mono = true), color = modeTextAccent(mode))
            }
        }

        if (weapons) {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                TrackTitle(L(if (t.game.hasAccountMastery) "mw4.ui.section.completionist" else "mw4.ui.section.mastery"))
                MasteryTrack(completionistNodes(t, mode))
            }
            // Each weapon's badges and Prestige camos, counted across the mode's weapons
            for (section in t.extraStats(mode)) {
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    TrackTitle(section.title?.resolved() ?: L("mw4.ui.section.camos"))
                    StatRows(twoColumns, section.rows.map { row ->
                        StatLine(row.name.resolved(), if (row.total > 0) row.done.toDouble() / row.total else 0.0, "${row.done}/${row.total}")
                    }, accent)
                }
            }
        } else {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                TrackTitle(L("mw4.ui.section.mastery"))
                MasteryTrack(t.masteryCamos(mode).mapIndexed { index, camo ->
                    val p = t.masteryProgress(mode, index + 1)
                    TrackNode(camo.name, camo.tint, camo.colors, t.isMasteryAchieved(mode, index + 1), "${p.done}/${p.total}")
                })
            }
        }

        if ((weapons && categories.isNotEmpty()) || (!weapons && objectives.isNotEmpty())) {
            val turn by animateFloatAsState(if (expanded) 180f else 0f, label = "chevron")
            Row(Modifier.fillMaxWidth().clickable { expanded = !expanded }, verticalAlignment = Alignment.CenterVertically) {
                Text(L("mw4.ui.stats.breakdown"), style = sys(12f, FontWeight.SemiBold), color = Ink.muted, modifier = Modifier.weight(1f))
                Icon(Icons.Filled.ExpandMore, null, tint = Ink.muted, modifier = Modifier.size(18.dp).rotate(turn))
            }
            if (expanded) {
                val last = t.lastCompletionist(mode).name
                val lines = if (weapons) categories.map { category ->
                    // The whole track: a class at Divergence reads as further on than one with only its camos
                    StatLine(category.name.resolved(), t.categoryTrueCompletionFraction(category, mode),
                        "${t.categoryLastCompletionistCount(category, mode)}/${category.weapons.size} $last")
                } else objectives.map { StatLine(it.name.resolved(), t.objectiveProgressFraction(it, mode), null) }
                StatRows(twoColumns, lines, accent)
            }
        }
    }
}

private data class StatLine(val name: String, val fraction: Double, val count: String?)

@Composable
private fun TrackTitle(title: String) {
    Text(title, style = sys(12f, FontWeight.SemiBold), color = Ink.muted, modifier = Modifier.fillMaxWidth())
}

@Composable
private fun StatRows(twoColumns: Boolean, lines: List<StatLine>, accent: Color) {
    if (twoColumns) {
        Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
            for (pair in lines.chunked(2)) {
                Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                    for (i in 0..1) Box(Modifier.weight(1f)) { pair.getOrNull(i)?.let { CompactStatRow(it, accent) } }
                }
            }
        }
    } else {
        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) { for (line in lines) WideStatRow(line, accent) }
    }
}

/** Half a card wide: the name and percentage over the bar, the count under it. */
@Composable
private fun CompactStatRow(line: StatLine, accent: Color) {
    Column(verticalArrangement = Arrangement.spacedBy(5.dp)) {
        Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            Text(line.name, style = sys(13f), color = Ink.text, maxLines = 2, modifier = Modifier.weight(1f))
            Text(percentText(line.fraction), style = sys(12f, mono = true), color = Ink.muted)
        }
        ProgressBar(line.fraction, accent)
        line.count?.let { Text(it, style = sys(11f, mono = true), color = Ink.muted, maxLines = 1) }
    }
}

@Composable
private fun WideStatRow(line: StatLine, accent: Color) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(line.name, style = sys(13f), color = Ink.text, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f, fill = false))
                line.count?.let { Text(it, style = sys(11f, mono = true), color = Ink.muted, maxLines = 1) }
            }
            ProgressBar(line.fraction, accent)
        }
        Text(percentText(line.fraction), style = sys(12f, mono = true), color = Ink.muted)
    }
}

/** Gold, Platinum, Harmonic Break and the final camo (out of the launch roster), then 100%+ once that's full. */
private fun completionistNodes(t: GameTracker, mode: String): List<TrackNode> {
    val total = t.launchRoster(mode)
    val nodes = t.completionistCamos(mode).mapIndexed { index, camo ->
        val done = t.launchProgress(t.completionistCount(mode, index), mode).done
        TrackNode(camo.name, camo.tint, camo.colors, total > 0 && done >= total, "$done/$total")
    }.toMutableList()
    if (nodes.lastOrNull()?.achieved == true) {
        val full = t.fullRosterFinalProgress(mode)
        nodes += TrackNode(L("mw4.ui.stats.100_plus"), PlatinumColors[0], PlatinumColors, full.total > 0 && full.done >= full.total, "${full.done}/${full.total}")
    }
    return nodes
}

/** Black Ops' camos earned across the game, each with its count. */
@Composable
private fun GameCamosStatsCard(t: GameTracker) {
    val accent = hexColor(t.game.theme?.accent) ?: CamoGold
    Column(Modifier.fillMaxWidth().borderedCard(accent = accent).padding(14.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Icon(Icons.Filled.WorkspacePremium, null, tint = accent, modifier = Modifier.size(17.dp))
            Text(L("ct.ui.stats.game_camos"), style = displayStyle(17.sp), color = Ink.text)
        }
        for (camo in t.gameCamoProgress) {
            val colors = colorsOf(camo.gradient)
            val fraction = if (camo.total > 0) camo.done.toDouble() / camo.total else 0.0
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(camo.name.resolved(), style = displayStyle(14.sp).copy(brush = Brush.horizontalGradient(colors.ifEmpty { GoldColors }.let { if (it.size > 1) it else it + it })),
                        modifier = Modifier.weight(1f))
                    Text("${camo.done}/${camo.total}", style = sys(12f, mono = true), color = Ink.muted)
                }
                ProgressBar(fraction, colors.firstOrNull() ?: accent)
            }
        }
    }
}

/** MW4's Flashpoint: each mode's three Mastery camos, then the camo for having all of them. */
@Composable
private fun GlobalMasteryStatsCard(t: GameTracker) {
    val capstone = t.game.capstone ?: return
    val progress = t.globalMasteryProgress
    val fraction = if (progress.total > 0) progress.done.toDouble() / progress.total else 0.0
    val colors = colorsOf(HexColor.parseAll(capstone.colors))
    val accent = colors.firstOrNull() ?: CamoGold
    val modes = t.modeIds.filter { t.modes[it] != null }
    val nodes = modes.map { mode ->
        val done = (1..3).count { t.isMasteryAchieved(mode, it) }
        TrackNode(modeName(mode), modeAccent(mode), t.masteryCamos(mode)[2].colors, done == 3, "$done/3")
    } + TrackNode(capstone.name.resolved(), accent, colors.ifEmpty { GoldColors }, t.isGlobalMasteryAchieved, "${progress.done}/${progress.total}")
    Column(Modifier.fillMaxWidth().borderedCard(accent = accent).padding(14.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Icon(Icons.Filled.WorkspacePremium, null, tint = accent, modifier = Modifier.size(17.dp))
            Text(L("ct.mastery.global"), style = displayStyle(17.sp), color = Ink.text, modifier = Modifier.weight(1f))
            Box(contentAlignment = Alignment.Center) {
                ProgressRing(fraction, accent, lineWidth = 5.dp, size = 42.dp, showsPercentage = false, shimmer = colors.ifEmpty { GoldColors })
                Text(percentText(fraction), style = sys(11f, FontWeight.Bold, mono = true), color = Ink.text)
            }
        }
        MasteryTrack(nodes)
    }
}

/** Support contact at the foot of Stats. */
@Composable
private fun SupportRow() {
    val context = LocalContext.current
    Row(
        Modifier.fillMaxWidth().padding(top = 2.dp, bottom = 12.dp).borderedCard().clickable { SupportMail.open(context) }.padding(12.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Icon(Icons.Outlined.Email, null, tint = Ink.muted, modifier = Modifier.size(15.dp))
        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(L("mw4.ui.support"), style = sys(12f, FontWeight.SemiBold), color = Ink.muted)
            Text(SupportMail.ADDRESS, style = sys(12f, mono = true), color = Ink.muted)
        }
    }
}
