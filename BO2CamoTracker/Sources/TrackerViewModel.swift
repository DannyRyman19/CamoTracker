import Foundation
import Observation

@Observable
final class TrackerViewModel {
    var categories: [WeaponCategory] = []

    private let storageKey = "bo2_progress_v1"

    init() {
        loadWeaponData()
        mergeStoredProgress()
    }

    // MARK: - Data Loading

    private func loadWeaponData() {
        guard let url = Bundle.main.url(forResource: "BO2_Multiplayer_Camos", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([WeaponCategory].self, from: data) else {
            return
        }
        categories = decoded
    }

    private func mergeStoredProgress() {
        guard let saved = UserDefaults.standard.data(forKey: storageKey),
              let progress = try? JSONDecoder().decode([CategoryProgress].self, from: saved) else { return }

        for catProgress in progress {
            guard let ci = categories.firstIndex(where: { $0.WeaponCategoryID == catProgress.categoryID }) else { continue }
            for weapProgress in catProgress.weapons {
                guard let wi = categories[ci].Weapons.firstIndex(where: { $0.WeaponID == weapProgress.weaponID }) else { continue }
                for camoProgress in weapProgress.camos {
                    guard let ki = categories[ci].Weapons[wi].Camos.firstIndex(where: { $0.CamoID == camoProgress.camoID }) else { continue }
                    categories[ci].Weapons[wi].Camos[ki].CurrentAmount = camoProgress.currentAmount
                    categories[ci].Weapons[wi].Camos[ki].IsChallengeComplete = camoProgress.isComplete
                }
            }
        }
    }

    // MARK: - Mutations

    func toggleChallenge(categoryIndex ci: Int, weaponIndex wi: Int, camoIndex ki: Int) {
        let was = categories[ci].Weapons[wi].Camos[ki].IsChallengeComplete
        categories[ci].Weapons[wi].Camos[ki].IsChallengeComplete = !was
        categories[ci].Weapons[wi].Camos[ki].CurrentAmount = was
            ? 0
            : categories[ci].Weapons[wi].Camos[ki].AmountRequired
        saveProgress()
    }

    func setAmount(categoryIndex ci: Int, weaponIndex wi: Int, camoIndex ki: Int, amount: Int) {
        let required = categories[ci].Weapons[wi].Camos[ki].AmountRequired
        let clamped = max(0, min(amount, required))
        categories[ci].Weapons[wi].Camos[ki].CurrentAmount = clamped
        categories[ci].Weapons[wi].Camos[ki].IsChallengeComplete = clamped >= required
        saveProgress()
    }

    // MARK: - Persistence

    private func saveProgress() {
        let progress = categories.map { cat in
            CategoryProgress(
                categoryID: cat.WeaponCategoryID,
                weapons: cat.Weapons.map { weap in
                    WeaponProgress(
                        weaponID: weap.WeaponID,
                        camos: weap.Camos.map { camo in
                            CamoProgress(camoID: camo.CamoID, currentAmount: camo.CurrentAmount, isComplete: camo.IsChallengeComplete)
                        }
                    )
                }
            )
        }
        if let data = try? JSONEncoder().encode(progress) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    // MARK: - Stats

    var totalWeapons: Int { categories.reduce(0) { $0 + $1.Weapons.count } }
    var goldWeapons: Int { categories.reduce(0) { $0 + $1.goldCount } }
    var diamondCategories: Int { categories.filter(\.hasDiamond).count }
    var totalCategories: Int { categories.count }
    var overallProgress: Double {
        let total = categories.reduce(0) { $0 + $1.totalChallenges }
        let done = categories.reduce(0) { $0 + $1.completedChallenges }
        guard total > 0 else { return 0 }
        return Double(done) / Double(total)
    }
}

// MARK: - Compact persistence types

private struct CategoryProgress: Codable {
    let categoryID: Int
    var weapons: [WeaponProgress]
}
private struct WeaponProgress: Codable {
    let weaponID: Int
    var camos: [CamoProgress]
}
private struct CamoProgress: Codable {
    let camoID: Int
    var currentAmount: Int
    var isComplete: Bool
}
