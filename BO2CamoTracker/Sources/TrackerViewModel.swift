import Foundation
import Observation

@Observable
final class TrackerViewModel {
    var categories: [WeaponCategory] = []
    var challengeCategories: [ChallengeCategory] = []

    private let camoStorageKey = "bo2_camo_progress_v2"
    private let challengeStorageKey = "bo2_challenge_progress_v1"

    init() {
        loadWeaponData()
        mergeCamoProgress()
        loadChallengeData()
        mergeChallengeProgress()
    }

    // MARK: - Weapon / Camo loading

    private func loadWeaponData() {
        guard let url = Bundle.main.url(forResource: "BO2_Multiplayer_Camos", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([WeaponCategory].self, from: data) else { return }
        categories = decoded
    }

    private func mergeCamoProgress() {
        guard let saved = UserDefaults.standard.data(forKey: camoStorageKey),
              let stored = try? JSONDecoder().decode([CamoProgressStore].self, from: saved) else { return }
        let lookup = Dictionary(uniqueKeysWithValues: stored.map { ($0.key, $0) })
        for ci in categories.indices {
            for wi in categories[ci].Weapons.indices {
                for ki in categories[ci].Weapons[wi].Camos.indices {
                    let key = progressKey(ci, wi, ki)
                    if let s = lookup[key] {
                        categories[ci].Weapons[wi].Camos[ki].CurrentAmount = s.amount
                        categories[ci].Weapons[wi].Camos[ki].IsChallengeComplete = s.done
                    }
                }
            }
        }
    }

    // MARK: - Challenge loading

    private func loadChallengeData() {
        guard let url = Bundle.main.url(forResource: "BO2_Multiplayer_Challenges", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([ChallengeCategory].self, from: data) else { return }
        challengeCategories = decoded
    }

    private func mergeChallengeProgress() {
        guard let saved = UserDefaults.standard.data(forKey: challengeStorageKey),
              let stored = try? JSONDecoder().decode([ChallengeProg].self, from: saved) else { return }
        let lookup = Dictionary(uniqueKeysWithValues: stored.map { ("\($0.catID)-\($0.chalID)", $0) })
        for ci in challengeCategories.indices {
            for ji in challengeCategories[ci].Challenges.indices {
                let key = "\(challengeCategories[ci].CategoryID)-\(challengeCategories[ci].Challenges[ji].ChallengeID)"
                if let s = lookup[key] {
                    challengeCategories[ci].Challenges[ji].CurrentAmount = s.amount
                    challengeCategories[ci].Challenges[ji].IsComplete = s.done
                }
            }
        }
    }

    // MARK: - Camo mutations

    func toggleCamo(categoryIndex ci: Int, weaponIndex wi: Int, camoIndex ki: Int) {
        let was = categories[ci].Weapons[wi].Camos[ki].IsChallengeComplete
        categories[ci].Weapons[wi].Camos[ki].IsChallengeComplete = !was
        categories[ci].Weapons[wi].Camos[ki].CurrentAmount = was ? 0 : categories[ci].Weapons[wi].Camos[ki].AmountRequired
        saveCamoProgress()
    }

    func setCamoAmount(categoryIndex ci: Int, weaponIndex wi: Int, camoIndex ki: Int, amount: Int) {
        let required = categories[ci].Weapons[wi].Camos[ki].AmountRequired
        let clamped = max(0, min(amount, required))
        categories[ci].Weapons[wi].Camos[ki].CurrentAmount = clamped
        categories[ci].Weapons[wi].Camos[ki].IsChallengeComplete = clamped >= required
        saveCamoProgress()
    }

    // MARK: - Challenge mutations

    func toggleChallenge(categoryIndex ci: Int, challengeIndex ji: Int) {
        let was = challengeCategories[ci].Challenges[ji].IsComplete
        challengeCategories[ci].Challenges[ji].IsComplete = !was
        challengeCategories[ci].Challenges[ji].CurrentAmount = was ? 0 : challengeCategories[ci].Challenges[ji].AmountRequired
        saveChallengeProgress()
    }

    func setChallengeAmount(categoryIndex ci: Int, challengeIndex ji: Int, amount: Int) {
        let required = challengeCategories[ci].Challenges[ji].AmountRequired
        let clamped = max(0, min(amount, required))
        challengeCategories[ci].Challenges[ji].CurrentAmount = clamped
        challengeCategories[ci].Challenges[ji].IsComplete = clamped >= required
        saveChallengeProgress()
    }

    // MARK: - Persistence

    private func progressKey(_ ci: Int, _ wi: Int, _ ki: Int) -> String {
        "\(categories[ci].WeaponCategoryID)-\(categories[ci].Weapons[wi].WeaponID)-\(ki)"
    }

    private func saveCamoProgress() {
        var records: [CamoProgressStore] = []
        for ci in categories.indices {
            for wi in categories[ci].Weapons.indices {
                for ki in categories[ci].Weapons[wi].Camos.indices {
                    let c = categories[ci].Weapons[wi].Camos[ki]
                    if c.CurrentAmount > 0 || c.IsChallengeComplete {
                        records.append(CamoProgressStore(key: progressKey(ci, wi, ki), amount: c.CurrentAmount, done: c.IsChallengeComplete))
                    }
                }
            }
        }
        if let data = try? JSONEncoder().encode(records) {
            UserDefaults.standard.set(data, forKey: camoStorageKey)
        }
    }

    private func saveChallengeProgress() {
        var records: [ChallengeProg] = []
        for ci in challengeCategories.indices {
            for ji in challengeCategories[ci].Challenges.indices {
                let ch = challengeCategories[ci].Challenges[ji]
                if ch.CurrentAmount > 0 || ch.IsComplete {
                    records.append(ChallengeProg(catID: challengeCategories[ci].CategoryID, chalID: ch.ChallengeID, amount: ch.CurrentAmount, done: ch.IsComplete))
                }
            }
        }
        if let data = try? JSONEncoder().encode(records) {
            UserDefaults.standard.set(data, forKey: challengeStorageKey)
        }
    }

    // MARK: - Stats

    var totalWeapons: Int { categories.reduce(0) { $0 + $1.Weapons.count } }
    var goldWeapons: Int { categories.reduce(0) { $0 + $1.goldCount } }
    var diamondCategories: Int { categories.filter(\.hasDiamond).count }
    var totalCategories: Int { categories.count }
    var overallCamoProgress: Double {
        let total = categories.reduce(0) { $0 + $1.totalChallenges }
        let done = categories.reduce(0) { $0 + $1.completedChallenges }
        guard total > 0 else { return 0 }
        return Double(done) / Double(total)
    }
    var totalChallenges: Int { challengeCategories.reduce(0) { $0 + $1.totalCount } }
    var completedChallenges: Int { challengeCategories.reduce(0) { $0 + $1.completedCount } }
    var overallChallengeProgress: Double {
        guard totalChallenges > 0 else { return 0 }
        return Double(completedChallenges) / Double(totalChallenges)
    }
}

// MARK: - Compact persistence types

private struct CamoProgressStore: Codable {
    let key: String
    var amount: Int
    var done: Bool
}
private struct ChallengeProg: Codable {
    let catID: Int
    let chalID: Int
    var amount: Int
    var done: Bool
}
