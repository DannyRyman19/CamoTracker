import Foundation

/// Deliberately `ObservableObject` + `@Published`, not `@Observable` — the latter
/// is iOS 17+ only, and this app targets iOS 16.
@MainActor
final class TrackerViewModel: ObservableObject {
    @Published private(set) var catalog: WeaponCatalog?
    @Published private(set) var modes: [String: ModeFile] = [:]
    @Published private(set) var isRefreshing = false
    @Published var refreshError: String?

    /// A transient Gold/Diamond celebration — see `Suggestions.swift`. Not
    /// `private(set)` because the `checkMilestone`/`announce` pair that drives
    /// it lives in an extension in that file.
    @Published var milestoneBanner: MilestoneBanner?

    /// Bumped when a weapon finishing its base camos earns a rating prompt.
    /// `ContentView` owns the presentation, since `requestReview` needs a
    /// SwiftUI environment value.
    @Published private(set) var reviewRequestToken = 0

    /// The one weapon pinned for quick access at the top of every mode tab —
    /// global like weapon level, not per-mode, since you pin a weapon, not a
    /// mode-specific track.
    @Published private(set) var pinnedWeaponId: Int?
    private let pinnedWeaponKey = "mw4_pinned_weapon_v1"

    /// The pending widget refresh (see WidgetSync.swift), so a burst of
    /// ticks writes the snapshot once.
    var widgetTask: Task<Void, Never>?

    private let dataService: DataService

    /// Weapon level is the one thing genuinely global: keyed by `weaponId` alone,
    /// so it reads the same from the Multiplayer tab or the DMZ tab.
    private var weaponLevels: [Int: Int] = [:]

    /// Weapon Prestige reached, per weapon — global like level. 0 is the
    /// weapon's normal levels; n is `prestigeStages[n - 1]`. `weaponLevels`
    /// is always the level *within* the current stage.
    private var weaponPrestige: [Int: Int] = [:]

    /// Camo and objective completion, keyed by mode — each mode has its own
    /// camo track for the same weapon.
    private var amounts: [String: Int] = [:]
    private var completed: Set<String> = []

    private let storeKey = "mw4_progress_v2"
    private let defaults: UserDefaults

    /// `defaults` is where progress and the pin are kept; tests pass a
    /// throwaway suite.
    init(dataService: DataService = DataService(), defaults: UserDefaults = .standard) {
        self.dataService = dataService
        self.defaults = defaults
        loadProgress()
        catalog = dataService.loadCachedCatalog() ?? dataService.loadSeedCatalog()
        var loaded: [String: ModeFile] = [:]
        for mode in ["multiplayer", "warzone", "dmz"] {
            loaded[mode] = dataService.loadCached(mode: mode) ?? dataService.loadSeed(mode: mode)
        }
        MasteryOverrides.byMode = loaded.compactMapValues(\.mastery)
        CompletionistOverrides.byMode = loaded.compactMapValues(\.completionist)
        TrackSharing.update(from: loaded)
        SpecialRule.update(from: loaded)
        modes = loaded
        if defaults.object(forKey: pinnedWeaponKey) != nil {
            pinnedWeaponId = defaults.integer(forKey: pinnedWeaponKey)
        }
    }

    /// Checks the CDN manifest and pulls only the catalog/mode files whose version changed.
    /// Raised from `checkMilestone` (which lives in Suggestions.swift) once a
    /// weapon has actually just finished. The token itself stays
    /// `private(set)` so nothing else can nudge the prompt.
    @MainActor
    func raiseReviewRequest() { reviewRequestToken += 1 }

