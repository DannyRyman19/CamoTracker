package app.camotrack.android.ui.screens

import android.annotation.SuppressLint
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Intent
import android.graphics.Color as AColor
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.Share
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import app.camotrack.android.AppState
import app.camotrack.android.i18n.L
import app.camotrack.android.services.StreamOverlay
import app.camotrack.android.services.StreamOverlay.Content
import app.camotrack.android.services.StreamOverlay.Layout
import app.camotrack.android.services.StreamOverlay.Style
import app.camotrack.android.ui.Ink
import app.camotrack.android.ui.LocalPalette
import app.camotrack.android.ui.readableInset

/**
 * Customise > Stream overlay (iOS StreamOverlayView): switch it on, choose
 * what it shows and how it looks, copy the link for OBS. The preview runs
 * the real page.
 */
@Composable
fun StreamOverlayScreen() {
    val palette = LocalPalette.current
    val accent = palette.accent
    val t = AppState.tracker
    AppState.revision
    val o = StreamOverlay
    val context = LocalContext.current
    var picking by remember { mutableStateOf(false) }
    var copied by remember { mutableStateOf(false) }
    val gameId = t.game.id
    val weaponName = o.weaponId(gameId)?.let { t.weapon(it)?.name?.resolved() }

    LaunchedEffect(Unit) {
        // The weapon view starts on the pinned gun, if there is one
        if (o.weaponId(gameId) == null) t.pinnedWeaponId?.let { o.setWeapon(it, gameId) }
        o.refresh(immediately = true)
    }
    if (picking) return WeaponPicker { picking = false }

    Column(Modifier.fillMaxSize().background(palette.background).statusBarsPadding()) {
        SettingsTopBar(L("ct.overlay.title"))
        LazyColumn(contentPadding = PaddingValues(horizontal = readableInset() + 16.dp, vertical = 16.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
            item {
                SettingsCard {
                    OverlayPreview(o.previewUrl, o.layout, o.status)
                    SettingsSwitch(L("ct.overlay.on"), o.isOn, accent) { if (it) o.turnOn() else o.turnOff() }
                }
                SettingsFooter(L("ct.overlay.footer"))
            }
            item {
                SettingsHeader(L("ct.overlay.shows"))
                SettingsCard {
                    SettingsSegmented(listOf(L("ct.overlay.overview"), L("ct.overlay.weapon")), Content.entries.indexOf(o.content), accent) {
                        o.changeContent(Content.entries[it])
                    }
                    if (o.content == Content.weapon) {
                        Row(Modifier.fillMaxWidth().clickable { picking = true }.padding(vertical = 12.dp)) {
                            Text(L("ct.overlay.which_weapon"), color = Ink.text, modifier = Modifier.weight(1f))
                            Text(weaponName ?: L("ct.overlay.pick"), color = if (weaponName == null) accent else Ink.muted)
                        }
                    }
                    if (t.visibleModes.size > 1) {
                        val options = listOf("") + t.visibleModes
                        val labels = listOf(L("ct.overlay.mode_start")) + t.visibleModes.map { L(t.modeNameKey(it)) }
                        Text(L("ct.overlay.mode"), color = Ink.muted, fontSize = 13.sp, modifier = Modifier.padding(top = 8.dp, bottom = 6.dp))
                        SettingsSegmented(labels, options.indexOf(o.mode).coerceAtLeast(0), accent) { o.changeMode(options[it]) }
                    }
                }
            }
            item {
                SettingsHeader(L("ct.overlay.look"))
                SettingsCard {
                    SettingsSegmented(listOf(L("ct.overlay.layout.card"), L("ct.overlay.layout.vertical"), L("ct.overlay.layout.minimal")),
                              Layout.entries.indexOf(o.layout), accent) { o.changeLayout(Layout.entries[it]); copied = false }
                    Spacer(Modifier.height(10.dp))
                    SettingsSegmented(listOf("Camo Track", L("ct.overlay.style.glass"), L("ct.overlay.style.clean")),
                              Style.entries.indexOf(o.style), accent) { o.changeStyle(Style.entries[it]); copied = false }
                    SettingsSwitch(L("ct.overlay.qr"), o.showsQR, accent) { o.changeShowsQR(it) }
                    SettingsSwitch(L("ct.overlay.celebrate"), o.celebrates, accent) { o.changeCelebrates(it) }
                    SettingsSwitch(L("ct.overlay.right"), o.alignsRight, accent) { o.changeAlignsRight(it) }
                }
            }
            if (o.isOn) item {
                SettingsHeader(L("ct.overlay.link"))
                SettingsCard {
                    Text(o.pageUrl, color = Ink.text, fontSize = 12.sp, fontFamily = FontFamily.Monospace)
                    Row(Modifier.fillMaxWidth().clickable {
                        context.getSystemService(ClipboardManager::class.java).setPrimaryClip(ClipData.newPlainText("Overlay", o.pageUrl))
                        copied = true
                    }.padding(vertical = 12.dp), verticalAlignment = Alignment.CenterVertically) {
                        Icon(if (copied) Icons.Filled.Check else Icons.Filled.ContentCopy, null, tint = accent, modifier = Modifier.size(18.dp))
                        Spacer(Modifier.width(8.dp))
                        Text(L(if (copied) "ct.overlay.copied" else "ct.overlay.copy"), color = accent)
                    }
                    Row(Modifier.fillMaxWidth().clickable {
                        context.startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, o.pageUrl), null))
                    }.padding(vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Filled.Share, null, tint = accent, modifier = Modifier.size(18.dp))
                        Spacer(Modifier.width(8.dp))
                        Text(L("ct.overlay.share"), color = accent)
                    }
                }
                val status = when (o.status) {
                    StreamOverlay.Status.Waiting -> L("ct.overlay.status.waiting")
                    is StreamOverlay.Status.Live -> L("ct.overlay.status.live")
                    StreamOverlay.Status.Failed -> L("ct.overlay.status.failed")
                    StreamOverlay.Status.Off -> ""
                }
                SettingsFooter(L("ct.overlay.link_footer", o.layout.width, o.layout.height) + " " + status)
            }
            if (o.isOn) item {
                SettingsCard {
                    var channel by remember { mutableStateOf(o.channel) }
                    OutlinedTextField(channel, { channel = it; o.changeChannel(it) }, Modifier.fillMaxWidth(),
                        placeholder = { Text(L("ct.overlay.channel")) }, singleLine = true,
                        keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.None, autoCorrectEnabled = false))
                    TextButton(onClick = { o.replaceLink(); copied = false }) { Text(L("ct.overlay.new_link"), color = Color(0xFFFF453A)) }
                }
                SettingsFooter(L("ct.overlay.channel_footer"))
            }
        }
    }
}

