package app.camotrack.android.ui.screens

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.provider.Settings
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowForward
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Layers
import androidx.compose.material.icons.filled.NotificationsActive
import androidx.compose.material.icons.filled.Podcasts
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Sync
import androidx.compose.material.icons.filled.TouchApp
import androidx.compose.material.icons.outlined.Notifications
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.ContextCompat
import app.camotrack.android.AppState
import app.camotrack.android.Route
import app.camotrack.android.WhatsNew
import app.camotrack.android.i18n.L
import app.camotrack.android.ui.*

/** What's new since the version last seen, each with a button to go to it (iOS WhatsNewSheet). */
@Composable
fun WhatsNewScreen(onClose: () -> Unit) {
    val palette = LocalPalette.current
    val accent = modeAccent(AppState.mode)
    val items = remember { WhatsNew.items(AppState.store) }
    LaunchedEffect(Unit) { WhatsNew.markSeen(AppState.store) }
    Column(Modifier.fillMaxSize().background(palette.background).systemBarsPadding()) {
        TopBar("", onBack = onClose)
        Column(
            Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = readableInset()).padding(horizontal = 20.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            Text(L("ct.whatsnew.heading", WhatsNew.version), style = displayStyle(28.sp), color = Ink.text, modifier = Modifier.padding(bottom = 4.dp))
            for (item in items) ItemCard(item, accent, onClose)
        }
        Text(
            L("ct.whatsnew.continue"), style = sys(17f, FontWeight.SemiBold), color = Color.Black,
            textAlign = androidx.compose.ui.text.style.TextAlign.Center,
            modifier = Modifier.padding(20.dp).fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(accent)
                .clickable(onClick = onClose).padding(vertical = 14.dp),
        )
    }
}

private fun icon(symbol: String): ImageVector = when (symbol) {
    "sync" -> Icons.Filled.Sync
    "overlay" -> Icons.Filled.Podcasts
    "bell" -> Icons.Filled.NotificationsActive
    "modes" -> Icons.Filled.Layers
    "hand" -> Icons.Filled.TouchApp
    else -> Icons.Filled.AutoAwesome
}

@Composable
private fun ItemCard(item: WhatsNew.Item, accent: Color, onClose: () -> Unit) {
    Column(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp)).background(LocalPalette.current.surface).padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Icon(icon(item.symbol), null, tint = accent, modifier = Modifier.size(26.dp))
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(L(item.titleKey), style = sys(17f, FontWeight.SemiBold), color = Ink.text)
                Text(L(item.bodyKey), style = sys(15f), color = Ink.muted)
            }
        }
        when (item.action) {
            WhatsNew.Action.STREAM_OVERLAY -> ActionLink(L("ct.whatsnew.overlay.action"), Icons.AutoMirrored.Filled.ArrowForward, accent) {
                onClose()
                AppState.push(Route.StreamOverlay)
            }
            WhatsNew.Action.NOTIFICATIONS -> NotificationsAction(accent)
            null -> {}
        }
    }
}

@Composable
private fun ActionLink(title: String, icon: ImageVector, color: Color, onClick: (() -> Unit)?) {
    Row(
        Modifier.padding(start = 38.dp).then(if (onClick != null) Modifier.clickable(onClick = onClick) else Modifier).padding(vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Icon(icon, null, tint = color, modifier = Modifier.size(16.dp))
        Text(title, style = sys(15f, FontWeight.SemiBold), color = color)
    }
}

/** On, or a button to ask; once refused, Settings is the way back. */
@Composable
private fun NotificationsAction(accent: Color) {
    val context = LocalContext.current
    fun granted() = Build.VERSION.SDK_INT < 33 ||
        ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
    var on by remember { mutableStateOf(granted()) }
    var refused by remember { mutableStateOf(false) }
    val ask = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { ok -> on = ok; refused = !ok }
    when {
        on -> ActionLink(L("ct.whatsnew.push.on"), Icons.Filled.CheckCircle, Ink.muted, null)
        refused -> ActionLink(L("ct.whatsnew.push.settings"), Icons.Filled.Settings, accent) {
            context.startActivity(Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName))
        }
        else -> ActionLink(L("ct.whatsnew.push.action"), Icons.Outlined.Notifications, accent) {
            if (Build.VERSION.SDK_INT >= 33) ask.launch(Manifest.permission.POST_NOTIFICATIONS)
        }
    }
}
