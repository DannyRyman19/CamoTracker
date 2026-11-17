package app.camotrack.android.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.filled.Podcasts
import androidx.compose.material.icons.filled.Verified
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.camotrack.android.core.GameTracker
import app.camotrack.android.core.WeaponEntry
import app.camotrack.android.i18n.L
import app.camotrack.android.ui.*

/**
 * A weapon's card: its picture, name and how it's acquired, the camo pips
 * and Completionist diamonds over the level. Its border takes the best
 * Prestige or Completionist camo earned (Customise > Card outlines).
 * Press and hold for the quick look.
 */
@Composable
fun WeaponRow(mode: String, weapon: WeaponEntry, showsCamoCount: Boolean = true, onClick: () -> Unit) {
    val t = tracker()
    val id = weapon.weaponId
    val camos = t.camos(id, mode)
    val isGold = t.allCamosComplete(id, mode)
    val highest = t.highestCompletionist(mode, id)
    val track = t.completionist(mode)
    fun colorOf(index: Int): Color = if (index < track.steps.size) track.steps[index].tint else track.final.tint
    val outline by Prefs.string(Prefs.CARD_OUTLINE, "prestige")
    val prestigeBorder = t.prestigeCamos.indices.lastOrNull { t.isPrestigeCamoComplete(id, it) }
        ?.let { colorsOf(t.prestigeCamoColors(t.prestigeCamos[it], it, id)) }
    val completionistBorder = highest?.let { if (it < track.steps.size) track.steps[it].colors else track.final.colors }
    val border = when (outline) {
        "completionist" -> completionistBorder ?: prestigeBorder
        "off" -> null
        else -> prestigeBorder ?: completionistBorder
    }
    val accent = highest?.let(::colorOf) ?: if (isGold) modeAccent(mode) else null
    var peeking by remember { mutableStateOf(false) }

    Column(
        Modifier.fillMaxWidth()
            .borderedCard(accent = accent, borderGradient = border)
            // Inside the click, so a hold's release is taken before the card opens
            .clickable(onClick = onClick)
            .onPressHold { peeking = true }
            .padding(12.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        if (showsCamoCount) {
            val counts = t.camoCounts(id, mode)
            Eyebrow("${counts.done}/${counts.total} ${L("mw4.ui.section.camos")}")
        }
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            WeaponThumbnail(weapon.imageURL, 56.dp)
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(weapon.name.resolved(), style = displayStyle(15.sp), color = Ink.text, maxLines = 1, overflow = TextOverflow.Ellipsis)
                AcquiredByLabel(weapon, size = 10.5f)
            }
            Column(horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(4.dp)) {
                if (camos.isNotEmpty()) {
                    CamoPipRow(
                        done = camos.map { t.isCamoComplete(mode, id, it) },
                        filled = modeAccent(mode),
                        tiers = t.completionistCamos(mode).indices.map { ((highest ?: -1) >= it) to colorOf(it) },
                    )
                }
                if (!t.quickTick) {
                    Text(levelText(t, weapon), style = sys(11f, mono = true), color = Ink.muted, maxLines = 1)
                }
            }
        }
        if (peeking) PeekPopup(onDismiss = { peeking = false }) { WeaponPeekMenu(mode, weapon) { peeking = false } }
    }
}

/** "P1 · LVL 12/71" or "17/40 UNLOCKS". */
fun levelText(t: GameTracker, weapon: WeaponEntry): String {
    val id = weapon.weaponId
    val max = t.maxLevel(weapon)
    return if (!t.countsUnlocks(id)) {
        val prestige = t.prestige(id)
        (if (prestige > 0) "P$prestige · " else "") + L("ct.ui.level_short", t.level(id), max)
    } else {
        L("mw4.ui.unlocks_short", GameTracker.unlocks(t.level(id)), GameTracker.unlocks(max))
    }
}

// MARK: - Quick look

private data class PeekCamo(val image: String?, val done: Boolean)
private data class PeekNext(val name: String, val detail: String, val done: Int, val total: Int)

/** The quick look and its actions: tick the next camo, share. */
@Composable
fun WeaponPeekMenu(mode: String, weapon: WeaponEntry, dismiss: () -> Unit) {
    val t = tracker()
    val id = weapon.weaponId
    val nextCamo = t.camos(id, mode).flatMap(t::leafItems).firstOrNull { !t.isCamoComplete(mode, id, it) }
    val track = t.completionist(mode)
    val nextStep = if (nextCamo != null) null else (0 until minOf(track.steps.size, GameTracker.COMPLETIONIST_STEP_COUNT))
        .firstOrNull { !t.isCompletionistComplete(mode, id, it) }
        ?.takeIf { t.isCompletionistAvailable(mode, id, it) }
    Column(Modifier.width(340.dp).heightIn(max = 460.dp).verticalScroll(rememberScrollState())) {
        WeaponPeek(mode, weapon)
        if (nextCamo != null) {
            PeekAction(L("ct.peek.mark_done", nextCamo.name.resolved()), Icons.Outlined.CheckCircle) { t.toggleCamo(mode, id, nextCamo) }
        } else if (nextStep != null) {
            PeekAction(L("ct.peek.mark_done", track.steps[nextStep].name), Icons.Outlined.CheckCircle) { t.toggleCompletionist(mode, id, nextStep) }
        }
        // Only while the overlay is on: it puts this gun on stream
        val overlay = app.camotrack.android.services.StreamOverlay
        val onOverlay = overlay.content == app.camotrack.android.services.StreamOverlay.Content.weapon &&
            overlay.mode == mode && overlay.weaponId(t.game.id) == id
        if (overlay.isOn && !onOverlay) {
            PeekAction(L("ct.peek.overlay"), Icons.Filled.Podcasts) {
                overlay.changeMode(mode)
                overlay.changeContent(app.camotrack.android.services.StreamOverlay.Content.weapon)
                overlay.setWeapon(id, t.game.id)
                dismiss()
            }
        }
        PeekAction(L("mw4.ui.share.button"), Icons.Filled.Share) {
            dismiss()
            app.camotrack.android.ui.share.Sharing.open(app.camotrack.android.ui.share.ShareRequest.Weapon(id, mode))
        }
    }
}

