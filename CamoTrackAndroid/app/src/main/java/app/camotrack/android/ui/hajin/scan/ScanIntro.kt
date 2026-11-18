package app.camotrack.android.ui.hajin.scan

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.camotrack.android.AppState
import app.camotrack.android.Route
import app.camotrack.android.i18n.L
import app.camotrack.android.services.Premium
import app.camotrack.android.services.Rewarded
import app.camotrack.android.ui.*
import app.camotrack.android.ui.hajin.*
import app.camotrack.android.ui.screens.findActivity
import java.io.File
import kotlin.math.roundToInt

/**
 * What "Read from a photo" does, before the photo picker (iOS
 * HajinStashScanIntro): a looping demo, tips for a good photo, and the Take /
 * Choose a photo buttons. Free players get Watch an ad and Go Premium in
 * their place until the ad has played (with ads not set up, never).
 */
@Composable
fun ScanIntro(onClose: () -> Unit) {
    val context = LocalContext.current
    val palette = LocalPalette.current
    /** This scan's ad has been watched (or there was none to show) */
    var watched by remember { mutableStateOf(false) }
    var noAd by remember { mutableStateOf(false) }
    var recent by remember { mutableStateOf(RecentPhotos.all(context)) }
    val needsAd = !Premium.isPremium && Rewarded.showsAds && !watched

    // At the largest text sizes the pinned buttons took most of the screen,
    // leaving a sliver for the explanation: there they scroll in after the
    // tips instead (as on iPhone)
    val pinsButtons = !isAccessibilityFontSize()
    Column(Modifier.fillMaxSize().background(palette.background).systemBarsPadding()) {
        // A bar's title stops growing at iOS's largest standard size, so "Read from a photo" stays whole
        CapFontScale {
        Row(Modifier.fillMaxWidth().heightIn(min = 52.dp).padding(horizontal = 4.dp), verticalAlignment = Alignment.CenterVertically) {
            TextButton(onClick = onClose, modifier = Modifier.widthIn(min = 88.dp)) { Text(L("mw4.ui.hajin.cancel"), color = HajinColors.text, style = sys(16f), maxLines = 1) }
            Text(L("mw4.ui.hajin.grid_scan"), style = displayStyle(17.sp), color = Ink.text, maxLines = 2,
                modifier = Modifier.weight(1f), textAlign = androidx.compose.ui.text.style.TextAlign.Center)
            Spacer(Modifier.width(88.dp))
        }
        }
        val actions: @Composable () -> Unit = { ScanIntroActions(needsAd, recent, onClose, onWatched = { watched = true }, onNoAd = { noAd = true },
            onRecentChange = { recent = RecentPhotos.all(context) }) }
        Column(
            Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = readableInset()).padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(18.dp),
        ) {
            // A picture of a stash: its labels stop growing at the largest standard size, so the names still fit
            Box(Modifier.fillMaxWidth().padding(vertical = 6.dp), contentAlignment = Alignment.Center) { CapFontScale { ScanDemo() } }
            Text(L("mw4.ui.hajin.grid_intro"), style = sys(15f), color = Ink.text)
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Filled.PhonelinkLock, null, tint = HajinColors.text, modifier = Modifier.size(18.dp))
                Text(L("mw4.ui.hajin.grid_private"), style = sys(13f, FontWeight.SemiBold), color = HajinColors.text)
            }
            Column(
                Modifier.fillMaxWidth().clip(RoundedCornerShape(10.dp)).background(palette.surface).padding(14.dp),
                verticalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                SmallCaps(L("mw4.ui.hajin.grid_tips_title"))
                Tip(Icons.Filled.Screenshot, L("mw4.ui.hajin.grid_tip_screenshot"), best = true)
                Tip(Icons.Filled.CenterFocusWeak, L("mw4.ui.hajin.grid_tip_straight"))
                Tip(Icons.Filled.WbSunny, L("mw4.ui.hajin.grid_tip_glare"))
                // The rest depends on which screen it is
                TipsHeading(Icons.Filled.GridOn, L("mw4.ui.hajin.read_as_stash"))
                Tip(Icons.Filled.Apps, L("mw4.ui.hajin.grid_tip_tab"))
                Tip(Icons.Filled.Crop, L("mw4.ui.hajin.grid_tip_crop"))
                TipsHeading(Icons.Filled.ShoppingBag, L("mw4.ui.postmatch.title"))
                Tip(Icons.Filled.Backpack, L("mw4.ui.postmatch.tip_screen"))
                Tip(Icons.Filled.Apps, L("mw4.ui.postmatch.tip_whole"))
            }
            if (!pinsButtons) actions()
        }
        if (pinsButtons) {
            // Pinned under the tips, so the next step is always in view
            Box(Modifier.fillMaxWidth().height(1.dp).background(Ink.muted.copy(alpha = 0.25f)))
            Box(Modifier.fillMaxWidth().background(palette.background).padding(horizontal = 16.dp).padding(top = 12.dp, bottom = 8.dp)) { actions() }
        }
    }
    if (noAd) {
        AlertDialog(
            onDismissRequest = { noAd = false },
            containerColor = palette.surface2,
            title = { Text(L("mw4.ui.premium.no_ad_title"), color = Ink.text) },
            text = { Text(L("mw4.ui.premium.no_ad_message"), color = Ink.muted) },
            confirmButton = { TextButton(onClick = { noAd = false; onClose(); AppState.push(Route.Premium) }) { Text(L("mw4.ui.premium.scan_premium"), color = HajinColors.text) } },
            dismissButton = { TextButton(onClick = { noAd = false }) { Text(L("mw4.ui.hajin.cancel"), color = HajinColors.text) } },
        )
    }
}

