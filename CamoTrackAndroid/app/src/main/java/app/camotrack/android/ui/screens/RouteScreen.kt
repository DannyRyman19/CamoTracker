package app.camotrack.android.ui.screens

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import app.camotrack.android.Route
import app.camotrack.android.i18n.L
import app.camotrack.android.ui.TopBar
import app.camotrack.android.ui.appBackground
import app.camotrack.android.ui.modeAccent
import app.camotrack.android.ui.tracker

/** A pushed screen (iOS's RouteDestinationView); routes not ported yet show a placeholder. */
@Composable
fun RouteScreen(route: Route, mode: String) {
    val t = tracker()
    when (route) {
        is Route.WeaponCategory -> {
            val category = t.categories(mode).firstOrNull { it.categoryId == route.categoryId }
                ?: t.catalog?.categories?.firstOrNull { it.categoryId == route.categoryId }
            if (category != null) WeaponListScreen(mode, category, category.name.resolved()) else Missing()
        }
        Route.AllWeapons -> {
            val all = t.allWeaponsCategory(mode)
            if (all != null) WeaponListScreen(mode, all, L("mw4.ui.all_weapons")) else Missing()
        }
        is Route.Weapon -> {
            val weapon = t.weapon(route.weaponId)
            if (weapon != null) WeaponDetailScreen(mode, weapon) else Missing()
        }
        is Route.ObjectiveCategory -> {
            val category = t.modes[mode]?.objectives?.firstOrNull { it.categoryId == route.categoryId }
            if (category != null) ObjectiveListScreen(mode, category) else Missing()
        }
        is Route.ObjectiveItem -> {
            val category = t.modes[mode]?.objectives?.firstOrNull { it.categoryId == route.categoryId }
            val item = category?.items?.firstOrNull { it.itemId == route.itemId }
            if (category != null && item != null) ObjectiveItemScreen(mode, category, item) else Missing()
        }
        Route.Customise -> Pending(L("mw4.ui.customise"), mode)
        Route.Premium -> PremiumScreen()
        Route.StreamOverlay -> StreamOverlayScreen()
        Route.AppIcons -> Pending(L("mw4.ui.app_icon.title"), mode)
        Route.WhatsNew -> Pending(L("ct.whatsnew.title"), mode)
    }
}

/** A screen someone else is porting: its bar, and a placeholder. */
@Composable
private fun Pending(title: String, mode: String) {
    Column(Modifier.fillMaxSize().appBackground(modeAccent(mode))) {
        TopBar(title)
        Box(Modifier.weight(1f)) { Placeholder(title) }
    }
}

/** The route's weapon or objective isn't in the data (any more). */
@Composable
private fun Missing() {
    Column(Modifier.fillMaxSize()) {
        TopBar("")
        Box(Modifier.weight(1f)) { Placeholder(L("mw4.ui.filter.empty")) }
    }
}