/** Every weapon in the game, by class, to put on the overlay. */
@Composable
private fun WeaponPicker(done: () -> Unit) {
    val palette = LocalPalette.current
    val t = AppState.tracker
    androidx.activity.compose.BackHandler { done() }
    Column(Modifier.fillMaxSize().background(palette.background).statusBarsPadding()) {
        SettingsTopBar(L("ct.overlay.which_weapon"), done)
        LazyColumn(contentPadding = PaddingValues(horizontal = readableInset() + 16.dp, vertical = 16.dp)) {
            t.catalog?.categories.orEmpty().forEach { category ->
                item { SettingsHeader(category.name.resolved()) }
                items(category.weapons, key = { "w${it.weaponId}" }) { weapon ->
                    Row(Modifier.fillMaxWidth().clickable { StreamOverlay.setWeapon(weapon.weaponId, t.game.id); done() }.padding(vertical = 12.dp)) {
                        Text(weapon.name.resolved(), color = Ink.text, modifier = Modifier.weight(1f))
                        if (StreamOverlay.weaponId(t.game.id) == weapon.weaponId) Icon(Icons.Filled.Check, null, tint = palette.accent)
                    }
                }
            }
        }
    }
}

/** The overlay page at its Browser source size, scaled to fit, over a stand-in for gameplay. */
@SuppressLint("SetJavaScriptEnabled")
@Composable
private fun OverlayPreview(url: String, layout: Layout, status: StreamOverlay.Status) {
    val density = LocalDensity.current
    BoxWithConstraints(Modifier.fillMaxWidth().padding(bottom = 10.dp), contentAlignment = Alignment.Center) {
        val maxH = if (layout.height > layout.width) 460.dp else 300.dp
        val scale = minOf(maxWidth / layout.width.dp, maxH / layout.height.dp, 1f)
        val w = layout.width.dp * scale
        val h = layout.height.dp * scale
        // Reload when the link, layout or a landed send changes
        val reload = url + "|" + ((status as? StreamOverlay.Status.Live)?.at ?: 0)
        Box(Modifier.size(w, h).clip(RoundedCornerShape(12.dp))
            .background(Brush.linearGradient(listOf(Color(0xFF3D4733), Color(0xFF735C2E), Color(0xFF9E6B24))))) {
            AndroidView(
                factory = { ctx ->
                    WebView(ctx).apply {
                        setBackgroundColor(AColor.TRANSPARENT)
                        settings.javaScriptEnabled = true
                        settings.cacheMode = WebSettings.LOAD_NO_CACHE
                        settings.useWideViewPort = false
                        isVerticalScrollBarEnabled = false
                        webViewClient = WebViewClient()
                    }
                },
                update = { web ->
                    if (web.tag != reload) { web.tag = reload; web.loadUrl(url) }
                    // The page laid out at its source size, then scaled down
                    with(density) {
                        web.layoutParams = android.view.ViewGroup.LayoutParams(layout.width.dp.roundToPx(), layout.height.dp.roundToPx())
                    }
                    web.pivotX = 0f; web.pivotY = 0f
                    web.scaleX = scale; web.scaleY = scale
                },
                modifier = Modifier.requiredSize(layout.width.dp, layout.height.dp).offset(
                    x = -(layout.width.dp - w) / 2, y = -(layout.height.dp - h) / 2),
            )
        }
    }
}

