import Foundation

// MARK: - Camo models

struct WeaponCategory: Codable, Identifiable {
    var id: Int { WeaponCategoryID }
    let WeaponCategoryID: Int
    let WeaponCategoryName: String
    var Weapons: [Weapon]

    var goldCount: Int { Weapons.filter(\.hasGold).count }
    var hasDiamond: Bool { Weapons.allSatisfy(\.hasGold) }
    var totalChallenges: Int { Weapons.reduce(0) { $0 + $1.Camos.count } }
    var completedChallenges: Int { Weapons.reduce(0) { $0 + $1.completedChallenges } }
    var overallProgress: Double {
        guard totalChallenges > 0 else { return 0 }
        return Double(completedChallenges) / Double(totalChallenges)
    }

    var categoryIcon: String {
        switch WeaponCategoryName {
        case "Assault Rifles": return "scope"
        case "SMGs":           return "bolt.fill"
        case "LMGs":           return "flame.fill"
        case "Shotguns":       return "burst.fill"
        case "Sniper Rifles":  return "target"
        case "Pistols":        return "smallcircle.filled.circle"
        case "Launchers":      return "tornado"
        case "Specials":       return "scissors"
        default:               return "star.fill"
        }
    }
}

struct Weapon: Codable, Identifiable {
    var id: Int { WeaponID }
    let WeaponID: Int
    let WeaponName: String
    let WeaponImageURL: String
    let UnlockRequirement: String
    var Camos: [Camo]
    var MasteryCamos: [MasteryCamo]

    var completedChallenges: Int { Camos.filter(\.IsChallengeComplete).count }
    var totalChallenges: Int { Camos.count }
    var progress: Double {
        guard totalChallenges > 0 else { return 0 }
        return Double(completedChallenges) / Double(totalChallenges)
    }
    var hasGold: Bool { Camos.allSatisfy(\.IsChallengeComplete) }
}

struct Camo: Codable, Identifiable {
    var id: Int { CamoID }
    let CamoID: Int
    let CamoName: String
    let CamoImageURL: String
    let CategoryRequirement: String
    let AmountRequired: Int
    var CurrentAmount: Int
    var IsChallengeComplete: Bool

    var displayRequirement: String {
        CategoryRequirement.replacingOccurrences(of: "{0}", with: "\(AmountRequired)")
    }
    var progress: Double {
        guard AmountRequired > 0 else { return 0 }
        return min(Double(CurrentAmount) / Double(AmountRequired), 1.0)
    }
}

struct MasteryCamo: Codable, Identifiable {
    var id: Int { CamoID }
    let CamoID: Int
    let CamoName: String
    let CamoImageURL: String
    let CategoryRequirement: String
    let AmountRequired: Int
    var CurrentAmount: Int
    var IsChallengeComplete: Bool
}

// MARK: - Multiplayer challenge models

struct ChallengeCategory: Codable, Identifiable {
    var id: Int { CategoryID }
    let CategoryID: Int
    let CategoryName: String
    let CategoryIcon: String
    var Challenges: [MPChallenge]

    var completedCount: Int { Challenges.filter(\.IsComplete).count }
    var totalCount: Int { Challenges.count }
    var progress: Double {
        guard totalCount > 0 else { return 0 }
        return Double(completedCount) / Double(totalCount)
    }
    var isComplete: Bool { Challenges.allSatisfy(\.IsComplete) }

    /// Groups challenges by SeriesName for tiered display.
    /// Non-tiered challenges are returned as single-element groups.
    var groupedChallenges: [[MPChallenge]] {
        var result: [[MPChallenge]] = []
        var seen: [String: Int] = [:]
        for challenge in Challenges {
            if let series = challenge.SeriesName {
                if let idx = seen[series] {
                    result[idx].append(challenge)
                } else {
                    seen[series] = result.count
                    result.append([challenge])
                }
            } else {
                result.append([challenge])
            }
        }
        return result
    }
}

struct MPChallenge: Codable, Identifiable {
    var id: Int { ChallengeID }
    let ChallengeID: Int
    let ChallengeName: String
    let ChallengeDescription: String
    let AmountRequired: Int
    var CurrentAmount: Int
    var IsComplete: Bool
    /// Non-nil for tiered challenges; 1 = tier I, 2 = tier II, etc.
    let Tier: Int?
    /// Challenges sharing a SeriesName are displayed as a collapsible group.
    let SeriesName: String?

    var displayDescription: String {
        ChallengeDescription.replacingOccurrences(of: "{0}", with: "\(AmountRequired)")
    }
    var progress: Double {
        guard AmountRequired > 0 else { return 0 }
        return min(Double(CurrentAmount) / Double(AmountRequired), 1.0)
    }
    var tierLabel: String? {
        guard let t = Tier else { return nil }
        let numerals = ["I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X"]
        return t >= 1 && t <= numerals.count ? numerals[t - 1] : "\(t)"
    }
}

// MARK: - Reticle models

struct ReticleOptic: Codable, Identifiable {
    var id: Int { OpticID }
    let OpticID: Int
    let OpticName: String
    let OpticDescription: String
    let UnlockDescription: String
    let ImageURL: String?
    var CurrentAmount: Int
    var Reticles: [ReticleChallenge]

    var unlockedCount: Int { Reticles.filter(\.IsUnlocked).count }
    var totalCount: Int { Reticles.count }
    var isComplete: Bool { Reticles.allSatisfy(\.IsUnlocked) }
    var progress: Double {
        guard let max = Reticles.last?.AmountRequired, max > 0 else { return 0 }
        return min(Double(CurrentAmount) / Double(max), 1.0)
    }

    /// Sync IsUnlocked on each reticle from CurrentAmount.
    mutating func syncUnlocked() {
        for i in Reticles.indices {
            Reticles[i].IsUnlocked = CurrentAmount >= Reticles[i].AmountRequired
        }
    }
}

struct ReticleChallenge: Codable, Identifiable {
    var id: Int { ReticleID }
    let ReticleID: Int
    let ReticleName: String
    let AmountRequired: Int
    let ImageURL: String?
    var IsUnlocked: Bool
}
