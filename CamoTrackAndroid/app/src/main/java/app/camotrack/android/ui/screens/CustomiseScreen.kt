package app.camotrack.android.ui.screens

import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material.icons.outlined.Circle
import androidx.compose.material.icons.outlined.Email
import androidx.compose.material.icons.outlined.PrivacyTip
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import app.camotrack.android.AppState
import app.camotrack.android.Route
import app.camotrack.android.WhatsNew
import app.camotrack.android.core.ModeSelection
import app.camotrack.android.i18n.L
import app.camotrack.android.i18n.Strings
import app.camotrack.android.services.AdConsent
import app.camotrack.android.services.Premium
import app.camotrack.android.ui.*
import kotlinx.coroutines.launch

private const val PRIVACY_URL = "https://camo-track.app/privacy-policy"

private val HomeSection.icon: ImageVector
    get() = when (this) {
        HomeSection.SUMMARY -> Icons.Filled.PieChart
        HomeSection.LIVE -> Icons.Filled.Schedule
        HomeSection.PINNED -> Icons.Filled.PushPin
        HomeSection.SUGGESTED -> Icons.Filled.NorthEast
        HomeSection.WEAPONS -> Icons.Filled.GridView
        HomeSection.OBJECTIVES -> Icons.Filled.Checklist
    }

/**
 * Customise (iOS CustomiseHomeSheet): the modes played, language, start tab,
 * the Weapons tab's sections, quick tick and specials first, locked-camo
 * challenges and card outlines, personalised ads where the law asks, then
 * the stream overlay, What's New and Premium. Layout and look are Premium:
 * free players see them locked, and the lock opens Premium.
 */
