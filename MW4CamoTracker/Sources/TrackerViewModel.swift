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
                modes = merged
            }
            refreshError = nil
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

    // MARK: - Weapon level (global — same value in every mode)

    func level(for weaponId: Int) -> Int {
        weaponLevels[weaponId] ?? 0
    }

    func setLevel(_ level: Int, for weapon: WeaponEntry) {
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
    }

    // MARK: - Camo challenges (per mode, per weapon)

    /// That mode's camo track for a weapon — empty if the mode file doesn't
    /// cover it.
    func camos(weaponId: Int, mode: String) -> [ChallengeItem] {
        modes[mode]?.weaponCamos.first { $0.weaponId == weaponId }?.camos ?? []
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
            return hasReached(level, weaponId: weaponId)
        }
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
        let max = maxLevel(for: weapon)
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
        let req = camo.requirement?.amount ?? 1
        amounts[camoKey(mode, weaponId, camo.itemId)] = max(0, min(newAmount, req))
        saveProgress()
        objectWillChange.send()
        checkMilestone(weaponId: weaponId, mode: mode, wasGold: wasGold)
    }

    func toggleCamo(mode: String, weaponId: Int, camo: ChallengeItem) {
        // A Military camo is the weapon level: tapping one sets the level to
        // it, tapping an earned one steps back to just below it. A prestiged
        // weapon has them all, so there is nothing to change.
        if let level = militaryLevel(mode: mode, weaponId: weaponId, camo: camo) {
            guard prestige(for: weaponId) == 0, let weapon = weapon(id: weaponId) else { return }
            setLevel(isCamoComplete(mode: mode, weaponId: weaponId, camo: camo) ? level - 1 : level, for: weapon)
            return
        }
        let wasGold = allCamosComplete(weaponId: weaponId, mode: mode)
        let k = camoKey(mode, weaponId, camo.itemId)
        if let req = camo.requirement {
            let done = (amounts[k] ?? 0) >= req.amount
            amounts[k] = done ? 0 : req.amount
        } else if completed.contains(k) {
            completed.remove(k)
        } else {
            completed.insert(k)
        }
        saveProgress()
        objectWillChange.send()
        checkMilestone(weaponId: weaponId, mode: mode, wasGold: wasGold)
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
        if isCamoComplete(mode: mode, weaponId: weaponId, camo: camo) { return true }
        // Always tappable: a tap sets the weapon level.
        if militaryLevel(mode: mode, weaponId: weaponId, camo: camo) != nil { return true }
        // Specials stay shut until every Military camo is earned, then also
        // wait for their own level if they have one.
        if camo.group == "special" {
            guard allMilitaryComplete(mode: mode, weaponId: weaponId) else { return false }
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

    private func completionistKey(_ mode: String, _ weaponId: Int, _ step: Int) -> String {
        "comp|\(mode)|\(weaponId)|\(step)"
    }

    /// Gold, Platinum or Harmonic Break's challenge for this weapon: its
    /// category's own, else the step's default, else none (a tick box).
    func completionistRequirement(mode: String, weaponId: Int, step: Int) -> Requirement? {
        guard let steps = CompletionistOverrides.byMode[mode]?.steps, steps.indices.contains(step) else { return nil }
        let config = steps[step]
        if let categoryId = category(containingWeaponId: weaponId)?.categoryId,
           let own = config.byCategory?[String(categoryId)] {
            return own
        }
        return config.requirement
    }

    /// Capped at the current requirement on read — see `camoAmount`.
    func completionistAmount(mode: String, weaponId: Int, step: Int) -> Int {
        min(amounts[completionistKey(mode, weaponId, step)] ?? 0,
            completionistRequirement(mode: mode, weaponId: weaponId, step: step)?.amount ?? .max)
    }

    func isCompletionistComplete(mode: String, weaponId: Int, step: Int) -> Bool {
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
        let steps = CompletionistOverrides.byMode[mode]?.steps
        let configured = steps.flatMap { $0.indices.contains(step) ? $0[step].unlock : nil }
        return configured.flatMap(CompletionistGate.init(rawValue:)) ?? [.weapon, .category, .mode][min(step, 2)]
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
        let total = max(1, min(totalWeaponCount, baseWeaponCount))
        let done = allWeapons.filter { hasPrerequisite(mode: mode, weaponId: $0.weaponId, step: step) }.count
        return (min(done, total), total)
    }

    /// For a "category" gate: weapons in the class with the step before, out
    /// of how many the class had at launch. Launch weapons are the ones with
    /// ids below `baseWeaponCount` (ids are handed out in order), so a DLC
    /// weapon added later can stand in for a launch one left unfinished.
    func completionistCategoryGateProgress(_ category: WeaponCategory, mode: String, step: Int) -> (done: Int, total: Int) {
        let launch = category.weapons.filter { $0.weaponId < baseWeaponCount }.count
        let total = max(1, launch)
        let done = category.weapons.filter { hasPrerequisite(mode: mode, weaponId: $0.weaponId, step: step) }.count
        return (min(done, total), total)
    }

    /// Open once this weapon has the step before (its camo list for Gold)
    /// and the gate's wider condition holds. Earned stays open.
    func isCompletionistAvailable(mode: String, weaponId: Int, step: Int) -> Bool {
        if isCompletionistComplete(mode: mode, weaponId: weaponId, step: step) { return true }
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
        let cap = completionistRequirement(mode: mode, weaponId: weaponId, step: step)?.amount ?? 1
        amounts[completionistKey(mode, weaponId, step)] = max(0, min(newAmount, cap))
        saveProgress()
        objectWillChange.send()
        checkCompletionistMilestone(mode: mode, weaponId: weaponId, before: before)
    }

    func toggleCompletionist(mode: String, weaponId: Int, step: Int) {
        let before = completionistSnapshot(mode: mode, weaponId: weaponId)
        let key = completionistKey(mode, weaponId, step)
        if let requirement = completionistRequirement(mode: mode, weaponId: weaponId, step: step) {
            amounts[key] = isCompletionistComplete(mode: mode, weaponId: weaponId, step: step) ? 0 : requirement.amount
        } else if completed.contains(key) {
            completed.remove(key)
        } else {
            completed.insert(key)
        }
        saveProgress()
        objectWillChange.send()
        checkCompletionistMilestone(mode: mode, weaponId: weaponId, before: before)
    }

    /// How many weapons have their Harmonic Break in this mode.
    func harmonicBreakCount(mode: String) -> Int {
        allWeapons.filter { isCompletionistComplete(mode: mode, weaponId: $0.weaponId, step: 2) }.count
    }

    /// Harmonic Breaks across the mode that open the final camo. Zero (no
    /// number published) means a weapon's own Harmonic Break is enough.
    func harmonicBreaksNeeded(mode: String) -> Int {
        max(0, CompletionistOverrides.byMode[mode]?.final?.harmonicBreaksNeeded ?? 0)
    }

    func hasFinalCamo(mode: String, weaponId: Int) -> Bool {
        isCompletionistComplete(mode: mode, weaponId: weaponId, step: 2)
            && harmonicBreakCount(mode: mode) >= harmonicBreaksNeeded(mode: mode)
    }

    func finalCamoCount(mode: String) -> Int {
        guard harmonicBreakCount(mode: mode) >= harmonicBreaksNeeded(mode: mode) else { return 0 }
        return harmonicBreakCount(mode: mode)
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

    private var allWeapons: [WeaponEntry] { catalog?.categories.flatMap(\.weapons) ?? [] }

    // MARK: - Where a weapon is on its track (filters)

    enum WeaponStage { case military, special, completionist, finished }

    /// The part of the track this weapon is working through in this mode.
    func stage(mode: String, weaponId: Int) -> WeaponStage {
        if hasFinalCamo(mode: mode, weaponId: weaponId) { return .finished }
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
        return (0..<Self.completionistStepCount).contains { step in
            !isCompletionistComplete(mode: mode, weaponId: weaponId, step: step)
                && isCompletionistAvailable(mode: mode, weaponId: weaponId, step: step)
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

    // MARK: - Mastery (per mode, not per weapon)
    //
    // Each mode's trio (Mercurial Drift → Polyatomic Reforged → Orion
    // Reforged in Multiplayer, Parallax → Damascus Reforged → Empyros in
    // Warzone, Chiral → Ripple Tide → Helio in DMZ) unlocks one tier at a
    // time as more weapons earn the mode's final Completionist camo. The
    // counts come from the mode file; until they're published, a third, two
    // thirds and all of the launch roster.

    func masteryWeaponsNeeded(mode: String, tier: Int) -> Int {
        let tiers = AppMode(rawValue: mode)?.masteryCamos
        let configured = [tiers?.tier1, tiers?.tier2, tiers?.tier3][max(0, min(tier, 3) - 1)]?.weaponsNeeded
        let roster = max(1, min(totalWeaponCount, baseWeaponCount))
        return configured ?? max(1, Int((Double(roster) * Double(tier) / 3).rounded(.up)))
    }

    func masteryProgress(mode: String, tier: Int) -> (done: Int, total: Int) {
        let needed = masteryWeaponsNeeded(mode: mode, tier: tier)
        return (min(finalCamoCount(mode: mode), needed), needed)
    }

    func isMasteryAchieved(mode: String, tier: Int) -> Bool {
        guard tier <= 1 || isMasteryAchieved(mode: mode, tier: tier - 1) else { return false }
        let progress = masteryProgress(mode: mode, tier: tier)
        return progress.done >= progress.total
    }

    /// The final camo on literally every weapon that currently exists (DLC
    /// included) — the "100%+" flex milestone past the third Mastery tier.
    func fullRosterFinalProgress(mode: String) -> (done: Int, total: Int) {
        (finalCamoCount(mode: mode), totalWeaponCount)
    }

    func is100PlusAchieved(mode: String) -> Bool {
        let progress = fullRosterFinalProgress(mode: mode)
        return progress.total > 0 && progress.done >= progress.total
    }

    /// What a Completionist change can newly unlock, taken before it.
    struct CompletionistSnapshot {
        let steps: [Bool]
        let finalCamoCount: Int
        let mastery: [Bool]
        let is100Plus: Bool
    }

    func completionistSnapshot(mode: String, weaponId: Int) -> CompletionistSnapshot {
        CompletionistSnapshot(
            steps: (0..<Self.completionistStepCount).map { isCompletionistComplete(mode: mode, weaponId: weaponId, step: $0) },
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
            total += leaves.count + Self.completionistStepCount + 1
            done += leaves.filter { isCamoComplete(mode: mode, weaponId: weapon.weaponId, camo: $0) }.count
            done += (0..<Self.completionistStepCount).filter { isCompletionistComplete(mode: mode, weaponId: weapon.weaponId, step: $0) }.count
            if hasFinalCamo(mode: mode, weaponId: weapon.weaponId) { done += 1 }
        }
        guard total > 0 else { return 0 }
        return Double(done) / Double(total)
    }

    // MARK: - Pinned weapon (quick-access card at the top of each mode tab)

    func pin(weaponId: Int) {
        pinnedWeaponId = weaponId
        defaults.set(weaponId, forKey: pinnedWeaponKey)
    }

    func unpin() {
        pinnedWeaponId = nil
        defaults.removeObject(forKey: pinnedWeaponKey)
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

    private func leafItems(_ item: ChallengeItem) -> [ChallengeItem] {
        item.isLeaf ? [item] : item.children.flatMap(leafItems)
    }

    // MARK: - Persistence

    private func camoKey(_ mode: String, _ weaponId: Int, _ camoId: Int) -> String {
        "camo|\(mode)|\(weaponId)|\(camoId)"
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
    }
}

private struct ProgressStore: Codable {
    var weaponLevels: [Int: Int]
    /// Optional so a save from before Weapon Prestige existed still decodes.
    var weaponPrestige: [Int: Int]?
    var amounts: [String: Int]
    var completed: [String]
}
