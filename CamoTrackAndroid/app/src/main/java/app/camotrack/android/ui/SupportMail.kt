package app.camotrack.android.ui

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.widget.Toast
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.padding
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowRight
import androidx.compose.material.icons.automirrored.outlined.Chat
import androidx.compose.material.icons.filled.Checklist
import androidx.compose.material.icons.filled.MoreHoriz
import androidx.compose.material.icons.outlined.Image
import androidx.compose.material.icons.outlined.LockOpen
import androidx.compose.material.icons.outlined.TextFields
import androidx.compose.material.icons.outlined.UnfoldMore
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.foundation.text.KeyboardOptions
import app.camotrack.android.BuildConfig
import app.camotrack.android.core.ChallengeItem
import app.camotrack.android.core.MasteryKind
import app.camotrack.android.core.WeaponEntry
import app.camotrack.android.i18n.L

/**
 * Data reports and feedback by email (iOS SupportMail.swift): there's no
 * backend, so a pre-filled email to support is the quickest way in. Each
 * carries what's needed to fix the row without a reply: which weapon, which
 * mode, and what the app has now.
 */
object SupportMail {
    const val ADDRESS = "support@camo-track.app"

    /** What a weapon's unlock should be: a level, a challenge, or none. */
    sealed interface UnlockRef {
        data class PlayerLevel(val level: Int?) : UnlockRef
        data object Challenge : UnlockRef
        data object ByDefault : UnlockRef

        val describedForMail: String
            get() = when (this) {
                is PlayerLevel -> level?.let { "Player level $it" } ?: "A player level (number not given)"
                Challenge -> "A challenge (described above)"
                ByDefault -> "Unlocked by default"
            }
    }

    /** A Completionist or Mastery camo, as a report target. */
    data class MasteryRef(val name: String, val tier: Int, val requirement: Int?)

    /** The kinds of data problem; the English text is the subject's suffix. */
    enum class Kind(val mail: String, val labelKey: String, val icon: ImageVector) {
        MAX_LEVEL("Wrong max level", "mw4.ui.report.max_level", Icons.Outlined.UnfoldMore),
        UNLOCK("Wrong unlock requirement", "mw4.ui.report.unlock", Icons.Outlined.LockOpen),
        CHALLENGE("Wrong challenge", "mw4.ui.report.challenge", Icons.Filled.Checklist),
        MISSING_IMAGE("Missing or wrong image", "mw4.ui.report.image", Icons.Outlined.Image),
        NAME("Wrong name", "mw4.ui.report.name", Icons.Outlined.TextFields),
        OTHER("Something else", "mw4.ui.report.other", Icons.Filled.MoreHoriz),
    }

    /** A plain email to support (the foot of Stats). */
    fun open(context: Context) = send(context, null, null)

    fun report(
        context: Context, kind: Kind, weapon: WeaponEntry, mode: String, category: String? = null,
        camo: ChallengeItem? = null, mastery: MasteryRef? = null, unlock: UnlockRef? = null, correctedMaxLevel: Int? = null,
    ) {
        val lines = mutableListOf(
            "Issue type: ${kind.mail}",
            "Weapon: ${weapon.name.resolved()}",
            "Weapon ID: ${weapon.weaponId}",
            "Mode: $mode",
        )
        category?.let { lines += "Category: $it" }
        lines += "Max level in app: ${weapon.maxLevel}"
        lines += "Unlock in app: " + (weapon.unlockLevel(listOf("en"))?.let { "Player level $it" }
            ?: weapon.acquiredBy?.let { when (it) { "battlePass" -> "Battle Pass"; "event" -> "Event"; "armory" -> "Armory"; else -> it } }
            ?: "Unlocked by default")
        // The file name only: enough to find the asset
        lines += "Image: " + (weapon.imageURL?.substringAfterLast('/')?.takeIf { it.isNotEmpty() } ?: "none")
        correctedMaxLevel?.let { lines += "Should be: $it" }
        if (camo != null) {
            lines += "Camo: ${camo.name.resolved()}"
            lines += "Camo ID: ${camo.itemId}"
            camo.requirement?.let { lines += "Requirement in app: ${it.amount} ${it.unit}" }
            camo.unlockLevel?.let { lines += "Unlocks in app: Weapon level $it" }
        }
        unlock?.let { lines += "Should be: ${it.describedForMail}" }
        if (mastery != null) {
            lines += "Mastery camo: ${mastery.name}"
            lines += "Mastery tier: ${mastery.tier}"
            mastery.requirement?.let { lines += "Requirement in app: $it" }
        }
        send(context, "Camo Tracker: ${kind.mail}", lines.joinToString("\n") + "\n\n" + diagnosticsFooter())
    }