// ── Small settings pieces, in the iPhone grouped-list look ──

@Composable
internal fun SettingsTopBar(title: String, back: () -> Unit = { AppState.pop() }) {
    Row(Modifier.fillMaxWidth().padding(4.dp), verticalAlignment = Alignment.CenterVertically) {
        IconButton(onClick = back) { Icon(Icons.AutoMirrored.Filled.ArrowBack, null, tint = Ink.text) }
        Text(title, color = Ink.text, fontSize = 18.sp, fontWeight = FontWeight.SemiBold)
    }
}

@Composable
internal fun SettingsHeader(text: String) =
    Text(text.uppercase(), color = Ink.muted, fontSize = 12.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.padding(start = 4.dp, bottom = 6.dp))

@Composable
internal fun SettingsFooter(text: String) =
    Text(text, color = Ink.muted, fontSize = 12.sp, modifier = Modifier.padding(start = 4.dp, top = 6.dp, end = 4.dp))

@Composable
internal fun SettingsCard(content: @Composable ColumnScope.() -> Unit) {
    Column(Modifier.fillMaxWidth().background(LocalPalette.current.surface, RoundedCornerShape(12.dp)).padding(14.dp), content = content)
}

@Composable
internal fun SettingsSwitch(label: String, on: Boolean, accent: Color, onChange: (Boolean) -> Unit) {
    Row(Modifier.fillMaxWidth().padding(vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(label, color = Ink.text, modifier = Modifier.weight(1f))
        Switch(on, onChange, colors = SwitchDefaults.colors(checkedTrackColor = accent))
    }
}

@Composable
internal fun SettingsSegmented(labels: List<String>, selected: Int, accent: Color, onPick: (Int) -> Unit) {
    SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
        labels.forEachIndexed { i, label ->
            SegmentedButton(
                selected = i == selected, onClick = { onPick(i) },
                shape = SegmentedButtonDefaults.itemShape(i, labels.size),
                colors = SegmentedButtonDefaults.colors(activeContainerColor = accent.copy(alpha = 0.25f), activeContentColor = Ink.text,
                                                        inactiveContainerColor = Color.Transparent, inactiveContentColor = Ink.muted),
                icon = {},
            ) { Text(label, fontSize = 12.sp, maxLines = 1) }
        }
    }
}
