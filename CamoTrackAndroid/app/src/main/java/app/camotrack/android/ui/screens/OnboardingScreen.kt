package app.camotrack.android.ui.screens

import android.Manifest
import android.icu.text.ListFormatter
import android.os.Build
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.BarChart
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Diamond
import androidx.compose.material.icons.filled.EmojiEvents
import androidx.compose.material.icons.filled.PushPin
import androidx.compose.material.icons.filled.Tune
import androidx.compose.material.icons.filled.TouchApp
import androidx.compose.material.icons.automirrored.filled.Chat
import androidx.compose.material.icons.outlined.Circle
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.camotrack.android.AppState
import app.camotrack.android.WhatsNew
import app.camotrack.android.core.BuiltInColors
import app.camotrack.android.core.ChallengeItem
import app.camotrack.android.core.Game
import app.camotrack.android.core.GameTracker
import app.camotrack.android.core.LocalizedText
import app.camotrack.android.core.Requirement
import app.camotrack.android.i18n.L
import app.camotrack.android.ui.*
import app.camotrack.android.ui.share.ShareCard
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * The walkthrough (iOS OnboardingView): the game, the modes played, how to
 * track, the real rows to tap, Suggested, making it yours, Free and Premium,
 * and on the first run what the one notification is for, whose button leads
 * to Android's permission prompt. Replayed from the Weapons title's help.
 */
@Composable
fun OnboardingScreen() {
    val store = AppState.store
    val firstRun = remember { !store.getBoolean(AppState.HAS_ONBOARDED) }
    val pageCount = if (firstRun) 8 else 7
    val pager = rememberPagerState { pageCount }
    val scope = rememberCoroutineScope()
    val page = pager.currentPage
    val t = tracker()
    val gameAccent = hexColor(t.game.theme?.accent) ?: CamoGold
    val accent by animateColorAsState(
        when (page) {
            0, 1 -> gameAccent
            2 -> ModeColors.warzone
            3 -> ModeColors.multiplayer
            4 -> PlatinumColors[0]
            5 -> Color(BuiltInColors.mercurialDrift)
            6 -> ModeColors.dmz
            else -> CamoGold
        }, label = "accent",
    )

    fun finish() {
        // A fresh install starts on this version: nothing is "new"
        if (firstRun) WhatsNew.markSeen(store)
        store.putBoolean(AppState.HAS_ONBOARDED, true)
        AppState.showsOnboarding = false
    }
    val askNotifications = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { finish() }
    fun done() {
        if (firstRun && Build.VERSION.SDK_INT >= 33) askNotifications.launch(Manifest.permission.POST_NOTIFICATIONS) else finish()
    }

    // Back steps through the pages; on the first, a replay closes (the first run has to finish)
    BackHandler(page > 0 || !firstRun) {
        if (page > 0) scope.launch { pager.animateScrollToPage(page - 1) } else AppState.showsOnboarding = false
    }

    Column(
        Modifier.fillMaxSize().background(LocalPalette.current.background)
            .background(Brush.verticalGradient(0f to accent.copy(alpha = 0.16f), 0.5f to Color.Transparent))
            .systemBarsPadding().padding(vertical = 20.dp),
        verticalArrangement = Arrangement.spacedBy(18.dp),
    ) {
        // Header: the step, and segmented bars
        Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Text("${L("mw4.onboarding.step")} ${page + 1}/$pageCount".uppercase(appLocale), style = sys(11f, FontWeight.Bold), color = accent)
            Row(horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                for (index in 0 until pageCount) {
                    val width by animateDpAsState(if (index == page) 28.dp else 16.dp, label = "bar")
                    Box(Modifier.width(width).height(3.dp).clip(RoundedCornerShape(1.5.dp))
                        .background(if (index <= page) accent else Ink.muted.copy(alpha = 0.25f)))
                }
            }
        }

        HorizontalPager(pager, Modifier.weight(1f), verticalAlignment = Alignment.Top) { index ->
            when (index) {
                0 -> GamePickerPage()
                1 -> WelcomePage()
                2 -> TrackingStylePage(ModeColors.warzone)
                3 -> MarkProgressPage()
                4 -> SuggestedPage()
                5 -> MakeItYoursPage(Color(BuiltInColors.mercurialDrift))
                6 -> FreeAndPremiumPage(ModeColors.dmz)
                else -> NotificationsPage()
            }
        }

        Column(Modifier.padding(horizontal = 24.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(14.dp)) {
            val last = page >= pageCount - 1
            Text(
                L(if (!last) "mw4.onboarding.next" else if (firstRun) "mw4.onboarding.continue" else "mw4.onboarding.get_started"),
                style = displayStyle(16.sp), color = LocalPalette.current.background, textAlign = TextAlign.Center,
                modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(8.dp)).background(accent)
                    .clickable { if (!last) scope.launch { pager.animateScrollToPage(page + 1) } else done() }
                    .padding(vertical = 15.dp),
            )
            if (!last) {
                // Skipping still lands on the notifications page when there is one, so the prompt never comes unexplained
                Text(
                    L("mw4.onboarding.skip"), style = sys(13f, FontWeight.SemiBold), color = Ink.muted,
                    modifier = Modifier.clip(RoundedCornerShape(6.dp)).clickable {
                        if (firstRun) scope.launch { pager.animateScrollToPage(pageCount - 1) } else finish()
                    }.padding(horizontal = 12.dp, vertical = 4.dp),
                )
            }
        }
    }
}