/** Watch an ad and Go Premium for a free player's scan, else the recent photos and Take / Choose a photo. */
@Composable
private fun ScanIntroActions(needsAd: Boolean, recent: List<File>, onClose: () -> Unit, onWatched: () -> Unit, onNoAd: () -> Unit, onRecentChange: () -> Unit) {
    val context = LocalContext.current
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        if (needsAd) {
            // Free players: an ad for this scan, or Premium for none
            FilledButton(L("mw4.ui.premium.scan_watch"), Icons.Filled.SmartDisplay) {
                Rewarded.afterAd(context.findActivity(), AppState.store, onWatched, onNoAd)
            }
            Row(
                Modifier.fillMaxWidth().borderedCard(accent = HajinColors.accent).clickable { onClose(); AppState.push(Route.Premium) }.padding(12.dp),
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                CardSymbol(Icons.Filled.AutoAwesome)
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text(L("mw4.ui.premium.scan_premium"), style = displayStyle(16.sp), color = Ink.text)
                    Text(L("mw4.ui.premium.subtitle"), style = sys(12f), color = Ink.muted)
                }
                Chevron()
            }
        } else {
            if (recent.isNotEmpty()) RecentStrip(recent, onRemove = { RecentPhotos.remove(it); onRecentChange() }) {
                ScanFlow.recent(context, it)
            }
            if (ScanFlow.hasCamera) {
                FilledButton(L("mw4.ui.hajin.grid_camera"), Icons.Filled.PhotoCamera) { ScanFlow.replacing = false; ScanFlow.takePhoto() }
            }
            OutlineButton(L("mw4.ui.hajin.grid_choose"), Icons.Filled.PhotoLibrary) { ScanFlow.replacing = false; ScanFlow.pickPhotos() }
        }
    }
}

@Composable
internal fun FilledButton(title: String, icon: ImageVector, onClick: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(HajinColors.accent).clickable(onClick = onClick).padding(vertical = 14.dp),
        horizontalArrangement = Arrangement.Center, verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(icon, null, tint = Color.White, modifier = Modifier.size(20.dp))
        Spacer(Modifier.width(8.dp))
        Text(title, style = sys(17f, FontWeight.SemiBold), color = Color.White)
    }
}

@Composable
private fun OutlineButton(title: String, icon: ImageVector, onClick: () -> Unit) {
    val shape = RoundedCornerShape(12.dp)
    Row(
        Modifier.fillMaxWidth().clip(shape).border(2.dp, HajinColors.accent, shape).clickable(onClick = onClick).padding(vertical = 14.dp),
        horizontalArrangement = Arrangement.Center, verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(icon, null, tint = Ink.text, modifier = Modifier.size(20.dp))
        Spacer(Modifier.width(8.dp))
        Text(title, style = sys(17f, FontWeight.SemiBold), color = Ink.text)
    }
}

/** The last few camera shots, to read again without retaking them; long-press to remove one. */
@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun RecentStrip(files: List<File>, onRemove: (File) -> Unit, onPick: (File) -> Unit) {
    var removing by remember { mutableStateOf<File?>(null) }
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Text(L("mw4.ui.hajin.recent_photos"), style = sys(12f, FontWeight.SemiBold), color = Ink.muted)
        Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            for (file in files) {
                val thumb = remember(file) { RecentPhotos.thumbnail(file)?.asImageBitmap() } ?: continue
                val shape = RoundedCornerShape(6.dp)
                Image(
                    thumb, null, contentScale = ContentScale.Crop,
                    modifier = Modifier.size(72.dp, 54.dp).clip(shape).border(1.dp, LocalPalette.current.surface2, shape)
                        .combinedClickable(onLongClick = { removing = file }) { onPick(file) },
                )
            }
        }
    }
    removing?.let { file ->
        AlertDialog(
            onDismissRequest = { removing = null },
            containerColor = LocalPalette.current.surface2,
            text = { Text(L("ct.android.hajin.scan_remove_recent"), color = Ink.text) },
            confirmButton = { TextButton(onClick = { onRemove(file); removing = null }) { Text(L("mw4.ui.hajin.remove"), color = HajinColors.short) } },
            dismissButton = { TextButton(onClick = { removing = null }) { Text(L("mw4.ui.hajin.cancel"), color = HajinColors.text) } },
        )
    }
}

