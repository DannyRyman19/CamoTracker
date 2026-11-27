package app.camotrack.android

import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import app.camotrack.android.core.DataService
import app.camotrack.android.core.Game
import app.camotrack.android.core.GameRegistry
import app.camotrack.android.core.GameTracker
import app.camotrack.android.core.KeyValueStore
import app.camotrack.android.core.Milestone
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import app.camotrack.android.services.GoogleSync
import app.camotrack.android.services.Premium
import app.camotrack.android.services.StreamOverlay
import app.camotrack.android.services.overlayPayload
import app.camotrack.android.widgets.WidgetSync
import java.io.File

/** Where a tab can go, past its root (iOS's Route). */
sealed interface Route {
    data class WeaponCategory(val categoryId: Int) : Route
    data class Weapon(val weaponId: Int) : Route
    data class ObjectiveCategory(val categoryId: Int) : Route
    data class ObjectiveItem(val categoryId: Int, val itemId: Int) : Route
    data object AllWeapons : Route
    data object Customise : Route
    data object Premium : Route
    data object StreamOverlay : Route
    data object AppIcons : Route
    data object WhatsNew : Route
    // The Hajin tab (MW4's DMZ map and guide)
    data class HajinSection(val id: String) : Route
    data class HajinItem(val id: String) : Route
    data class HajinOrder(val check: String) : Route
    /** The Tac Map, opened on a marker when one is given. */
    data class HajinMap(val startAt: String? = null) : Route
    /** A Gunsmith weapon's camos, in DMZ. */
    data class HajinWeapon(val weaponId: Int) : Route
    data object HajinStash : Route
    data object HajinKeepSell : Route
    data object HajinShopping : Route
    data object HajinBlueprints : Route
}

enum class Tab { WEAPONS, MASTERY, HAJIN, STATS }

/**
 * The app's state outside any one screen: the games, the picked game's
 * tracker, the mode the Weapons tab is in, each tab's back stack. Screens
 * read `tracker` and recompose on `revision`.
 */
object AppState {
    lateinit var store: KeyValueStore
        private set
    lateinit var games: List<Game>
        private set
    private lateinit var seeds: AssetSeeds
    private lateinit var cacheRoot: File
    val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    private var current by mutableStateOf<GameTracker?>(null)
    /** The picked game's tracker (set in [start], before any screen). */
    val tracker: GameTracker get() = current ?: error("AppState.start not called")
    /** Bumped whenever the tracker changes; reading it in a composable recomposes on changes. */
    var revision by mutableIntStateOf(0)
        private set
    /** The latest milestone, for the banner (cleared by the banner). */
    var milestone by mutableStateOf<Milestone?>(null)

    var tab by mutableStateOf(Tab.WEAPONS)
    val stacks: Map<Tab, MutableList<Route>> = Tab.entries.associateWith { mutableStateListOf<Route>() }

    private var watch: Job? = null

    /** The walkthrough is up: on first launch, and from the Weapons title's help button. */
    var showsOnboarding by mutableStateOf(false)
    /** What's New is up (after an update, or from Customise). */
    var showsWhatsNew by mutableStateOf(false)
    /** Bumped when the language changes, so every screen redraws in it. */
    var languageTick by mutableIntStateOf(0)
        private set

    /** "I mostly play": the mode the Weapons tab is in (iOS's mw4.primaryMode). */
    var primaryMode by mutableStateOf("multiplayer")
        private set

