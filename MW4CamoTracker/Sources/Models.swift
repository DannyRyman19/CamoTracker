import Foundation

// MARK: - Weapon catalog (shared across every mode)

/// The one place a weapon's identity lives — name, image, category, max level.
/// Multiplayer, Warzone, and DMZ all reference these by `weaponId` instead of
/// re-declaring the weapon, so leveling a gun up means the same thing everywhere.
struct WeaponCatalog: Codable {
    let version: String
    let categories: [WeaponCategory]
}

struct WeaponCategory: Codable, Identifiable {
    let categoryId: Int
    let nameKey: String
    var weapons: [WeaponEntry]
    var id: Int { categoryId }
}

struct WeaponEntry: Codable, Identifiable {
    let weaponId: Int
    let nameKey: String
    let imageRef: String?
    let maxLevel: Int
    let unlockRequirementKey: String?
    var id: Int { weaponId }
}

// MARK: - Per-mode data (multiplayer.json / warzone.json / dmz.json)

/// A mode contributes two independent things:
/// - `weaponCamos`: that mode's camo challenge tree for each weapon it covers,
///   looked up by `weaponId` against the shared catalog above.
/// - `objectives`: mode-exclusive, non-weapon content (DMZ's Hajin extraction
///   objectives) that has no equivalent in other modes.
/// Multiplayer/Warzone currently only populate `weaponCamos`; DMZ can use either
/// or both, depending on whether it ends up with its own weapon-camo track.
struct ModeFile: Codable {
    let version: String
    let mode: String
    var weaponCamos: [WeaponCamoEntry]
    var objectives: [Category]
}

struct WeaponCamoEntry: Codable, Identifiable {
    let weaponId: Int
    var camos: [ChallengeItem]
    var id: Int { weaponId }
}

struct Category: Codable, Identifiable {
    let categoryId: Int
    let nameKey: String
    var items: [ChallengeItem]
    var id: Int { categoryId }
}

/// A camo tier or a DMZ objective sub-tier — same node either way.
struct ChallengeItem: Codable, Identifiable {
    let itemId: Int
    let nameKey: String
    let imageRef: String?
    let tier: Int?
    let requirement: Requirement?
    var children: [ChallengeItem]
    var id: Int { itemId }

    var isLeaf: Bool { children.isEmpty }
}

struct Requirement: Codable {
    let amount: Int
    let unit: String
    let descriptionKey: String
}
