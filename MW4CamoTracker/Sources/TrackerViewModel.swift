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

    /// The one weapon pinned for quick access at the top of every mode tab —
    /// global like weapon level, not per-mode, since you pin a weapon, not a
    /// mode-specific track.
    @Published private(set) var pinnedWeaponId: Int?
    private let pinnedWeaponKey = "mw4_pinned_weapon_v1"

    private let dataService: DataService

    /// Weapon level is the one thing genuinely global: keyed by `weaponId` alone,
    /// so it reads the same from the Multiplayer tab or the DMZ tab.
    private var weaponLevels: [Int: Int] = [:]

    /// Camo and objective completion, keyed by mode — a camo track (or a DMZ
    /// objective) can legitimately differ per mode even for the same weapon.
    private var amounts: [String: Int] = [:]
    private var completed: Set<String> = []

    private let storeKey = "mw4_progress_v2"

    init(dataService: DataService = DataService()) {
        self.dataService = dataService
        loadProgress()
        catalog = dataService.loadCachedCatalog() ?? dataService.loadSeedCatalog()
        for mode in ["multiplayer", "warzone", "dmz"] {
            modes[mode] = dataService.loadCached(mode: mode) ?? dataService.loadSeed(mode: mode)
        }
        if UserDefaults.standard.object(forKey: pinnedWeaponKey) != nil {
            pinnedWeaponId = UserDefaults.standard.integer(forKey: pinnedWeaponKey)
        }
    }

    /// Checks the CDN manifest and pulls only the catalog/mode files whose version changed.
    func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let result = try await dataService.refreshIfNeeded(
                knownCatalogVersion: catalog?.version,
                knownModeVersions: modes.mapValues { $0.version }
            )
            if let newCatalog = result.catalog { catalog = newCatalog }
            for (mode, file) in result.modes { modes[mode] = file }
            refreshError = nil
        } catch {
            refreshError = error.localizedDescription
        }
    }

    // MARK: - Weapon level (global — same value in every mode)

    func level(for weaponId: Int) -> Int {
        weaponLevels[weaponId] ?? 0
    }

    func setLevel(_ level: Int, for weapon: WeaponEntry) {
        weaponLevels[weapon.weaponId] = max(0, min(level, weapon.maxLevel))
        saveProgress()
        objectWillChange.send()
    }

    // MARK: - Camo challenges (per mode, per weapon)

    /// That mode's camo tree for a weapon — empty if the mode doesn't cover it
    /// (e.g. DMZ before it has its own weapon-camo track).
    func camos(weaponId: Int, mode: String) -> [ChallengeItem] {
        modes[mode]?.weaponCamos.first { $0.weaponId == weaponId }?.camos ?? []
    }

    func camoAmount(mode: String, weaponId: Int, camo: ChallengeItem) -> Int {
        amounts[camoKey(mode, weaponId, camo.itemId)] ?? 0
    }

    func isCamoComplete(mode: String, weaponId: Int, camo: ChallengeItem) -> Bool {
        let k = camoKey(mode, weaponId, camo.itemId)
        guard let req = camo.requirement else { return completed.contains(k) }
        return (amounts[k] ?? 0) >= req.amount
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

    /// Whether this camo tier is open to progress yet. Mirrors the real
    /// family's own cascading unlock chain — your BO7 Camo Tracker's
    /// `ProgressionService.isCamoAvailable` gates each tier on the one before
    /// it (first tier always open; every tier after requires its predecessor
    /// complete). This app didn't enforce that at all before: any tier could
    /// be toggled in any order, which doesn't match how camo grinding
    /// actually works in-game.
    func isCamoAvailable(mode: String, weaponId: Int, camo: ChallengeItem) -> Bool {
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

    func totalGoldWeaponCount(mode: String) -> Int {
        catalog?.categories.reduce(0) { $0 + goldWeaponCount(in: $1, mode: mode) } ?? 0
    }

    /// Whether this mode has its own per-weapon camo track (Multiplayer,
    /// Warzone) or is objectives-only (DMZ, which has no weapon Mastery
    /// chain of its own — see the DMZ branches below).
    func modeHasWeaponTrack(_ mode: String) -> Bool {
        !(modes[mode]?.weaponCamos.isEmpty ?? true)
    }

    // MARK: - Weapon Mastery — the real BO7 Camo Tracker shape
    //
    // Base track (Slate…Gold, above) is per weapon with no aggregate gate.
    // Past Gold, MW4's own Mercurial Drift → Polyatomic Reforged → Orion
    // Reforged (per mode) work the way BO7's Gold → Diamond → Tempest →
    // Singularity actually does:
    //   tier1: per weapon, opens once *that weapon's* Gold is done.
    //   tier2: per weapon, but only opens once *every weapon in that
    //          weapon's category* has earned tier1 — a category-wide gate.
    //   tier3: not per weapon at all — the single mode-wide capstone that
    //          unlocks once *every weapon in every category* has earned
    //          tier2. That's the whole requirement, no leveling condition.
    // DMZ has no weapon-camo track to hang any of this on, so its three
    // named camos fall back to counting fully-extracted objective
    // categories instead — the real content that track actually has.

    private func weaponMasteryKey(_ mode: String, _ weaponId: Int, _ tier: Int) -> String {
        "wmastery|\(mode)|\(weaponId)|\(tier)"
    }

    private func masteryRequirement(mode: String, tier: Int) -> MasteryRequirement? {
        guard let camos = AppMode(rawValue: mode)?.masteryCamos else { return nil }
        return tier == 1 ? camos.tier1.requirement : camos.tier2.requirement
    }

    /// This weapon's progress on its own tier1 or tier2 Mastery challenge.
    func weaponMasteryAmount(mode: String, weaponId: Int, tier: Int) -> Int {
        amounts[weaponMasteryKey(mode, weaponId, tier)] ?? 0
    }

    func setWeaponMasteryAmount(mode: String, weaponId: Int, tier: Int, amount newAmount: Int) {
        guard let requirement = masteryRequirement(mode: mode, tier: tier) else { return }
        let wasComplete = isWeaponMasteryComplete(mode: mode, weaponId: weaponId, tier: tier)
        let wasTier3Achieved = isMasteryTier3Achieved(mode: mode)
        let was100PlusAchieved = is100PlusAchieved(mode: mode)
        amounts[weaponMasteryKey(mode, weaponId, tier)] = max(0, min(newAmount, requirement.amount))
        saveProgress()
        objectWillChange.send()
        checkWeaponMasteryMilestone(mode: mode, weaponId: weaponId, tier: tier, wasComplete: wasComplete, wasTier3Achieved: wasTier3Achieved, was100PlusAchieved: was100PlusAchieved)
    }

    func isWeaponMasteryComplete(mode: String, weaponId: Int, tier: Int) -> Bool {
        guard let requirement = masteryRequirement(mode: mode, tier: tier) else { return false }
        return weaponMasteryAmount(mode: mode, weaponId: weaponId, tier: tier) >= requirement.amount
    }

    /// Tier1 opens once this weapon's own base track (Slate…Gold) is done.
    func isWeaponMasteryTier1Available(weaponId: Int, mode: String) -> Bool {
        allCamosComplete(weaponId: weaponId, mode: mode)
    }

    /// Tier2 opens on this weapon only once *every weapon in its category*
    /// has earned tier1 — the category-wide gate the old design was missing.
    func isWeaponMasteryTier2Available(weaponId: Int, mode: String) -> Bool {
        guard let category = category(containingWeaponId: weaponId) else { return false }
        return categoryHasMasteryTier1(category, mode: mode)
    }

    /// Every weapon in this category has earned tier1.
    func categoryHasMasteryTier1(_ category: WeaponCategory, mode: String) -> Bool {
        !category.weapons.isEmpty && category.weapons.allSatisfy { isWeaponMasteryComplete(mode: mode, weaponId: $0.weaponId, tier: 1) }
    }

    /// How many weapons in a category have earned tier1 already.
    func categoryMasteryTier1Count(_ category: WeaponCategory, mode: String) -> Int {
        category.weapons.filter { isWeaponMasteryComplete(mode: mode, weaponId: $0.weaponId, tier: 1) }.count
    }

    /// Every weapon in this category has earned tier2 too — one step higher
    /// than `categoryHasMasteryTier1`. A category can hit this even though
    /// tier2 itself is gated mode-wide by tier1, since the gate is "every
    /// weapon in the mode," which this category being done doesn't block.
    func categoryHasMasteryTier2(_ category: WeaponCategory, mode: String) -> Bool {
        !category.weapons.isEmpty && category.weapons.allSatisfy { isWeaponMasteryComplete(mode: mode, weaponId: $0.weaponId, tier: 2) }
    }

    /// How many weapons in a category have earned tier2 already.
    func categoryMasteryTier2Count(_ category: WeaponCategory, mode: String) -> Int {
        category.weapons.filter { isWeaponMasteryComplete(mode: mode, weaponId: $0.weaponId, tier: 2) }.count
    }

    /// Weapons (account-wide) that have earned tier1, out of the *launch*
    /// roster size — not the live (DLC-inclusive) weapon count. Real CoD
    /// trackers gate the mode-wide Mastery capstone on finishing tier2 on as
    /// many weapons as shipped at launch, not literally every weapon that
    /// will ever exist, so a completed DLC weapon can stand in for a launch
    /// weapon left unfinished. `done` is capped at that same total so a
    /// roster with more tier1-complete weapons than the threshold (once DLC
    /// weapons are also finished) still reads as "fully done," not over 100%.
    func masteryTier1Progress(mode: String) -> (done: Int, total: Int) {
        guard modeHasWeaponTrack(mode) else {
            let categories = modes[mode]?.objectives ?? []
            let done = categories.filter { !$0.items.isEmpty && objectiveProgressFraction(of: $0, mode: mode) >= 1 }.count
            return (done, categories.count)
        }
        let done = catalog?.categories.reduce(0) { $0 + categoryMasteryTier1Count($1, mode: mode) } ?? 0
        let total = min(totalWeaponCount, baseWeaponCount)
        return (min(done, total), total)
    }

    /// Same launch-roster-sized gate as `masteryTier1Progress`, for tier2 —
    /// this is what `isMasteryTier3Achieved` actually checks against.
    func masteryTier2Progress(mode: String) -> (done: Int, total: Int) {
        guard modeHasWeaponTrack(mode) else {
            // DMZ has no per-weapon track to gate tier2 on; fall back to the
            // same all-objective-categories-extracted signal as tier1's gate.
            let progress = masteryTier1Progress(mode: mode)
            return progress.total > 0 && progress.done == progress.total ? (1, 1) : (0, 1)
        }
        let total = min(totalWeaponCount, baseWeaponCount)
        return (min(tier2CompleteCount(mode: mode), total), total)
    }

    private func tier2CompleteCount(mode: String) -> Int {
        catalog?.categories.reduce(0) { total, category in
            total + category.weapons.filter { isWeaponMasteryComplete(mode: mode, weaponId: $0.weaponId, tier: 2) }.count
        } ?? 0
    }

    /// Tier2 earned on literally every weapon that currently exists (DLC
    /// included), not just `baseWeaponCount` of them — the "100%+" flex
    /// milestone past the real tier3 capstone. With no DLC shipped yet this
    /// lands on the exact same number as `masteryTier2Progress`; it only
    /// diverges once the roster grows past the launch count.
    func fullRosterTier2Progress(mode: String) -> (done: Int, total: Int) {
        guard modeHasWeaponTrack(mode) else { return masteryTier2Progress(mode: mode) }
        return (tier2CompleteCount(mode: mode), totalWeaponCount)
    }

    func is100PlusAchieved(mode: String) -> Bool {
        let progress = fullRosterTier2Progress(mode: mode)
        return progress.total > 0 && progress.done >= progress.total
    }

    /// The mode-wide capstone (tier3, "Orion Reforged" etc.) — tier2 earned
    /// on `baseWeaponCount` weapons, that's the entire requirement, no
    /// separate leveling condition on top (an earlier version of this added
    /// "+ every weapon maxed," which was wrong: not something you actually
    /// specified, just my own assumption from a different game). Deliberately
    /// *not* "every weapon in the mode" — see `masteryTier2Progress` — so a
    /// DLC weapon someone's finished can stand in for a launch weapon they
    /// haven't.
    func isMasteryTier3Achieved(mode: String) -> Bool {
        let progress = masteryTier2Progress(mode: mode)
        return progress.total > 0 && progress.done == progress.total
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

    /// True completionist percentage toward the mode's final Mastery camo —
    /// every base camo leaf *and* every weapon's tier1/tier2 Mastery
    /// challenge, not just the base track `overallProgressFraction` counts.
    /// Computed fresh from the current catalog every call (nothing cached to
    /// a fixed total), so it automatically accounts for new weapons the
    /// moment a content update adds them — a completionist who's already
    /// hit 100% today sees the percentage move again once there's more to do.
    func trueCompletionFraction(mode: String) -> Double {
        guard modeHasWeaponTrack(mode), let categories = catalog?.categories, !categories.isEmpty else {
            let progress = masteryTier1Progress(mode: mode)
            return progress.total > 0 ? Double(progress.done) / Double(progress.total) : 0
        }
        var done = 0
        var total = 0
        for category in categories {
            for weapon in category.weapons {
                let leaves = camos(weaponId: weapon.weaponId, mode: mode).flatMap(leafItems)
                total += leaves.count + 2 // + tier1 slot + tier2 slot
                done += leaves.filter { isCamoComplete(mode: mode, weaponId: weapon.weaponId, camo: $0) }.count
                if isWeaponMasteryComplete(mode: mode, weaponId: weapon.weaponId, tier: 1) { done += 1 }
                if isWeaponMasteryComplete(mode: mode, weaponId: weapon.weaponId, tier: 2) { done += 1 }
            }
        }
        guard total > 0 else { return 0 }
        return Double(done) / Double(total)
    }

    // MARK: - Pinned weapon (quick-access card at the top of each mode tab)

    func pin(weaponId: Int) {
        pinnedWeaponId = weaponId
        UserDefaults.standard.set(weaponId, forKey: pinnedWeaponKey)
    }

    func unpin() {
        pinnedWeaponId = nil
        UserDefaults.standard.removeObject(forKey: pinnedWeaponKey)
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

    func objectiveAmount(mode: String, categoryId: Int, item: ChallengeItem) -> Int {
        amounts[objectiveKey(mode, categoryId, item.itemId)] ?? 0
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
        guard let data = UserDefaults.standard.data(forKey: storeKey),
              let store = try? JSONDecoder().decode(ProgressStore.self, from: data) else { return }
        weaponLevels = store.weaponLevels
        amounts = store.amounts
        completed = Set(store.completed)
    }

    private func saveProgress() {
        let store = ProgressStore(weaponLevels: weaponLevels, amounts: amounts, completed: Array(completed))
        if let data = try? JSONEncoder().encode(store) {
            UserDefaults.standard.set(data, forKey: storeKey)
        }
    }
}

private struct ProgressStore: Codable {
    var weaponLevels: [Int: Int]
    var amounts: [String: Int]
    var completed: [String]
}
