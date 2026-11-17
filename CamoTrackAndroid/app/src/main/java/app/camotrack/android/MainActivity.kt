package app.camotrack.android

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.SystemBarStyle
import androidx.activity.compose.BackHandler
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.BarChart
import androidx.compose.material.icons.filled.MilitaryTech
import androidx.compose.material.icons.filled.GpsFixed
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.clickable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import app.camotrack.android.ui.MilestoneBannerView
import app.camotrack.android.ui.bannerText
import androidx.compose.ui.graphics.vector.ImageVector
import app.camotrack.android.i18n.L
import app.camotrack.android.ui.AppPalette
import app.camotrack.android.ui.CamoTheme
import app.camotrack.android.ui.Fonts
import app.camotrack.android.ui.Ink
import app.camotrack.android.ui.hexColor
import app.camotrack.android.ui.screens.MasteryScreen
import app.camotrack.android.ui.screens.RouteScreen
import app.camotrack.android.ui.screens.StatsScreen
import app.camotrack.android.ui.screens.WeaponsHome
import app.camotrack.android.ui.screens.OnboardingScreen
import app.camotrack.android.ui.screens.WhatsNewScreen
import app.camotrack.android.ui.screens.findActivity
import app.camotrack.android.ui.share.ShareRequest
import app.camotrack.android.ui.share.ShareSheetHost
import app.camotrack.android.ui.share.Sharing
import app.camotrack.android.services.AdConsent
import app.camotrack.android.services.Ads
import app.camotrack.android.services.Interstitials
import app.camotrack.android.ui.LocalPalette
import app.camotrack.android.ui.sys
import androidx.compose.ui.platform.LocalContext

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Light status and navigation bar icons: the app is always on a dark ground
        enableEdgeToEdge(
            statusBarStyle = SystemBarStyle.dark(android.graphics.Color.TRANSPARENT),
            navigationBarStyle = SystemBarStyle.dark(android.graphics.Color.TRANSPARENT),
        )
        if (savedInstanceState == null) openLink(intent)
        setContent { Root() }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        openLink(intent)
    }

    override fun onResume() {
        super.onResume()
        // Free players: the ad SDK, once onboarding and the consent question are behind them
        Ads.start(this)
    }

    /** A notification's (or any) mw4camo:// link. */
    private fun openLink(intent: Intent?) {
        val link = intent?.data?.toString() ?: return
        if (link.startsWith("mw4camo://")) AppState.openLink(link)
    }
}

/** The game's look (games.json theme) over the defaults, accented by the Weapons tab's mode. */
@Composable
fun currentPalette(): AppPalette {
    val t = AppState.tracker
    AppState.revision
    val theme = t.game.theme
    val base = AppPalette()
    return base.copy(
        background = hexColor(theme?.background) ?: base.background,
        surface = hexColor(theme?.surface) ?: base.surface,
        surface2 = hexColor(theme?.surface2) ?: base.surface2,
        accent = androidx.compose.ui.graphics.Color(t.modeAccent(AppState.mode)),
        display = Fonts.named(theme?.font),
        displayScale = (theme?.fontScale ?: 1.0).toFloat(),
    )
}

@Composable
private fun Root() {
    // A language change redraws every screen in it
    key(AppState.languageTick) { Screens() }
}

@Composable
private fun Screens() {
    val palette = currentPalette()
    val context = LocalContext.current
    CamoTheme(palette) {
        val stack = AppState.stacks.getValue(AppState.tab)
        BackHandler(stack.isNotEmpty()) { AppState.pop() }
        Scaffold(
            containerColor = palette.background,
            bottomBar = {
                Column {
                // Free players: the banner above the tabs on each tab's main screen (as on iPhone)
                if (stack.isEmpty()) app.camotrack.android.ui.AdBanner()
                NavigationBar(containerColor = palette.surface) {
                    TabItem(Tab.WEAPONS, Icons.Filled.GpsFixed, L("mw4.ui.section.weapons"))
                    TabItem(Tab.MASTERY, Icons.Filled.MilitaryTech, L("mw4.ui.section.mastery"))
                    TabItem(Tab.STATS, Icons.Filled.BarChart, L("mw4.ui.tab.stats"))
                }
                }
            },
        ) { padding ->
            Box(Modifier.padding(bottom = padding.calculateBottomPadding()).fillMaxSize()) {
                val route = stack.lastOrNull()
                when {
                    route != null -> RouteScreen(route, AppState.mode)
                    AppState.tab == Tab.WEAPONS -> WeaponsHome(AppState.mode)
                    AppState.tab == Tab.MASTERY -> MasteryScreen()
                    else -> StatsScreen()
                }
                MilestoneOverlay()
            }
        }
        WeaponInterstitials()
        // After an update, once, never over onboarding (iOS shows it after the splash)
        LaunchedEffect(Unit) {
            if (!AppState.showsOnboarding && WhatsNew.shouldShow(AppState.store, AppState.store.getBoolean(AppState.HAS_ONBOARDED))) {
                AppState.showsWhatsNew = true
            }
        }
        if (AppState.showsWhatsNew && !AppState.showsOnboarding) {
            BackHandler { AppState.showsWhatsNew = false }
            WhatsNewScreen(onClose = { AppState.showsWhatsNew = false })
        }
        if (AppState.showsOnboarding) OnboardingScreen()
        AdConsentQuestion()
        ShareSheetHost()
    }
}

