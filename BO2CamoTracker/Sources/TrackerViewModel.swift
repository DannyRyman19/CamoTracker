import Foundation
import Observation

@Observable
final class TrackerViewModel {
    var categories: [WeaponCategory] = []
    var challengeCategories: [ChallengeCategory] = []
    var reticleOptics: [ReticleOptic] = []

    private let camoKey       = "bo2_camo_v2"
    private let challengeKey  = "bo2_challenge_v1"
    private let reticleKey    = "bo2_reticle_v1"

    init() {
        loadWeaponData();    mergeCamoProgress()
        loadChallengeData(); mergeChallengeProgress()
        loadReticleData();   mergeReticleProgress()
    }

    // MARK: - Load

    private func loadWeaponData() {
        categories = decode([WeaponCategory].self, resource: "BO2_Multiplayer_Camos") ?? []
    }
    private func loadChallengeData() {
        challengeCategories = decode([ChallengeCategory].self, resource: "BO2_Multiplayer_Challenges") ?? []
    }
    private func loadReticleData() {
        reticleOptics = decode([ReticleOptic].self, resource: "BO2_Reticles") ?? []
    }

    private func decode<T: Decodable>(_ type: T.Type, resource: String) -> T? {
        guard let url = Bundle.main.url(forResource: resource, withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    // MARK: - Merge stored progress

    private func mergeCamoProgress() {
        guard let stored = load([CamoStore].self, key: camoKey) else { return }
        let lookup = Dictionary(uniqueKeysWithValues: stored.map { ($0.key, $0) })
        for ci in categories.indices {
            for wi in categories[ci].Weapons.indices {
                for ki in categories[ci].Weapons[wi].Camos.indices {
                    if let s = lookup[camoKey(ci, wi, ki)] {
                        categories[ci].Weapons[wi].Camos[ki].CurrentAmount = s.amount
                        categories[ci].Weapons[wi].Camos[ki].IsChallengeComplete = s.done
                    }
                }
            }
        }
    }

    private func mergeChallengeProgress() {
        guard let stored = load([ChallengeStore].self, key: challengeKey) else { return }
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

    private func mergeReticleProgress() {
        guard let stored = load([ReticleStore].self, key: reticleKey) else { return }
        let lookup = Dictionary(uniqueKeysWithValues: stored.map { ($0.opticID, $0) })
        for i in reticleOptics.indices {
            if let s = lookup[reticleOptics[i].OpticID] {
                reticleOptics[i].CurrentAmount = s.amount
                reticleOptics[i].syncUnlocked()
            }
        }
    }

    // MARK: - Camo mutations

    func toggleCamo(categoryIndex ci: Int, weaponIndex wi: Int, camoIndex ki: Int) {
        let was = categories[ci].Weapons[wi].Camos[ki].IsChallengeComplete
        categories[ci].Weapons[wi].Camos[ki].IsChallengeComplete = !was
        categories[ci].Weapons[wi].Camos[ki].CurrentAmount = was ? 0 : categories[ci].Weapons[wi].Camos[ki].AmountRequired
        saveCamos()
    }

    func setCamoAmount(ci: Int, wi: Int, ki: Int, amount: Int) {
        let req = categories[ci].Weapons[wi].Camos[ki].AmountRequired
        categories[ci].Weapons[wi].Camos[ki].CurrentAmount = max(0, min(amount, req))
        categories[ci].Weapons[wi].Camos[ki].IsChallengeComplete = amount >= req
        saveCamos()
    }

    // MARK: - Challenge mutations

    func toggleChallenge(categoryIndex ci: Int, challengeIndex ji: Int) {
        let was = challengeCategories[ci].Challenges[ji].IsComplete
        challengeCategories[ci].Challenges[ji].IsComplete = !was
        challengeCategories[ci].Challenges[ji].CurrentAmount = was ? 0 : challengeCategories[ci].Challenges[ji].AmountRequired
        saveChallenges()
    }

    func setChallengeAmount(ci: Int, ji: Int, amount: Int) {
        let req = challengeCategories[ci].Challenges[ji].AmountRequired
        challengeCategories[ci].Challenges[ji].CurrentAmount = max(0, min(amount, req))
        challengeCategories[ci].Challenges[ji].IsComplete = amount >= req
        saveChallenges()
    }

    // MARK: - Reticle mutations

    func setReticleAmount(opticIndex i: Int, amount: Int) {
        let max = reticleOptics[i].Reticles.last?.AmountRequired ?? 0
        reticleOptics[i].CurrentAmount = Swift.max(0, Swift.min(amount, max))
        reticleOptics[i].syncUnlocked()
        saveReticles()
    }

    func unlockAllReticles(opticIndex i: Int) {
        guard let max = reticleOptics[i].Reticles.last?.AmountRequired else { return }
        reticleOptics[i].CurrentAmount = max
        reticleOptics[i].syncUnlocked()
        saveReticles()
    }

    // MARK: - Persistence helpers

    private func camoKey(_ ci: Int, _ wi: Int, _ ki: Int) -> String {
        "\(categories[ci].WeaponCategoryID)-\(categories[ci].Weapons[wi].WeaponID)-\(ki)"
    }

    private func saveCamos() {
        var records: [CamoStore] = []
        for ci in categories.indices {
            for wi in categories[ci].Weapons.indices {
                for ki in categories[ci].Weapons[wi].Camos.indices {
                    let c = categories[ci].Weapons[wi].Camos[ki]
                    if c.CurrentAmount > 0 || c.IsChallengeComplete {
                        records.append(CamoStore(key: camoKey(ci, wi, ki), amount: c.CurrentAmount, done: c.IsChallengeComplete))
                    }
                }
            }
        }
        save(records, key: camoKey)
    }

    private func saveChallenges() {
        var records: [ChallengeStore] = []
        for ci in challengeCategories.indices {
            for ji in challengeCategories[ci].Challenges.indices {
                let ch = challengeCategories[ci].Challenges[ji]
                if ch.CurrentAmount > 0 || ch.IsComplete {
                    records.append(ChallengeStore(catID: challengeCategories[ci].CategoryID, chalID: ch.ChallengeID, amount: ch.CurrentAmount, done: ch.IsComplete))
                }
            }
        }
        save(records, key: challengeKey)
    }

    private func saveReticles() {
        let records = reticleOptics.filter { $0.CurrentAmount > 0 }
            .map { ReticleStore(opticID: $0.OpticID, amount: $0.CurrentAmount) }
        save(records, key: reticleKey)
    }

    private func save<T: Encodable>(_ value: T, key: String) {
        if let data = try? JSONEncoder().encode(value) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
    private func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    // MARK: - Stats

    var totalWeapons: Int { categories.reduce(0) { $0 + $1.Weapons.count } }
    var goldWeapons: Int { categories.reduce(0) { $0 + $1.goldCount } }
    var diamondCategories: Int { categories.filter(\.hasDiamond).count }
    var totalCategories: Int { categories.count }

    var overallCamoProgress: Double {
        let total = categories.reduce(0) { $0 + $1.totalChallenges }
        let done  = categories.reduce(0) { $0 + $1.completedChallenges }
        guard total > 0 else { return 0 }
        return Double(done) / Double(total)
    }

    var totalChallenges: Int { challengeCategories.reduce(0) { $0 + $1.totalCount } }
    var completedChallenges: Int { challengeCategories.reduce(0) { $0 + $1.completedCount } }
    var overallChallengeProgress: Double {
        guard totalChallenges > 0 else { return 0 }
        return Double(completedChallenges) / Double(totalChallenges)
    }

    var totalReticles: Int { reticleOptics.reduce(0) { $0 + $1.totalCount } }
    var unlockedReticles: Int { reticleOptics.reduce(0) { $0 + $1.unlockedCount } }
    var overallReticleProgress: Double {
        guard totalReticles > 0 else { return 0 }
        return Double(unlockedReticles) / Double(totalReticles)
    }
}

// MARK: - Compact persistence types

private struct CamoStore: Codable {
    let key: String; var amount: Int; var done: Bool
}
private struct ChallengeStore: Codable {
    let catID: Int; let chalID: Int; var amount: Int; var done: Bool
}
private struct ReticleStore: Codable {
    let opticID: Int; var amount: Int
}
