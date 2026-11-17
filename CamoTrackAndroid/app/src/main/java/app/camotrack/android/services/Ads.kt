package app.camotrack.android.services

import android.app.Activity
import android.content.Context
import android.telephony.TelephonyManager
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import app.camotrack.android.BuildConfig
import app.camotrack.android.core.KeyValueStore
import com.unity3d.mediation.LevelPlay
import com.unity3d.mediation.LevelPlayAdError
import com.unity3d.mediation.LevelPlayAdInfo
import com.unity3d.mediation.LevelPlayConfiguration
import com.unity3d.mediation.LevelPlayInitError
import com.unity3d.mediation.LevelPlayInitListener
import com.unity3d.mediation.LevelPlayInitRequest
import com.unity3d.mediation.interstitial.LevelPlayInterstitialAd
import com.unity3d.mediation.interstitial.LevelPlayInterstitialAdListener
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.util.Locale

/**
 * Unity LevelPlay (iOS Ads.swift): a banner under the Weapons, Mastery and
 * Stats screens and now and then a full-screen ad on leaving a weapon.
 * Premium players see none.
 *
 * Android is its own app in the LevelPlay dashboard, with its own key and ad
 * units. Until they're filled in below, ads stay off.
 */
object AdConfig {
    // TODO: the Android app's key and ad units from the LevelPlay dashboard
    const val appKey = ""
    const val defaultBannerUnit = ""
    /** Each game's own Banner and Interstitial units (as on iOS), so the dashboard shows what each game earns. */
    val units: Map<String, Pair<String, String>> = mapOf(
        // "mw4" to ("<banner unit>" to "<interstitial unit>"),
    )
    val isConfigured: Boolean get() = appKey.isNotEmpty() && defaultBannerUnit.isNotEmpty()

    fun bannerUnit(game: String): String = units[game]?.first?.takeIf { it.isNotEmpty() } ?: defaultBannerUnit
    fun interstitialUnit(game: String): String? = units[game]?.second?.takeIf { it.isNotEmpty() }
}

/**
 * Consent for personalised ads where the law asks (EU, EEA, UK,
 * Switzerland), as on iOS: asked once, changeable in Customise, passed to
 * LevelPlay. Elsewhere it's never asked.
 */
object AdConsent {
    const val KEY = "ct_ads_consent"
    private val regions = setOf(
        "AT", "BE", "BG", "HR", "CY", "CZ", "DK", "EE", "FI", "FR", "DE", "GR", "HU", "IE", "IT", "LV", "LT", "LU", "MT",
        "NL", "PL", "PT", "RO", "SK", "SI", "ES", "SE", "IS", "LI", "NO", "GB", "CH",
    )

    /** The phone's region or its SIM/network country is on the list. */
    fun applies(context: Context): Boolean {
        val tm = context.getSystemService(TelephonyManager::class.java)
        val countries = listOfNotNull(Locale.getDefault().country, tm?.simCountryIso, tm?.networkCountryIso)
        return countries.any { it.uppercase() in regions }
    }

    fun granted(store: KeyValueStore): Boolean? = if (store.contains(KEY)) store.getBoolean(KEY) else null
    fun needsAsking(context: Context, store: KeyValueStore) = applies(context) && granted(store) == null

    fun set(store: KeyValueStore, value: Boolean) {
        store.putBoolean(KEY, value)
        if (Ads.ready) LevelPlay.setConsent(value)
    }
}

object Ads {
    /** iOS's `ct_ads_past_first_session`: no ad, or ad question, before the second session. */
    const val PAST_FIRST_SESSION = "ct_ads_past_first_session"
    var ready by mutableStateOf(false); private set
    private var starting = false
    private lateinit var store: KeyValueStore

    /** Ads are shown: a free player, with ads set up. */
    val showsAds: Boolean get() = !Premium.isPremium && AdConfig.isConfigured