/**
 * The "About ads" question where the law asks it (EU, EEA, UK, Switzerland),
 * for free players from their second session, once nothing else is up
 * (onboarding, What's New); then the ad SDK starts.
 */
@Composable
private fun AdConsentQuestion() {
    val context = LocalContext.current
    var asking by remember { mutableStateOf(false) }
    val busy = AppState.showsOnboarding || AppState.showsWhatsNew || Sharing.request != null
    LaunchedEffect(busy) {
        if (busy) return@LaunchedEffect
        kotlinx.coroutines.delay(1_000)
        asking = Ads.showsAds && AppState.store.getBoolean(Ads.PAST_FIRST_SESSION) && AdConsent.needsAsking(context, AppState.store)
    }
    if (!asking) return
    fun answer(yes: Boolean) {
        asking = false
        AdConsent.set(AppState.store, yes)
        Ads.start(context)
    }
    AlertDialog(
        onDismissRequest = {},
        containerColor = LocalPalette.current.surface2,
        title = { Text(L("ct.ads.consent.title"), color = Ink.text) },
        text = { Text(L("ct.ads.consent.message"), color = Ink.muted) },
        confirmButton = { TextButton(onClick = { answer(true) }) { Text(L("ct.ads.consent.yes")) } },
        dismissButton = { TextButton(onClick = { answer(false) }) { Text(L("ct.ads.consent.no")) } },
    )
}

/**
 * Opening a weapon notes it; coming back from one to a list (the Weapons
 * tab or a class) may show a full-screen ad (iOS Interstitials).
 */
@Composable
private fun WeaponInterstitials() {
    val context = LocalContext.current
    val top = AppState.stacks.getValue(AppState.tab).lastOrNull()
    LaunchedEffect(top, AppState.tab) {
        when (top) {
            is Route.Weapon -> Interstitials.leftWeapon = true
            null, is Route.WeaponCategory, Route.AllWeapons -> if (AppState.tab == Tab.WEAPONS || top != null) {
                context.findActivity()?.let { Interstitials.weaponClosed(it, AppState.store, AppState.tracker.game.id) }
            }
            else -> {}
        }
    }
}

/** The latest milestone's banner, at the top for six seconds (iOS's MilestoneBannerView in ContentView). */
@Composable
private fun BoxScope.MilestoneOverlay() {
    val milestone = AppState.milestone
    LaunchedEffect(milestone) {
        if (milestone != null) {
            kotlinx.coroutines.delay(6_000)
            if (AppState.milestone == milestone) AppState.milestone = null
        }
    }
    AnimatedVisibility(
        visible = milestone != null,
        enter = slideInVertically { -it } + fadeIn(),
        exit = slideOutVertically { -it } + fadeOut(),
        modifier = Modifier.align(Alignment.TopCenter).statusBarsPadding().padding(top = 8.dp),
    ) {
        // Kept through the exit animation
        val shown = remember { mutableStateOf(milestone) }
        if (milestone != null) shown.value = milestone
        shown.value?.let { m ->
            // Its Share button (or a tap anywhere on it) opens the milestone's card
            val share = { Sharing.open(ShareRequest.Milestone(m)); AppState.milestone = null }
            MilestoneBannerView(bannerText(m), onShare = share, modifier = Modifier.clickable(onClick = share))
        }
    }
}

@Composable
private fun RowScope.TabItem(tab: Tab, icon: ImageVector, label: String) {
    val selected = AppState.tab == tab
    NavigationBarItem(
        selected = selected,
        onClick = { if (selected) AppState.stacks.getValue(tab).clear() else AppState.tab = tab },
        icon = { Icon(icon, contentDescription = null) },
        label = { Text(label) },
        colors = NavigationBarItemDefaults.colors(
            selectedIconColor = MaterialTheme.colorScheme.primary, selectedTextColor = MaterialTheme.colorScheme.primary,
            unselectedIconColor = Ink.muted, unselectedTextColor = Ink.muted,
            indicatorColor = MaterialTheme.colorScheme.surfaceVariant,
        ),
    )
}
