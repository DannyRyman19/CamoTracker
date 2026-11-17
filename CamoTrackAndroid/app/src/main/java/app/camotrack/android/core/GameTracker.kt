package app.camotrack.android.core

import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.builtins.MapSerializer
import kotlinx.serialization.builtins.serializer
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale
import kotlin.coroutines.cancellation.CancellationException
import kotlin.math.ceil

/** The saved progress, the same JSON shape the iOS app writes (`mw4_progress_v2` / `ct_progress_<game>`). */
@Serializable
data class ProgressStore(
    val weaponLevels: Map<Int, Int>,
    /** Optional so a save from before Weapon Prestige still decodes. */
    val weaponPrestige: Map<Int, Int>? = null,
    val amounts: Map<String, Int>,
    val completed: List<String>,
)

enum class CompletionistGate { WEAPON, CATEGORY, MODE;
    companion object {
        fun from(raw: String?): CompletionistGate? = entries.firstOrNull { it.name.lowercase() == raw }
    }
}

enum class MasteryKind { COUNT, CHALLENGE, MODE;
    companion object {
        fun from(raw: String?): MasteryKind? = entries.firstOrNull { it.name.lowercase() == raw }
    }
}

enum class WeaponStage { MILITARY, SPECIAL, COMPLETIONIST, FINISHED }

enum class WeaponFilter { ALL, INCOMPLETE, COMPLETE, READY, ON_MILITARY, ON_SPECIAL, IN_COMPLETIONIST, HAS_FINAL }

/** A done/total pair (Swift's `(done: Int, total: Int)` tuples). */
data class Progress(val done: Int, val total: Int)

/** When something was unlocked, and how sure that is. */
data class UnlockDate(val epochSeconds: Double, val kind: Kind) {
    enum class Kind { EXACT, ESTIMATE, ON_OR_BEFORE }
}

data class UnlockDuration(val seconds: Double, val estimate: Boolean)

/** How a level gate reads: in unlocks (MW4) or levels. */
data class LevelGate(val countsUnlocks: Boolean, val value: Int)

/** A game-wide camo for a game without account Mastery (BO7's Cold Snap, Nexus Horizon). */
data class GameCamoProgress(val name: LocalizedText, val gradient: List<Int>, val done: Int, val total: Int)

data class ExtraStat(val itemId: Int, val name: LocalizedText, val done: Int, val total: Int)

/** A section of `extra` challenges for Stats; a null title is the default "Camos" heading. */
data class ExtraSection(val title: LocalizedText?, val rows: List<ExtraStat>)

/** What a Completionist change can newly unlock, taken before it. */
data class CompletionistSnapshot(
    val steps: List<Boolean>,
    val weaponMastery: List<Boolean>,
    val finalCamoCount: Int,
    val mastery: List<Boolean>,
    val is100Plus: Boolean,
    val globalMastery: Boolean,
)

/**
 * One game's progress engine (the iOS `TrackerViewModel` minus UI, sync,
 * ads and widgets). Not thread-safe: use it from the main thread. Every change
 * bumps [revision]; milestones arrive on [milestones].
 */