    /** Called on each launch: a launch after onboarding counts as a second session. */
    fun noteLaunch(store: KeyValueStore) {
        this.store = store
        if (store.getBoolean("mw4_has_onboarded")) store.putBoolean(PAST_FIRST_SESSION, true)
    }

    /**
     * Starts the SDK once the consent question (where it applies) has an
     * answer. Nothing for Premium, or before the second session. The UI asks
     * the question (see AdConsent) and calls this again with the answer in.
     */
    fun start(context: Context) {
        if (!showsAds || ready || starting || !store.getBoolean(PAST_FIRST_SESSION)) return
        if (AdConsent.needsAsking(context, store)) return
        starting = true
        if (AdConsent.applies(context)) LevelPlay.setConsent(AdConsent.granted(store) == true)
        LevelPlay.init(context.applicationContext, LevelPlayInitRequest.Builder(AdConfig.appKey).build(), object : LevelPlayInitListener {
            override fun onInitSuccess(configuration: LevelPlayConfiguration) { starting = false; ready = true }
            override fun onInitFailed(error: LevelPlayInitError) { starting = false }
        })
    }
}

/**
 * Now and then a full-screen ad on going back from a weapon to the list (iOS
 * Interstitials): never in a player's first two days, at most one every ten
 * minutes.
 */
object Interstitials : LevelPlayInterstitialAdListener {
    private const val LAST_SHOWN = "ct_ads_interstitial_last"
    private const val FIRST_SEEN = "ct_ads_first_seen"
    private const val GAP = 10 * 60 * 1000L
    private const val GRACE = 2 * 24 * 60 * 60 * 1000L
    private var ad: LevelPlayInterstitialAd? = null
    private var unit: String? = null
    private var retry = 0
    private val scope = CoroutineScope(Dispatchers.Main.immediate)
    /** A weapon was open: the next list screen to appear is the way back. */
    var leftWeapon = false

    fun prepare(store: KeyValueStore, game: String) {
        if (!store.contains(FIRST_SEEN)) store.putString(FIRST_SEEN, System.currentTimeMillis().toString())
        val wanted = AdConfig.interstitialUnit(game)
        if (!Ads.ready || wanted == null) { ad = null; unit = null; return }
        if (unit != wanted || ad == null) {
            ad = LevelPlayInterstitialAd(wanted).also { it.setListener(this) }
            unit = wanted; retry = 0
        }
        if (ad?.isAdReady() != true) ad?.loadAd()
    }

    /** Back on a list from a weapon: shows one if it's due. */
    fun weaponClosed(activity: Activity, store: KeyValueStore, game: String) {
        if (!leftWeapon) return
        leftWeapon = false
        if (!Ads.showsAds) return
        prepare(store, game)
        val now = System.currentTimeMillis()
        val first = store.getString(FIRST_SEEN)?.toLongOrNull()
        if (first != null && now - first < GRACE) return
        val last = store.getString(LAST_SHOWN)?.toLongOrNull()
        if (last != null && now - last < GAP) return
        val ad = ad?.takeIf { it.isAdReady() } ?: return
        scope.launch {
            delay(450) // after the list has slid back in
            store.putString(LAST_SHOWN, now.toString())
            ad.showAd(activity)
        }
    }

    override fun onAdLoaded(adInfo: LevelPlayAdInfo) { retry = 0 }
    override fun onAdLoadFailed(error: LevelPlayAdError) {
        retry += 1
        val wait = minOf(64L, 1L shl minOf(retry, 6))
        scope.launch { delay(wait * 1000); ad?.loadAd() }
    }
    override fun onAdDisplayed(adInfo: LevelPlayAdInfo) {}
    override fun onAdClosed(adInfo: LevelPlayAdInfo) { ad?.loadAd() }
    override fun onAdDisplayFailed(error: LevelPlayAdError, adInfo: LevelPlayAdInfo) { ad?.loadAd() }
}
