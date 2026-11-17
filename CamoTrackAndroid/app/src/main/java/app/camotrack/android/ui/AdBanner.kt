package app.camotrack.android.ui

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import app.camotrack.android.AppState
import app.camotrack.android.Route
import app.camotrack.android.i18n.L
import app.camotrack.android.services.AdConfig
import app.camotrack.android.services.Ads
import com.unity3d.mediation.LevelPlayAdError
import com.unity3d.mediation.LevelPlayAdInfo
import com.unity3d.mediation.LevelPlayAdSize
import com.unity3d.mediation.banner.LevelPlayBannerAdView
import com.unity3d.mediation.banner.LevelPlayBannerAdViewListener

/**
 * The banner at the foot of the Weapons, Mastery and Stats screens, with a
 * "Remove ads" link to Premium above it, shown only once an ad has loaded
 * (as on iPhone). Nothing for Premium players or before the SDK is up.
 */
@Composable
fun AdBanner() {
    if (!Ads.showsAds || !Ads.ready) return
    val context = LocalContext.current
    val game = AppState.tracker.game.id
    var loaded by remember(game) { mutableStateOf(false) }
    val view = remember(game) {
        LevelPlayBannerAdView(context, AdConfig.bannerUnit(game),
            LevelPlayBannerAdView.Config.Builder().setAdSize(LevelPlayAdSize.BANNER).build()).apply {
            setBannerListener(object : LevelPlayBannerAdViewListener {
                override fun onAdLoaded(adInfo: LevelPlayAdInfo) { loaded = true }
                override fun onAdLoadFailed(error: LevelPlayAdError) {}
            })
            loadAd()
        }
    }
    DisposableEffect(view) { onDispose { view.destroy() } }
    Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally) {
        if (loaded) {
            TextButton(onClick = { AppState.push(Route.Premium) }) {
                Text(L("mw4.ui.premium.remove_ads"), fontSize = 12.sp, color = Ink.muted)
            }
        }
        AndroidView({ view }, Modifier.fillMaxWidth().height(if (loaded) 50.dp else 0.dp).padding(bottom = 2.dp))
    }
}