/** Page chrome: an optional kicker, the title in the display face, then the page. */
@Composable
private fun Scaffold(title: String, content: @Composable ColumnScope.() -> Unit) {
    Column(
        Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(top = 12.dp, bottom = 24.dp),
        verticalArrangement = Arrangement.spacedBy(20.dp),
    ) {
        Text(title, style = displayStyle(27.sp), color = Ink.text, textAlign = TextAlign.Center,
            modifier = Modifier.fillMaxWidth().padding(horizontal = 24.dp))
        Column(Modifier.padding(horizontal = 24.dp), content = content)
    }
}

/** Which game to track. Each keeps its own progress; the Weapons title switches later. */
@Composable
private fun GamePickerPage() {
    val t = tracker()
    Scaffold(L("ct.onboarding.game.title")) {
        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Text(L("ct.onboarding.game.body"), style = sys(14f), color = Ink.muted, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth())
            for (game in AppState.games) GameCard(game, game == t.game)
        }
    }
}

@Composable
private fun GameCard(game: Game, on: Boolean) {
    val color = hexColor(game.theme?.accent) ?: CamoGold
    val modes = ListFormatter.getInstance(appLocale).format(game.modes.map { it.name?.resolved() ?: L("mw4.mode.${it.id}") })
    val shape = RoundedCornerShape(10.dp)
    Row(
        Modifier.fillMaxWidth().clip(shape).background(if (on) color.copy(alpha = 0.14f) else LocalPalette.current.surface)
            .border(if (on) 2.dp else 1.dp, if (on) color else Ink.muted.copy(alpha = 0.25f), shape)
            // The game is the current one from the tap, so the pages after show its modes and look
            .clickable(enabled = !on) { AppState.open(game) }
            .padding(14.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Text(
            game.shortName, maxLines = 1, color = color, textAlign = TextAlign.Center, modifier = Modifier.width(74.dp),
            style = androidx.compose.ui.text.TextStyle(fontFamily = Fonts.named(game.theme?.font), fontWeight = FontWeight.Bold,
                fontSize = (24 * (game.theme?.fontScale ?: 1.0)).sp),
        )
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Text(game.name.resolved(), style = sys(16f, FontWeight.Bold), color = Ink.text)
            Text(modes, style = sys(12.5f), color = Ink.muted)
        }
        Icon(if (on) Icons.Filled.CheckCircle else Icons.Outlined.Circle, null, tint = if (on) color else Ink.muted.copy(alpha = 0.5f),
            modifier = Modifier.size(22.dp))
    }
}

@Composable
private fun WelcomePage() {
    val t = tracker()
    val context = LocalContext.current
    val icon = remember { ShareCard.appIcon(context) }
    // MW4 keeps its own line; another game lists its modes
    val body = if (t.game.isMW4) L("mw4.onboarding.welcome.body")
    else L("ct.onboarding.welcome.body", t.game.shortName, ListFormatter.getInstance(appLocale).format(t.modeIds.map(::modeName)))
    Scaffold(L("mw4.onboarding.welcome.title")) {
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(20.dp)) {
            icon?.let { Image(it, null, Modifier.size(110.dp).clip(RoundedCornerShape(24.dp))) }
            Text(body, style = sys(15f), color = Ink.muted, textAlign = TextAlign.Center,
                modifier = Modifier.fillMaxWidth().borderedCard().padding(14.dp))
            Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(L("mw4.ui.modes"), style = sys(13f, FontWeight.Bold), color = Ink.text)
                Text(L("mw4.onboarding.modes.hint"), style = sys(12.5f), color = Ink.muted)
                PlayedModesPicker()
            }
        }
    }
}