    fun start(context: Context) {
        store = PrefsStore(context)
        seeds = AssetSeeds(context)
        cacheRoot = File(context.filesDir, "data")
        games = GameRegistry.load(seeds)
        primaryMode = store.getString(PRIMARY_MODE) ?: "multiplayer"
        StreamOverlay.start(store)
        WidgetSync.start(context)
        Premium.start(context, store)
        GoogleSync.start(context, store)
        app.camotrack.android.services.Ads.noteLaunch(store)
        // Pins and the like follow Premium as soon as it changes
        // and sync starts (or stops) with it
        Premium.onChange = { owned -> current?.isPremium = owned; revision++; GoogleSync.syncAll() }
        app.camotrack.android.ui.hajin.Hajin.start(context)
        open(GameRegistry.saved(games, store))
        // The tab picked in Customise (iOS StartTab); DMZ only where the game has Hajin
        tab = when (store.getString(START_TAB)) {
            "mastery" -> Tab.MASTERY
            "stats" -> Tab.STATS
            "dmz" -> if (tracker.game.hasHajin) Tab.HAJIN else Tab.WEAPONS
            else -> Tab.WEAPONS
        }
        showsOnboarding = !store.getBoolean(HAS_ONBOARDED)
    }

    /** Redraws what reads progress after a setting the tracker reads from the store changed (modes played). */
    fun touch() { revision++; WidgetSync.refresh() }

    /** The picked language changed: re-read it and redraw everything. */
    fun languageChanged() {
        app.camotrack.android.i18n.Strings.refresh()
        languageTick++
        revision++
        WidgetSync.refresh()
    }

    /**
     * A link (`mw4camo://mode/...`, from a notification): the Weapons tab in
     * that mode (if played, else the current one), on the route it names,
     * switching game first when it names another.
     */
    fun openLink(link: String) {
        val target = DeepLink.parse(link) ?: return
        target.game?.let { id ->
            if (id != tracker.game.id) games.firstOrNull { it.id == id }?.let(::open)
        }
        val m = target.mode?.takeIf { it in tracker.visibleModes } ?: mode
        pickMode(m)
        tab = Tab.WEAPONS
        target.route?.let { push(it, Tab.WEAPONS) }
    }

    fun open(game: Game) {
        store.putString(GameRegistry.KEY, game.id)
        // The same name as the iPhone app's iCloud key; its saved entries can restore a save that won't read
        val syncKey = game.key("mw4_progress_sync", "sync")
        val t = GameTracker(game, DataService(game, File(cacheRoot, game.id), seeds), store,
            syncFallback = GoogleSync.engine(syncKey).snapshot.values.takeIf { it.isNotEmpty() })
        GoogleSync.attach(syncKey, t.syncValues(), holdsWrites = { !t.loadedCleanly }) { t.applySynced(it) }
        t.milestoneListener = { milestone = it }
        t.isPremium = Premium.isPremium
        current = t
        stacks.values.forEach { it.clear() }
        if (tab == Tab.HAJIN && !game.hasHajin) tab = Tab.WEAPONS
        watch?.cancel()
        watch = scope.launch {
            t.revision.collect {
                revision++
                GoogleSync.record(syncKey, t.syncValues())
                // The stream overlay follows every change (it skips sends that change nothing)
                StreamOverlay.refresh()
                // The widgets too, once changes settle (written only when the snapshot changed)
                WidgetSync.refresh()
            }
        }
        StreamOverlay.makePayload = {
            t.overlayPayload(StreamOverlay.content, StreamOverlay.mode, StreamOverlay.weaponId(t.game.id), mode)
        }
        refresh()
    }

    fun refresh() = scope.launch { runCatching { tracker.refresh() } }

    /** The Weapons tab's mode: the one picked, if this game shows it, else its first. */
    val mode: String
        get() {
            revision
            val visible = tracker.visibleModes
            return primaryMode.takeIf { it in visible } ?: visible.first()
        }

    fun pickMode(mode: String) {
        primaryMode = mode
        store.putString(PRIMARY_MODE, mode)
        stacks.getValue(Tab.WEAPONS).clear()
        // The pinned weapon widget shows the start mode
        WidgetSync.refresh()
    }

    fun push(route: Route, on: Tab = tab) { stacks.getValue(on).add(route) }
    fun pop(on: Tab = tab): Boolean = stacks.getValue(on).removeLastOrNull() != null

    const val PRIMARY_MODE = "mw4.primaryMode"
    const val START_TAB = "mw4_start_tab"
    const val HAS_ONBOARDED = "mw4_has_onboarded"
}