    /** A DMZ guide report (an item or section of the Hajin guide), with the guide's version (iOS dmzURL). */
    fun dmz(context: Context, kind: String, lines: List<String>, guideVersion: String?) {
        val body = (listOf("Issue type: $kind") + lines + "Guide data: ${guideVersion ?: "?"}").joinToString("\n")
        send(context, "Camo Tracker DMZ: $kind", body + "\n\n" + diagnosticsFooter())
    }

    private fun diagnosticsFooter(): String =
        "---\nApp ${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE}) · Android ${Build.VERSION.RELEASE} · ${Build.MANUFACTURER} ${Build.MODEL}"

    private fun send(context: Context, subject: String?, body: String?) {
        val intent = Intent(Intent.ACTION_SENDTO, Uri.parse("mailto:$ADDRESS")).apply {
            putExtra(Intent.EXTRA_EMAIL, arrayOf(ADDRESS))
            if (subject != null) putExtra(Intent.EXTRA_SUBJECT, subject)
            if (body != null) putExtra(Intent.EXTRA_TEXT, "Describe the issue:\n\n\n$body")
        }
        try {
            context.startActivity(intent)
        } catch (_: ActivityNotFoundException) {
            Toast.makeText(context, L("ct.android.no_mail"), Toast.LENGTH_LONG).show()
        }
    }
}

/**
 * "Report a data issue" on a weapon's page (iOS ReportIssueMenu): a menu so
 * the subject arrives sorted by kind. "Wrong challenge" lists the weapon's
 * camos and its Completionist and Mastery camos; "Wrong max level" and a
 * player-level unlock ask for the right number first.
 */
