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
import androidx.compose.ui.Modifier
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
                NavigationBar(containerColor = palette.surface) {
                    TabItem(Tab.WEAPONS, Icons.Filled.GpsFixed, L("mw4.ui.section.weapons"))
                    TabItem(Tab.MASTERY, Icons.Filled.MilitaryTech, L("mw4.ui.section.mastery"))
                    TabItem(Tab.STATS, Icons.Filled.BarChart, L("mw4.ui.tab.stats"))
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
            }
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
