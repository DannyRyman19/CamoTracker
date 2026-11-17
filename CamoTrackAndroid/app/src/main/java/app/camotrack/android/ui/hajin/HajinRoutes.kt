package app.camotrack.android.ui.hajin

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import app.camotrack.android.Route
import app.camotrack.android.i18n.L
import app.camotrack.android.ui.FilterEmptyRow
import app.camotrack.android.ui.TopBar

/** A screen pushed on the Hajin tab (iOS HajinScreenView, HajinItemRoute, HajinOrderRoute). */
@Composable
fun HajinRouteScreen(route: Route) {
    val store = hajin()
    when (route) {
        is Route.HajinSection -> store.guide?.section(route.id)?.let { GuideSectionScreen(it) } ?: Missing()
        is Route.HajinItem -> HajinItemScreen(route.id)
        is Route.HajinOrder -> HajinOrderScreen(route.check)
        is Route.HajinMap -> HajinMapScreen(route.startAt)
        Route.HajinStash -> StashScreen()
        Route.HajinKeepSell -> KeepSellScreen()
        Route.HajinShopping -> ShoppingScreen()
        Route.HajinBlueprints -> BlueprintsScreen()
        else -> Missing()
    }
}

@Composable
private fun Missing() {
    Column(Modifier.fillMaxSize()) {
        TopBar("")
        FilterEmptyRow(L("mw4.ui.hajin.no_results"))
    }
}