class GameTracker(
    val game: Game,
    private val dataService: DataService,
    private val store: KeyValueStore,
    /** Seconds since 1970, for first-earned dates. */
    private val clock: () -> Double = { System.currentTimeMillis() / 1000.0 },
    private val ioDispatcher: CoroutineDispatcher = Dispatchers.IO,
    /** The flat sync entries of the last save (see [syncValues]), used when the save can't be read. */
    syncFallback: Map<String, Int>? = null,
) {
    // MARK: Observable state

    private val _revision = MutableStateFlow(0)
    /** Bumped on every change to progress, data or settings. */
    val revision: StateFlow<Int> = _revision.asStateFlow()

    private val _milestones = MutableSharedFlow<Milestone>(extraBufferCapacity = 64)
    /** Milestones as they happen (the iOS banners), in announcement order. */
    val milestones: SharedFlow<Milestone> = _milestones.asSharedFlow()

    /** Called synchronously for each milestone, in addition to [milestones]. */
    var milestoneListener: ((Milestone) -> Unit)? = null

    /** Called after every change, with the new revision. */
    var changeListener: ((Int) -> Unit)? = null

    private fun changed() {
        _revision.value += 1
        changeListener?.invoke(_revision.value)
    }

    /** Premium keeps up to [MAX_PREMIUM_PINS] pins visible; the UI sets it. */
    var isPremium: Boolean = false
        set(value) { field = value; changed() }

    var catalog: WeaponCatalog? = null
        private set
    var modes: Map<String, ModeFile> = emptyMap()
        private set
    var isRefreshing: Boolean = false
        private set
    var refreshError: String? = null
        private set
    /** The manifest's announcement from the last refresh that reached it. */
    var lastAnnouncement: Manifest.Announcement? = null
        private set

    /** False when a save existed but couldn't be read (it was kept aside under `<key>_unreadable`). */
    val loadedCleanly: Boolean

    // MARK: Rules from the mode files (iOS keeps these in global tables)

    private var masteryOverrides: Map<String, MasteryConfig> = emptyMap()
    private var completionistOverrides: Map<String, CompletionistConfig> = emptyMap()
    private var trackSharing: Map<String, String> = emptyMap()
    private var specialsAfterMilitarySet: Set<String> = emptySet()
    private var camoTrackModesCache: List<String> = emptyList()
    private var categoryByWeapon: Map<Int, WeaponCategory> = emptyMap()
    private var weaponById: Map<Int, WeaponEntry> = emptyMap()

    private fun applyRules(files: Map<String, ModeFile>) {
        masteryOverrides = files.mapNotNull { (k, v) -> v.mastery?.let { k to it } }.toMap()
        completionistOverrides = files.mapNotNull { (k, v) -> v.completionist?.let { k to it } }.toMap()
        // A name that isn't a loaded mode, or a mode that itself shares, is ignored rather than chained
        trackSharing = files.mapNotNull { (mode, file) ->
            val source = file.trackFrom ?: return@mapNotNull null
            if (source != mode && files[source] != null && files[source]?.trackFrom == null) mode to source else null
        }.toMap()
        specialsAfterMilitarySet = files.filter { it.value.specialsAfterMilitary == true }.keys
        modes = files
        camoTrackModesCache = files.keys.map(::trackMode).toSet().sorted()
    }

    private fun applyCatalog(new: WeaponCatalog?) {
        catalog = new
        val byWeapon = HashMap<Int, WeaponCategory>()
        val weapons = HashMap<Int, WeaponEntry>()
        for (category in new?.categories.orEmpty()) for (weapon in category.weapons) {
            byWeapon.putIfAbsent(weapon.weaponId, category)
            weapons.putIfAbsent(weapon.weaponId, weapon)
        }
        categoryByWeapon = byWeapon
        weaponById = weapons
    }

    // MARK: Stored progress

    private var weaponLevels = HashMap<Int, Int>()
    private var weaponPrestige = HashMap<Int, Int>()
    private var amounts = HashMap<String, Int>()
    private var completed = HashSet<String>()
    /** When each camo/step/tier was first done (seconds; 0 = before tracking), kept on this device. */
    private var firstEarned = HashMap<String, Double>()
    private var bulkWindows: Set<Long> = emptySet()

    private val storeKey get() = game.key("mw4_progress_v2", "progress")
    private val pinnedWeaponKey get() = game.key("mw4_pinned_weapon_v1", "pinned_weapon")
    private val pinnedWeaponsKey get() = game.key("mw4_pinned_weapons_v2", "pinned_weapons")
    private val prestigeTicksLiftedKey get() = game.key("mw4_prestige_ticks_lifted", "prestige_ticks_lifted")
    private val firstEarnedKey get() = game.key("mw4_first_earned", "first_earned")

    /** Pinned weapons, newest first. */
    var pinnedWeaponIds: List<Int> = emptyList()
        private set
    val pinnedWeaponId: Int? get() = pinnedWeaponIds.firstOrNull()

    init {
        loadedCleanly = loadProgress(syncFallback)
        applyCatalog(dataService.loadCatalog())
        val loaded = linkedMapOf<String, ModeFile>()
        for (mode in game.modeIds) dataService.load(mode)?.let { loaded[mode] = it }
        applyRules(loaded)
        val pins = store.getString(pinnedWeaponsKey)?.let {
            runCatching { CamoJson.decodeFromString(ListSerializer(Int.serializer()), it) }.getOrNull()
        }
        pinnedWeaponIds = pins ?: store.getInt(pinnedWeaponKey)?.let { listOf(it) } ?: emptyList()
        liftPrestigeFromTicks()
        recordFirstEarned()
    }

    // MARK: - Refresh

    private var runningRefresh: Deferred<Unit>? = null

    /**
     * Checks the manifest and installs only newer files. A second call while
     * one runs joins it instead of downloading again.
     */
    suspend fun refresh() {
        runningRefresh?.let { return it.await() }
        coroutineScope {
            val check = async { performRefresh() }
            runningRefresh = check
            try {
                check.await()
            } finally {
                if (runningRefresh === check) runningRefresh = null
            }
        }
    }

    private suspend fun performRefresh() {
        isRefreshing = true
        changed()
        try {
            val result = withContext(ioDispatcher) {
                dataService.refreshIfNeeded(catalog?.version, modes.mapValues { it.value.version })
            }
            lastAnnouncement = result.notification
            val newCatalog = result.catalog
            if (newCatalog != null && DataService.canReplace(catalog?.version, newCatalog.version)) {
                applyCatalog(newCatalog)
            }
            val fresh = result.modes.filter { DataService.canReplace(modes[it.key]?.version, it.value.version) }
            if (fresh.isNotEmpty()) applyRules(modes + fresh)
            refreshError = null
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            refreshError = e.message ?: e.toString()
        } finally {
            isRefreshing = false
            changed()
        }
    }

    // MARK: - Modes (iOS `AppMode`)

    val modeIds: List<String> get() = game.modeIds

    fun isMode(mode: String): Boolean = mode in game.modeIds

    fun modeDefinition(mode: String): GameMode? = game.modes.firstOrNull { it.id == mode }

    /** The string resource key for a mode's built-in name; [modeDefinition]'s `name` wins when set. */
    fun modeNameKey(mode: String): String = "mw4.mode.$mode"

    fun modeAccent(mode: String): Int {
        modeDefinition(mode)?.accent?.let(HexColor::parse)?.let { return it }
        return when (mode) {
            "multiplayer" -> BuiltInColors.accentMultiplayer
            "warzone" -> BuiltInColors.accentWarzone
            "dmz" -> BuiltInColors.accentDMZ
            "zombies" -> HexColor.parse("#8CC63F")!!
            "campaign" -> HexColor.parse("#C9A24B")!!
            else -> BuiltInColors.accentMultiplayer
        }
    }

    /** The accent for small text: lightened built-ins; a game's own accent as it is. */
    fun modeTextAccent(mode: String): Int {
        if (modeDefinition(mode)?.accent != null) return modeAccent(mode)
        return when (mode) {
            "multiplayer" -> BuiltInColors.accentMultiplayerText
            "dmz" -> BuiltInColors.accentDMZText
            else -> modeAccent(mode)
        }
    }

    /** The mode's three Mastery camos with the mode file's overrides laid over them. */
    fun masteryCamos(mode: String): List<MasteryCamo> {
        val base = builtInMasteryCamos(mode)
        val config = masteryOverrides[mode] ?: return base
        return listOf(base[0].applying(config.tier1), base[1].applying(config.tier2), base[2].applying(config.tier3))
    }

    private fun builtInMasteryCamos(mode: String): List<MasteryCamo> = when (mode) {
        "warzone" -> listOf(
            MasteryCamo("mw4.ui.parallax", BuiltInColors.parallax, BuiltInColors.parallaxGradient),
            MasteryCamo("mw4.ui.damascus_reforged", BuiltInColors.damascusReforged, BuiltInColors.damascusReforgedGradient),
            MasteryCamo("mw4.ui.empyros", BuiltInColors.empyros, BuiltInColors.empyrosGradient),
        )
        "dmz" -> listOf(
            MasteryCamo("mw4.ui.chiral", BuiltInColors.chiral, BuiltInColors.chiralGradient),
            MasteryCamo("mw4.ui.ripple_tide", BuiltInColors.rippleTide, BuiltInColors.rippleTideGradient),
            MasteryCamo("mw4.ui.helio", BuiltInColors.helio, BuiltInColors.helioGradient),
        )
        else -> listOf(
            MasteryCamo("mw4.ui.mercurial_drift", BuiltInColors.mercurialDrift, BuiltInColors.mercurialDriftGradient),
            MasteryCamo("mw4.ui.polyatomic_reforged", BuiltInColors.polyatomicReforged, BuiltInColors.polyatomicReforgedGradient),
            MasteryCamo("mw4.ui.orion_reforged", BuiltInColors.orionReforged, BuiltInColors.orionReforgedGradient),
        )
    }

    /** The mode's Completionist camos (a mode sharing another's track shows that track's). */
    fun completionist(mode: String): CompletionistTrack {
        val shared = trackSharing[mode] ?: mode
        val source = if (isMode(shared)) shared else mode
        val config = completionistOverrides[source]
        val builtIn = listOf(
            MasteryCamo("mw4.ui.completionist.gold", BuiltInColors.gold, BuiltInColors.goldGradient),
            MasteryCamo("mw4.ui.completionist.platinum", BuiltInColors.platinum, BuiltInColors.platinumGradient),
            MasteryCamo("mw4.ui.completionist.harmonic_break", BuiltInColors.harmonicBreak, BuiltInColors.harmonicBreakGradient),
        )
        val steps = builtIn.mapIndexed { index, camo ->
            val step = config?.steps?.getOrNull(index)
            camo.overriding(step?.name, step?.colors, step?.imageURL)
        }
        val builtInFinal = MasteryCamo(
            "mw4.ui.completionist.final", BuiltInColors.divergence, BuiltInColors.divergenceGradient,
            nameOverride = if (source == "multiplayer" && game.isMW4) LocalizedText("Divergence") else null,
        )
        val final = builtInFinal.overriding(config?.final?.name, config?.final?.colors, config?.final?.imageURL)
        return CompletionistTrack(steps, final)
    }

    /** Gold, Platinum, Harmonic Break, and the final camo when there is one. */
    fun completionistCamos(mode: String): List<MasteryCamo> {
        val track = completionist(mode)
        return track.steps + if (finalEnabled(mode)) listOf(track.final) else emptyList()
    }

    /** The end of the Completionist track: what Mastery builds on. */
    fun lastCompletionist(mode: String): MasteryCamo = completionistCamos(mode).lastOrNull() ?: completionist(mode).final

    /** The modes to show: the ones the player picked, less any the data hides. */
    val visibleModes: List<String>
        get() {
            val picked = ModeSelection.played(store.getString(ModeSelection.playedKey(game)) ?: "", modeIds)
            val shown = picked.filter { modes[it]?.hidden != true }
            return shown.ifEmpty { listOf("multiplayer") }
        }

    // MARK: - Quick tick

    var quickTick: Boolean
        get() = store.getBoolean(QUICK_TICK_KEY)
        set(on) {
            if (on == quickTick) return
            store.putBoolean(QUICK_TICK_KEY, on)
            changed()
        }

    private fun run(index: Int, count: Int, done: Boolean): List<Int> {
        if (!quickTick) return listOf(index)
        return if (done) (0..index).toList() else (index until count).toList()
    }

    /** Ticks or clears one challenge; clearing leaves an unfinished count alone. */
    private fun mark(key: String, requirement: Requirement?, done: Boolean) {
        if (requirement != null) {
            val current = amounts[key] ?: 0
            if (done) amounts[key] = maxOf(current, requirement.amount)
            else if (current >= requirement.amount) amounts[key] = 0
        } else if (done) {
            completed.add(key)
        } else {
            completed.remove(key)
        }
    }

    // MARK: - Weapon level (global)

    fun level(weaponId: Int): Int = weaponLevels[weaponId] ?: 0

    /** Launchers and melee (the game's `levelCategories`) and prestiged weapons count levels; MW4 otherwise counts unlocks. */
    fun countsUnlocks(weaponId: Int): Boolean {
        if (game.countsUnlocks != true || prestige(weaponId) != 0) return false
        val category = category(weaponId)?.categoryId ?: return true
        return category !in game.levelCategories.orEmpty()
    }

    /** What a level gate reads as for this weapon: unlocks (level - 1) or the level. */
    fun levelGate(level: Int, weaponId: Int): LevelGate =
        if (countsUnlocks(weaponId)) LevelGate(true, unlocks(level)) else LevelGate(false, level)

    fun setLevel(level: Int, weapon: WeaponEntry) {
        if (level == level(weapon.weaponId)) return
        applyLevel(level, weapon)
    }

    fun setLevel(level: Int, weaponId: Int) { weapon(weaponId)?.let { setLevel(level, it) } }

    private fun applyLevel(level: Int, weapon: WeaponEntry) {
        // Military camos are earned by level, so a level change can finish a camo list in any mode
        val wasComplete = orderedModeKeys().associateWith { allCamosComplete(weapon.weaponId, it) }
        weaponLevels[weapon.weaponId] = maxOf(0, minOf(level, maxLevel(weapon)))
        saveProgress()
        changed()
        for ((mode, was) in wasComplete) checkMilestone(weapon.weaponId, mode, was)
    }

    // MARK: - Weapon Prestige

    val prestigeStages: List<PrestigeStage> get() = catalog?.weaponPrestige.orEmpty()

    fun prestige(weaponId: Int): Int = minOf(weaponPrestige[weaponId] ?: 0, prestigeStages.size)

    fun prestigeName(weaponId: Int): LocalizedText? {
        val stage = prestige(weaponId)
        return if (stage > 0) prestigeStages[stage - 1].name else null
    }

    /** The level cap of the stage this weapon is in. */
    fun maxLevel(weapon: WeaponEntry): Int {
        val stage = prestige(weapon.weaponId)
        if (stage <= 0) return weapon.maxLevel
        return prestigeStages[stage - 1].maxLevel ?: weapon.maxLevel
    }

    fun canPrestige(weapon: WeaponEntry): Boolean =
        prestige(weapon.weaponId) < prestigeStages.size && level(weapon.weaponId) >= maxLevel(weapon)

    fun prestigeUp(weapon: WeaponEntry) {
        if (!canPrestige(weapon)) return
        weaponPrestige[weapon.weaponId] = prestige(weapon.weaponId) + 1
        weaponLevels[weapon.weaponId] = 1
        saveProgress()
        changed()
    }

    fun prestigeDown(weapon: WeaponEntry) {
        val stage = prestige(weapon.weaponId)
        if (stage <= 0) return
        weaponPrestige[weapon.weaponId] = stage - 1
        weaponLevels[weapon.weaponId] = maxLevel(weapon)
        saveProgress()
        changed()
    }

    // MARK: - Prestige camos

    val prestigeCamos: List<PrestigeCamo> get() = catalog?.prestigeCamos.orEmpty()

    fun prestigeCamoStage(camo: PrestigeCamo): Int? {
        val count = prestigeStages.size
        if (count <= 0) return null
        return minOf(camo.stage ?: count, count)
    }

    fun prestigeCamoLevel(camo: PrestigeCamo, weaponId: Int): Int? {
        camo.byWeapon?.get(weaponId.toString())?.level?.let { return it }
        if (camo.afterWeaponMaxLevel == true) return weapon(weaponId)?.let { it.maxLevel + 1 }
        return camo.level
    }

    fun hasReachedPrestigeCamo(camo: PrestigeCamo, weaponId: Int): Boolean {
        val stage = prestigeCamoStage(camo) ?: return false
        val current = prestige(weaponId)
        if (current != stage) return current > stage
        return level(weaponId) >= (prestigeCamoLevel(camo, weaponId) ?: 0)
    }

    fun isPrestigeCamoComplete(weaponId: Int, index: Int): Boolean {
        val camo = prestigeCamos.getOrNull(index) ?: return false
        val needed = camo.weaponsNeeded
        if (needed != null) return prestigeCamoWeaponCount(camo) >= needed || prestigeCamoKey(weaponId, index) in completed
        return hasReachedPrestigeCamo(camo, weaponId) || prestigeCamoKey(weaponId, index) in completed
    }

    fun prestigeCamoWeaponCount(camo: PrestigeCamo): Int = allWeapons.count { hasReachedPrestigeCamo(camo, it.weaponId) }

    /** Tapping one sets Prestige and level to it; tapping an earned one steps back to just below it. */
    fun togglePrestigeCamo(weaponId: Int, index: Int) {
        val camo = prestigeCamos.getOrNull(index) ?: return
        val weapon = weapon(weaponId) ?: return
        val stage = prestigeCamoStage(camo) ?: return
        val wasDone = isPrestigeCamoComplete(weaponId, index)
        if (camo.weaponsNeeded != null) {
            // Worked out across weapons, so only quick tick ticks it by hand
            if (!quickTick) return
            val key = prestigeCamoKey(weaponId, index)
            if (!completed.remove(key)) completed.add(key)
        } else if (wasDone) {
            for (later in index until prestigeCamos.size) completed.remove(prestigeCamoKey(weaponId, later))
            if (hasReachedPrestigeCamo(camo, weaponId)) {
                val level = prestigeCamoLevel(camo, weaponId)
                if (level != null && level > 1) {
                    weaponPrestige[weaponId] = stage
                    weaponLevels[weaponId] = level - 1
                } else {
                    weaponPrestige[weaponId] = stage - 1
                    weaponLevels[weaponId] = maxLevel(weapon)
                }
            }
        } else {
            if (quickTick) for (earlier in 0..index) completed.add(prestigeCamoKey(weaponId, earlier))
            reachPrestigeCamo(camo, stage, weaponId)
        }
        saveProgress()
        changed()
    }

    /** Sets Prestige and level up to what the camo needs; never lowers either. */
    private fun reachPrestigeCamo(camo: PrestigeCamo, stage: Int, weaponId: Int) {
        val current = prestige(weaponId)
        if (current > stage) return
        val start = if (current == stage) level(weaponId) else 1
        weaponPrestige[weaponId] = stage
        weaponLevels[weaponId] = maxOf(start, prestigeCamoLevel(camo, weaponId) ?: 1)
    }

    /** Once: Prestige camos quick-ticked before ticks set Prestige and level set them now. */
    private fun liftPrestigeFromTicks() {
        if (store.getBoolean(prestigeTicksLiftedKey)) return
        store.putBoolean(prestigeTicksLiftedKey, true)
        var didChange = false
        for (weapon in allWeapons) {
            val index = prestigeCamos.indices.lastOrNull {
                prestigeCamos[it].weaponsNeeded == null && prestigeCamoKey(weapon.weaponId, it) in completed
            } ?: continue
            val camo = prestigeCamos[index]
            val stage = prestigeCamoStage(camo) ?: continue
            if (hasReachedPrestigeCamo(camo, weapon.weaponId)) continue
            reachPrestigeCamo(camo, stage, weapon.weaponId)
            didChange = true
        }
        if (didChange) saveProgress()
    }

    fun prestigeCamoName(camo: PrestigeCamo, weaponId: Int): LocalizedText =
        camo.byWeapon?.get(weaponId.toString())?.name ?: camo.name

    fun prestigeCamoImageURL(camo: PrestigeCamo, weaponId: Int): String? =
        camo.byWeapon?.get(weaponId.toString())?.imageURL ?: camo.imageURL

    fun prestigeCamoColors(camo: PrestigeCamo, index: Int, weaponId: Int): List<Int> {
        val own = HexColor.parseAll(camo.byWeapon?.get(weaponId.toString())?.colors)
        return if (own.size > 1) own else BuiltInColors.prestige(camo, index)
    }

    /** Each mode with a final camo, and whether it's unlocked: the capstone camo's parts. */
    val capstoneModes: List<Pair<String, Boolean>>
        get() = modeIds.filter { finalEnabled(it) && modes[it] != null }.map { it to (finalCamoCount(it) > 0) }

    /** Mastery tiers earned out of every mode's three. */
    val globalMasteryProgress: Progress
        get() {
            val all = modeIds.filter { modes[it] != null }
            val done = all.sumOf { mode -> (1..3).count { isMasteryAchieved(mode, it) } }
            return Progress(done, all.size * 3)
        }

    val isGlobalMasteryAchieved: Boolean
        get() {
            if (!game.hasAccountMastery || game.capstone == null) return false
            val progress = globalMasteryProgress
            return progress.total > 0 && progress.done >= progress.total
        }

    val gameCamoProgress: List<GameCamoProgress>
        get() {
            if (game.hasMastery != false) return emptyList()
            val rows = prestigeCamos.mapIndexedNotNull { index, camo ->
                val needed = camo.weaponsNeeded ?: return@mapIndexedNotNull null
                GameCamoProgress(camo.name, BuiltInColors.prestige(camo, index), minOf(prestigeCamoWeaponCount(camo), needed), needed)
            }.toMutableList()
            game.capstone?.let { capstone ->
                val parts = capstoneModes
                val colors = HexColor.parseAll(capstone.colors)
                rows += GameCamoProgress(capstone.name, colors.ifEmpty { BuiltInColors.goldGradient }, parts.count { it.second }, parts.size)
            }
            return rows
        }

    // MARK: - Camo challenges (per mode, per weapon)

    /** The mode's camo chain for a weapon, without `extra` challenges. */
    fun camos(weaponId: Int, mode: String): List<ChallengeItem> = allCamos(weaponId, mode).filter { it.extra != true }

    /** Everything on the weapon's page: the chain and its `extra` challenges. */
    fun allCamos(weaponId: Int, mode: String): List<ChallengeItem> =
        modes[trackMode(mode)]?.weaponCamos?.firstOrNull { it.weaponId == weaponId }?.camos.orEmpty()

    /** Capped at the current requirement on read, not on save. */
    fun camoAmount(mode: String, weaponId: Int, camo: ChallengeItem): Int =
        minOf(amounts[counterKey(mode, weaponId, camo)] ?: 0, camo.requirement?.amount ?: Int.MAX_VALUE)

    private fun counterKey(mode: String, weaponId: Int, camo: ChallengeItem) = camoKey(mode, weaponId, camo.counter ?: camo.itemId)

    private fun counterGroup(mode: String, weaponId: Int, camo: ChallengeItem): List<ChallengeItem> {
        val counter = camo.counter ?: return listOf(camo)
        return allCamos(weaponId, mode).filter { it.counter == counter }
    }

    fun isCamoComplete(mode: String, weaponId: Int, camo: ChallengeItem): Boolean {
        val level = militaryLevel(mode, weaponId, camo)
        if (level != null) {
            return hasReached(level, weaponId) || countingModes(mode).any { camoKey(it, weaponId, camo.itemId) in completed }
        }
        // One camo grind per weapon across modes (MW4): finished in any mode is unlocked in all
        return countingModes(mode).any { other ->
            val own = if (trackMode(other) == trackMode(mode)) camo
            else allCamos(weaponId, other).firstOrNull { it.itemId == camo.itemId }
            own?.let { isCamoDone(other, weaponId, it) } ?: false
        }
    }

    /** Every mode with its own camo track. */
    private val camoTrackModes: List<String> get() = camoTrackModesCache

    /** The modes whose progress counts for this one: all of them when the game shares camos. */
    private fun countingModes(mode: String): List<String> =
        if (game.sharedCamos == true) camoTrackModes else listOf(trackMode(mode))

    private fun isCamoDone(mode: String, weaponId: Int, camo: ChallengeItem): Boolean {
        val req = camo.requirement ?: return camoKey(mode, weaponId, camo.itemId) in completed
        return (amounts[counterKey(mode, weaponId, camo)] ?: 0) >= req.amount
    }

    /** The weapon level that earns this Military camo, or null for any other camo. */
    fun militaryLevel(mode: String, weaponId: Int, camo: ChallengeItem): Int? {
        if (camo.group != "military" || camo.requirement != null) return null
        camo.unlockLevel?.let { return it }
        val military = camos(weaponId, mode).filter { it.group == "military" }
        val index = military.indexOfFirst { it.itemId == camo.itemId }
        val weapon = weapon(weaponId)
        if (index < 0 || weapon == null) return null
        // The weapon's own normal max, never a prestige stage's
        val max = weapon.maxLevel
        return maxOf(1, ceil(max.toDouble() * (index + 1).toDouble() / military.size.toDouble()).toInt())
    }

    fun allMilitaryComplete(mode: String, weaponId: Int): Boolean =
        camos(weaponId, mode).filter { it.group == "military" }.all { isCamoComplete(mode, weaponId, it) }

    /** Level gates are on normal levels, so a prestiged weapon has passed them all. */
    private fun hasReached(unlockLevel: Int, weaponId: Int): Boolean =
        unlockLevel <= 1 || prestige(weaponId) > 0 || level(weaponId) >= unlockLevel

    fun setCamoAmount(mode: String, weaponId: Int, camo: ChallengeItem, amount: Int) {
        val wasGold = allCamosComplete(weaponId, mode)
        // A shared count runs up to the last camo on it
        val req = counterGroup(mode, weaponId, camo).mapNotNull { it.requirement?.amount }.maxOrNull() ?: 1
        amounts[counterKey(mode, weaponId, camo)] = maxOf(0, minOf(amount, req))
        saveProgress()
        changed()
        checkMilestone(weaponId, mode, wasGold)
    }

    fun toggleCamo(mode: String, weaponId: Int, camo: ChallengeItem) {
        // A Military camo is the weapon level (a plain tick in quick tick); a prestiged weapon has them all
        val level = militaryLevel(mode, weaponId, camo)
        if (level != null) {
            if (prestige(weaponId) != 0) return
            val weapon = weapon(weaponId) ?: return
            val wasGold = allCamosComplete(weaponId, mode)
            val wasDone = isCamoComplete(mode, weaponId, camo)
            val military = camos(weaponId, mode).filter { it.group == "military" }
            val index = military.indexOfFirst { it.itemId == camo.itemId }.coerceAtLeast(0)
            if (wasDone) {
                for (later in military.drop(index)) {
                    for (other in countingModes(mode)) completed.remove(camoKey(other, weaponId, later.itemId))
                }
                if (hasReached(level, weaponId)) applyLevel(level - 1, weapon)
            } else if (!quickTick) {
                applyLevel(level, weapon)
            } else {
                for (earlier in military.take(index + 1)) completed.add(camoKey(mode, weaponId, earlier.itemId))
                checkMilestone(weaponId, mode, wasGold)
            }
            saveProgress()
            changed()
            return
        }
        val wasGold = allCamosComplete(weaponId, mode)
        val wasDone = isCamoComplete(mode, weaponId, camo)
        val req = camo.requirement
        if (camo.counter != null && req != null) {
            // A shared count: ticking runs it up to this camo, unticking back to the camo before it
            val below = counterGroup(mode, weaponId, camo).mapNotNull { it.requirement?.amount }
                .filter { it < req.amount }.maxOrNull() ?: 0
            for (other in if (wasDone) countingModes(mode) else listOf(mode)) {
                val k = counterKey(other, weaponId, camo)
                amounts[k] = if (wasDone) minOf(amounts[k] ?: 0, below) else maxOf(amounts[k] ?: 0, req.amount)
            }
        } else if (wasDone) {
            // Unticking clears it in every mode
            for (other in countingModes(mode)) {
                val k = camoKey(other, weaponId, camo.itemId)
                amounts.remove(k)
                completed.remove(k)
            }
        } else {
            val k = camoKey(mode, weaponId, camo.itemId)
            if (req != null) amounts[k] = req.amount else completed.add(k)
        }
        saveProgress()
        changed()
        checkMilestone(weaponId, mode, wasGold)
    }

    // MARK: - First earned (local only; iOS also estimates from iCloud stamps, which Android doesn't have)

    private fun firstEarnedCamoKey(mode: String, weaponId: Int, itemId: Int) = "c|${trackMode(mode)}|$weaponId|$itemId"
    private fun firstEarnedStepKey(mode: String, weaponId: Int, step: Int) = "s|${trackMode(mode)}|$weaponId|$step"

    private fun earnedNow(): Map<String, Boolean> {
        val out = HashMap<String, Boolean>()
        for (mode in camoTrackModes) {
            val finals = finalEnabled(mode)
            val hbReady = harmonicBreakCount(mode) >= harmonicBreaksNeeded(mode)
            for (weapon in weapons(mode)) {
                val id = weapon.weaponId
                for (camo in camos(id, mode).flatMap(::leafItems)) {
                    out[firstEarnedCamoKey(mode, id, camo.itemId)] = isCamoComplete(mode, id, camo)
                }
                for (step in 0 until COMPLETIONIST_STEP_COUNT) {
                    out[firstEarnedStepKey(mode, id, step)] = isCompletionistComplete(mode, id, step)
                }
                if (finals) {
                    // hasFinalCamo, with the mode-wide count worked out once
                    out[firstEarnedStepKey(mode, id, COMPLETIONIST_STEP_COUNT)] = isCompletionistComplete(mode, id, 2) && hbReady
                }
            }
        }
        if (game.hasAccountMastery) {
            for (mode in modes.keys) for (tier in 1..3) out["m|$mode|$tier"] = isMasteryAchieved(mode, tier)
        }
        return out
    }

    /** Notes the first time each thing is done; what was done before the first run is marked 0 (unknown). */
    private fun recordFirstEarned() {
        if (modes.isEmpty()) return
        val baseline = !store.contains(firstEarnedKey)
        if (!baseline && firstEarned.isEmpty()) {
            store.getString(firstEarnedKey)?.let { saved ->
                runCatching { CamoJson.decodeFromString(MapSerializer(String.serializer(), Double.serializer()), saved) }
                    .getOrNull()?.let { firstEarned = HashMap(it) }
            }
            bulkWindows = bulkWindows(firstEarned)
        }
        val estimatedKey = firstEarnedKey + "_estimated"
        val estimating = baseline || !store.getBoolean(estimatedKey)
        val now = clock()
        var didChange = baseline
        for ((key, done) in earnedNow()) {
            if (done && baseline) {
                firstEarned[key] = 0.0
                didChange = true
            } else if (done && firstEarned[key] == null) {
                firstEarned[key] = now
                didChange = true
            } else if (!done) {
                val at = firstEarned[key]
                if (at != null && at > 0 && now - at < MISTAP_WINDOW) {
                    firstEarned.remove(key)
                    didChange = true
                }
            }
        }
        if (didChange) {
            store.putString(firstEarnedKey, CamoJson.encodeToString(MapSerializer(String.serializer(), Double.serializer()), firstEarned))
            bulkWindows = bulkWindows(firstEarned)
        }
        if (estimating) store.putBoolean(estimatedKey, true)
    }

    private fun bulkWindows(earned: Map<String, Double>): Set<Long> {
        val counts = HashMap<Long, Int>()
        for (value in earned.values) if (value < 0) {
            val window = (-value / BULK_WINDOW).toLong()
            counts[window] = (counts[window] ?: 0) + 1
        }
        return counts.filter { it.value >= 15 }.keys
    }

    private fun unlock(key: String): UnlockDate? {
        val value = firstEarned[key] ?: return null
        if (value == 0.0) return null
        if (value > 0) return UnlockDate(value, UnlockDate.Kind.EXACT)
        val at = -value
        val kind = if ((at / BULK_WINDOW).toLong() in bulkWindows) UnlockDate.Kind.ON_OR_BEFORE else UnlockDate.Kind.ESTIMATE
        return UnlockDate(at, kind)
    }

    fun camoUnlockedDate(mode: String, weaponId: Int, camo: ChallengeItem): UnlockDate? {
        if (!isCamoComplete(mode, weaponId, camo)) return null
        return unlock(firstEarnedCamoKey(mode, weaponId, camo.itemId))
    }

    /** When Gold, Platinum, Harmonic Break (or, at [COMPLETIONIST_STEP_COUNT], the final camo) was unlocked. */
    fun completionistUnlockedDate(mode: String, weaponId: Int, step: Int): UnlockDate? {
        val done = if (step >= COMPLETIONIST_STEP_COUNT) hasFinalCamo(mode, weaponId) else isCompletionistComplete(mode, weaponId, step)
        return if (done) unlock(firstEarnedStepKey(mode, weaponId, step)) else null
    }

    /** How long a Completionist camo took on this weapon from its first dated camo; null under an hour or unknown. */
    fun completionistDuration(mode: String, weaponId: Int, step: Int): UnlockDuration? {
        val end = unlock(firstEarnedStepKey(mode, weaponId, step)) ?: return null
        if (end.kind == UnlockDate.Kind.ON_OR_BEFORE) return null
        var start = end.epochSeconds
        var estimate = end.kind == UnlockDate.Kind.ESTIMATE
        for (camo in camos(weaponId, mode).flatMap(::leafItems)) {
            val key = firstEarnedCamoKey(mode, weaponId, camo.itemId)
            val value = firstEarned[key] ?: continue
            if (value == 0.0) {
                if (militaryLevel(mode, weaponId, camo) != null) continue
                return null
            }
            val at = unlock(key) ?: return null
            if (at.kind == UnlockDate.Kind.ON_OR_BEFORE) return null
            if (at.kind == UnlockDate.Kind.ESTIMATE) estimate = true
            start = minOf(start, at.epochSeconds)
        }
        val took = end.epochSeconds - start
        return if (took >= 3600) UnlockDuration(took, estimate) else null
    }

    fun masteryUnlockedDate(mode: String, tier: Int): UnlockDate? = unlock("m|$mode|$tier")

    // MARK: - Availability

    /** Whether this camo's challenge is open yet. Earned stays open. */
    fun isCamoAvailable(mode: String, weaponId: Int, camo: ChallengeItem): Boolean {
        if (quickTick || isCamoComplete(mode, weaponId, camo)) return true
        camo.afterCompletionist?.let { step ->
            val has = if (step >= COMPLETIONIST_STEP_COUNT) hasFinalCamo(mode, weaponId) else isCompletionistComplete(mode, weaponId, step)
            if (!has) return false
        }
        camo.afterItem?.let { after ->
            val before = allCamos(weaponId, mode).firstOrNull { it.itemId == after }
            if (before != null && !isCamoComplete(mode, weaponId, before)) return false
        }
        // Always tappable: a tap sets the weapon level
        if (militaryLevel(mode, weaponId, camo) != null) return true
        if (camo.group == "special") {
            if (specialsWaitForMilitary(mode) && !allMilitaryComplete(mode, weaponId)) return false
            return camo.unlockLevel?.let { hasReached(it, weaponId) } ?: true
        }
        camo.unlockLevel?.let { return hasReached(it, weaponId) }
        val siblings = camos(weaponId, mode)
        val index = siblings.indexOfFirst { it.itemId == camo.itemId }
        if (index <= 0) return true
        return isCamoComplete(mode, weaponId, siblings[index - 1])
    }

    /** An objective's sub-tier: `afterSiblings` waits for the rest; otherwise in order unless [ordered] is false. */
    fun isObjectiveAvailable(mode: String, categoryId: Int, siblings: List<ChallengeItem>, item: ChallengeItem, ordered: Boolean = true): Boolean {
        if (item.afterSiblings == true) {
            return siblings.all { it.itemId == item.itemId || isObjectiveComplete(mode, categoryId, it) }
        }
        if (!ordered) return true
        val index = siblings.indexOfFirst { it.itemId == item.itemId }
        if (index <= 0) return true
        return isObjectiveComplete(mode, categoryId, siblings[index - 1])
    }

    /** Where an objective can be earned; null when only one mode has objectives or none carries it. */
    fun objectiveScope(categoryId: Int, itemId: Int): ObjectiveScope? {
        val withObjectives = modeIds.filter { modes[it]?.objectives.orEmpty().isNotEmpty() }
        if (withObjectives.size <= 1) return null
        val carrying = withObjectives.filter { m ->
            modes[m]?.objectives?.firstOrNull { it.categoryId == categoryId }?.items?.any { it.itemId == itemId } == true
        }
        if (carrying.isEmpty()) return null
        return if (carrying.size == withObjectives.size) ObjectiveScope.AllModes else ObjectiveScope.Only(carrying)
    }

    /** Time-limited objectives live now and not finished, soonest-ending first. */
    fun liveObjectives(mode: String, now: Instant = Instant.now()): List<LiveObjective> =
        modes[mode]?.objectives.orEmpty().flatMap { category ->
            category.items
                .filter { it.window(now) == ChallengeItem.Window.LIVE }
                .filter { objectiveProgressFraction(it, mode, category.categoryId) < 1 }
                .map { LiveObjective(category.categoryId, it) }
        }.sortedBy { it.item.endDate ?: Instant.MAX }

    // MARK: - Camo list counts

    fun allCamosComplete(weaponId: Int, mode: String): Boolean {
        val leaves = camos(weaponId, mode).flatMap(::leafItems)
        return leaves.isNotEmpty() && leaves.all { isCamoComplete(mode, weaponId, it) }
    }

    fun remainingCamoCount(weaponId: Int, mode: String): Int =
        camos(weaponId, mode).flatMap(::leafItems).count { !isCamoComplete(mode, weaponId, it) }

    fun goldWeaponCount(category: WeaponCategory, mode: String): Int = category.weapons.count { allCamosComplete(it.weaponId, mode) }

    val totalWeaponCount: Int get() = catalog?.categories?.sumOf { it.weapons.size } ?: 0
    val totalCategoryCount: Int get() = catalog?.categories?.size ?: 0

    /** The weapon classes a mode covers. */
    fun categories(mode: String): List<WeaponCategory> {
        val all = catalog?.categories.orEmpty()
        val ids = modeCategoryIds(mode) ?: return all
        return all.filter { it.categoryId in ids }
    }

    private fun modeCategoryIds(mode: String): Set<Int>? = modeDefinition(mode)?.categories?.toSet()

    fun weapons(mode: String): List<WeaponEntry> = categories(mode).flatMap { it.weapons }

    fun weaponCount(mode: String): Int = weapons(mode).size

    /** The launch roster of the guns this mode covers. */
    fun launchRoster(mode: String): Int {
        if (modeCategoryIds(mode) == null) return launchRoster
        return maxOf(1, weapons(mode).count { it.weaponId < baseWeaponCount })
    }

    fun launchProgress(done: Int, mode: String): Progress {
        val roster = launchRoster(mode)
        return Progress(minOf(done, roster), roster)
    }

    val baseWeaponCount: Int get() = catalog?.baseWeaponCount ?: totalWeaponCount

    /** Weapons whose camo list is finished in at least one mode. */
    val weaponsWithBaseCamosComplete: Int
        get() = allWeapons.count { weapon -> modes.keys.any { allCamosComplete(weapon.weaponId, it) } }

    fun totalGoldWeaponCount(mode: String): Int = categories(mode).sumOf { goldWeaponCount(it, mode) }

    // MARK: - Completionist (per weapon, per mode)

    /** The mode whose camo list and Completionist progress this mode uses. */
    fun trackMode(mode: String): String = trackSharing[mode] ?: mode

    fun specialsWaitForMilitary(mode: String): Boolean = trackMode(mode) in specialsAfterMilitarySet

    /** Whether this mode's track has the final camo after Harmonic Break. */
    fun finalEnabled(mode: String): Boolean = completionistOverrides[trackMode(mode)]?.final?.enabled ?: true

    private fun completionistKey(mode: String, weaponId: Int, step: Int) = "comp|${trackMode(mode)}|$weaponId|$step"

    /** The step's challenge for this weapon: its own, its class's, the default, or none (a tick box). */
    fun completionistRequirement(mode: String, weaponId: Int, step: Int): Requirement? {
        val config = completionistOverrides[trackMode(mode)]?.steps?.getOrNull(step) ?: return null
        return requirement(weaponId, config.byWeapon, config.byCategory, config.requirement)
    }

    private fun requirement(weaponId: Int, own: Map<String, Requirement>?, byCategory: Map<String, Requirement>?, fallback: Requirement?): Requirement? {
        own?.get(weaponId.toString())?.let { return it }
        val categoryId = category(weaponId)?.categoryId
        if (categoryId != null) byCategory?.get(categoryId.toString())?.let { return it }
        return fallback
    }

    fun completionistAmount(mode: String, weaponId: Int, step: Int): Int =
        minOf(amounts[completionistKey(mode, weaponId, step)] ?: 0, completionistRequirement(mode, weaponId, step)?.amount ?: Int.MAX_VALUE)

    fun isCompletionistComplete(mode: String, weaponId: Int, step: Int): Boolean =
        countingModes(mode).any { isCompletionistDone(it, weaponId, step) }

    private fun isCompletionistDone(mode: String, weaponId: Int, step: Int): Boolean {
        val key = completionistKey(mode, weaponId, step)
        val requirement = completionistRequirement(mode, weaponId, step) ?: return key in completed
        return (amounts[key] ?: 0) >= requirement.amount
    }

    /** How widely the step before must be done: Gold weapon, Platinum category, Harmonic Break mode by default. */
    fun completionistGate(mode: String, step: Int): CompletionistGate =
        CompletionistGate.from(completionistStepConfig(mode, step)?.unlock)
            ?: listOf(CompletionistGate.WEAPON, CompletionistGate.CATEGORY, CompletionistGate.MODE)[minOf(step, 2).coerceAtLeast(0)]

    private fun completionistStepConfig(mode: String, step: Int): CompletionistStepConfig? =
        completionistOverrides[trackMode(mode)]?.steps?.getOrNull(step)

    private fun gateTotal(needed: Int?, available: Int, launch: Int): Int =
        needed?.let { maxOf(1, minOf(it, maxOf(1, available))) } ?: maxOf(1, launch)

    private fun hasPrerequisite(mode: String, weaponId: Int, step: Int): Boolean =
        if (step == 0) allCamosComplete(weaponId, mode) else isCompletionistComplete(mode, weaponId, step - 1)

    fun completionistModeGateProgress(mode: String, step: Int): Progress {
        val total = gateTotal(completionistStepConfig(mode, step)?.needed, weaponCount(mode), launchRoster(mode))
        val done = weapons(mode).count { hasPrerequisite(mode, it.weaponId, step) }
        return Progress(minOf(done, total), total)
    }

    fun completionistCategoryGateProgress(category: WeaponCategory, mode: String, step: Int): Progress {
        val launch = category.weapons.count { it.weaponId < baseWeaponCount }
        val config = completionistStepConfig(mode, step)
        val total = gateTotal(config?.neededByCategory?.get(category.categoryId.toString()) ?: config?.needed, category.weapons.size, launch)
        val done = category.weapons.count { hasPrerequisite(mode, it.weaponId, step) }
        return Progress(minOf(done, total), total)
    }

    fun isCompletionistAvailable(mode: String, weaponId: Int, step: Int): Boolean {
        if (quickTick || isCompletionistComplete(mode, weaponId, step)) return true
        if (!hasPrerequisite(mode, weaponId, step)) return false
        return when (completionistGate(mode, step)) {
            CompletionistGate.WEAPON -> true
            CompletionistGate.CATEGORY -> {
                val category = category(weaponId) ?: return true
                val p = completionistCategoryGateProgress(category, mode, step)
                p.done >= p.total
            }
            CompletionistGate.MODE -> {
                val p = completionistModeGateProgress(mode, step)
                p.done >= p.total
            }
        }
    }

    fun setCompletionistAmount(mode: String, weaponId: Int, step: Int, amount: Int) {
        val before = completionistSnapshot(mode, weaponId)
        val cap = completionistRequirement(mode, weaponId, step)?.amount ?: 1
        amounts[completionistKey(mode, weaponId, step)] = maxOf(0, minOf(amount, cap))
        saveProgress()
        changed()
        checkCompletionistMilestone(mode, weaponId, before)
    }

    fun toggleCompletionist(mode: String, weaponId: Int, step: Int) {
        val before = completionistSnapshot(mode, weaponId)
        val wasDone = isCompletionistComplete(mode, weaponId, step)
        // Quick tick: the camos it builds on come with it
        if (quickTick && !wasDone) completeCamoList(mode, weaponId)
        for (each in run(step, COMPLETIONIST_STEP_COUNT, !wasDone)) {
            // Unticking clears it in every mode; ticking marks this mode
            for (other in if (wasDone) countingModes(mode) else listOf(mode)) {
                mark(completionistKey(other, weaponId, each), completionistRequirement(other, weaponId, each), !wasDone)
            }
        }
        saveProgress()
        changed()
        checkCompletionistMilestone(mode, weaponId, before)
    }

    /** Quick tick: the weapon's whole camo list in this mode (not its extras). */
    private fun completeCamoList(mode: String, weaponId: Int) {
        for (camo in camos(weaponId, mode)) {
            if (isCamoComplete(mode, weaponId, camo)) continue
            val requirement = camo.requirement
            if (militaryLevel(mode, weaponId, camo) != null) {
                completed.add(camoKey(mode, weaponId, camo.itemId))
            } else if (camo.counter != null && requirement != null) {
                val key = counterKey(mode, weaponId, camo)
                amounts[key] = maxOf(amounts[key] ?: 0, requirement.amount)
            } else {
                mark(camoKey(mode, weaponId, camo.itemId), requirement, true)
            }
        }
    }

    fun harmonicBreakCount(mode: String): Int = weapons(mode).count { isCompletionistComplete(mode, it.weaponId, 2) }

    /** Harmonic Breaks across the mode that open the final camo; 0 = the weapon's own is enough. */
    fun harmonicBreaksNeeded(mode: String): Int =
        maxOf(0, completionistOverrides[trackMode(mode)]?.final?.harmonicBreaksNeeded ?: 0)

    fun hasFinalCamo(mode: String, weaponId: Int): Boolean =
        finalEnabled(mode) && isCompletionistComplete(mode, weaponId, 2) && harmonicBreakCount(mode) >= harmonicBreaksNeeded(mode)

    fun finalCamoCount(mode: String): Int {
        if (!finalEnabled(mode)) return 0
        val count = harmonicBreakCount(mode)
        return if (count >= harmonicBreaksNeeded(mode)) count else 0
    }

    /** The final camo, or Harmonic Break when the mode has none. What Mastery builds on. */
    fun hasLastCompletionist(mode: String, weaponId: Int): Boolean =
        if (finalEnabled(mode)) hasFinalCamo(mode, weaponId) else isCompletionistComplete(mode, weaponId, 2)

    fun lastCompletionistCount(mode: String): Int = if (finalEnabled(mode)) finalCamoCount(mode) else harmonicBreakCount(mode)

    fun categoryLastCompletionistCount(category: WeaponCategory, mode: String): Int =
        category.weapons.count { hasLastCompletionist(mode, it.weaponId) }

    fun categoryCompletionistCount(category: WeaponCategory, mode: String, step: Int): Int =
        category.weapons.count { isCompletionistComplete(mode, it.weaponId, step) }

    fun categoryFinalCount(category: WeaponCategory, mode: String): Int = category.weapons.count { hasFinalCamo(mode, it.weaponId) }

    /** 0 Gold, 1 Platinum, 2 Harmonic Break, 3 the final camo; null for none. */
    fun highestCompletionist(mode: String, weaponId: Int): Int? {
        if (hasFinalCamo(mode, weaponId)) return 3
        return (0 until COMPLETIONIST_STEP_COUNT).lastOrNull { isCompletionistComplete(mode, weaponId, it) }
    }

    val allWeapons: List<WeaponEntry> get() = catalog?.categories?.flatMap { it.weapons }.orEmpty()

    // MARK: - Stage and filters

    fun stage(mode: String, weaponId: Int): WeaponStage {
        if (hasLastCompletionist(mode, weaponId)) return WeaponStage.FINISHED
        if (allCamosComplete(weaponId, mode)) return WeaponStage.COMPLETIONIST
        val hasMilitary = camos(weaponId, mode).any { it.group == "military" }
        return if (hasMilitary && !allMilitaryComplete(mode, weaponId)) WeaponStage.MILITARY else WeaponStage.SPECIAL
    }

    /** A Special camo, Completionist or Mastery challenge that's open but not done. */
    fun hasOpenChallenge(mode: String, weaponId: Int): Boolean {
        val openSpecial = camos(weaponId, mode).any { camo ->
            militaryLevel(mode, weaponId, camo) == null && !isCamoComplete(mode, weaponId, camo) && isCamoAvailable(mode, weaponId, camo)
        }
        if (openSpecial) return true
        val openStep = (0 until COMPLETIONIST_STEP_COUNT).any {
            !isCompletionistComplete(mode, weaponId, it) && isCompletionistAvailable(mode, weaponId, it)
        }
        if (openStep) return true
        return (1..3).any { !isWeaponMasteryComplete(mode, weaponId, it) && isWeaponMasteryAvailable(mode, weaponId, it) }
    }

    fun matches(filter: WeaponFilter, mode: String, weaponId: Int): Boolean = when (filter) {
        WeaponFilter.ALL -> true
        WeaponFilter.INCOMPLETE -> !allCamosComplete(weaponId, mode)
        WeaponFilter.COMPLETE -> allCamosComplete(weaponId, mode)
        WeaponFilter.READY -> hasOpenChallenge(mode, weaponId)
        WeaponFilter.ON_MILITARY -> stage(mode, weaponId) == WeaponStage.MILITARY
        WeaponFilter.ON_SPECIAL -> stage(mode, weaponId) == WeaponStage.SPECIAL
        WeaponFilter.IN_COMPLETIONIST -> stage(mode, weaponId) == WeaponStage.COMPLETIONIST
        WeaponFilter.HAS_FINAL -> stage(mode, weaponId) == WeaponStage.FINISHED
    }

    /** The mode's `extra` challenges, by section, with how many weapons that have each have earned it. */
    fun extraStats(mode: String, languages: List<String> = LocalizedText.preferredLanguages()): List<ExtraSection> {
        data class Row(val name: LocalizedText, var done: Int, var total: Int)
        val sections = linkedMapOf<String?, Pair<LocalizedText?, LinkedHashMap<Int, Row>>>()
        for (weapon in weapons(mode)) {
            for (camo in allCamos(weapon.weaponId, mode)) {
                if (camo.extra != true) continue
                val title = camo.section?.resolved(languages)
                val section = sections.getOrPut(title) { camo.section to linkedMapOf() }
                val row = section.second.getOrPut(camo.itemId) { Row(camo.name, 0, 0) }
                if (isCamoComplete(mode, weapon.weaponId, camo)) row.done += 1
                row.total += 1
            }
        }
        return sections.values.map { (title, rows) ->
            ExtraSection(title, rows.map { (id, row) -> ExtraStat(id, row.name, row.done, row.total) })
        }
    }

    /** Every weapon as one list (id [ALL_WEAPONS_CATEGORY_ID]); the UI names it. */
    fun allWeaponsCategory(mode: String? = null): WeaponCategory? {
        if (catalog == null) return null
        return WeaponCategory(ALL_WEAPONS_CATEGORY_ID, LocalizedText(emptyMap()), mode?.let(::weapons) ?: allWeapons)
    }

    // MARK: - Mastery (per mode)

    fun masteryKind(mode: String, tier: Int): MasteryKind {
        val raw = masteryTierConfig(mode, tier)?.kind ?: masteryOverrides[mode]?.unlock
        return MasteryKind.from(raw) ?: MasteryKind.COUNT
    }

    fun masteryUsesChallenges(mode: String): Boolean = (1..3).any { masteryKind(mode, it) == MasteryKind.CHALLENGE }

    private fun masteryTierConfig(mode: String, tier: Int): MasteryTierConfig? {
        val config = masteryOverrides[mode]
        return listOf(config?.tier1, config?.tier2, config?.tier3)[maxOf(0, minOf(tier, 3) - 1)]
    }

    fun masteryWeaponsNeeded(mode: String, tier: Int): Int {
        val configured = if (isMode(mode)) masteryCamos(mode)[maxOf(0, minOf(tier, 3) - 1)].weaponsNeeded else null
        return configured ?: maxOf(1, ceil(launchRoster(mode).toDouble() * tier / 3).toInt())
    }

    /** The weapons the game launched with. */
    val launchRoster: Int get() = maxOf(1, minOf(totalWeaponCount, baseWeaponCount))

    fun launchProgress(done: Int): Progress = Progress(minOf(done, launchRoster), launchRoster)

    fun masteryProgress(mode: String, tier: Int): Progress = when (masteryKind(mode, tier)) {
        MasteryKind.MODE -> {
            val requirement = modeMasteryRequirement(mode, tier)
            if (requirement == null) Progress(if (isModeMasteryComplete(mode, tier)) 1 else 0, 1)
            else Progress(modeMasteryAmount(mode, tier), maxOf(1, requirement.amount))
        }
        MasteryKind.CHALLENGE -> launchProgress(weapons(mode).count { isWeaponMasteryComplete(mode, it.weaponId, tier) }, mode)
        MasteryKind.COUNT -> {
            val needed = masteryWeaponsNeeded(mode, tier)
            Progress(minOf(lastCompletionistCount(mode), needed), needed)
        }
    }

    fun hasTierBefore(mode: String, weaponId: Int, tier: Int): Boolean =
        if (masteryKind(mode, tier - 1) == MasteryKind.CHALLENGE) isWeaponMasteryComplete(mode, weaponId, tier - 1)
        else isMasteryAchieved(mode, tier - 1)

    fun isMasteryAchieved(mode: String, tier: Int): Boolean {
        if (!game.hasAccountMastery) return false
        if (tier > 1 && !isMasteryAchieved(mode, tier - 1)) return false
        val progress = masteryProgress(mode, tier)
        return progress.done >= progress.total
    }

    private fun modeMasteryKey(mode: String, tier: Int) = "modemastery|$mode|$tier"

    fun modeMasteryRequirement(mode: String, tier: Int): Requirement? = masteryTierConfig(mode, tier)?.requirement

    /** What a self-counting tier counts, for its line ("12/20 Platinum"). */
    fun modeMasteryCountedCamo(mode: String, tier: Int): MasteryCamo? {
        val unit = modeMasteryRequirement(mode, tier)?.unit ?: return null
        val step = SELF_COUNTING_UNITS[unit] ?: return null
        if (!isMode(mode)) return null
        val camos = completionistCamos(mode)
        return camos.getOrNull(step) ?: lastCompletionist(mode)
    }

    fun modeMasteryCountsItself(mode: String, tier: Int): Boolean =
        modeMasteryRequirement(mode, tier)?.let { SELF_COUNTING_UNITS[it.unit] } != null

    fun modeMasteryAmount(mode: String, tier: Int): Int {
        val requirement = modeMasteryRequirement(mode, tier)
        val cap = requirement?.amount ?: 1
        val step = requirement?.unit?.let { SELF_COUNTING_UNITS[it] }
        val raw = if (step != null) completionistCount(mode, step)
        else amounts[modeMasteryKey(mode, tier)] ?: if (modeMasteryKey(mode, tier) in completed) 1 else 0
        return minOf(raw, cap)
    }

    fun isModeMasteryComplete(mode: String, tier: Int): Boolean {
        if (masteryKind(mode, tier) != MasteryKind.MODE) return false
        val requirement = modeMasteryRequirement(mode, tier) ?: return modeMasteryKey(mode, tier) in completed
        return modeMasteryAmount(mode, tier) >= requirement.amount
    }

    fun modeMasteryWeaponsNeeded(mode: String, tier: Int): Int =
        maxOf(0, masteryTierConfig(mode, tier)?.weaponsNeeded ?: if (tier == 1) 1 else 0)

    fun isModeMasteryAvailable(mode: String, tier: Int): Boolean {
        if (masteryKind(mode, tier) != MasteryKind.MODE) return false
        if (quickTick || isModeMasteryComplete(mode, tier)) return true
        if (tier != 1 && !isMasteryAchieved(mode, tier - 1)) return false
        return lastCompletionistCount(mode) >= modeMasteryWeaponsNeeded(mode, tier)
    }

    /** [weaponId] is the weapon whose page the change came from, for the milestone. */
    fun setModeMasteryAmount(mode: String, tier: Int, weaponId: Int, amount: Int) {
        if (modeMasteryCountsItself(mode, tier)) return
        val before = completionistSnapshot(mode, weaponId)
        val cap = modeMasteryRequirement(mode, tier)?.amount ?: 1
        amounts[modeMasteryKey(mode, tier)] = maxOf(0, minOf(amount, cap))
        saveProgress()
        changed()
        checkCompletionistMilestone(mode, weaponId, before)
    }

    fun toggleModeMastery(mode: String, tier: Int, weaponId: Int) {
        if (modeMasteryCountsItself(mode, tier)) return
        val before = completionistSnapshot(mode, weaponId)
        val wasDone = isModeMasteryComplete(mode, tier)
        for (each in run(tier - 1, 3, !wasDone).map { it + 1 }) {
            if (masteryKind(mode, each) != MasteryKind.MODE || modeMasteryCountsItself(mode, each)) continue
            mark(modeMasteryKey(mode, each), modeMasteryRequirement(mode, each), !wasDone)
        }
        saveProgress()
        changed()
        checkCompletionistMilestone(mode, weaponId, before)
    }

    private fun masteryKey(mode: String, weaponId: Int, tier: Int) = "mastery|$mode|$weaponId|$tier"

    fun masteryRequirement(mode: String, weaponId: Int, tier: Int): Requirement? {
        val config = masteryTierConfig(mode, tier) ?: return null
        return requirement(weaponId, config.byWeapon, config.byCategory, config.requirement)
    }

    fun weaponMasteryAmount(mode: String, weaponId: Int, tier: Int): Int =
        minOf(amounts[masteryKey(mode, weaponId, tier)] ?: 0, masteryRequirement(mode, weaponId, tier)?.amount ?: Int.MAX_VALUE)

    fun isWeaponMasteryComplete(mode: String, weaponId: Int, tier: Int): Boolean {
        if (masteryKind(mode, tier) != MasteryKind.CHALLENGE) return false
        val key = masteryKey(mode, weaponId, tier)
        val requirement = masteryRequirement(mode, weaponId, tier) ?: return key in completed
        return (amounts[key] ?: 0) >= requirement.amount
    }

    fun masteryGate(mode: String, tier: Int): CompletionistGate =
        CompletionistGate.from(masteryTierConfig(mode, tier)?.unlock)
            ?: if (tier == 1) CompletionistGate.MODE else CompletionistGate.WEAPON

    private fun hasMasteryPrerequisite(mode: String, weaponId: Int, tier: Int): Boolean =
        if (tier == 1) hasLastCompletionist(mode, weaponId) else hasTierBefore(mode, weaponId, tier)

    fun masteryGateProgress(mode: String, tier: Int, category: WeaponCategory? = null): Progress {
        val weapons = category?.weapons ?: weapons(mode)
        val needed = masteryTierConfig(mode, tier)?.needed
        val total = if (category != null) {
            gateTotal(needed, category.weapons.size, category.weapons.count { it.weaponId < baseWeaponCount })
        } else {
            gateTotal(needed, weaponCount(mode), launchRoster(mode))
        }
        val done = weapons.count { hasMasteryPrerequisite(mode, it.weaponId, tier) }
        return Progress(minOf(done, total), total)
    }

    fun isWeaponMasteryAvailable(mode: String, weaponId: Int, tier: Int): Boolean {
        if (masteryKind(mode, tier) != MasteryKind.CHALLENGE) return false
        if (quickTick || isWeaponMasteryComplete(mode, weaponId, tier)) return true
        if (!hasMasteryPrerequisite(mode, weaponId, tier)) return false
        return when (masteryGate(mode, tier)) {
            CompletionistGate.WEAPON -> true
            CompletionistGate.CATEGORY -> {
                val category = category(weaponId) ?: return true
                val p = masteryGateProgress(mode, tier, category)
                p.done >= p.total
            }
            CompletionistGate.MODE -> {
                val p = masteryGateProgress(mode, tier)
                p.done >= p.total
            }
        }
    }

    fun setWeaponMasteryAmount(mode: String, weaponId: Int, tier: Int, amount: Int) {
        val before = completionistSnapshot(mode, weaponId)
        val cap = masteryRequirement(mode, weaponId, tier)?.amount ?: 1
        amounts[masteryKey(mode, weaponId, tier)] = maxOf(0, minOf(amount, cap))
        saveProgress()
        changed()
        checkCompletionistMilestone(mode, weaponId, before)
    }

    fun toggleWeaponMastery(mode: String, weaponId: Int, tier: Int) {
        val before = completionistSnapshot(mode, weaponId)
        val wasDone = isWeaponMasteryComplete(mode, weaponId, tier)
        // Quick tick: the camo list and every Completionist camo come with it
        if (quickTick && !wasDone) {
            completeCamoList(mode, weaponId)
            for (step in 0 until COMPLETIONIST_STEP_COUNT) {
                mark(completionistKey(mode, weaponId, step), completionistRequirement(mode, weaponId, step), true)
            }
        }
        for (each in run(tier - 1, 3, !wasDone).map { it + 1 }) {
            if (masteryKind(mode, each) != MasteryKind.CHALLENGE) continue
            mark(masteryKey(mode, weaponId, each), masteryRequirement(mode, weaponId, each), !wasDone)
        }
        saveProgress()
        changed()
        checkCompletionistMilestone(mode, weaponId, before)
    }

    /** The "100%+" milestone: the last thing on every weapon that exists now, DLC included. */
    fun fullRosterFinalProgress(mode: String): Progress {
        if (masteryKind(mode, 3) == MasteryKind.CHALLENGE) {
            return Progress(weapons(mode).count { isWeaponMasteryComplete(mode, it.weaponId, 3) }, weaponCount(mode))
        }
        return Progress(lastCompletionistCount(mode), weaponCount(mode))
    }

    fun is100PlusAchieved(mode: String): Boolean {
        val p = fullRosterFinalProgress(mode)
        return p.total > 0 && p.done >= p.total
    }

    fun completionistSnapshot(mode: String, weaponId: Int) = CompletionistSnapshot(
        steps = (0 until COMPLETIONIST_STEP_COUNT).map { isCompletionistComplete(mode, weaponId, it) },
        weaponMastery = (1..3).map { isWeaponMasteryComplete(mode, weaponId, it) },
        finalCamoCount = finalCamoCount(mode),
        mastery = (1..3).map { isMasteryAchieved(mode, it) },
        is100Plus = is100PlusAchieved(mode),
        globalMastery = isGlobalMasteryAchieved,
    )

    // MARK: - Progress fractions

    fun overallProgressFraction(mode: String): Double {
        var done = 0
        var total = 0
        for (weapon in weapons(mode)) {
            val leaves = camos(weapon.weaponId, mode).flatMap(::leafItems)
            total += leaves.size
            done += leaves.count { isCamoComplete(mode, weapon.weaponId, it) }
        }
        return if (total == 0) 0.0 else done.toDouble() / total
    }

    /** How far along the mode's whole track is: camo lists, each Completionist camo, each Mastery tier, equally weighted. */
    fun trueCompletionFraction(mode: String): Double = fullTrackFraction(weapons(mode), mode, modeMastery = true)

    fun categoryTrueCompletionFraction(category: WeaponCategory, mode: String): Double =
        fullTrackFraction(category.weapons, mode, modeMastery = false)

    /** Weapons with this step, or the final camo for `step == COMPLETIONIST_STEP_COUNT`. */
    fun completionistCount(mode: String, step: Int): Int {
        if (step >= COMPLETIONIST_STEP_COUNT) return finalCamoCount(mode)
        return weapons(mode).count { isCompletionistComplete(mode, it.weaponId, step) }
    }

    private fun fullTrackFraction(weapons: List<WeaponEntry>, mode: String, modeMastery: Boolean): Double {
        if (weapons.isEmpty()) return 0.0
        val count = weapons.size.toDouble()
        fun share(has: (Int) -> Boolean): Double = weapons.count { has(it.weaponId) } / count
        val stages = mutableListOf<Double>()

        var done = 0
        var total = 0
        for (weapon in weapons) {
            val leaves = camos(weapon.weaponId, mode).flatMap(::leafItems)
            total += leaves.size
            done += leaves.count { isCamoComplete(mode, weapon.weaponId, it) }
        }
        if (total > 0) stages += done.toDouble() / total

        for (step in 0 until COMPLETIONIST_STEP_COUNT) stages += share { isCompletionistComplete(mode, it, step) }
        if (finalEnabled(mode)) stages += share { hasFinalCamo(mode, it) }
        if (game.hasAccountMastery) {
            for (tier in 1..3) {
                if (masteryKind(mode, tier) == MasteryKind.CHALLENGE) {
                    stages += share { isWeaponMasteryComplete(mode, it, tier) }
                } else if (modeMastery) {
                    val p = masteryProgress(mode, tier)
                    stages += if (isMasteryAchieved(mode, tier)) 1.0
                    else if (p.total > 0) minOf(p.done.toDouble() / p.total, 1.0) else 0.0
                }
            }
        }
        if (stages.isEmpty()) return 0.0
        return stages.sum() / stages.size
    }

    fun camoProgressFraction(weaponId: Int, mode: String): Double {
        val c = camoCounts(weaponId, mode)
        return if (c.total == 0) 0.0 else c.done.toDouble() / c.total
    }

    /** "x/y camos done" for a weapon. */
    fun camoCounts(weaponId: Int, mode: String): Progress {
        val leaves = camos(weaponId, mode).flatMap(::leafItems)
        return Progress(leaves.count { isCamoComplete(mode, weaponId, it) }, leaves.size)
    }

    fun weaponCategoryProgressFraction(category: WeaponCategory, mode: String): Double {
        var done = 0
        var total = 0
        for (weapon in category.weapons) {
            val c = camoCounts(weapon.weaponId, mode)
            done += c.done
            total += c.total
        }
        return if (total == 0) 0.0 else done.toDouble() / total
    }

    // MARK: - Pins

    val visiblePinnedWeaponIds: List<Int> get() = pinnedWeaponIds.take(if (isPremium) MAX_PREMIUM_PINS else 1)

    fun isPinned(weaponId: Int): Boolean = weaponId in visiblePinnedWeaponIds

    /** Pins a weapon as the newest: free players keep one, Premium up to five. */
    fun pin(weaponId: Int) {
        val ids = listOf(weaponId) + pinnedWeaponIds.filter { it != weaponId }
        savePins(ids.take(if (isPremium) MAX_PREMIUM_PINS else 1))
    }

    fun unpin(weaponId: Int) = savePins(pinnedWeaponIds.filter { it != weaponId })

    private fun savePins(ids: List<Int>) {
        pinnedWeaponIds = ids
        store.putString(pinnedWeaponsKey, CamoJson.encodeToString(ListSerializer(Int.serializer()), ids))
        // Kept for anything still reading the single pin
        store.putInt(pinnedWeaponKey, ids.firstOrNull())
        changed()
    }

    fun weapon(id: Int): WeaponEntry? = weaponById[id]

    fun category(weaponId: Int): WeaponCategory? = categoryByWeapon[weaponId]

    // MARK: - Objectives

    fun objectiveAmount(mode: String, categoryId: Int, item: ChallengeItem): Int =
        minOf(amounts[objectiveKey(mode, categoryId, item.itemId)] ?: 0, item.requirement?.amount ?: Int.MAX_VALUE)

    fun isObjectiveComplete(mode: String, categoryId: Int, item: ChallengeItem): Boolean {
        val k = objectiveKey(mode, categoryId, item.itemId)
        val req = item.requirement ?: return k in completed
        return (amounts[k] ?: 0) >= req.amount
    }

    fun setObjectiveAmount(mode: String, categoryId: Int, item: ChallengeItem, amount: Int) {
        val req = item.requirement?.amount ?: 1
        amounts[objectiveKey(mode, categoryId, item.itemId)] = maxOf(0, minOf(amount, req))
        saveProgress()
        changed()
    }

    fun toggleObjective(mode: String, categoryId: Int, item: ChallengeItem) {
        val k = objectiveKey(mode, categoryId, item.itemId)
        val req = item.requirement
        if (req != null) {
            val done = (amounts[k] ?: 0) >= req.amount
            amounts[k] = if (done) 0 else req.amount
        } else if (!completed.remove(k)) {
            completed.add(k)
        }
        saveProgress()
        changed()
    }

    fun objectiveProgressFraction(item: ChallengeItem, mode: String, categoryId: Int): Double =
        fraction(leafItems(item), mode, categoryId)

    fun objectiveProgressFraction(category: ObjectiveCategory, mode: String): Double =
        fraction(category.items.flatMap(::leafItems), mode, category.categoryId)

    private fun fraction(leaves: List<ChallengeItem>, mode: String, categoryId: Int): Double {
        if (leaves.isEmpty()) return 0.0
        return leaves.count { isObjectiveComplete(mode, categoryId, it) }.toDouble() / leaves.size
    }

    fun leafItems(item: ChallengeItem): List<ChallengeItem> = if (item.isLeaf) listOf(item) else item.children.flatMap(::leafItems)

    // MARK: - Suggestions and milestones

    /**
     * Weapons close to their next camo: those on their Completionist or
     * Mastery camos first (furthest along first), then by fewest camos left.
     */
    fun suggestions(mode: String, limit: Int = 3): List<Suggestion> {
        val categories = categories(mode)
        if (categories.isEmpty() || !isMode(mode)) return emptyList()
        val steps = completionist(mode).steps
        val onCompletionist = mutableListOf<Pair<Suggestion, Int>>()
        val onCamoList = mutableListOf<Pair<Suggestion, Int>>()
        for (category in categories) for (weapon in category.weapons) {
            val weaponId = weapon.weaponId
            if (allCamosComplete(weaponId, mode)) {
                val next = (0 until COMPLETIONIST_STEP_COUNT).firstOrNull { !isCompletionistComplete(mode, weaponId, it) }
                if (next == null) {
                    // Past Harmonic Break: an open Mastery challenge, if any
                    val tiers = masteryCamos(mode)
                    val tier = (1..3).firstOrNull { !isWeaponMasteryComplete(mode, weaponId, it) && isWeaponMasteryAvailable(mode, weaponId, it) }
                    if (tier != null) {
                        val needed = masteryRequirement(mode, weaponId, tier)?.amount ?: 0
                        onCompletionist += Suggestion(weaponId, weapon.name, tiers[tier - 1], 0,
                            fraction(weaponMasteryAmount(mode, weaponId, tier), needed)) to (COMPLETIONIST_STEP_COUNT + tier)
                    }
                    continue
                }
                if (!isCompletionistAvailable(mode, weaponId, next)) continue
                val needed = completionistRequirement(mode, weaponId, next)?.amount ?: 0
                onCompletionist += Suggestion(weaponId, weapon.name, steps[next], 0,
                    fraction(completionistAmount(mode, weaponId, next), needed)) to next
            } else {
                val remaining = remainingCamoCount(weaponId, mode)
                if (remaining <= 0) continue
                onCamoList += Suggestion(weaponId, weapon.name, null, remaining, camoProgressFraction(weaponId, mode)) to remaining
            }
        }
        // Stable sorts, as Swift's sort is in practice for these lists
        val ranked = onCompletionist.sortedByDescending { it.second }.map { it.first } + onCamoList.sortedBy { it.second }.map { it.first }
        return ranked.take(limit)
    }

    private fun fraction(done: Int, needed: Int): Double = if (needed > 0) minOf(done.toDouble() / needed, 1.0) else 0.0

    private fun announce(milestone: Milestone) {
        _milestones.tryEmit(milestone)
        milestoneListener?.invoke(milestone)
    }

    /** Camos shared by every mode (MW4) don't name one on the share card, unless the milestone is the mode's own. */
    private fun named(mode: String, perMode: Boolean): String? = if (perMode || game.sharedCamos != true) mode else null

    /** After a camo or level change: finishing the list opens Gold. */
    private fun checkMilestone(weaponId: Int, mode: String, wasGold: Boolean) {
        if (wasGold || !allCamosComplete(weaponId, mode)) return
        announce(Milestone.CamosComplete(mode, named(mode, false), weaponId))
    }

    /** After a Completionist or Mastery change: each newly reached milestone, in the iOS order. */
    private fun checkCompletionistMilestone(mode: String, weaponId: Int, before: CompletionistSnapshot) {
        if (!isMode(mode) || weapon(weaponId) == null) return
        val track = completionist(mode)
        for (step in (0 until COMPLETIONIST_STEP_COUNT).reversed()) {
            if (!before.steps[step] && isCompletionistComplete(mode, weaponId, step)) {
                announce(Milestone.CompletionistUnlocked(mode, named(mode, false), weaponId, step, track.steps[step]))
                break
            }
        }
        val finals = finalCamoCount(mode)
        if (finals > before.finalCamoCount) {
            val gained = finals - before.finalCamoCount
            val one = gained == 1 && hasFinalCamo(mode, weaponId)
            announce(Milestone.FinalUnlocked(mode, named(mode, false), if (one) weaponId else null, gained, track.final))
        }
        val tierCamos = masteryCamos(mode)
        for (tier in (1..3).reversed()) {
            if (!before.weaponMastery[tier - 1] && isWeaponMasteryComplete(mode, weaponId, tier)) {
                announce(Milestone.WeaponMasteryUnlocked(mode, named(mode, true), weaponId, tier, tierCamos[tier - 1]))
                break
            }
        }
        for (tier in (1..3).reversed()) {
            if (!before.mastery[tier - 1] && isMasteryAchieved(mode, tier)) {
                val kind = masteryKind(mode, tier)
                announce(Milestone.MasteryUnlocked(
                    mode, named(mode, true), tier, tierCamos[tier - 1], kind,
                    masteryProgress(mode, tier).total,
                    if (kind == MasteryKind.CHALLENGE) tierCamos[tier - 1] else lastCompletionist(mode),
                ))
                break
            }
        }
        if (!before.is100Plus && is100PlusAchieved(mode)) {
            announce(Milestone.HundredPlus(mode, named(mode, true),
                if (masteryKind(mode, 3) == MasteryKind.CHALLENGE) tierCamos[2] else lastCompletionist(mode)))
        }
        // Last, so it's the one left showing
        val capstone = game.capstone
        if (!before.globalMastery && isGlobalMasteryAchieved && capstone != null) {
            announce(Milestone.GlobalMastery(mode, named(mode, false), capstone))
        }
    }

    // MARK: - Persistence

    private fun prestigeCamoKey(weaponId: Int, index: Int) = "prestigecamo|$weaponId|$index"

    private fun camoKey(mode: String, weaponId: Int, camoId: Int) = "camo|${trackMode(mode)}|$weaponId|$camoId"

    private fun objectiveKey(mode: String, categoryId: Int, itemId: Int): String {
        val shared = modes[mode]?.objectives?.firstOrNull { it.categoryId == categoryId }?.shared == true
        return "obj|${if (shared) "shared" else mode}|$categoryId|$itemId"
    }

    private fun orderedModeKeys(): List<String> = modeIds.filter { it in modes } + modes.keys.filter { it !in modeIds }

    /** Reads the save; false when there is one and it can't be read (kept aside, [fallback] used). */
    private fun loadProgress(fallback: Map<String, Int>?): Boolean {
        val data = store.getString(storeKey) ?: return true
        val saved = runCatching { CamoJson.decodeFromString(ProgressStore.serializer(), data) }.getOrNull()
        if (saved == null) {
            keepUnreadableSave(data)
            fallback?.let(::restore)
            return false
        }
        weaponLevels = HashMap(saved.weaponLevels)
        weaponPrestige = HashMap(saved.weaponPrestige.orEmpty())
        amounts = HashMap(saved.amounts)
        completed = HashSet(saved.completed)
        return true
    }

    /** The unreadable save under `<key>_unreadable`, plus a timestamped copy; never deleted. */
    private fun keepUnreadableSave(data: String) {
        val key = "${storeKey}_unreadable"
        if (store.getString(key) == data) return
        val stamp = DateTimeFormatter.ofPattern("yyyyMMdd-HHmmss", Locale.US)
            .withZone(ZoneId.systemDefault()).format(Instant.ofEpochMilli((clock() * 1000).toLong()))
        store.putString(key, data)
        store.putString("${key}_$stamp", data)
    }

    private fun saveProgress() {
        writeProgress()
        recordFirstEarned()
    }

    private fun writeProgress() {
        val saved = ProgressStore(weaponLevels, weaponPrestige, amounts, completed.toList())
        store.putString(storeKey, CamoJson.encodeToString(ProgressStore.serializer(), saved))
    }

    /** Progress as flat entries (the iOS sync format): `l|id`, `p|id`, `a|key`, `d|key`. */
    fun syncValues(): Map<String, Int> {
        val values = HashMap<String, Int>()
        for ((id, level) in weaponLevels) values["l|$id"] = level
        for ((id, stage) in weaponPrestige) values["p|$id"] = stage
        for ((key, amount) in amounts) values["a|$key"] = amount
        for (key in completed) values["d|$key"] = 1
        return values
    }

    /** Replaces progress with flat entries from [syncValues] (another device's) and saves it. */
    fun applySynced(values: Map<String, Int>) {
        restore(values)
        writeProgress()
        recordFirstEarned()
        changed()
    }

    private fun restore(values: Map<String, Int>) {
        val levels = HashMap<Int, Int>()
        val prestige = HashMap<Int, Int>()
        val counts = HashMap<String, Int>()
        val done = HashSet<String>()
        for ((key, value) in values) {
            if (key.length < 2) continue
            val rest = key.substring(2)
            when (key.substring(0, 2)) {
                "l|" -> rest.toIntOrNull()?.let { levels[it] = value }
                "p|" -> rest.toIntOrNull()?.let { prestige[it] = value }
                "a|" -> counts[rest] = value
                "d|" -> done.add(rest)
            }
        }
        weaponLevels = levels
        weaponPrestige = prestige
        amounts = counts
        completed = done
    }

    companion object {
        const val COMPLETIONIST_STEP_COUNT = 3
        const val MAX_PREMIUM_PINS = 5
        const val ALL_WEAPONS_CATEGORY_ID = -1
        /** Global, not per game, as on iOS. */
        const val QUICK_TICK_KEY = "mw4_quick_tick"
        /** A requirement unit that counts a Completionist camo across the mode by itself. */
        val SELF_COUNTING_UNITS = mapOf("golds" to 0, "platinums" to 1, "harmonic_breaks" to 2, "finals" to 3)
        private const val MISTAP_WINDOW = 10.0 * 60
        private const val BULK_WINDOW = 600.0

        /** MW4 counts unlocks: every level after the first gives one. */
        fun unlocks(level: Int): Int = maxOf(0, level - 1)
        fun levelForUnlocks(unlocks: Int): Int = if (unlocks <= 0) 0 else unlocks + 1
    }
}