@Composable
private fun Tip(icon: ImageVector, text: String, best: Boolean = false) {
    Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.Top) {
        Icon(icon, null, tint = HajinColors.text, modifier = Modifier.padding(top = 1.dp).size(20.dp))
        Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
            if (best) {
                Text(
                    L("mw4.ui.hajin.grid_tip_best").uppercase(appLocale), style = sys(10f, FontWeight.Black).copy(letterSpacing = 0.8.sp),
                    color = Color.Black.copy(alpha = 0.85f),
                    modifier = Modifier.clip(CircleShape).background(HajinColors.accent).padding(horizontal = 6.dp, vertical = 2.dp),
                )
            }
            Text(text, style = sys(15f, if (best) FontWeight.SemiBold else FontWeight.Normal), color = Ink.text)
        }
    }
}

@Composable
private fun TipsHeading(icon: ImageVector, text: String) {
    Row(Modifier.padding(top = 8.dp), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
        Icon(icon, null, tint = Ink.text, modifier = Modifier.size(18.dp))
        Text(text, style = displayStyle(15.sp), color = Ink.text)
    }
}

/**
 * The demo (iOS HajinStashScanDemo): a little 3 x 3 stash with stack counts;
 * a scan line sweeps down, each row lights up as it's read, and the totals
 * on the right count up. Loops every few seconds.
 */
@Composable
fun ScanDemo() {
    val store = hajin()
    val grid = remember {
        listOf(
            listOf("rigid-synthetics" to 10, "rigid-synthetics" to 10, "rigid-synthetics" to 9),
            listOf("biomaterials" to 10, "biomaterials" to 3, "detonators" to 10),
            listOf("reactive-metals" to 10, "reactive-metals" to 2, "cpu" to 6),
        )
    }
    val cycle = 6.0; val sweep = 3.0
    val reduceMotion = reducedMotion()
    val t by produceState(if (reduceMotion) sweep + 0.4 else 0.0) {
        if (reduceMotion) return@produceState
        val start = withFrameMillis { it }
        while (true) withFrameMillis { value = ((it - start) / 1000.0) % cycle }
    }
    val progress = ((t - 0.4) / sweep).coerceIn(0.0, 1.0)
    val fade = if (t > cycle - 0.5) ((cycle - t) / 0.5).toFloat() else 1f
    Row(Modifier.height(190.dp).alpha(fade), horizontalArrangement = Arrangement.spacedBy(16.dp), verticalAlignment = Alignment.CenterVertically) {
        val tile = 52.dp; val gap = 6.dp
        val height = tile * 3 + gap * 2
        Box(Modifier.size(tile * 3 + gap * 2, height).clip(RoundedCornerShape(2.dp))) {
            Column(verticalArrangement = Arrangement.spacedBy(gap)) {
                grid.forEachIndexed { r, row ->
                    Row(horizontalArrangement = Arrangement.spacedBy(gap)) {
                        for ((id, count) in row) {
                            val read = progress * 3 > r + 0.5
                            Box(Modifier.scale(if (read) 1f else 0.96f).then(
                                if (read) Modifier.border(2.dp, HajinColors.accent, RoundedCornerShape(6.dp)) else Modifier)) {
                                ItemTile(store.guide?.item(id), tile)
                                Text("$count", style = sys(11f, FontWeight.Black, mono = true), color = Color.White,
                                    modifier = Modifier.align(Alignment.TopEnd).padding(3.dp))
                            }
                        }
                    }
                }
            }
            // the scan line
            if (progress > 0 && progress < 1) {
                Box(
                    Modifier.offset(y = height * progress.toFloat() - 26.dp).fillMaxWidth().height(26.dp)
                        .background(Brush.verticalGradient(listOf(HajinColors.accent.copy(alpha = 0f), HajinColors.accent.copy(alpha = 0.55f)))),
                ) { Box(Modifier.align(Alignment.BottomCenter).fillMaxWidth().height(2.dp).background(HajinColors.accent)) }
            }
        }
        // Each item's total, counting up as its stacks are read
        val order = grid.flatten().map { it.first }.distinct()
        Column(Modifier.width(150.dp), verticalArrangement = Arrangement.spacedBy(7.dp)) {
            for (id in order) {
                var soFar = 0
                grid.forEachIndexed { r, row ->
                    val rowRead = (progress * 3 - r).coerceIn(0.0, 1.0)
                    soFar += row.filter { it.first == id }.sumOf { (it.second * rowRead).roundToInt() }
                }
                val item = store.guide?.item(id)
                Row(Modifier.alpha(if (soFar > 0) 1f else 0.35f), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    ItemTile(item, 20.dp)
                    Text(item?.name?.resolved ?: id, style = sys(12f), color = Ink.text, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
                    Text("$soFar", style = sys(12f, FontWeight.Bold, mono = true), color = if (soFar > 0) HajinColors.text else Ink.muted)
                }
            }
        }
    }
}

/** The phone's "Remove animations" setting. */
@Composable
internal fun reducedMotion(): Boolean {
    val context = LocalContext.current
    return remember {
        runCatching {
            android.provider.Settings.Global.getFloat(context.contentResolver, android.provider.Settings.Global.ANIMATOR_DURATION_SCALE, 1f) == 0f
        }.getOrDefault(false)
    }
}