@Composable
fun CustomiseScreen() {
    val t = tracker()
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val accent = modeAccent(AppState.mode)
    val locked = !Premium.isPremium
    var order by Prefs.string(HomeLayout.ORDER_KEY, "")
    var hidden by Prefs.string(HomeLayout.HIDDEN_KEY, "")
    var language by Prefs.string(Strings.KEY, "")
    var startTab by Prefs.string(AppState.START_TAB, "weapons")
    var specialsFirst by Prefs.bool(Prefs.SPECIALS_FIRST, false)
    var showLocked by Prefs.bool(Prefs.SHOW_LOCKED, false)
    var outline by Prefs.string(Prefs.CARD_OUTLINE, "prestige")
    var adConsent by remember { mutableStateOf(AdConsent.granted(AppState.store) == true) }
    var notice by remember { mutableStateOf<Premium.Notice?>(null) }
    val layout = HomeLayout(order, hidden)
    val openPremium = { AppState.push(Route.Premium) }

    Column(Modifier.fillMaxSize().appBackground(accent)) {
        TopBar(L("mw4.ui.customise"))
        LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(bottom = 32.dp)) {
            if (locked) item(key = "premium-card") {
                Group {
                    Row(
                        Modifier.fillMaxWidth().clickable(onClick = openPremium).padding(14.dp),
                        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp),
                    ) {
                        Box(Modifier.size(30.dp).clip(CircleShape).background(accent), contentAlignment = Alignment.Center) {
                            Icon(Icons.Filled.AutoAwesome, null, tint = Color.White, modifier = Modifier.size(16.dp))
                        }
                        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                            Text(L("mw4.ui.premium.customise_title"), style = sys(16f, FontWeight.SemiBold), color = Ink.text)
                            Text(L("mw4.ui.premium.customise_body"), style = sys(12f), color = Ink.muted)
                        }
                    }
                }
            }

            section(L("mw4.ui.modes"), footer = L("mw4.ui.modes.footer")) {
                Box(Modifier.padding(vertical = 4.dp)) { PlayedModesPicker() }
            }

            section(title = null) {
                Group {
                    PickerRow(
                        L("mw4.ui.language"), accent, language,
                        listOf("" to L("mw4.ui.language.system")) + Strings.supported,
                    ) { language = it; AppState.languageChanged() }
                    RowDivider()
                    PickerRow(
                        L("mw4.ui.start_tab"), accent, startTab,
                        listOfNotNull("weapons" to L("mw4.ui.section.weapons"), "mastery" to L("mw4.ui.section.mastery"),
                            ("dmz" to L("mw4.ui.hajin.title")).takeIf { AppState.tracker.game.hasHajin }, "stats" to L("mw4.ui.tab.stats")),
                    ) { startTab = it }
                }
            }

            headedSection(premiumHeader(locked, accent, openPremium), footer = L("mw4.ui.customise.footer")) {
                Group {
                    layout.order.forEachIndexed { index, homeSection ->
                        if (index > 0) RowDivider()
                        SectionRow(
                            homeSection, accent, shown = homeSection !in layout.hidden, enabled = !locked,
                            canUp = index > 0, canDown = index < layout.order.size - 1,
                            onShow = { show ->
                                val set = layout.hidden.toMutableSet()
                                if (show) set.remove(homeSection) else set.add(homeSection)
                                hidden = HomeSection.entries.filter { it in set }.joinToString(",") { it.raw }
                            },
                            onMove = { by ->
                                val list = layout.order.toMutableList()
                                list.add(index + by, list.removeAt(index))
                                order = list.joinToString(",") { it.raw }
                            },
                        )
                    }
                }
            }

            section(L("mw4.ui.tracking"), footer = L("mw4.ui.quick_tick.footer") + " " + L("mw4.ui.specials_first.footer")) {
                Group {
                    ToggleRow(L("mw4.ui.quick_tick.title"), t.quickTick, accent) { t.quickTick = it }
                    RowDivider()
                    ToggleRow(L("mw4.ui.specials_first.title"), specialsFirst, accent) { specialsFirst = it }
                }
            }

            headedSection(premiumHeader(locked, accent, openPremium), footer = L("mw4.ui.customise.locked_footer")) {
                Group { ToggleRow(L("mw4.ui.customise.locked_title"), showLocked, accent, enabled = !locked) { showLocked = it } }
            }

            headedSection(premiumHeader(locked, accent, openPremium), footer = L("mw4.ui.card_outline.footer")) {
                Group {
                    PickerRow(
                        L("mw4.ui.card_outline.title"), accent, outline,
                        listOf("prestige", "completionist", "off").map { it to L("mw4.ui.card_outline.$it") }, enabled = !locked,
                    ) { outline = it }
                }
            }

            if (AdConsent.applies(context) && !Premium.isPremium) {
                section(title = null, footer = L("ct.ads.consent.footer")) {
                    Group {
                        ToggleRow(L("ct.ads.consent.toggle"), adConsent, accent) { adConsent = it; AdConsent.set(AppState.store, it) }
                    }
                }
            }

            section(title = null) {
                Group {
                    if (WhatsNew.items(AppState.store).isNotEmpty()) {
                        LinkRow(Icons.Filled.AutoAwesome, L("ct.whatsnew.title"), accent) { AppState.push(Route.WhatsNew) }
                        RowDivider()
                    }
                    LinkRow(Icons.Filled.AppShortcut, L("mw4.ui.app_icon.title"), accent) { AppState.push(Route.AppIcons) }
                    LinkRow(Icons.Filled.Podcasts, L("ct.overlay.title"), accent) { AppState.push(Route.StreamOverlay) }
                }
            }

            section(title = null, footer = if (Premium.isPremium) null else L("mw4.ui.premium.subtitle")) {
                Group {
                    if (Premium.isPremium) {
                        Row(
                            Modifier.fillMaxWidth().clickable(onClick = openPremium).padding(horizontal = 16.dp, vertical = 12.dp),
                            horizontalArrangement = Arrangement.spacedBy(10.dp),
                        ) {
                            Icon(Icons.Filled.Verified, null, tint = accent, modifier = Modifier.size(20.dp))
                            Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
                                Text(Premium.plan?.line ?: L("ct.premium.plan.unknown"), style = sys(16f, FontWeight.SemiBold), color = Ink.text)
                                Text(L("ct.premium.thanks_short"), style = sys(13f), color = Ink.muted)
                            }
                        }
                    } else {
                        LinkRow(Icons.Filled.AutoAwesome, L("mw4.ui.premium.title"), accent, onClick = openPremium)
                    }
                    RowDivider()
                    Row(Modifier.padding(horizontal = 4.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        if (Premium.isSubscriber) {
                            TextButton(onClick = {
                                context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(
                                    "https://play.google.com/store/account/subscriptions?sku=${Premium.YEARLY}&package=${context.packageName}")))
                            }) { Text(L("ct.premium.manage"), color = accent, fontWeight = FontWeight.SemiBold) }
                        }
                        TextButton(onClick = { scope.launch { notice = Premium.restore() } }) {
                            Text(L("mw4.ui.premium.restore"), color = accent, fontWeight = FontWeight.SemiBold)
                        }
                    }
                }
            }

            section(title = null) {
                Group {
                    LinkRow(Icons.Outlined.PrivacyTip, L("mw4.ui.premium.privacy"), accent) {
                        context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(PRIVACY_URL)))
                    }
                    RowDivider()
                    LinkRow(Icons.Outlined.Email, L("mw4.ui.support"), accent, detail = SupportMail.ADDRESS) { SupportMail.open(context) }
                }
            }

            if (!locked) section(title = null) {
                Group {
                    Text(
                        L("mw4.ui.customise.reset"), style = sys(16f), color = accent,
                        modifier = Modifier.fillMaxWidth().clickable { order = ""; hidden = "" }.padding(horizontal = 16.dp, vertical = 13.dp),
                    )
                }
            }
        }
    }
    notice?.let { n ->
        AlertDialog(
            onDismissRequest = { notice = null },
            containerColor = LocalPalette.current.surface2,
            title = { Text(n.title, color = Ink.text) },
            text = { Text(n.message, color = Ink.muted) },
            confirmButton = { TextButton(onClick = { notice = null }) { Text(L("mw4.ui.done")) } },
        )
    }
}

