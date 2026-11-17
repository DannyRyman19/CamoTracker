package app.camotrack.android.ui.hajin.scan

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.camotrack.android.i18n.L
import app.camotrack.android.ui.*
import app.camotrack.android.ui.hajin.Chevron
import app.camotrack.android.ui.hajin.HajinColors

/**
 * The big My DMZ card until there's a stash (iOS HajinStashGridButton hero):
 * what it does, the little demo, and the button.
 */
@Composable
fun ScanHeroCard() {
    val shape = RoundedCornerShape(14.dp)
    Column(
        Modifier.padding(horizontal = 12.dp, vertical = 6.dp).fillMaxWidth().clip(shape)
            .background(Brush.linearGradient(listOf(HajinColors.accent.copy(alpha = 0.22f), LocalPalette.current.surface)))
            .border(1.dp, HajinColors.accent.copy(alpha = 0.5f), shape)
            .clickable { ScanFlow.requestScan() }.padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(L("mw4.ui.hajin.beta").uppercase(appLocale), style = sys(10f, FontWeight.Black).copy(letterSpacing = 0.8.sp),
                color = Color.Black.copy(alpha = 0.85f),
                modifier = Modifier.clip(CircleShape).background(HajinColors.accent).padding(horizontal = 7.dp, vertical = 3.dp))
            Text(L("mw4.ui.hajin.scan_hero_kicker"), style = sys(12f, FontWeight.SemiBold), color = Ink.muted)
        }
        Text(L("mw4.ui.hajin.scan_hero_title"), style = displayStyle(22.sp), color = Ink.text)
        Text(L("mw4.ui.hajin.scan_hero_subtitle"), style = sys(15f), color = Ink.muted)
        Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) { ScanDemo() }
        Row(
            Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(HajinColors.accent).padding(vertical = 12.dp),
            horizontalArrangement = Arrangement.Center, verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(Icons.Filled.CenterFocusStrong, null, tint = Color.Black.copy(alpha = 0.85f), modifier = Modifier.size(20.dp))
            Spacer(Modifier.width(8.dp))
            Text(L("mw4.ui.hajin.scan_hero_button"), style = sys(17f, FontWeight.SemiBold), color = Color.Black.copy(alpha = 0.85f))
        }
    }
}

/**
 * The photo reader once there's a stash (iOS HajinReaderTile): one card for
 * the stash and the backpack after a match, worked out from the photo.
 */
@Composable
fun ScanReaderTile() {
    Row(
        Modifier.padding(horizontal = 12.dp, vertical = 4.dp).fillMaxWidth().borderedCard(accent = HajinColors.accent)
            .clickable { ScanFlow.requestScan() }.padding(12.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Box(Modifier.size(38.dp).clip(RoundedCornerShape(8.dp)).background(HajinColors.accent.copy(alpha = 0.16f)), contentAlignment = Alignment.Center) {
            Icon(Icons.Filled.CenterFocusStrong, null, tint = HajinColors.text, modifier = Modifier.size(20.dp))
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                Text(L("mw4.ui.hajin.grid_scan"), style = displayStyle(16.sp), color = Ink.text)
                // Still learning the game's screens
                Text(L("mw4.ui.hajin.beta"), style = sys(11f, FontWeight.Bold), color = HajinColors.text,
                    modifier = Modifier.border(1.dp, HajinColors.accent.copy(alpha = 0.6f), CircleShape).padding(horizontal = 7.dp, vertical = 2.dp))
            }
            Text(L("mw4.ui.hajin.read_auto"), style = sys(12f), color = Ink.muted)
        }
        Chevron()
    }
}

/** "Read from a photo" at the top of My stash (iOS HajinStashGridButton row). */
@Composable
fun ScanStashRow() {
    Row(
        Modifier.padding(horizontal = 12.dp, vertical = 4.dp).fillMaxWidth().clip(RoundedCornerShape(8.dp)).background(LocalPalette.current.surface)
            .clickable { ScanFlow.requestScan() }.padding(12.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Icon(Icons.Filled.GridOn, null, tint = HajinColors.text, modifier = Modifier.size(22.dp))
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(L("mw4.ui.hajin.grid_scan"), style = sys(15f, FontWeight.SemiBold), color = Ink.text)
            Text(L("mw4.ui.hajin.grid_scan_hint"), style = sys(12f), color = Ink.muted)
        }
    }
}
