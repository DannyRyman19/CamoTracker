package app.camotrack.android.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.Diamond
import androidx.compose.material.icons.filled.EmojiEvents
import androidx.compose.material.icons.filled.GraphicEq
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.Verified
import androidx.compose.material.icons.filled.WorkspacePremium
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import app.camotrack.android.AppState
import app.camotrack.android.core.MasteryKind
import app.camotrack.android.core.Milestone
import app.camotrack.android.i18n.L
import app.camotrack.android.i18n.Strings

/** What a milestone's banner says (iOS's MilestoneBanner, built in Suggestions.swift). */
data class BannerText(val title: String, val subtitle: String, val gradient: List<Color>, val icon: ImageVector)

fun bannerText(milestone: Milestone): BannerText {
    val t = AppState.tracker
    fun weaponName(id: Int?) = id?.let { t.weapon(it)?.name?.resolved() } ?: ""
    fun unlocked(name: String) = L("mw4.ui.milestone.unlocked_title", name)
    return when (milestone) {
        is Milestone.CamosComplete -> BannerText(
            L("mw4.ui.milestone.camos_complete_title"), "${weaponName(milestone.weaponId)}.", GoldColors, Icons.Filled.EmojiEvents,
        )
        is Milestone.CompletionistUnlocked -> BannerText(
            unlocked(milestone.camo.name), weaponName(milestone.weaponId), milestone.camo.colors,
            listOf(Icons.Filled.EmojiEvents, Icons.Filled.Verified, Icons.Filled.GraphicEq).getOrElse(milestone.step) { Icons.Filled.EmojiEvents },
        )
        is Milestone.FinalUnlocked -> BannerText(
            unlocked(milestone.camo.name),
            if (milestone.weaponId != null) weaponName(milestone.weaponId) else Strings.plural("mw4.ui.milestone.final_many", milestone.gained),
            milestone.camo.colors, Icons.Filled.AutoAwesome,
        )
        is Milestone.WeaponMasteryUnlocked -> BannerText(
            unlocked(milestone.camo.name), weaponName(milestone.weaponId), milestone.camo.colors, Icons.Filled.Diamond,
        )
        is Milestone.MasteryUnlocked -> BannerText(
            unlocked(milestone.camo.name),
            when {
                milestone.tier == 3 -> L("mw4.ui.milestone.tier3_subtitle")
                milestone.kind == MasteryKind.MODE -> modeName(milestone.mode)
                else -> L("mw4.ui.milestone.mastery_subtitle", milestone.total, milestone.basis.name)
            },
            milestone.camo.colors, if (milestone.tier == 3) Icons.Filled.Star else Icons.Filled.Diamond,
        )
        is Milestone.HundredPlus -> BannerText(
            L("mw4.ui.milestone.100_plus_title"), L("mw4.ui.milestone.100_plus_subtitle", milestone.basis.name),
            PlatinumColors, Icons.Filled.WorkspacePremium,
        )
        is Milestone.GlobalMastery -> BannerText(
            unlocked(milestone.capstone.name.resolved()), L("ct.mastery.global"),
            colorsOf(app.camotrack.android.core.HexColor.parseAll(milestone.capstone.colors)).ifEmpty { GoldColors },
            Icons.Filled.WorkspacePremium,
        )
    }
}

/** The transient banner for a milestone, with a Share button when [onShare] is given. */
@Composable
fun MilestoneBannerView(banner: BannerText, onShare: (() -> Unit)? = null, modifier: Modifier = Modifier) {
    val first = banner.gradient.firstOrNull() ?: CamoGold
    val shape = RoundedCornerShape(14.dp)
    Column(
        modifier
            .padding(horizontal = 24.dp)
            .shadow(12.dp, shape)
            .clip(shape)
            .background(LocalPalette.current.surface2)
            .border(1.5.dp, Brush.horizontalGradient(banner.gradient.ifEmpty { GoldColors }.map { it.copy(alpha = 0.6f) }), shape)
            .padding(horizontal = 20.dp, vertical = 12.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Icon(banner.icon, null, tint = first, modifier = Modifier.size(22.dp))
        AnimatedGradientText(banner.title, banner.gradient, size = 16f, textAlign = TextAlign.Center)
        Text(banner.subtitle, style = sys(12.5f), color = Ink.muted, textAlign = TextAlign.Center)
        if (onShare != null) {
            Row(
                Modifier.padding(top = 6.dp).clip(CircleShape).background(first.copy(alpha = 0.22f))
                    .border(1.dp, first.copy(alpha = 0.6f), CircleShape).clickable(onClick = onShare)
                    .padding(horizontal = 14.dp, vertical = 6.dp),
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                Icon(Icons.Filled.Share, null, tint = Ink.text, modifier = Modifier.size(14.dp))
                Text(L("mw4.ui.share.button"), style = sys(12.5f, FontWeight.SemiBold), color = Ink.text)
            }
        }
    }
}
