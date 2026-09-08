import Foundation

/// Inline per-language text shipped *in the network JSON itself*, not a key
/// into the app bundle. That distinction matters: a key would only resolve
/// once a new app build shipped a matching entry in Localizable.strings,
/// which defeats the point of fetching content over the air. A weapon added
/// mid-season carries its own name in every supported language right in the
/// JSON, so it displays correctly the moment the CDN file updates — no app
/// update required. Static app chrome (tab names, button labels) still uses
/// Localizable.strings, since that never needs to change without a build.
struct LocalizedText: Codable {
    let values: [String: String]

    /// A single-language value — for onboarding mockups and other in-app
    /// illustrative content that isn't real network data.
    init(_ value: String) {
        values = ["en": value]
    }

    init(from decoder: Decoder) throws {
        values = try [String: String](from: decoder)
    }

    func encode(to encoder: Encoder) throws {
        try values.encode(to: encoder)
    }

    /// Resolves to the user's preferred language, falling back to English,
    /// then to whatever translation exists — so a missing language never
    /// surfaces blank text or a raw key to the player.
    func resolved() -> String {
        for identifier in Locale.preferredLanguages {
            if let code = Locale(identifier: identifier).language.languageCode?.identifier,
               let value = values[code] {
                return value
            }
        }
        return values["en"] ?? values.values.first ?? ""
    }
}

// MARK: - Weapon catalog (shared across every mode)

/// The one place a weapon's identity lives — name, image, category, max level.
/// Multiplayer, Warzone, and DMZ all reference these by `weaponId` instead of
/// re-declaring the weapon, so leveling a gun up means the same thing everywhere.
struct WeaponCatalog: Codable {
    let version: String
    /// The weapon roster size at launch, frozen forever after — not
    /// `categories.flatMap(\.weapons).count`, which keeps growing as DLC
    /// weapons ship. The mode-wide Mastery tier3 capstone needs this fixed
    /// number: real CoD trackers gate that capstone on completing Mastery
    /// tier2 on as many weapons as shipped at launch, not literally every
    /// weapon that will ever exist, so a player can finish a new DLC weapon
    /// in place of a base one they skipped. Optional (not decoded from an
    /// older cached catalog that predates this field) — `TrackerViewModel`
    /// falls back to the live weapon count when absent.
    let baseWeaponCount: Int?
    let categories: [WeaponCategory]
}

struct WeaponCategory: Codable, Identifiable {
    let categoryId: Int
    let name: LocalizedText
    var weapons: [WeaponEntry]
    var id: Int { categoryId }
}

struct WeaponEntry: Codable, Identifiable {
    let weaponId: Int
    let name: LocalizedText
    let imageURL: String?
    let maxLevel: Int
    let unlockRequirement: LocalizedText?
    var id: Int { weaponId }

    /// The level this weapon unlocks at, pulled out of `unlockRequirement`'s
    /// resolved sentence ("Unlock at level 9." / "Freischaltung auf Stufe 9."
    /// / …) instead of a second structured field — every language keeps the
    /// same plain digit substring, so one locale-agnostic regex covers all of
    /// them without touching the network JSON's shape. `nil` for a weapon
    /// that's unlocked by default (no digits in that sentence at all).
    var unlockLevel: Int? {
        guard let text = unlockRequirement?.resolved(),
              let range = text.range(of: #"\d+"#, options: .regularExpression) else { return nil }
        return Int(text[range])
    }
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
    let name: LocalizedText
    var items: [ChallengeItem]
    var id: Int { categoryId }
}

/// A camo tier or a DMZ objective sub-tier — same node either way.
struct ChallengeItem: Codable, Identifiable {
    let itemId: Int
    let name: LocalizedText
    let imageURL: String?
    let tier: Int?
    let requirement: Requirement?
    var children: [ChallengeItem]
    var id: Int { itemId }

    var isLeaf: Bool { children.isEmpty }
}

struct Requirement: Codable {
    let amount: Int
    let unit: String
    let description: LocalizedText
}