@Composable
fun ReportIssueMenu(weapon: WeaponEntry, mode: String, camos: List<ChallengeItem>, tint: androidx.compose.ui.graphics.Color) {
    val t = tracker()
    val context = LocalContext.current
    val category = t.category(weapon.weaponId)?.name?.resolved()
    var open by remember { mutableStateOf(false) }
    var sub by remember { mutableStateOf<SupportMail.Kind?>(null) }
    var askMax by remember { mutableStateOf(false) }
    var askUnlock by remember { mutableStateOf(false) }
    val palette = LocalPalette.current

    val masteryRefs: List<SupportMail.MasteryRef> = run {
        val track = t.completionist(mode)
        val tiers = t.masteryCamos(mode)
        val steps = track.steps.mapIndexed { index, camo ->
            SupportMail.MasteryRef(camo.name, index + 1, t.completionistRequirement(mode, weapon.weaponId, index)?.amount)
        }
        val final = if (t.finalEnabled(mode)) listOf(SupportMail.MasteryRef(track.final.name, 4, null)) else emptyList()
        fun amount(tier: Int): Int? = when (t.masteryKind(mode, tier)) {
            MasteryKind.MODE -> t.modeMasteryRequirement(mode, tier)?.amount
            MasteryKind.CHALLENGE -> t.masteryRequirement(mode, weapon.weaponId, tier)?.amount
            MasteryKind.COUNT -> null
        }
        val mastery = if (t.game.hasAccountMastery) (1..3).map { SupportMail.MasteryRef(tiers[it - 1].name, it + 4, amount(it)) } else emptyList()
        steps + final + mastery
    }

    fun send(kind: SupportMail.Kind, camo: ChallengeItem? = null, mastery: SupportMail.MasteryRef? = null,
             unlock: SupportMail.UnlockRef? = null, corrected: Int? = null) {
        open = false; sub = null
        SupportMail.report(context, kind, weapon, mode, category, camo, mastery, unlock, corrected)
    }

    Box {
        IconButton(onClick = { open = true }) { Icon(Icons.AutoMirrored.Outlined.Chat, L("mw4.ui.report.title"), tint = tint) }
        DropdownMenu(open && sub == null, onDismissRequest = { open = false }, containerColor = palette.surface2) {
            Text(L("mw4.ui.report.title"), style = sys(12f, FontWeight.SemiBold), color = Ink.muted,
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 6.dp))
            for (kind in SupportMail.Kind.entries) {
                val hasSub = kind == SupportMail.Kind.UNLOCK || (kind == SupportMail.Kind.CHALLENGE && (camos.isNotEmpty() || masteryRefs.isNotEmpty()))
                DropdownMenuItem(
                    text = { Text(L(kind.labelKey), color = Ink.text) },
                    leadingIcon = { Icon(kind.icon, null, tint = Ink.text) },
                    trailingIcon = if (hasSub) ({ Icon(Icons.AutoMirrored.Filled.ArrowRight, null, tint = Ink.muted) }) else null,
                    onClick = {
                        when {
                            hasSub -> sub = kind
                            kind == SupportMail.Kind.MAX_LEVEL -> { open = false; askMax = true }
                            else -> send(kind)
                        }
                    },
                )
            }
        }
        DropdownMenu(open && sub != null, onDismissRequest = { open = false; sub = null }, containerColor = palette.surface2) {
            when (sub) {
                SupportMail.Kind.UNLOCK -> {
                    DropdownMenuItem(text = { Text(L("mw4.ui.report.unlock.level"), color = Ink.text) }, onClick = { open = false; sub = null; askUnlock = true })
                    DropdownMenuItem(text = { Text(L("mw4.ui.report.unlock.challenge"), color = Ink.text) },
                        onClick = { send(SupportMail.Kind.UNLOCK, unlock = SupportMail.UnlockRef.Challenge) })
                    DropdownMenuItem(text = { Text(L("mw4.ui.report.unlock.default"), color = Ink.text) },
                        onClick = { send(SupportMail.Kind.UNLOCK, unlock = SupportMail.UnlockRef.ByDefault) })
                }
                SupportMail.Kind.CHALLENGE -> {
                    for (camo in camos) {
                        DropdownMenuItem(text = { Text(camo.name.resolved(), color = Ink.text) }, onClick = { send(SupportMail.Kind.CHALLENGE, camo = camo) })
                    }
                    if (camos.isNotEmpty() && masteryRefs.isNotEmpty()) HorizontalDivider(color = Ink.muted.copy(alpha = 0.2f))
                    for (ref in masteryRefs) {
                        DropdownMenuItem(text = { Text(ref.name, color = Ink.text) }, onClick = { send(SupportMail.Kind.CHALLENGE, mastery = ref) })
                    }
                }
                else -> {}
            }
        }
    }
    if (askMax) {
        NumberAsk(L("mw4.ui.report.max_level"), L("mw4.ui.report.max_level.message", weapon.maxLevel), L("mw4.ui.report.max_level.field"),
            onDismiss = { askMax = false }) { value -> askMax = false; send(SupportMail.Kind.MAX_LEVEL, corrected = value) }
    }
    if (askUnlock) {
        NumberAsk(L("mw4.ui.report.unlock"), L("mw4.ui.report.unlock.message", weapon.unlockLevel(listOf("en"))?.toString() ?: "-"), L("mw4.ui.report.unlock.field"),
            onDismiss = { askUnlock = false }) { value -> askUnlock = false; send(SupportMail.Kind.UNLOCK, unlock = SupportMail.UnlockRef.PlayerLevel(value)) }
    }
}

/** A number to send with a report; an empty field still sends (a vaguer report beats none). */
@Composable
private fun NumberAsk(title: String, message: String, field: String, onDismiss: () -> Unit, onSend: (Int?) -> Unit) {
    var text by remember { mutableStateOf("") }
    AlertDialog(
        onDismissRequest = onDismiss,
        containerColor = LocalPalette.current.surface2,
        title = { Text(title, color = Ink.text) },
        text = {
            Column {
                Text(message, color = Ink.muted)
                OutlinedTextField(
                    text, { text = it.filter(Char::isDigit).take(4) }, label = { Text(field) }, singleLine = true,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                    modifier = Modifier.padding(top = 12.dp),
                )
            }
        },
        confirmButton = { TextButton(onClick = { onSend(text.toIntOrNull()) }) { Text(L("mw4.ui.report.send")) } },
        dismissButton = { TextButton(onClick = onDismiss) { Text(L("mw4.ui.cancel")) } },
    )
}
