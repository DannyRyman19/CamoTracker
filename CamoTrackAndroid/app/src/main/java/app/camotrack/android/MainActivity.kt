package app.camotrack.android

import android.os.Bundle
import androidx.activity.ComponentActivity
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

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent { Root() }
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
    val palette = currentPalette()
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
        shown.value?.let { MilestoneBannerView(bannerText(it), modifier = Modifier.clickable { AppState.milestone = null }) }
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