/** The modes that get a tab: a chip each, at least one on (iOS PlayedModesPicker). */
@Composable
fun PlayedModesPicker() {
    val t = tracker()
    var raw by Prefs.string(ModeSelection.playedKey(t.game), "")
    val all = t.modeIds
    val played = ModeSelection.played(raw, all)
    val offered = all.filter { t.modes[it]?.hidden != true }
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        for (mode in offered) {
            val on = mode in played
            val accent = modeAccent(mode)
            val shape = RoundedCornerShape(14.dp)
            val muted = Ink.muted.copy(alpha = 0.3f)
            Box(
                Modifier.weight(1f).clip(shape)
                    .background(if (on) accent.copy(alpha = 0.18f) else Color.Transparent)
                    .then(
                        if (on) Modifier.border(2.dp, accent, shape)
                        else Modifier.drawBehind {
                            drawRoundRect(muted, cornerRadius = CornerRadius(14.dp.toPx()),
                                style = Stroke(1.dp.toPx(), pathEffect = PathEffect.dashPathEffect(floatArrayOf(4.dp.toPx(), 3.dp.toPx()))))
                        },
                    )
                    .clickable {
                        val next = ModeSelection.toggling(mode, raw, all)
                        if (next != raw) { raw = next; AppState.touch() }
                    },
            ) {
                Column(
                    Modifier.fillMaxWidth().padding(vertical = 12.dp),
                    horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(5.dp),
                ) {
                    val color = if (on) accent else Ink.muted.copy(alpha = 0.7f)
                    Icon(modeIcon(mode), null, tint = color, modifier = Modifier.size(20.dp))
                    Text(modeName(mode), style = sys(12f, FontWeight.Bold), color = color, maxLines = 1, overflow = TextOverflow.Ellipsis,
                        modifier = Modifier.padding(horizontal = 6.dp))
                }
                Icon(
                    if (on) Icons.Filled.CheckCircle else Icons.Outlined.Circle, null,
                    tint = if (on) accent else Ink.muted.copy(alpha = 0.5f),
                    modifier = Modifier.align(Alignment.TopEnd).padding(6.dp).size(15.dp),
                )
            }
        }
    }
}

// MARK: - Settings rows

/** A section's header: plain text, or (free players) the Premium lock that opens Premium. */
private sealed interface Header {
    data class Plain(val text: String) : Header
    data class Premium(val accent: Color, val open: () -> Unit) : Header
}

private fun premiumHeader(locked: Boolean, accent: Color, open: () -> Unit): Header? = if (locked) Header.Premium(accent, open) else null

private fun LazyListScope.section(title: String?, footer: String? = null, content: @Composable () -> Unit) =
    headedSection(title?.let { Header.Plain(it) }, footer, content)

private fun LazyListScope.headedSection(header: Header?, footer: String? = null, content: @Composable () -> Unit) {
    item {
        Column(Modifier.fillMaxWidth().padding(top = 18.dp)) {
            when (header) {
                is Header.Plain -> Text(header.text.uppercase(appLocale), style = sys(12.5f), color = Ink.muted,
                    modifier = Modifier.padding(horizontal = 32.dp, vertical = 6.dp))
                is Header.Premium -> Row(
                    Modifier.fillMaxWidth().clickable(onClick = header.open).padding(horizontal = 32.dp, vertical = 6.dp),
                    horizontalArrangement = Arrangement.End, verticalAlignment = Alignment.CenterVertically,
                ) {
                    Icon(Icons.Filled.Lock, null, tint = header.accent, modifier = Modifier.size(12.dp))
                    Spacer(Modifier.width(4.dp))
                    Text(L("mw4.ui.app_icon.premium"), style = sys(12f, FontWeight.SemiBold), color = header.accent)
                }
                null -> {}
            }
            Box(Modifier.padding(horizontal = 16.dp)) { content() }
            if (footer != null) {
                Text(footer, style = sys(12.5f), color = Ink.muted, modifier = Modifier.padding(horizontal = 32.dp, vertical = 6.dp))
            }
        }
    }
}

/** An inset group of rows on the surface. */
@Composable
private fun Group(content: @Composable ColumnScope.() -> Unit) {
    Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(10.dp)).background(LocalPalette.current.surface), content = content)
}

