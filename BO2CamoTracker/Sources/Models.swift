import Foundation

// MARK: - Camo tracker models

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
        case "SMGs": return "bolt.fill"
        case "LMGs": return "flame.fill"
        case "Shotguns": return "burst.fill"
        case "Sniper Rifles": return "target"
        case "Pistols": return "smallcircle.filled.circle"
        case "Launchers": return "tornado"
        case "Specials": return "scissors"
        default: return "star.fill"
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
}

struct MPChallenge: Codable, Identifiable {
    var id: Int { ChallengeID }
    let ChallengeID: Int
    let ChallengeName: String
    let ChallengeDescription: String
    let AmountRequired: Int
    var CurrentAmount: Int
    var IsComplete: Bool

    var displayDescription: String {
        ChallengeDescription.replacingOccurrences(of: "{0}", with: "\(AmountRequired)")
    }
    var progress: Double {
        guard AmountRequired > 0 else { return 0 }
        return min(Double(CurrentAmount) / Double(AmountRequired), 1.0)
    }
}
