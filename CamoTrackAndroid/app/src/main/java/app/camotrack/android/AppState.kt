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
import app.camotrack.android.services.Premium
import app.camotrack.android.services.StreamOverlay
import app.camotrack.android.services.overlayPayload
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
}

enum class Tab { WEAPONS, MASTERY, STATS }

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
        Premium.start(context, store)
        app.camotrack.android.services.Ads.noteLaunch(store)
        // Pins and the like follow Premium as soon as it changes
        Premium.onChange = { owned -> current?.isPremium = owned; revision++ }
        open(GameRegistry.saved(games, store))
    }

    fun open(game: Game) {
        store.putString(GameRegistry.KEY, game.id)
        val t = GameTracker(game, DataService(game, File(cacheRoot, game.id), seeds), store)
        t.milestoneListener = { milestone = it }
        t.isPremium = Premium.isPremium
        current = t
        stacks.values.forEach { it.clear() }
        watch?.cancel()
        watch = scope.launch {
            t.revision.collect {
                revision++
                // The stream overlay follows every change (it skips sends that change nothing)
                StreamOverlay.refresh()
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
    }

    fun push(route: Route, on: Tab = tab) { stacks.getValue(on).add(route) }
    fun pop(on: Tab = tab): Boolean = stacks.getValue(on).removeLastOrNull() != null

    const val PRIMARY_MODE = "mw4.primaryMode"
}