/** "Grind this next": [nextCamo] is the Completionist/Mastery camo it's on, or null with [camosLeft] on the camo list. */
data class Suggestion(
    val weaponId: Int,
    val weaponName: LocalizedText,
    val nextCamo: MasteryCamo?,
    val camosLeft: Int,
    /** Toward the camo it names (0 for a tick box). */
    val progress: Double,
) {
    val highlight: Int? get() = nextCamo?.color
}

/**
 * A milestone (the iOS banner) as data. [mode] is where it happened;
 * [shareMode] is the mode to name on a share card (null in a game whose camos
 * are shared across modes, for camo milestones).
 */
sealed interface Milestone {
    val mode: String
    val shareMode: String?

    /** The weapon's camo list is finished (Gold opens). */
    data class CamosComplete(override val mode: String, override val shareMode: String?, val weaponId: Int) : Milestone

    data class CompletionistUnlocked(override val mode: String, override val shareMode: String?, val weaponId: Int, val step: Int, val camo: MasteryCamo) : Milestone

    /** The final camo; [weaponId] null when [gained] > 1 (the mode count unlocked several at once). */
    data class FinalUnlocked(override val mode: String, override val shareMode: String?, val weaponId: Int?, val gained: Int, val camo: MasteryCamo) : Milestone

    data class WeaponMasteryUnlocked(override val mode: String, override val shareMode: String?, val weaponId: Int, val tier: Int, val camo: MasteryCamo) : Milestone

    /**
     * A mode Mastery tier. Subtitle on iOS: tier 3 a fixed line, a "mode"
     * kind the mode's name, else "[total] [basis]" weapons.
     */
    data class MasteryUnlocked(
        override val mode: String, override val shareMode: String?, val tier: Int, val camo: MasteryCamo,
        val kind: MasteryKind, val total: Int, val basis: MasteryCamo,
    ) : Milestone

    /** Every weapon that exists now has [basis]. */
    data class HundredPlus(override val mode: String, override val shareMode: String?, val basis: MasteryCamo) : Milestone

    /** Every mode's Mastery: the game's capstone camo (MW4's Flashpoint). */
    data class GlobalMastery(override val mode: String, override val shareMode: String?, val capstone: CapstoneCamo) : Milestone
}