@Composable
private fun PeekAction(title: String, icon: ImageVector, run: () -> Unit) {
    CardDivider()
    Row(
        Modifier.fillMaxWidth().clickable(onClick = run).padding(horizontal = 16.dp, vertical = 13.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(title, style = sys(16f), color = Ink.text, modifier = Modifier.weight(1f))
        Icon(icon, null, tint = Ink.text, modifier = Modifier.size(20.dp))
    }
}

/** The quick look: the same figures the stream overlay shows for a weapon. */
@Composable
private fun WeaponPeek(mode: String, weapon: WeaponEntry) {
    val t = tracker()
    val id = weapon.weaponId
    val accent = modeAccent(mode)
    val leaves = t.camos(id, mode).flatMap(t::leafItems)
    val completionist = t.completionistCamos(mode)
    fun stepDone(step: Int) = if (step >= GameTracker.COMPLETIONIST_STEP_COUNT) t.hasFinalCamo(mode, id) else t.isCompletionistComplete(mode, id, step)
    val camoRow = leaves.map { PeekCamo(it.imageURL, t.isCamoComplete(mode, id, it)) } +
        completionist.mapIndexed { step, camo -> PeekCamo(camo.imageURL, stepDone(step)) } +
        t.prestigeCamos.mapIndexed { index, camo -> PeekCamo(t.prestigeCamoImageURL(camo, id), t.isPrestigeCamoComplete(id, index)) }
    val levelLine = L("ct.overlay.level", t.level(id), t.maxLevel(weapon))
    val badge = t.prestigeName(id)?.let { "${it.resolved()} · $levelLine" } ?: levelLine
    val next: PeekNext? = run {
        val camo = leaves.firstOrNull { !t.isCamoComplete(mode, id, it) }
        if (camo != null) {
            val requirement = camo.requirement
            if (requirement != null) {
                val current = requirement.byMode?.firstOrNull { it.mode == mode }?.description?.resolved()
                return@run PeekNext(camo.name.resolved(), current ?: requirement.description.resolved(), t.camoAmount(mode, id, camo), maxOf(requirement.amount, 1))
            }
            val level = t.militaryLevel(mode, id, camo)
            if (level != null) return@run PeekNext(camo.name.resolved(), levelGateText(t, level, id, "reach"), minOf(t.level(id), level), maxOf(level, 1))
            return@run PeekNext(camo.name.resolved(), "", 0, 1)
        }
        val step = completionist.indices.firstOrNull { !stepDone(it) } ?: return@run null
        val requirement = t.completionistRequirement(mode, id, step)
        if (requirement != null) {
            PeekNext(completionist[step].name, requirement.description.resolved(), minOf(t.completionistAmount(mode, id, step), requirement.amount), maxOf(requirement.amount, 1))
        } else PeekNext(completionist[step].name, "", 0, 1)
    }
    Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            WeaponThumbnail(weapon.imageURL, 64.dp)
            Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(weapon.name.resolved(), style = displayStyle(20.sp), color = Ink.text, maxLines = 1)
                Text("${modeName(mode)} · $badge", style = sys(13f), color = Ink.muted, maxLines = 2)
            }
        }
        if (camoRow.isNotEmpty()) {
            camoRow.chunked(10).forEach { row ->
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    row.forEach { CamoThumbnail(it.image, 26.dp, modifier = Modifier.alpha(if (it.done) 1f else 0.3f), peeks = false) }
                }
            }
            Text(L("ct.peek.camos", camoRow.count { it.done }, camoRow.size), style = sys(12f, FontWeight.SemiBold), color = Ink.muted)
        }
        if (next != null) {
            Column(
                Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(LocalPalette.current.surface2).padding(12.dp),
                verticalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(next.name, style = sys(17f, FontWeight.SemiBold), color = accent, modifier = Modifier.weight(1f))
                    if (next.total > 1) Text("${next.done}/${next.total}", style = sys(15f, FontWeight.SemiBold, mono = true), color = Ink.text)
                }
                if (next.detail.isNotEmpty()) Text(next.detail, style = sys(15f), color = Ink.muted)
                if (next.total > 1) ProgressBar(next.done.toDouble() / next.total, accent)
            }
        } else {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Icon(Icons.Filled.Verified, null, tint = accent, modifier = Modifier.size(20.dp))
                Text(L("ct.peek.all_done"), style = sys(17f, FontWeight.SemiBold), color = accent)
            }
        }
    }
}