/** Full tracking or quick tick, picked here and changeable in Customise. */
@Composable
private fun TrackingStylePage(accent: Color) {
    val t = tracker()
    Scaffold(L("mw4.onboarding.tracking.title")) {
        Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
            TrackingOption(t, false, Icons.Filled.BarChart, L("mw4.onboarding.tracking.full.title"),
                L(if (t.game.sharedCamos == true) "mw4.onboarding.tracking.full.body" else "ct.onboarding.tracking.full.body"), accent)
            TrackingOption(t, true, Icons.Filled.CheckCircle, L("mw4.ui.quick_tick.title"), L("mw4.onboarding.tracking.quick.body"), accent)
            Text(L("mw4.onboarding.tracking.footer"), style = sys(13f), color = Ink.muted)
        }
    }
}

@Composable
private fun TrackingOption(t: GameTracker, quick: Boolean, icon: ImageVector, title: String, body: String, accent: Color) {
    val picked = t.quickTick == quick
    Row(
        Modifier.fillMaxWidth().borderedCard(accent = if (picked) accent else null).clickable { t.quickTick = quick }.padding(14.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Icon(icon, null, tint = if (picked) accent else Ink.muted, modifier = Modifier.size(22.dp))
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(title, style = displayStyle(16.sp), color = Ink.text)
            Text(body, style = sys(13.5f), color = Ink.muted)
        }
        Icon(if (picked) Icons.Filled.CheckCircle else Icons.Outlined.Circle, null, tint = if (picked) accent else Ink.muted, modifier = Modifier.size(22.dp))
    }
}

/**
 * Real rows to tap, kept on the page only (nothing is saved): tick the
 * circle, type a count, and once both are done the "Camos complete"
 * banner. In quick tick, the first weapon's last two Military camos,
 * where ticking the second ticks the first too.
 */
@Composable
private fun MarkProgressPage() {
    val t = tracker()
    val names = listOf("Smoke", "Stormwave")
    val required = listOf(10, 10)
    val firstWeapon = t.weapons(t.visibleModes.first()).firstOrNull()
    val quickDemo = firstWeapon?.let { w -> t.camos(w.weaponId, t.visibleModes.first()).filter { it.group == "military" }.takeLast(2) }.orEmpty()
    val showsQuick = t.quickTick && quickDemo.size == 2
    val amounts = remember { mutableStateListOf(10, 6) }
    var celebrating by remember { mutableStateOf(false) }
    LaunchedEffect(celebrating) { if (celebrating) { delay(2400); celebrating = false } }
    fun check() { if (amounts.indices.all { amounts[it] >= required[it] }) celebrating = true }
    val accent = ModeColors.multiplayer

    Scaffold(L(if (t.quickTick) "mw4.onboarding.mark.quick_title" else "mw4.onboarding.mark.title")) {
        Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
            AnimatedVisibility(celebrating, enter = fadeIn(), exit = fadeOut()) {
                MilestoneBannerView(BannerText(L("mw4.ui.milestone.camos_complete_title"), L("mw4.onboarding.mark.celebration_subtitle"),
                    GoldColors, Icons.Filled.EmojiEvents), modifier = Modifier.fillMaxWidth())
            }
            for (index in 0..1) {
                Column(Modifier.fillMaxWidth().borderedCard().padding(12.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    val done = amounts[index] >= required[index]
                    if (showsQuick) {
                        val camo = quickDemo[index]
                        ChallengeRow(
                            item = camo, accent = accent, amount = amounts[index], isDone = done,
                            detail = camo.unlockLevel?.let { L("mw4.ui.camo_unlocks_reach", GameTracker.unlocks(it)) },
                            onToggle = {
                                val range = if (done) index until amounts.size else 0..index
                                for (each in range) amounts[each] = if (done) 0 else required[each]
                                check()
                            },
                            onSetAmount = {},
                        )
                    } else {
                        ChallengeRow(
                            item = ChallengeItem(index, LocalizedText(names[index]), requirement = Requirement(required[index], "kills",
                                LocalizedText(L("mw4.onboarding.mark.demo_challenge", required[index]))), children = emptyList()),
                            accent = accent, amount = amounts[index], isDone = done,
                            onToggle = { amounts[index] = if (done) 0 else required[index]; check() },
                            onSetAmount = { amounts[index] = it; check() },
                        )
                    }
                    val hint = if (index == 0) L("mw4.onboarding.mark.tap_circle")
                    else L(if (t.quickTick) "mw4.onboarding.mark.quick_hint" else "mw4.onboarding.mark.tap_pill")
                    Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        Icon(Icons.Filled.TouchApp, null, tint = ModeColors.multiplayerText, modifier = Modifier.size(15.dp))
                        Text(hint, style = sys(12.5f), color = ModeColors.multiplayerText)
                    }
                }
            }
        }
    }
}