    func refresh() async {
        #if DEBUG
        // Screenshots of the bundled data, whatever the CDN has right now.
        if ProcessInfo.processInfo.environment["MW4_OFFLINE"] != nil { return }
        #endif
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            #if DEBUG
            // MW4_FORCE_FULL_REFRESH pretends nothing is cached, so the whole
            // download/decode/apply path runs against the real CDN even when
            // the bundled seed is already current.
            let forceFull = ProcessInfo.processInfo.environment["MW4_FORCE_FULL_REFRESH"] != nil
            #else
            let forceFull = false
            #endif
            let result = try await dataService.refreshIfNeeded(
                knownCatalogVersion: forceFull ? nil : catalog?.version,
                knownModeVersions: forceFull ? [:] : modes.mapValues { $0.version }
            )
            if let newCatalog = result.catalog { catalog = newCatalog }
            if !result.modes.isEmpty {
                let merged = modes.merging(result.modes) { _, new in new }
                MasteryOverrides.byMode = merged.compactMapValues(\.mastery)
                CompletionistOverrides.byMode = merged.compactMapValues(\.completionist)
                TrackSharing.update(from: merged)
                SpecialRule.update(from: merged)
                modes = merged
            }
            refreshError = nil
            // Every launch passes through here, and new data can rename or
            // add camos, so the widgets get a fresh snapshot.
            refreshWidgets()
            #if DEBUG
            // `refreshError` is not shown anywhere, so a broken feed is
            // invisible: Data/MW4 did not exist on the CDN for the app's
            // whole life and every refresh threw without anyone noticing.
            let took = (result.catalog != nil ? ["catalog"] : []) + result.modes.keys.sorted()
            print("MW4DATA refresh ok, updated: \(took.isEmpty ? "nothing (all versions current)" : took.joined(separator: ", "))")
            #endif
        } catch {
            refreshError = error.localizedDescription
            #if DEBUG
            print("MW4DATA refresh FAILED: \(error)")
            #endif
        }
    }

    // MARK: - Quick tick (no weapon levels)

    /// Quick tick: the player ticks what they've done rather than keeping
    /// weapon levels and counts. Military camos are tick boxes, nothing is
    /// locked, every counter is one tap, and ticking one in a run (Military,
    /// Completionist, Mastery) ticks the ones before it, as unticking clears
    /// the ones after. Anything already earned by level stays earned, and
    /// switching back loses nothing.
    static let quickTickKey = "mw4_quick_tick"

    var quickTick: Bool { defaults.bool(forKey: Self.quickTickKey) }

    func setQuickTick(_ on: Bool) {
        guard on != quickTick else { return }
        defaults.set(on, forKey: Self.quickTickKey)
        objectWillChange.send()
        Haptics.change(wasDone: false, isDone: false)
    }

    /// The indices (0-based, of `count`) a tick at `index` changes: just it,
    /// or in quick tick it and everything before it when ticking, it and
    /// everything after it when unticking.
    private func run(_ index: Int, through count: Int, done: Bool) -> [Int] {
        guard quickTick else { return [index] }
        return done ? Array(0...index) : Array(index..<count)
    }

    /// Ticks or clears one challenge: its count up to the requirement or
    /// back to zero, or the tick for one without a count. Clearing leaves a
    /// count that isn't finished alone, so unticking an earlier step in
    /// quick tick never wipes progress kept in full tracking.
    private func mark(_ key: String, requirement: Requirement?, done: Bool) {
        if let requirement {
            let current = amounts[key] ?? 0
            if done {
                amounts[key] = max(current, requirement.amount)
            } else if current >= requirement.amount {
                amounts[key] = 0
            }
        } else if done {
            completed.insert(key)
        } else {
            completed.remove(key)
        }
    }

    // MARK: - Weapon level (global — same value in every mode)

    func level(for weaponId: Int) -> Int {
        weaponLevels[weaponId] ?? 0
    }

    /// MW4 counts weapon progress in unlocks, not levels: every level after
    /// the first gives one unlock, so a camo the data puts at level 44 needs
    /// 43 unlocks. Levels whose reward is a shared attachment the player
    /// already owns are skipped, so the game's level can run ahead of this.
    /// Stored values stay levels (prestige, max level and the camo gates all
    /// work on them); only what's shown and typed is in unlocks.
    static func unlocks(forLevel level: Int) -> Int { max(0, level - 1) }
    static func level(forUnlocks unlocks: Int) -> Int { unlocks <= 0 ? 0 : unlocks + 1 }

    /// Launchers (7) and melee (8) have no shared attachments, so the game
    /// keeps counting them in levels; so does any weapon in Weapon Prestige.
    func countsUnlocks(weaponId: Int) -> Bool {
        guard prestige(for: weaponId) == 0 else { return false }
        guard let category = category(containingWeaponId: weaponId)?.categoryId else { return true }
        return ![7, 8].contains(category)
    }

    /// What a level gate reads as for this weapon: "Needs 43 weapon unlocks."
    /// or "Unlocks at weapon level 44." `kind` is locked, reach or earned.
    func levelGateText(_ level: Int, weaponId: Int, kind: String) -> String {
        countsUnlocks(weaponId: weaponId)
            ? String(format: "mw4.ui.camo_unlocks_\(kind)".localized(), Self.unlocks(forLevel: level))
            : String(format: "mw4.ui.camo_level_\(kind)".localized(), level)
    }

    func setLevel(_ level: Int, for weapon: WeaponEntry) {
        guard level != self.level(for: weapon.weaponId) else { return }
        applyLevel(level, for: weapon)
        Haptics.change(wasDone: false, isDone: false)
    }

    private func applyLevel(_ level: Int, for weapon: WeaponEntry) {
        // Military camos are earned by level, so a level change can finish a
        // weapon's camo list in any mode.
        let wasComplete = Dictionary(uniqueKeysWithValues: modes.keys.map { ($0, allCamosComplete(weaponId: weapon.weaponId, mode: $0)) })
        weaponLevels[weapon.weaponId] = max(0, min(level, maxLevel(for: weapon)))
        saveProgress()
        objectWillChange.send()
        for (mode, was) in wasComplete {
            checkMilestone(weaponId: weapon.weaponId, mode: mode, wasGold: was)
        }
    }

    // MARK: - Weapon Prestige (global, like level)

    var prestigeStages: [PrestigeStage] {
        catalog?.weaponPrestige ?? []
    }

    /// Clamped, so a stage dropped from the JSON never indexes past the end.
    func prestige(for weaponId: Int) -> Int {
        min(weaponPrestige[weaponId] ?? 0, prestigeStages.count)
    }

    /// The current stage's name ("Prestige 1"), or `nil` before prestiging.
    func prestigeName(for weaponId: Int) -> String? {
        let stage = prestige(for: weaponId)
        return stage > 0 ? prestigeStages[stage - 1].name.resolved() : nil
    }

    /// The level cap of the stage this weapon is currently in.
    func maxLevel(for weapon: WeaponEntry) -> Int {
        let stage = prestige(for: weapon.weaponId)
        guard stage > 0 else { return weapon.maxLevel }
        return prestigeStages[stage - 1].maxLevel ?? weapon.maxLevel
    }

    /// Prestiging needs the current stage maxed and a stage left to go to.
    func canPrestige(_ weapon: WeaponEntry) -> Bool {
        prestige(for: weapon.weaponId) < prestigeStages.count
            && level(for: weapon.weaponId) >= maxLevel(for: weapon)
    }

    /// Moves to the next stage, back at level 1 the way the game resets it.
    func prestigeUp(_ weapon: WeaponEntry) {
        guard canPrestige(weapon) else { return }
        weaponPrestige[weapon.weaponId] = prestige(for: weapon.weaponId) + 1
        weaponLevels[weapon.weaponId] = 1
        saveProgress()
        objectWillChange.send()
        Haptics.heavy()
    }

    /// Undoes a prestige tapped by mistake, landing on the previous stage
    /// maxed — which it must have been to prestige in the first place.
    func prestigeDown(_ weapon: WeaponEntry) {
        let stage = prestige(for: weapon.weaponId)
        guard stage > 0 else { return }
        weaponPrestige[weapon.weaponId] = stage - 1
        weaponLevels[weapon.weaponId] = maxLevel(for: weapon)
        saveProgress()
        objectWillChange.send()
        Haptics.undone()
    }

    // MARK: - Prestige camos (global, like level and Prestige)

    var prestigeCamos: [PrestigeCamo] { catalog?.prestigeCamos ?? [] }

    /// The stage a Prestige camo sits in, counting from 1 (`nil` in the data
    /// means the last stage). `nil` here when there are no stages at all.
    func prestigeCamoStage(_ camo: PrestigeCamo) -> Int? {
        let count = prestigeStages.count
        guard count > 0 else { return nil }
        return min(camo.stage ?? count, count)
    }

    /// The level within its stage a Prestige camo needs on this weapon:
    /// the weapon's own override, the level after its max when the camo
    /// says so, or
    /// the camo's level. `nil` when reaching the stage is enough.
    func prestigeCamoLevel(_ camo: PrestigeCamo, weaponId: Int) -> Int? {
        if let level = camo.byWeapon?[String(weaponId)]?.level { return level }
        if camo.afterWeaponMaxLevel == true { return weapon(id: weaponId).map { $0.maxLevel + 1 } }
        return camo.level
    }

    /// Earned by the weapon's own Prestige and level, the way a Military
    /// camo is by its level.
    func hasReachedPrestigeCamo(_ camo: PrestigeCamo, weaponId: Int) -> Bool {
        guard let stage = prestigeCamoStage(camo) else { return false }
        let current = prestige(for: weaponId)
        if current != stage { return current > stage }
        return level(for: weaponId) >= (prestigeCamoLevel(camo, weaponId: weaponId) ?? 0)
    }

    func isPrestigeCamoComplete(weaponId: Int, index: Int) -> Bool {
        guard prestigeCamos.indices.contains(index) else { return false }
        return hasReachedPrestigeCamo(prestigeCamos[index], weaponId: weaponId)
            || completed.contains(prestigeCamoKey(weaponId, index))
    }

    /// Like a Military camo: tapping one sets the weapon's Prestige and
    /// level to it, tapping an earned one steps back to just below it. In
    /// quick tick it's a plain tick, with the ones before it.
    func togglePrestigeCamo(weaponId: Int, index: Int) {
        guard prestigeCamos.indices.contains(index), let weapon = weapon(id: weaponId),
              let stage = prestigeCamoStage(prestigeCamos[index]) else { return }
        let camo = prestigeCamos[index]
        let wasDone = isPrestigeCamoComplete(weaponId: weaponId, index: index)
        if wasDone {
            for later in index..<prestigeCamos.count { completed.remove(prestigeCamoKey(weaponId, later)) }
            if hasReachedPrestigeCamo(camo, weaponId: weaponId) {
                if let level = prestigeCamoLevel(camo, weaponId: weaponId), level > 1 {
                    weaponPrestige[weaponId] = stage
                    weaponLevels[weaponId] = level - 1
                } else {
                    // Reaching the stage was all it took: back to the one
                    // before it, maxed, as undoing a prestige does.
                    weaponPrestige[weaponId] = stage - 1
                    weaponLevels[weaponId] = maxLevel(for: weapon)
                }
            }
        } else if quickTick {
            for earlier in 0...index { completed.insert(prestigeCamoKey(weaponId, earlier)) }
        } else {
            let current = prestige(for: weaponId) == stage ? level(for: weaponId) : 1
            weaponPrestige[weaponId] = stage
            weaponLevels[weaponId] = max(current, prestigeCamoLevel(camo, weaponId: weaponId) ?? 1)
        }
        saveProgress()
        objectWillChange.send()
        Haptics.change(wasDone: wasDone, isDone: isPrestigeCamoComplete(weaponId: weaponId, index: index))
    }

    /// The camo's name, or the weapon's own when it has one.
    func prestigeCamoName(_ camo: PrestigeCamo, weaponId: Int) -> LocalizedText {
        camo.byWeapon?[String(weaponId)]?.name ?? camo.name
    }

    func prestigeCamoImageURL(_ camo: PrestigeCamo, weaponId: Int) -> String? {
        camo.byWeapon?[String(weaponId)]?.imageURL ?? camo.imageURL
    }

    // MARK: - Camo challenges (per mode, per weapon)

    /// That mode's camo track for a weapon — empty if the mode file doesn't
    /// cover it.
    func camos(weaponId: Int, mode: String) -> [ChallengeItem] {
        modes[trackMode(mode)]?.weaponCamos.first { $0.weaponId == weaponId }?.camos ?? []
    }

    /// Capped at the current requirement on read, not on save: a requirement
    /// lowered over the air (10 → 5) must not show "8/5" or make − jump
    /// straight to 5, but the stored 8 stays, so raising it again later
    /// gives the player their real progress back.
    func camoAmount(mode: String, weaponId: Int, camo: ChallengeItem) -> Int {
        min(amounts[camoKey(mode, weaponId, camo.itemId)] ?? 0, camo.requirement?.amount ?? .max)
    }

    func isCamoComplete(mode: String, weaponId: Int, camo: ChallengeItem) -> Bool {
        if let level = militaryLevel(mode: mode, weaponId: weaponId, camo: camo) {
            // By level, or ticked by hand in quick tick.
            return hasReached(level, weaponId: weaponId) || completed.contains(camoKey(mode, weaponId, camo.itemId))
        }
        // One camo grind per weapon across modes (launch blog, 19 Oct
        // 2026): finished in any mode is unlocked in all. Each mode keeps
        // its own count, read as saved, progress from before this included.
        return camoTrackModes.contains { other in
            let own = trackMode(other) == trackMode(mode) ? camo
                : camos(weaponId: weaponId, mode: other).first { $0.itemId == camo.itemId }
            return own.map { isCamoDone(in: other, weaponId: weaponId, camo: $0) } ?? false
        }
    }

    /// Every mode with its own camo track (a mode sharing another's counts
    /// as that one).
    private var camoTrackModes: [String] {
        Array(Set(modes.keys.map(trackMode))).sorted()
    }

    /// Finished in this mode's own count.
    private func isCamoDone(in mode: String, weaponId: Int, camo: ChallengeItem) -> Bool {
        let k = camoKey(mode, weaponId, camo.itemId)
        guard let req = camo.requirement else { return completed.contains(k) }
        return (amounts[k] ?? 0) >= req.amount
    }

    /// The weapon level that earns this Military camo, or nil for any other
    /// camo. Military camos have no challenge: reaching the level is the
    /// whole of it. Until the mode file gives the real `unlockLevel`, the
    /// weapon's Military camos are spread evenly up to its max level, so the
    /// last one lands on max.
    func militaryLevel(mode: String, weaponId: Int, camo: ChallengeItem) -> Int? {
        guard camo.group == "military", camo.requirement == nil else { return nil }
        if let level = camo.unlockLevel { return level }
        let military = camos(weaponId: weaponId, mode: mode).filter { $0.group == "military" }
        guard let index = military.firstIndex(where: { $0.itemId == camo.itemId }),
              let weapon = weapon(id: weaponId) else { return nil }
        // The weapon's own normal max, never the current prestige stage's
        // (Prestige Master runs to 250), so the levels don't move on prestige.
        let max = weapon.maxLevel
        return Swift.max(1, Int((Double(max) * Double(index + 1) / Double(military.count)).rounded(.up)))
    }

    /// Every Military camo on this weapon is earned: what opens its Specials.
    func allMilitaryComplete(mode: String, weaponId: Int) -> Bool {
        camos(weaponId: weaponId, mode: mode).filter { $0.group == "military" }
            .allSatisfy { isCamoComplete(mode: mode, weaponId: weaponId, camo: $0) }
    }

    /// Level gates are on the weapon's normal levels, so a prestiged weapon
    /// has passed every one of them even though its level has reset.
    private func hasReached(_ unlockLevel: Int, weaponId: Int) -> Bool {
        prestige(for: weaponId) > 0 || level(for: weaponId) >= unlockLevel
    }

    func setCamoAmount(mode: String, weaponId: Int, camo: ChallengeItem, amount newAmount: Int) {
        let wasGold = allCamosComplete(weaponId: weaponId, mode: mode)
        let wasDone = isCamoComplete(mode: mode, weaponId: weaponId, camo: camo)
        let req = camo.requirement?.amount ?? 1
        amounts[camoKey(mode, weaponId, camo.itemId)] = max(0, min(newAmount, req))
        saveProgress()
        objectWillChange.send()
        checkMilestone(weaponId: weaponId, mode: mode, wasGold: wasGold)
        Haptics.change(wasDone: wasDone, isDone: isCamoComplete(mode: mode, weaponId: weaponId, camo: camo))
    }

    func toggleCamo(mode: String, weaponId: Int, camo: ChallengeItem) {
        // A Military camo is the weapon level: tapping one sets the level to
        // it, tapping an earned one steps back to just below it. In quick
        // tick it's a plain tick instead. A prestiged weapon has them all.
        if let level = militaryLevel(mode: mode, weaponId: weaponId, camo: camo) {
            guard prestige(for: weaponId) == 0, let weapon = weapon(id: weaponId) else { return }
            let wasGold = allCamosComplete(weaponId: weaponId, mode: mode)
            let wasDone = isCamoComplete(mode: mode, weaponId: weaponId, camo: camo)
            let military = camos(weaponId: weaponId, mode: mode).filter { $0.group == "military" }
            let index = military.firstIndex { $0.itemId == camo.itemId } ?? 0
            // A level change checks its own milestones, in every mode.
            if wasDone {
                // This one and every one after it, as lowering the level would.
                for later in military[index...] { completed.remove(camoKey(mode, weaponId, later.itemId)) }
                if hasReached(level, weaponId: weaponId) { applyLevel(level - 1, for: weapon) }
            } else if !quickTick {
                applyLevel(level, for: weapon)
            } else {
                for earlier in military[...index] { completed.insert(camoKey(mode, weaponId, earlier.itemId)) }
                checkMilestone(weaponId: weaponId, mode: mode, wasGold: wasGold)
            }
            saveProgress()
            objectWillChange.send()
            Haptics.change(wasDone: wasDone, isDone: isCamoComplete(mode: mode, weaponId: weaponId, camo: camo))
            return
        }
        let wasGold = allCamosComplete(weaponId: weaponId, mode: mode)
        let wasDone = isCamoComplete(mode: mode, weaponId: weaponId, camo: camo)
        if wasDone {
            // Unticking clears it in every mode, or a finish elsewhere would
            // keep it ticked here
            for other in camoTrackModes {
                let k = camoKey(other, weaponId, camo.itemId)
                amounts[k] = nil
                completed.remove(k)
            }
        } else {
            let k = camoKey(mode, weaponId, camo.itemId)
            if let req = camo.requirement { amounts[k] = req.amount } else { completed.insert(k) }
        }
        saveProgress()
        objectWillChange.send()
        checkMilestone(weaponId: weaponId, mode: mode, wasGold: wasGold)
        Haptics.change(wasDone: wasDone, isDone: isCamoComplete(mode: mode, weaponId: weaponId, camo: camo))
    }

    /// Whether this camo's challenge is open yet. A camo with an
    /// `unlockLevel` opens when the weapon reaches that level, which is how
    /// MW4 gates its base camos; one without falls back to the cascading
    /// chain (first tier open, each later tier needs the one before it).
    /// A camo already earned stays open, so lowering the level afterwards
    /// doesn't lock something the player has. Gates are on the weapon's
    /// normal levels, so a prestiged weapon has passed every one of them
    /// even though its level has reset.
    func isCamoAvailable(mode: String, weaponId: Int, camo: ChallengeItem) -> Bool {
        if quickTick || isCamoComplete(mode: mode, weaponId: weaponId, camo: camo) { return true }
        // Always tappable: a tap sets the weapon level.
        if militaryLevel(mode: mode, weaponId: weaponId, camo: camo) != nil { return true }
        // Specials open at their own level; with `specialsAfterMilitary`
        // they also wait for every Military camo.
        if camo.group == "special" {
            if specialsWaitForMilitary(mode: mode), !allMilitaryComplete(mode: mode, weaponId: weaponId) { return false }
            return camo.unlockLevel.map { hasReached($0, weaponId: weaponId) } ?? true
        }
        if let unlockLevel = camo.unlockLevel {
            return hasReached(unlockLevel, weaponId: weaponId)
        }
        let siblings = camos(weaponId: weaponId, mode: mode)
        guard let index = siblings.firstIndex(where: { $0.itemId == camo.itemId }), index > 0 else { return true }
        return isCamoComplete(mode: mode, weaponId: weaponId, camo: siblings[index - 1])
    }

    /// Same cascading rule for a mode-exclusive objective's sub-tiers (DMZ).
    func isObjectiveAvailable(mode: String, categoryId: Int, siblings: [ChallengeItem], item: ChallengeItem) -> Bool {
        guard let index = siblings.firstIndex(where: { $0.itemId == item.itemId }), index > 0 else { return true }
        return isObjectiveComplete(mode: mode, categoryId: categoryId, item: siblings[index - 1])
    }

    /// Whether every camo for this weapon, in this mode, is complete — "Gold."
    func allCamosComplete(weaponId: Int, mode: String) -> Bool {
        let leaves = camos(weaponId: weaponId, mode: mode).flatMap(leafItems)
        return !leaves.isEmpty && leaves.allSatisfy { isCamoComplete(mode: mode, weaponId: weaponId, camo: $0) }
    }

    /// How many camos are left before this weapon goes Gold, in this mode.
    func remainingCamoCount(weaponId: Int, mode: String) -> Int {
        camos(weaponId: weaponId, mode: mode).flatMap(leafItems)
            .filter { !isCamoComplete(mode: mode, weaponId: weaponId, camo: $0) }.count
    }

    /// How many weapons in a category are already Gold, in this mode.
    func goldWeaponCount(in category: WeaponCategory, mode: String) -> Int {
        category.weapons.filter { allCamosComplete(weaponId: $0.weaponId, mode: mode) }.count
    }

    // MARK: - App-wide aggregates (mode-wide stat summary header)

    var totalWeaponCount: Int {
        catalog?.categories.reduce(0) { $0 + $1.weapons.count } ?? 0
    }

    var totalCategoryCount: Int {
        catalog?.categories.count ?? 0
    }

    /// The launch-day weapon roster size, for the Mastery tier3 capstone gate
    /// (see `WeaponCatalog.baseWeaponCount`) — falls back to the live weapon
    /// count for a catalog that predates this field, which just reproduces
    /// the old (DLC-unaware) behavior rather than under- or over-counting.
    var baseWeaponCount: Int {
        catalog?.baseWeaponCount ?? totalWeaponCount
    }

    /// Weapons whose base camo track is finished in at least one mode.
    /// Counted per weapon rather than per mode, so a gun taken all the way in
    /// both Multiplayer and Warzone is one finished weapon, not two - which
    /// is what "5 weapons done" means to someone playing.
    var weaponsWithBaseCamosComplete: Int {
        guard let catalog else { return 0 }
        return catalog.categories.reduce(0) { running, category in
            running + category.weapons.filter { weapon in
                modes.keys.contains { allCamosComplete(weaponId: weapon.weaponId, mode: $0) }
            }.count
        }
    }

    func totalGoldWeaponCount(mode: String) -> Int {
        catalog?.categories.reduce(0) { $0 + goldWeaponCount(in: $1, mode: mode) } ?? 0
    }

    // MARK: - Completionist (per weapon, per mode)
    //
    // Once a weapon's Military and Special camos are done in a mode, its
    // Completionist camos open there, one after another:
    //   Gold → Platinum → Harmonic Break, each with its own challenge (the
    //   mode file can set a different one per weapon category), then
    //   the final camo (Divergence in Multiplayer), which has no challenge:
    //   the weapon earns it once it has its own Harmonic Break and the mode
    //   has `harmonicBreaksNeeded` Harmonic Breaks across all its weapons.

    static let completionistStepCount = 3

    /// The mode whose camo list and Completionist progress this mode uses:
    /// itself, or the one its file's `trackFrom` names for a grind shared
    /// across modes. Mastery is always the mode's own.
    func trackMode(_ mode: String) -> String { TrackSharing.byMode[mode] ?? mode }

    /// The modes to show: every mode its file doesn't mark `hidden`.
    var visibleModes: [AppMode] {
        // The modes the player picked (Customise > Modes you play), less any
        // the data hides for now (Warzone until Season 1)
        let picked = AppMode.played(UserDefaults.standard.string(forKey: AppMode.playedKey) ?? "")
        let shown = picked.filter { modes[$0.rawValue]?.hidden != true }
        return shown.isEmpty ? [.multiplayer] : shown
    }

    /// Whether this mode's Specials stay shut until every Military camo is
    /// earned, rather than opening at their own level.
    func specialsWaitForMilitary(mode: String) -> Bool {
        SpecialRule.afterMilitary.contains(trackMode(mode))
    }

    /// Whether this mode's track has the final camo after Harmonic Break.
    func finalEnabled(mode: String) -> Bool {
        CompletionistOverrides.byMode[trackMode(mode)]?.final?.enabled ?? true
    }

    private func completionistKey(_ mode: String, _ weaponId: Int, _ step: Int) -> String {
        "comp|\(trackMode(mode))|\(weaponId)|\(step)"
    }

    /// Gold, Platinum or Harmonic Break's challenge for this weapon: its
    /// own, else its category's, else the step's default, else none (a
    /// tick box).
    func completionistRequirement(mode: String, weaponId: Int, step: Int) -> Requirement? {
        guard let steps = CompletionistOverrides.byMode[trackMode(mode)]?.steps, steps.indices.contains(step) else { return nil }
        let config = steps[step]
        return requirement(weaponId: weaponId, own: config.byWeapon, byCategory: config.byCategory, fallback: config.requirement)
    }

    /// The most specific challenge for a weapon: its own, its class's, then
    /// the default.
    private func requirement(weaponId: Int, own: [String: Requirement]?, byCategory: [String: Requirement]?,
                             fallback: Requirement?) -> Requirement? {
        if let mine = own?[String(weaponId)] { return mine }
        if let categoryId = category(containingWeaponId: weaponId)?.categoryId,
           let classs = byCategory?[String(categoryId)] {
            return classs
        }
        return fallback
    }

    /// Capped at the current requirement on read — see `camoAmount`.
    func completionistAmount(mode: String, weaponId: Int, step: Int) -> Int {
        min(amounts[completionistKey(mode, weaponId, step)] ?? 0,
            completionistRequirement(mode: mode, weaponId: weaponId, step: step)?.amount ?? .max)
    }

    /// Like camos, Gold, Platinum and Harmonic Break count in every mode
    /// once done in one ("wholly or partly in Multiplayer or DMZ").
    func isCompletionistComplete(mode: String, weaponId: Int, step: Int) -> Bool {
        camoTrackModes.contains { isCompletionistDone(in: $0, weaponId: weaponId, step: step) }
    }

    private func isCompletionistDone(in mode: String, weaponId: Int, step: Int) -> Bool {
        let key = completionistKey(mode, weaponId, step)
        guard let requirement = completionistRequirement(mode: mode, weaponId: weaponId, step: step) else {
            return completed.contains(key)
        }
        return (amounts[key] ?? 0) >= requirement.amount
    }

    enum CompletionistGate: String { case weapon, category, mode }

    /// How widely the step before has to be done for this step to open:
    /// Gold on the weapon alone, Platinum once its whole class has Gold,
    /// Harmonic Break once every weapon has Platinum. The mode file can
    /// change any of them.
    func completionistGate(mode: String, step: Int) -> CompletionistGate {
        completionistStepConfig(mode: mode, step: step)?.unlock.flatMap(CompletionistGate.init(rawValue:))
            ?? [.weapon, .category, .mode][min(step, 2)]
    }

    private func completionistStepConfig(mode: String, step: Int) -> CompletionistStepConfig? {
        let steps = CompletionistOverrides.byMode[trackMode(mode)]?.steps
        return steps.flatMap { $0.indices.contains(step) ? $0[step] : nil }
    }

    /// A gate's count: `needed` capped at what's there to count, else the
    /// launch count it defaults to.
    private func gateTotal(needed: Int?, available: Int, launch: Int) -> Int {
        needed.map { max(1, min($0, max(1, available))) } ?? max(1, launch)
    }

    /// Whether this weapon has done what opens `step`: its camo list for
    /// Gold, the step before for the rest.
    private func hasPrerequisite(mode: String, weaponId: Int, step: Int) -> Bool {
        step == 0
            ? allCamosComplete(weaponId: weaponId, mode: mode)
            : isCompletionistComplete(mode: mode, weaponId: weaponId, step: step - 1)
    }

    /// For a "mode" gate: weapons with the step before, out of the launch
    /// roster (a finished DLC weapon can stand in for a launch one).
    func completionistModeGateProgress(mode: String, step: Int) -> (done: Int, total: Int) {
        let total = gateTotal(needed: completionistStepConfig(mode: mode, step: step)?.needed,
                              available: totalWeaponCount, launch: min(totalWeaponCount, baseWeaponCount))
        let done = allWeapons.filter { hasPrerequisite(mode: mode, weaponId: $0.weaponId, step: step) }.count
        return (min(done, total), total)
    }

    /// For a "category" gate: weapons in the class with the step before, out
    /// of how many the class had at launch. Launch weapons are the ones with
    /// ids below `baseWeaponCount` (ids are handed out in order), so a DLC
    /// weapon added later can stand in for a launch one left unfinished.
    func completionistCategoryGateProgress(_ category: WeaponCategory, mode: String, step: Int) -> (done: Int, total: Int) {
        let launch = category.weapons.filter { $0.weaponId < baseWeaponCount }.count
        let total = gateTotal(needed: completionistStepConfig(mode: mode, step: step)?.needed,
                              available: category.weapons.count, launch: launch)
        let done = category.weapons.filter { hasPrerequisite(mode: mode, weaponId: $0.weaponId, step: step) }.count
        return (min(done, total), total)
    }

    /// Open once this weapon has the step before (its camo list for Gold)
    /// and the gate's wider condition holds. Earned stays open.
    func isCompletionistAvailable(mode: String, weaponId: Int, step: Int) -> Bool {
        if quickTick || isCompletionistComplete(mode: mode, weaponId: weaponId, step: step) { return true }
        guard hasPrerequisite(mode: mode, weaponId: weaponId, step: step) else { return false }
        switch completionistGate(mode: mode, step: step) {
        case .weapon:
            return true
        case .category:
            guard let category = category(containingWeaponId: weaponId) else { return true }
            let progress = completionistCategoryGateProgress(category, mode: mode, step: step)
            return progress.done >= progress.total
        case .mode:
            let progress = completionistModeGateProgress(mode: mode, step: step)
            return progress.done >= progress.total
        }
    }

    func setCompletionistAmount(mode: String, weaponId: Int, step: Int, amount newAmount: Int) {
        let before = completionistSnapshot(mode: mode, weaponId: weaponId)
        let wasDone = isCompletionistComplete(mode: mode, weaponId: weaponId, step: step)
        let cap = completionistRequirement(mode: mode, weaponId: weaponId, step: step)?.amount ?? 1
        amounts[completionistKey(mode, weaponId, step)] = max(0, min(newAmount, cap))
        saveProgress()
        objectWillChange.send()
        checkCompletionistMilestone(mode: mode, weaponId: weaponId, before: before)
        Haptics.change(wasDone: wasDone, isDone: isCompletionistComplete(mode: mode, weaponId: weaponId, step: step))
    }

    func toggleCompletionist(mode: String, weaponId: Int, step: Int) {
        let before = completionistSnapshot(mode: mode, weaponId: weaponId)
        let wasDone = isCompletionistComplete(mode: mode, weaponId: weaponId, step: step)
        for each in run(step, through: Self.completionistStepCount, done: !wasDone) {
            // Unticking clears it in every mode; ticking marks this mode
            for other in wasDone ? camoTrackModes : [mode] {
                mark(completionistKey(other, weaponId, each),
                     requirement: completionistRequirement(mode: other, weaponId: weaponId, step: each), done: !wasDone)
            }
        }
        saveProgress()
        objectWillChange.send()
        checkCompletionistMilestone(mode: mode, weaponId: weaponId, before: before)
        Haptics.change(wasDone: wasDone, isDone: isCompletionistComplete(mode: mode, weaponId: weaponId, step: step))
    }

    /// How many weapons have their Harmonic Break in this mode.
    func harmonicBreakCount(mode: String) -> Int {
        allWeapons.filter { isCompletionistComplete(mode: mode, weaponId: $0.weaponId, step: 2) }.count
    }

    /// Harmonic Breaks across the mode that open the final camo. Zero (no
    /// number published) means a weapon's own Harmonic Break is enough.
    func harmonicBreaksNeeded(mode: String) -> Int {
        max(0, CompletionistOverrides.byMode[trackMode(mode)]?.final?.harmonicBreaksNeeded ?? 0)
    }

    func hasFinalCamo(mode: String, weaponId: Int) -> Bool {
        finalEnabled(mode: mode)
            && isCompletionistComplete(mode: mode, weaponId: weaponId, step: 2)
            && harmonicBreakCount(mode: mode) >= harmonicBreaksNeeded(mode: mode)
    }

    func finalCamoCount(mode: String) -> Int {
        guard finalEnabled(mode: mode), harmonicBreakCount(mode: mode) >= harmonicBreaksNeeded(mode: mode) else { return 0 }
        return harmonicBreakCount(mode: mode)
    }

    /// The end of the Completionist track: the final camo, or Harmonic
    /// Break when the mode has no final camo. What Mastery builds on.
    func hasLastCompletionist(mode: String, weaponId: Int) -> Bool {
        finalEnabled(mode: mode)
            ? hasFinalCamo(mode: mode, weaponId: weaponId)
            : isCompletionistComplete(mode: mode, weaponId: weaponId, step: 2)
    }

    func lastCompletionistCount(mode: String) -> Int {
        finalEnabled(mode: mode) ? finalCamoCount(mode: mode) : harmonicBreakCount(mode: mode)
    }

    func categoryLastCompletionistCount(_ category: WeaponCategory, mode: String) -> Int {
        category.weapons.filter { hasLastCompletionist(mode: mode, weaponId: $0.weaponId) }.count
    }

    /// Weapons in a category with this Completionist step (0 Gold, 1
    /// Platinum, 2 Harmonic Break), or with the final camo for `final`.
    func categoryCompletionistCount(_ category: WeaponCategory, mode: String, step: Int) -> Int {
        category.weapons.filter { isCompletionistComplete(mode: mode, weaponId: $0.weaponId, step: step) }.count
    }

    func categoryFinalCount(_ category: WeaponCategory, mode: String) -> Int {
        category.weapons.filter { hasFinalCamo(mode: mode, weaponId: $0.weaponId) }.count
    }

    /// The best Completionist camo this weapon has in this mode: 0 Gold,
    /// 1 Platinum, 2 Harmonic Break, 3 the final camo; nil for none yet.
    func highestCompletionist(mode: String, weaponId: Int) -> Int? {
        if hasFinalCamo(mode: mode, weaponId: weaponId) { return 3 }
        return (0..<Self.completionistStepCount).last { isCompletionistComplete(mode: mode, weaponId: weaponId, step: $0) }
    }

    var allWeapons: [WeaponEntry] { catalog?.categories.flatMap(\.weapons) ?? [] }

    // MARK: - Where a weapon is on its track (filters)

    enum WeaponStage { case military, special, completionist, finished }

    /// The part of the track this weapon is working through in this mode.
    func stage(mode: String, weaponId: Int) -> WeaponStage {
        if hasLastCompletionist(mode: mode, weaponId: weaponId) { return .finished }
        if allCamosComplete(weaponId: weaponId, mode: mode) { return .completionist }
        let hasMilitary = camos(weaponId: weaponId, mode: mode).contains { $0.group == "military" }
        return hasMilitary && !allMilitaryComplete(mode: mode, weaponId: weaponId) ? .military : .special
    }

    /// A Special camo or Completionist challenge that's unlocked but not
    /// done: something to work on in the next match.
    func hasOpenChallenge(mode: String, weaponId: Int) -> Bool {
        let openSpecial = camos(weaponId: weaponId, mode: mode).contains { camo in
            militaryLevel(mode: mode, weaponId: weaponId, camo: camo) == nil
                && !isCamoComplete(mode: mode, weaponId: weaponId, camo: camo)
                && isCamoAvailable(mode: mode, weaponId: weaponId, camo: camo)
        }
        if openSpecial { return true }
        let openStep = (0..<Self.completionistStepCount).contains { step in
            !isCompletionistComplete(mode: mode, weaponId: weaponId, step: step)
                && isCompletionistAvailable(mode: mode, weaponId: weaponId, step: step)
        }
        if openStep { return true }
        return (1...3).contains { tier in
            !isWeaponMasteryComplete(mode: mode, weaponId: weaponId, tier: tier)
                && isWeaponMasteryAvailable(mode: mode, weaponId: weaponId, tier: tier)
        }
    }

    func matches(_ filter: WeaponFilter, mode: String, weaponId: Int) -> Bool {
        switch filter {
        case .all: return true
        case .incomplete: return !allCamosComplete(weaponId: weaponId, mode: mode)
        case .complete: return allCamosComplete(weaponId: weaponId, mode: mode)
        case .ready: return hasOpenChallenge(mode: mode, weaponId: weaponId)
        case .onMilitary: return stage(mode: mode, weaponId: weaponId) == .military
        case .onSpecial: return stage(mode: mode, weaponId: weaponId) == .special
        case .inCompletionist: return stage(mode: mode, weaponId: weaponId) == .completionist
        case .hasFinal: return stage(mode: mode, weaponId: weaponId) == .finished
        }
    }

    /// Every weapon as one list, for the "All weapons" screen.
    var allWeaponsCategory: WeaponCategory? {
        guard let catalog else { return nil }
        return WeaponCategory(categoryId: Self.allWeaponsCategoryId,
                              name: LocalizedText("mw4.ui.all_weapons".localized()),
                              weapons: catalog.categories.flatMap(\.weapons))
    }

    static let allWeaponsCategoryId = -1

    // MARK: - Mastery (per mode)
    //
    // Each mode's trio (Mercurial Drift → Polyatomic Reforged → Orion
    // Reforged in Multiplayer, Parallax → Damascus Reforged → Empyros in
    // Warzone, Chiral → Ripple Tide → Helio in DMZ). Three ways it can
    // unlock, chosen by the mode file's `mastery.unlock`:
    //   "count" (default): one tier at a time for the mode, once
    //   `weaponsNeeded` weapons have the last Completionist camo (a third,
    //   two thirds and all of the launch roster until published).
    //   "challenge": each tier is a per-weapon challenge like Platinum,
    //   opened by its gate (tier 1: the last Completionist camo on the whole
    //   launch roster; later tiers: the tier before on the weapon).
    //   "mode": each tier is one challenge for the whole mode, as the game
    //   shows them (tier 1 after Divergence, then each after the last).
    // A tier's own `kind` beats the mode's `unlock`, so they can be mixed.

    enum MasteryKind: String { case count, challenge, mode }

    func masteryKind(mode: String, tier: Int) -> MasteryKind {
        let raw = masteryTierConfig(mode: mode, tier: tier)?.kind ?? MasteryOverrides.byMode[mode]?.unlock
        return raw.flatMap(MasteryKind.init(rawValue:)) ?? .count
    }

    /// Whether any tier is a per-weapon challenge.
    func masteryUsesChallenges(mode: String) -> Bool {
        (1...3).contains { masteryKind(mode: mode, tier: $0) == .challenge }
    }

    private func masteryTierConfig(mode: String, tier: Int) -> MasteryTierConfig? {
        let config = MasteryOverrides.byMode[mode]
        return [config?.tier1, config?.tier2, config?.tier3][max(0, min(tier, 3) - 1)]
    }

    func masteryWeaponsNeeded(mode: String, tier: Int) -> Int {
        let tiers = AppMode(rawValue: mode)?.masteryCamos
        let configured = [tiers?.tier1, tiers?.tier2, tiers?.tier3][max(0, min(tier, 3) - 1)]?.weaponsNeeded
        return configured ?? max(1, Int((Double(launchRoster) * Double(tier) / 3).rounded(.up)))
    }

    private var launchRoster: Int { max(1, min(totalWeaponCount, baseWeaponCount)) }

    /// Count Mastery: weapons with the last Completionist camo out of the
    /// tier's count. Challenge Mastery: weapons with this tier out of the
    /// launch roster.
    func masteryProgress(mode: String, tier: Int) -> (done: Int, total: Int) {
        switch masteryKind(mode: mode, tier: tier) {
        case .mode:
            guard let requirement = modeMasteryRequirement(mode: mode, tier: tier) else {
                return (isModeMasteryComplete(mode: mode, tier: tier) ? 1 : 0, 1)
            }
            return (modeMasteryAmount(mode: mode, tier: tier), max(1, requirement.amount))
        case .challenge:
            let done = allWeapons.filter { isWeaponMasteryComplete(mode: mode, weaponId: $0.weaponId, tier: tier) }.count
            return (min(done, launchRoster), launchRoster)
        case .count:
            let needed = masteryWeaponsNeeded(mode: mode, tier: tier)
            return (min(lastCompletionistCount(mode: mode), needed), needed)
        }
    }

    /// The tier before is done as far as this weapon is concerned: on the
    /// weapon itself for a per-weapon tier, for the mode otherwise.
    func hasTierBefore(mode: String, weaponId: Int, tier: Int) -> Bool {
        masteryKind(mode: mode, tier: tier - 1) == .challenge
            ? isWeaponMasteryComplete(mode: mode, weaponId: weaponId, tier: tier - 1)
            : isMasteryAchieved(mode: mode, tier: tier - 1)
    }

    func isMasteryAchieved(mode: String, tier: Int) -> Bool {
        guard tier <= 1 || isMasteryAchieved(mode: mode, tier: tier - 1) else { return false }
        let progress = masteryProgress(mode: mode, tier: tier)
        return progress.done >= progress.total
    }

    // Mode Mastery: one challenge per tier for the whole mode.

    private func modeMasteryKey(_ mode: String, _ tier: Int) -> String {
        "modemastery|\(mode)|\(tier)"
    }

    func modeMasteryRequirement(mode: String, tier: Int) -> Requirement? {
        masteryTierConfig(mode: mode, tier: tier)?.requirement
    }

    /// The Completionist camo a unit counts across the mode, for a tier the
    /// app counts by itself: "golds", "platinums", "harmonic_breaks" or
    /// "finals" (the final camo). Nil for a unit the player counts.
    static let selfCountingUnits = ["golds": 0, "platinums": 1, "harmonic_breaks": 2, "finals": 3]

    /// What a self-counting tier counts, for its line ("12/20 Platinum").
    func modeMasteryCountedCamo(mode: String, tier: Int) -> MasteryCamo? {
        guard let unit = modeMasteryRequirement(mode: mode, tier: tier)?.unit,
              let step = Self.selfCountingUnits[unit], let appMode = AppMode(rawValue: mode) else { return nil }
        return appMode.completionistCamos.indices.contains(step) ? appMode.completionistCamos[step] : appMode.lastCompletionist
    }

    func modeMasteryCountsItself(mode: String, tier: Int) -> Bool {
        modeMasteryRequirement(mode: mode, tier: tier).flatMap { Self.selfCountingUnits[$0.unit] } != nil
    }

    /// Capped at the requirement on read, like every other count.
    func modeMasteryAmount(mode: String, tier: Int) -> Int {
        let cap = modeMasteryRequirement(mode: mode, tier: tier)?.amount ?? 1
        let raw: Int
        if let unit = modeMasteryRequirement(mode: mode, tier: tier)?.unit, let step = Self.selfCountingUnits[unit] {
            raw = completionistCount(mode: mode, step: step)
        } else {
            raw = amounts[modeMasteryKey(mode, tier)] ?? (completed.contains(modeMasteryKey(mode, tier)) ? 1 : 0)
        }
        return min(raw, cap)
    }

    func isModeMasteryComplete(mode: String, tier: Int) -> Bool {
        guard masteryKind(mode: mode, tier: tier) == .mode else { return false }
        guard let requirement = modeMasteryRequirement(mode: mode, tier: tier) else {
            return completed.contains(modeMasteryKey(mode, tier))
        }
        return modeMasteryAmount(mode: mode, tier: tier) >= requirement.amount
    }

    /// Weapons with the last Completionist camo this tier waits for: its
    /// `weaponsNeeded`, else one for tier 1 (the game's "Divergence" line)
    /// and none after it.
    func modeMasteryWeaponsNeeded(mode: String, tier: Int) -> Int {
        max(0, masteryTierConfig(mode: mode, tier: tier)?.weaponsNeeded ?? (tier == 1 ? 1 : 0))
    }

    /// Open once the tier before is earned (for the mode) and enough
    /// weapons have the last Completionist camo.
    func isModeMasteryAvailable(mode: String, tier: Int) -> Bool {
        guard masteryKind(mode: mode, tier: tier) == .mode else { return false }
        if quickTick || isModeMasteryComplete(mode: mode, tier: tier) { return true }
        guard tier == 1 || isMasteryAchieved(mode: mode, tier: tier - 1) else { return false }
        return lastCompletionistCount(mode: mode) >= modeMasteryWeaponsNeeded(mode: mode, tier: tier)
    }

    /// `weaponId` is the weapon whose page the change came from, for the
    /// milestone banner.
    func setModeMasteryAmount(mode: String, tier: Int, weaponId: Int, amount newAmount: Int) {
        guard !modeMasteryCountsItself(mode: mode, tier: tier) else { return }
        let before = completionistSnapshot(mode: mode, weaponId: weaponId)
        let wasDone = isModeMasteryComplete(mode: mode, tier: tier)
        let cap = modeMasteryRequirement(mode: mode, tier: tier)?.amount ?? 1
        amounts[modeMasteryKey(mode, tier)] = max(0, min(newAmount, cap))
        saveProgress()
        objectWillChange.send()
        checkCompletionistMilestone(mode: mode, weaponId: weaponId, before: before)
        Haptics.change(wasDone: wasDone, isDone: isModeMasteryComplete(mode: mode, tier: tier))
    }

    func toggleModeMastery(mode: String, tier: Int, weaponId: Int) {
        guard !modeMasteryCountsItself(mode: mode, tier: tier) else { return }
        let before = completionistSnapshot(mode: mode, weaponId: weaponId)
        let wasDone = isModeMasteryComplete(mode: mode, tier: tier)
        for each in run(tier - 1, through: 3, done: !wasDone).map({ $0 + 1 })
        where masteryKind(mode: mode, tier: each) == .mode && !modeMasteryCountsItself(mode: mode, tier: each) {
            mark(modeMasteryKey(mode, each), requirement: modeMasteryRequirement(mode: mode, tier: each), done: !wasDone)
        }
        saveProgress()
        objectWillChange.send()
        checkCompletionistMilestone(mode: mode, weaponId: weaponId, before: before)
        Haptics.change(wasDone: wasDone, isDone: isModeMasteryComplete(mode: mode, tier: tier))
    }

    // Challenge Mastery, per weapon.

    private func masteryKey(_ mode: String, _ weaponId: Int, _ tier: Int) -> String {
        "mastery|\(mode)|\(weaponId)|\(tier)"
    }

    func masteryRequirement(mode: String, weaponId: Int, tier: Int) -> Requirement? {
        guard let config = masteryTierConfig(mode: mode, tier: tier) else { return nil }
        return requirement(weaponId: weaponId, own: config.byWeapon, byCategory: config.byCategory, fallback: config.requirement)
    }

    func weaponMasteryAmount(mode: String, weaponId: Int, tier: Int) -> Int {
        min(amounts[masteryKey(mode, weaponId, tier)] ?? 0,
            masteryRequirement(mode: mode, weaponId: weaponId, tier: tier)?.amount ?? .max)
    }

    func isWeaponMasteryComplete(mode: String, weaponId: Int, tier: Int) -> Bool {
        guard masteryKind(mode: mode, tier: tier) == .challenge else { return false }
        let key = masteryKey(mode, weaponId, tier)
        guard let requirement = masteryRequirement(mode: mode, weaponId: weaponId, tier: tier) else {
            return completed.contains(key)
        }
        return (amounts[key] ?? 0) >= requirement.amount
    }

    func masteryGate(mode: String, tier: Int) -> CompletionistGate {
        masteryTierConfig(mode: mode, tier: tier)?.unlock.flatMap(CompletionistGate.init(rawValue:))
            ?? (tier == 1 ? .mode : .weapon)
    }

    /// Tier 1 builds on the last Completionist camo on the weapon, later
    /// tiers on the tier before (on the weapon when that one is per weapon).
    private func hasMasteryPrerequisite(mode: String, weaponId: Int, tier: Int) -> Bool {
        tier == 1
            ? hasLastCompletionist(mode: mode, weaponId: weaponId)
            : hasTierBefore(mode: mode, weaponId: weaponId, tier: tier)
    }

    /// Weapons with what this tier builds on, out of the launch roster
    /// ("mode" gate) or the class's launch count (pass its category).
    func masteryGateProgress(mode: String, tier: Int, category: WeaponCategory? = nil) -> (done: Int, total: Int) {
        let weapons = category?.weapons ?? allWeapons
        let needed = masteryTierConfig(mode: mode, tier: tier)?.needed
        let total = category.map {
            gateTotal(needed: needed, available: $0.weapons.count, launch: $0.weapons.filter { $0.weaponId < baseWeaponCount }.count)
        } ?? gateTotal(needed: needed, available: totalWeaponCount, launch: launchRoster)
        let done = weapons.filter { hasMasteryPrerequisite(mode: mode, weaponId: $0.weaponId, tier: tier) }.count
        return (min(done, total), total)
    }

    func isWeaponMasteryAvailable(mode: String, weaponId: Int, tier: Int) -> Bool {
        guard masteryKind(mode: mode, tier: tier) == .challenge else { return false }
        if quickTick || isWeaponMasteryComplete(mode: mode, weaponId: weaponId, tier: tier) { return true }
        guard hasMasteryPrerequisite(mode: mode, weaponId: weaponId, tier: tier) else { return false }
        switch masteryGate(mode: mode, tier: tier) {
        case .weapon:
            return true
        case .category:
            guard let category = category(containingWeaponId: weaponId) else { return true }
            let progress = masteryGateProgress(mode: mode, tier: tier, category: category)
            return progress.done >= progress.total
        case .mode:
            let progress = masteryGateProgress(mode: mode, tier: tier)
            return progress.done >= progress.total
        }
    }

    func setWeaponMasteryAmount(mode: String, weaponId: Int, tier: Int, amount newAmount: Int) {
        let before = completionistSnapshot(mode: mode, weaponId: weaponId)
        let wasDone = isWeaponMasteryComplete(mode: mode, weaponId: weaponId, tier: tier)
        let cap = masteryRequirement(mode: mode, weaponId: weaponId, tier: tier)?.amount ?? 1
        amounts[masteryKey(mode, weaponId, tier)] = max(0, min(newAmount, cap))
        saveProgress()
        objectWillChange.send()
        checkCompletionistMilestone(mode: mode, weaponId: weaponId, before: before)
        Haptics.change(wasDone: wasDone, isDone: isWeaponMasteryComplete(mode: mode, weaponId: weaponId, tier: tier))
    }

    func toggleWeaponMastery(mode: String, weaponId: Int, tier: Int) {
        let before = completionistSnapshot(mode: mode, weaponId: weaponId)
        let wasDone = isWeaponMasteryComplete(mode: mode, weaponId: weaponId, tier: tier)
        for each in run(tier - 1, through: 3, done: !wasDone).map({ $0 + 1 })
        where masteryKind(mode: mode, tier: each) == .challenge {
            mark(masteryKey(mode, weaponId, each),
                 requirement: masteryRequirement(mode: mode, weaponId: weaponId, tier: each), done: !wasDone)
        }
        saveProgress()
        objectWillChange.send()
        checkCompletionistMilestone(mode: mode, weaponId: weaponId, before: before)
        Haptics.change(wasDone: wasDone, isDone: isWeaponMasteryComplete(mode: mode, weaponId: weaponId, tier: tier))
    }

    /// The last thing on every weapon that currently exists (DLC included):
    /// the "100%+" flex milestone past the third Mastery tier.
    func fullRosterFinalProgress(mode: String) -> (done: Int, total: Int) {
        if masteryKind(mode: mode, tier: 3) == .challenge {
            let done = allWeapons.filter { isWeaponMasteryComplete(mode: mode, weaponId: $0.weaponId, tier: 3) }.count
            return (done, totalWeaponCount)
        }
        return (lastCompletionistCount(mode: mode), totalWeaponCount)
    }

    func is100PlusAchieved(mode: String) -> Bool {
        let progress = fullRosterFinalProgress(mode: mode)
        return progress.total > 0 && progress.done >= progress.total
    }

    /// What a Completionist change can newly unlock, taken before it.
    struct CompletionistSnapshot {
        let steps: [Bool]
        /// This weapon's challenge Mastery tiers.
        let weaponMastery: [Bool]
        let finalCamoCount: Int
        let mastery: [Bool]
        let is100Plus: Bool
    }

    func completionistSnapshot(mode: String, weaponId: Int) -> CompletionistSnapshot {
        CompletionistSnapshot(
            steps: (0..<Self.completionistStepCount).map { isCompletionistComplete(mode: mode, weaponId: weaponId, step: $0) },
            weaponMastery: (1...3).map { isWeaponMasteryComplete(mode: mode, weaponId: weaponId, tier: $0) },
            finalCamoCount: finalCamoCount(mode: mode),
            mastery: (1...3).map { isMasteryAchieved(mode: mode, tier: $0) },
            is100Plus: is100PlusAchieved(mode: mode)
        )
    }

    /// Overall camo completion across every weapon in every category, for this mode.
    func overallProgressFraction(mode: String) -> Double {
        guard let categories = catalog?.categories else { return 0 }
        let leaves = categories.flatMap { $0.weapons.flatMap { camos(weaponId: $0.weaponId, mode: mode).flatMap(leafItems) } }
        guard !leaves.isEmpty else { return 0 }
        let done = categories.reduce(0) { partial, category in
            partial + category.weapons.reduce(0) { partial, weaponId in
                partial + camos(weaponId: weaponId.weaponId, mode: mode).flatMap(leafItems)
                    .filter { isCamoComplete(mode: mode, weaponId: weaponId.weaponId, camo: $0) }.count
            }
        }
        return Double(done) / Double(leaves.count)
    }

    /// True completionist percentage toward the mode's last Mastery camo —
    /// every camo in the weapon's list *and* its four Completionist camos,
    /// not just the list `overallProgressFraction` counts. Computed fresh
    /// from the current catalog every call, so new weapons count the moment
    /// a content update adds them.
    func trueCompletionFraction(mode: String) -> Double {
        fullTrackFraction(of: catalog?.categories.flatMap(\.weapons) ?? [], mode: mode)
    }

    /// The same full-track measure for one weapon class, for the Stats
    /// breakdown: its camo lists and its Completionist camos together.
    func categoryTrueCompletionFraction(_ category: WeaponCategory, mode: String) -> Double {
        fullTrackFraction(of: category.weapons, mode: mode)
    }

    /// How many weapons in this mode have this Completionist step, or the
    /// final camo for `step == completionistStepCount`.
    func completionistCount(mode: String, step: Int) -> Int {
        guard step < Self.completionistStepCount else { return finalCamoCount(mode: mode) }
        return allWeapons.filter { isCompletionistComplete(mode: mode, weaponId: $0.weaponId, step: step) }.count
    }

    private func fullTrackFraction(of weapons: [WeaponEntry], mode: String) -> Double {
        var done = 0
        var total = 0
        for weapon in weapons {
            let leaves = camos(weaponId: weapon.weaponId, mode: mode).flatMap(leafItems)
            let hasFinal = finalEnabled(mode: mode)
            let weaponTiers = (1...3).filter { masteryKind(mode: mode, tier: $0) == .challenge }
            total += leaves.count + Self.completionistStepCount + (hasFinal ? 1 : 0) + weaponTiers.count
            done += leaves.filter { isCamoComplete(mode: mode, weaponId: weapon.weaponId, camo: $0) }.count
            done += (0..<Self.completionistStepCount).filter { isCompletionistComplete(mode: mode, weaponId: weapon.weaponId, step: $0) }.count
            if hasFinalCamo(mode: mode, weaponId: weapon.weaponId) { done += 1 }
            done += weaponTiers.filter { isWeaponMasteryComplete(mode: mode, weaponId: weapon.weaponId, tier: $0) }.count
        }
        guard total > 0 else { return 0 }
        return Double(done) / Double(total)
    }

    // MARK: - Pinned weapon (quick-access card at the top of each mode tab)

    func pin(weaponId: Int) {
        pinnedWeaponId = weaponId
        defaults.set(weaponId, forKey: pinnedWeaponKey)
        refreshWidgets()
        Haptics.light()
    }

    func unpin() {
        pinnedWeaponId = nil
        defaults.removeObject(forKey: pinnedWeaponKey)
        refreshWidgets()
        Haptics.undone()
    }

    func weapon(id: Int) -> WeaponEntry? {
        catalog?.categories.flatMap(\.weapons).first { $0.weaponId == id }
    }

    func category(containingWeaponId weaponId: Int) -> WeaponCategory? {
        catalog?.categories.first { $0.weapons.contains { $0.weaponId == weaponId } }
    }

    func camoProgressFraction(weaponId: Int, mode: String) -> Double {
        let leaves = camos(weaponId: weaponId, mode: mode).flatMap(leafItems)
        guard !leaves.isEmpty else { return 0 }
        let done = leaves.filter { isCamoComplete(mode: mode, weaponId: weaponId, camo: $0) }.count
        return Double(done) / Double(leaves.count)
    }

    /// Raw "x/y camos done" for a weapon — the count `camoProgressFraction`
    /// only expresses as a fraction. Used on rows scoped outside any one
    /// category (search results, the pinned weapon), where "how far along
    /// is this weapon" is more useful at a glance than which category it's in.
    func camoCounts(weaponId: Int, mode: String) -> (done: Int, total: Int) {
        let leaves = camos(weaponId: weaponId, mode: mode).flatMap(leafItems)
        let done = leaves.filter { isCamoComplete(mode: mode, weaponId: weaponId, camo: $0) }.count
        return (done, leaves.count)
    }

    func weaponCategoryProgressFraction(_ category: WeaponCategory, mode: String) -> Double {
        let leaves = category.weapons.flatMap { camos(weaponId: $0.weaponId, mode: mode).flatMap(leafItems) }
        guard !leaves.isEmpty else { return 0 }
        let weaponIds = category.weapons.map(\.weaponId)
        let done = weaponIds.reduce(0) { partial, weaponId in
            partial + camos(weaponId: weaponId, mode: mode).flatMap(leafItems)
                .filter { isCamoComplete(mode: mode, weaponId: weaponId, camo: $0) }.count
        }
        return Double(done) / Double(leaves.count)
    }

    // MARK: - Objectives (mode-exclusive, non-weapon — DMZ extraction goals etc.)

    /// Capped at the current requirement on read — see `camoAmount`.
    func objectiveAmount(mode: String, categoryId: Int, item: ChallengeItem) -> Int {
        min(amounts[objectiveKey(mode, categoryId, item.itemId)] ?? 0, item.requirement?.amount ?? .max)
    }

    func isObjectiveComplete(mode: String, categoryId: Int, item: ChallengeItem) -> Bool {
        let k = objectiveKey(mode, categoryId, item.itemId)
        guard let req = item.requirement else { return completed.contains(k) }
        return (amounts[k] ?? 0) >= req.amount
    }

    func setObjectiveAmount(mode: String, categoryId: Int, item: ChallengeItem, amount newAmount: Int) {
        let req = item.requirement?.amount ?? 1
        amounts[objectiveKey(mode, categoryId, item.itemId)] = max(0, min(newAmount, req))
        saveProgress()
        objectWillChange.send()
    }

    func toggleObjective(mode: String, categoryId: Int, item: ChallengeItem) {
        let k = objectiveKey(mode, categoryId, item.itemId)
        if let req = item.requirement {
            let done = (amounts[k] ?? 0) >= req.amount
            amounts[k] = done ? 0 : req.amount
        } else if completed.contains(k) {
            completed.remove(k)
        } else {
            completed.insert(k)
        }
        saveProgress()
        objectWillChange.send()
    }

    func objectiveProgressFraction(of item: ChallengeItem, mode: String, categoryId: Int) -> Double {
        fraction(of: leafItems(item), mode: mode, categoryId: categoryId)
    }

    func objectiveProgressFraction(of category: Category, mode: String) -> Double {
        fraction(of: category.items.flatMap(leafItems), mode: mode, categoryId: category.categoryId)
    }

    private func fraction(of leaves: [ChallengeItem], mode: String, categoryId: Int) -> Double {
        guard !leaves.isEmpty else { return 0 }
        let done = leaves.filter { isObjectiveComplete(mode: mode, categoryId: categoryId, item: $0) }.count
        return Double(done) / Double(leaves.count)
    }

    func leafItems(_ item: ChallengeItem) -> [ChallengeItem] {
        item.isLeaf ? [item] : item.children.flatMap(leafItems)
    }

    // MARK: - Persistence

    private func prestigeCamoKey(_ weaponId: Int, _ index: Int) -> String {
        "prestigecamo|\(weaponId)|\(index)"
    }

    private func camoKey(_ mode: String, _ weaponId: Int, _ camoId: Int) -> String {
        "camo|\(trackMode(mode))|\(weaponId)|\(camoId)"
    }

    private func objectiveKey(_ mode: String, _ categoryId: Int, _ itemId: Int) -> String {
        "obj|\(mode)|\(categoryId)|\(itemId)"
    }

    private func loadProgress() {
        guard let data = defaults.data(forKey: storeKey),
              let store = try? JSONDecoder().decode(ProgressStore.self, from: data) else { return }
        weaponLevels = store.weaponLevels
        weaponPrestige = store.weaponPrestige ?? [:]
        amounts = store.amounts
        completed = Set(store.completed)
    }

    private func saveProgress() {
        let store = ProgressStore(weaponLevels: weaponLevels, weaponPrestige: weaponPrestige, amounts: amounts, completed: Array(completed))
        if let data = try? JSONEncoder().encode(store) {
            defaults.set(data, forKey: storeKey)
        }
        refreshWidgets()
    }
}

private struct ProgressStore: Codable {
    var weaponLevels: [Int: Int]
    /// Optional so a save from before Weapon Prestige existed still decodes.
    var weaponPrestige: [Int: Int]?
    var amounts: [String: Int]
    var completed: [String]
}