@Composable
private fun RowDivider() {
    Box(Modifier.padding(start = 16.dp).fillMaxWidth().height(0.5.dp).background(Ink.muted.copy(alpha = 0.2f)))
}

@Composable
private fun ToggleRow(title: String, checked: Boolean, accent: Color, enabled: Boolean = true, onChange: (Boolean) -> Unit) {
    Row(
        Modifier.fillMaxWidth().clickable(enabled = enabled) { onChange(!checked) }.padding(horizontal = 16.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(title, style = sys(16f), color = if (enabled) Ink.text else Ink.muted, modifier = Modifier.weight(1f))
        Switch(
            checked = checked, onCheckedChange = onChange, enabled = enabled,
            colors = SwitchDefaults.colors(checkedTrackColor = accent, checkedThumbColor = Color.White, disabledCheckedTrackColor = accent.copy(alpha = 0.35f), disabledCheckedThumbColor = Color.White.copy(alpha = 0.6f)),
        )
    }
}

/** A setting with a few choices: its value on the right, a menu of the rest. */
@Composable
private fun PickerRow(title: String, accent: Color, selection: String, options: List<Pair<String, String>>, enabled: Boolean = true, onPick: (String) -> Unit) {
    var open by remember { mutableStateOf(false) }
    Box {
        Row(
            Modifier.fillMaxWidth().clickable(enabled = enabled) { open = true }.padding(horizontal = 16.dp, vertical = 14.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(title, style = sys(16f), color = if (enabled) Ink.text else Ink.muted, modifier = Modifier.weight(1f))
            Text(options.firstOrNull { it.first == selection }?.second ?: options.first().second, style = sys(16f),
                color = if (enabled) accent else Ink.muted)
            Icon(Icons.Filled.UnfoldMore, null, tint = if (enabled) accent else Ink.muted, modifier = Modifier.size(18.dp))
        }
        DropdownMenu(open, onDismissRequest = { open = false }, containerColor = LocalPalette.current.surface2,
            modifier = Modifier.align(Alignment.TopEnd)) {
            for ((value, label) in options) {
                DropdownMenuItem(
                    text = { Text(label, color = Ink.text) },
                    leadingIcon = { if (value == selection) Icon(Icons.Filled.Check, null, tint = Ink.text) else Spacer(Modifier.size(24.dp)) },
                    onClick = { open = false; if (value != selection) onPick(value) },
                )
            }
        }
    }
}

@Composable
private fun LinkRow(icon: ImageVector, title: String, accent: Color, detail: String? = null, onClick: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().clickable(onClick = onClick).padding(horizontal = 16.dp, vertical = 13.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Icon(icon, null, tint = accent, modifier = Modifier.size(20.dp))
        Column(Modifier.weight(1f)) {
            Text(title, style = sys(16f), color = accent)
            detail?.let { Text(it, style = sys(12f, mono = true), color = Ink.muted) }
        }
    }
}

/** A Weapons tab section: its symbol, a switch to show it, and arrows to move it. */
@Composable
private fun SectionRow(
    section: HomeSection, accent: Color, shown: Boolean, enabled: Boolean, canUp: Boolean, canDown: Boolean,
    onShow: (Boolean) -> Unit, onMove: (Int) -> Unit,
) {
    Row(Modifier.fillMaxWidth().padding(start = 16.dp, end = 4.dp, top = 4.dp, bottom = 4.dp), verticalAlignment = Alignment.CenterVertically) {
        Icon(section.icon, null, tint = accent, modifier = Modifier.size(20.dp))
        Spacer(Modifier.width(12.dp))
        Text(L(section.titleKey), style = sys(16f), color = if (enabled) Ink.text else Ink.muted, modifier = Modifier.weight(1f))
        Switch(
            checked = shown, onCheckedChange = onShow, enabled = enabled && section.canHide,
            colors = SwitchDefaults.colors(checkedTrackColor = accent, checkedThumbColor = Color.White, disabledCheckedTrackColor = accent.copy(alpha = 0.35f), disabledCheckedThumbColor = Color.White.copy(alpha = 0.6f)),
        )
        IconButton(onClick = { onMove(-1) }, enabled = enabled && canUp) {
            Icon(Icons.Filled.KeyboardArrowUp, L("ct.android.move_up"), tint = Ink.muted, modifier = Modifier.alpha(if (enabled && canUp) 1f else 0.3f))
        }
        IconButton(onClick = { onMove(1) }, enabled = enabled && canDown, modifier = Modifier.padding(start = 0.dp)) {
            Icon(Icons.Filled.KeyboardArrowDown, L("ct.android.move_down"), tint = Ink.muted, modifier = Modifier.alpha(if (enabled && canDown) 1f else 0.3f))
        }
    }
}