@Composable
private fun SuggestedPage() {
    val t = tracker()
    val platinum = t.completionist(t.visibleModes.first()).steps[1]
    Scaffold(L("mw4.onboarding.suggested.title")) {
        Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
            Row(
                Modifier.fillMaxWidth().borderedCard(accent = CamoGold).padding(12.dp),
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                Box(Modifier.size(30.dp).clip(CircleShape).background(CamoGold), contentAlignment = Alignment.Center) {
                    Icon(Icons.Filled.EmojiEvents, null, tint = LocalPalette.current.background, modifier = Modifier.size(15.dp))
                }
                Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
                    Text("Kastov 762", style = displayStyle(15.sp), color = Ink.text)
                    Text(L("mw4.onboarding.suggested.demo"), style = sys(12.5f), color = Ink.muted)
                }
            }
            Text(L("mw4.onboarding.suggested.body1"), style = sys(15f), color = Ink.muted)
            MilestoneBannerView(
                BannerText(L("mw4.ui.milestone.unlocked_title", platinum.name), L("mw4.onboarding.suggested.banner_subtitle"), platinum.colors, Icons.Filled.Diamond),
                modifier = Modifier.fillMaxWidth(),
            )
            Text(L("mw4.onboarding.suggested.body2"), style = sys(15f), color = Ink.muted)
        }
    }
}

/** The ways to make the app your own, and how wrong data gets fixed. */
@Composable
private fun MakeItYoursPage(accent: Color) {
    Scaffold(L("mw4.onboarding.yours.title")) {
        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
            for ((icon, key) in listOf(
                Icons.Filled.PushPin to "mw4.onboarding.yours.pin",
                Icons.Filled.Tune to "mw4.onboarding.yours.customise",
                Icons.AutoMirrored.Filled.Chat to "mw4.onboarding.yours.report",
            )) {
                Row(Modifier.fillMaxWidth().borderedCard().padding(14.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    Icon(icon, null, tint = accent, modifier = Modifier.size(20.dp))
                    Text(L(key), style = sys(14.5f), color = Ink.text)
                }
            }
        }
    }
}

/** What's free and what Premium adds, said once, plainly, before anything asks for money. */
@Composable
private fun FreeAndPremiumPage(accent: Color) {
    Scaffold(L("mw4.onboarding.premium.title")) {
        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
            PerkGroup(L("mw4.onboarding.premium.free"), Icons.Filled.CheckCircle, accent, listOf("mw4.onboarding.premium.free_track"))
            PerkGroup(L("mw4.onboarding.premium.premium"), Icons.Filled.AutoAwesome, accent,
                listOf("mw4.ui.premium.perk_ads", "mw4.ui.premium.perk_icons", "mw4.ui.premium.perk_customise", "mw4.ui.premium.perk_pins"))
            Text(L("mw4.onboarding.premium.footer"), style = sys(13f), color = Ink.muted)
        }
    }
}

@Composable
private fun PerkGroup(title: String, icon: ImageVector, accent: Color, rows: List<String>) {
    Column(Modifier.fillMaxWidth().borderedCard().padding(14.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Icon(icon, null, tint = accent, modifier = Modifier.size(18.dp))
            Text(title, style = displayStyle(16.sp), color = accent)
        }
        for (key in rows) {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Text("•", style = sys(14.5f), color = Ink.muted)
                Text(L(key), style = sys(14.5f), color = Ink.text)
            }
        }
    }
}

/** The last first-run page: what the notification is for, with a preview of it. */
@Composable
private fun NotificationsPage() {
    val context = LocalContext.current
    val icon = remember { ShareCard.appIcon(context) }
    Scaffold(L("mw4.onboarding.notif.title")) {
        Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
            Row(
                Modifier.fillMaxWidth().clip(RoundedCornerShape(20.dp)).background(LocalPalette.current.surface2)
                    .border(1.dp, Ink.muted.copy(alpha = 0.25f), RoundedCornerShape(20.dp)).padding(13.dp),
                horizontalArrangement = Arrangement.spacedBy(11.dp),
            ) {
                icon?.let { Image(it, null, Modifier.size(40.dp).clip(RoundedCornerShape(9.dp))) }
                Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Row {
                        Text(L("mw4.notif.title"), style = sys(14f, FontWeight.SemiBold), color = Ink.text, modifier = Modifier.weight(1f),
                            maxLines = 1, overflow = TextOverflow.Ellipsis)
                        Text(L("mw4.onboarding.notif.now"), style = sys(12f), color = Ink.muted)
                    }
                    Text(L("mw4.notif.generic_body"), style = sys(13.5f), color = Ink.muted)
                }
            }
            Text(L("mw4.onboarding.notif.body"), style = sys(15f), color = Ink.muted)
            if (Build.VERSION.SDK_INT >= 33) Text(L("mw4.onboarding.notif.next_step"), style = sys(13f), color = Ink.muted.copy(alpha = 0.8f))
        }
    }
}
