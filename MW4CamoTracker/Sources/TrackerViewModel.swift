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

    /// Whether every weapon in a category is Gold, in this mode — "Diamond."
    func categoryIsDiamond(_ category: WeaponCategory, mode: String) -> Bool {
        !category.weapons.isEmpty && category.weapons.allSatisfy { allCamosComplete(weaponId: $0.weaponId, mode: mode) }
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
