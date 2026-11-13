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
        for code in AppLanguage.preferred {
            if let value = values[code] { return value }
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
    /// Weapon Prestige, as the stages that come *after* a weapon's normal
    /// levels, in order — so its count is how many times a weapon can
    /// prestige. Kept in the network JSON so the count and each stage's
    /// level cap can change without an app update. Optional: no prestige
    /// at all when absent.
    let weaponPrestige: [PrestigeStage]?
    /// Camos earned by Weapon Prestige rather than by a mode's challenges,
    /// so they're the same in every mode. In order: each one ticks itself
    /// once the weapon reaches its stage and level. Optional: none when
    /// absent.
    let prestigeCamos: [PrestigeCamo]?
    let categories: [WeaponCategory]
}

/// A Weapon Prestige camo ("Pyroclast Terminus: reach Prestige Master
/// level 73" on the HAN 86). `stage` is which `weaponPrestige` stage it's
/// in, counting from 1; `nil` means the last one, so the data doesn't need
/// changing if stages are added before it. `level` is the level within that
/// stage, and `afterWeaponMaxLevel` makes it the level after the weapon's
/// own `maxLevel` instead (73 on the HAN 86, whose max is 72; other numbers
/// on other guns). Neither means reaching the stage is enough.
struct PrestigeCamo: Codable {
    let name: LocalizedText
    let stage: Int?
    let level: Int?
    let afterWeaponMaxLevel: Bool?
    let imageURL: String?
    /// Hex colors for the name's shimmer once it's earned; the built-in
    /// `[Color].prestige` set for its place when absent.
    var colors: [String]? = nil
    /// A weapon's own name, image or level for this camo, keyed by `weaponId` as a
    /// string, for a weapon whose Prestige camos differ.
    let byWeapon: [String: PrestigeCamoOverride]?
    /// Earned on every weapon once this many weapons have reached the
    /// camo's stage and level (BO7's Cold Snap: Prestige Master level 250
    /// on 50 weapons). Absent: each weapon earns it itself.
    var weaponsNeeded: Int? = nil
}

struct PrestigeCamoOverride: Codable {
    let name: LocalizedText?
    let imageURL: String?
    let level: Int?
    /// This weapon's own shimmer colours, for a camo whose look differs
    /// per weapon (BO7's Prestige 1, 2 and Max).
    var colors: [String]? = nil
}

/// One Weapon Prestige stage. `maxLevel` is that stage's level cap; `nil`
/// means "the weapon's own `maxLevel` again", the usual case. A one-off
/// stage like BO7's Prestige Master (250 levels) sets it explicitly.
struct PrestigeStage: Codable {
    let name: LocalizedText
    let maxLevel: Int?
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
    /// How a weapon with no unlock level is obtained: `"battlePass"` or
    /// `"event"`. Absent: unlocked by default. (A sentence with no digits,
    /// like "Unlocked in the Battle Pass.", can't say this by itself.)
    var acquiredBy: String? = nil
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
/// - `weaponCamos`: that mode's own base camo track for each weapon, looked
///   up by `weaponId` against the shared catalog above. Every mode
///   (Multiplayer, Warzone, DMZ) has one; finishing it opens that weapon's
///   Completionist camos (`AppMode.completionist`), which in turn feed the
///   mode's Mastery camos (`AppMode.masteryCamos`).
/// - `objectives`: mode-exclusive, non-weapon content (DMZ's Hajin extraction
///   objectives) that has no equivalent in other modes and doesn't feed
///   Mastery.
struct ModeFile: Codable {
    let version: String
    let mode: String
    var weaponCamos: [WeaponCamoEntry]
    var objectives: [Category]
    /// Optional over-the-air override of this mode's Mastery trio. Absent
    /// (every file before launch, and any older cached copy) means the
    /// built-in names/colors/thresholds in `AppMode.builtInMasteryCamos` stand.
    var mastery: MasteryConfig? = nil
    /// This mode's Completionist camos: Gold, Platinum and Harmonic Break
    /// (each with its own challenge, which can differ by weapon category),
    /// then the final camo. Absent means plain tick boxes under the built-in
    /// names, and a final camo that needs only the weapon's own Harmonic Break.
    var completionist: CompletionistConfig? = nil
    /// Another mode whose camo list and Completionist progress this mode
    /// shares ("multiplayer"), for a grind that's one track across modes:
    /// a Harmonic Break earned anywhere counts everywhere. Mastery stays
    /// this mode's own. Absent: this mode tracks its own.
    var trackFrom: String? = nil
    /// `true` keeps every Special camo shut until all the weapon's Military
    /// camos are earned. Absent or `false`: each Special opens at its own
    /// `unlockLevel`, as the in-game camo screens show (Smoke on the HAN 86
    /// opens at level 25, before Military 4).
    var specialsAfterMilitary: Bool? = nil
    /// `true` hides this mode's tab and leaves it out of Stats, for a mode
    /// that isn't playable yet (Warzone until Season 1). Flip it over the
    /// air to bring the tab back; progress is kept either way.
    var hidden: Bool? = nil
}

/// The `completionist` block of a mode file.
struct CompletionistConfig: Codable {
    /// Gold, Platinum, Harmonic Break, in that order. Fewer entries leave the
    /// rest on their built-in names with no challenge.
    var steps: [CompletionistStepConfig]?
    var final: CompletionistFinalConfig?
}

struct CompletionistStepConfig: Codable {
    var name: LocalizedText?
    var colors: [String]?
    /// The camo's picture, shown beside its name like a camo-list camo's.
    var imageURL: String?
    /// The challenge for every weapon category without its own below.
    var requirement: Requirement?
    /// Per weapon category, keyed by `categoryId` as a string ("0").
    var byCategory: [String: Requirement]?
    /// Per weapon, keyed by `weaponId` as a string ("24"). Beats its
    /// category's: the Warlord's Platinum isn't the other Shotguns'.
    var byWeapon: [String: Requirement]?
    /// What has to be done before this step opens on a weapon, beyond the
    /// step before it on that weapon: "weapon" (nothing more), "category"
    /// (the step before on every weapon in its class) or "mode" (the step
    /// before on the whole launch roster). Absent: Gold "weapon", Platinum
    /// "category", Harmonic Break "mode".
    var unlock: String?
    /// How many weapons a "category" or "mode" gate needs with the step
    /// before ("Complete 5 Gold Camo Challenges using Assault Rifles"),
    /// capped at the class or roster size. Absent: all of its launch weapons.
    var needed: Int?
    /// A "category" gate's count per class, keyed by `categoryId` as a
    /// string, over `needed` (BO6: 7 Assault Rifles, 6 SMGs, 2 Shotguns...).
    var neededByCategory: [String: Int]?
}

/// The fourth Completionist camo (Divergence in Multiplayer). It has no
/// challenge: a weapon earns it once it has its own Harmonic Break and
/// `harmonicBreaksNeeded` Harmonic Breaks are done across the mode.
struct CompletionistFinalConfig: Codable {
    /// false drops the final camo: the track ends at Harmonic Break, and
    /// Mastery counts Harmonic Breaks instead. Absent means it's there.
    var enabled: Bool?
    var name: LocalizedText?
    var colors: [String]?
    var imageURL: String?
    var harmonicBreaksNeeded: Int?
}

/// Per-tier Mastery overrides from the mode JSON. Every field is optional and
/// only replaces what it names, so a file can correct just tier1's threshold
/// at launch without restating names or colors.
struct MasteryConfig: Codable {
    /// "count" (absent): each tier unlocks for the mode once `weaponsNeeded`
    /// weapons have the last Completionist camo. "challenge": each tier is a
    /// per-weapon challenge, like Platinum, opened by its `unlock` gate.
    /// "mode": each tier is one challenge for the whole mode (`requirement`,
    /// a tick box without one), opened by the tier before and by
    /// `weaponsNeeded` weapons with the last Completionist camo (tier 1:
    /// one, unless set). A requirement whose `unit` is "golds",
    /// "platinums", "harmonic_breaks" or "finals" counts those across the
    /// mode by itself. Any tier can pick its own with `kind`.
    var unlock: String?
    var tier1: MasteryTierConfig?
    var tier2: MasteryTierConfig?
    var tier3: MasteryTierConfig?
}

struct MasteryTierConfig: Codable {
    /// This tier's own "count", "challenge" or "mode", over the mode's
    /// `unlock`, so the tiers can differ (tier 1 per weapon, 2 and 3 for
    /// the mode).
    var kind: String?
    var name: LocalizedText?
    /// How many weapons need this mode's final Completionist camo for this
    /// tier. Absent means a third, two thirds and all of the launch roster.
    var weaponsNeeded: Int?
    /// "#RRGGBB" hex; the first is the badge/pip swatch, all of them together
    /// the animated gradient.
    var colors: [String]?
    var imageURL: String?
    /// "challenge" and "mode" Mastery: the tier's challenge. "challenge"
    /// only: per weapon class and per weapon.
    var requirement: Requirement?
    var byCategory: [String: Requirement]?
    var byWeapon: [String: Requirement]?
    /// "challenge" Mastery only: what opens this tier on a weapon beyond the
    /// tier before on it (or, for tier 1, its last Completionist camo):
    /// "weapon", "category" or "mode". Absent: tier 1 "mode" (the whole
    /// launch roster), later tiers "weapon".
    var unlock: String?
    /// "challenge" Mastery only: how many weapons a "category" or "mode"
    /// gate needs, as for a Completionist step.
    var needed: Int?
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
    /// `true` for objectives that are one track across modes (a BlackCell
    /// camo earned in any mode): every mode with this `categoryId` reads
    /// and writes the same progress. Absent: each mode keeps its own.
    var shared: Bool? = nil
    var id: Int { categoryId }
}

/// A camo tier or a DMZ objective sub-tier — same node either way.
struct ChallengeItem: Codable, Identifiable {
    let itemId: Int
    let name: LocalizedText
    let imageURL: String?
    let tier: Int?
    /// The weapon level this camo's challenge opens at. MW4 locks base camos
    /// behind weapon level; `nil` falls back to "finish the tier above".
    /// Weapon level is global, so one level opens camos in every mode.
    let unlockLevel: Int?
    let requirement: Requirement?
    var children: [ChallengeItem]
    /// "military" or "special": which section of a weapon's camo list this
    /// camo sits in. A Military camo with an `unlockLevel` and no challenge
    /// is earned by reaching that level. Absent means the plain "Camos" list.
    var group: String? = nil
    /// The heading this camo sits under on the weapon's page ("Badges"),
    /// over its `group`'s. Camos in a row with the same heading share one
    /// section.
    var section: LocalizedText? = nil
    /// Tracked on the weapon's page but not part of the camo chain: it
    /// doesn't hold up Gold or count in progress (BO6's elimination badges).
    var extra: Bool? = nil
    /// The `itemId` whose count this camo reads, for camos on one running
    /// count (BO6's Military camos: 5, 10, 15... headshots): each is earned
    /// once the shared count reaches its own requirement.
    var counter: Int? = nil
    /// When a time-limited objective runs ("2026-11-06", UTC days, both
    /// inclusive): a BlackCell season or an event. Live ones show on the
    /// mode tab; ended ones move to their category's Archive. No `ends`:
    /// live from `starts` on. Neither: not time-limited.
    var starts: String? = nil
    var ends: String? = nil
    /// `false` lets this item's children be done in any order (an event's
    /// challenges). Absent: each opens once the one before is done.
    var ordered: Bool? = nil
    /// `true` keeps this child shut until every other child is done (a
    /// BlackCell Mastery camo after the class camos).
    var afterSiblings: Bool? = nil
    var id: Int { itemId }

    enum Window { case undated, upcoming, live, ended }

    func window(at now: Date = Date()) -> Window {
        let day = ChallengeItem.dayFormatter
        let start = starts.flatMap(day.date(from:))
        // `ends` is inclusive: live until the end of that day (UTC).
        let end = ends.flatMap(day.date(from:)).map { $0.addingTimeInterval(86_400) }
        if start == nil && end == nil { return .undated }
        if let start, now < start { return .upcoming }
        if let end, now >= end { return .ended }
        return .live
    }

    var endDate: Date? { ends.flatMap(ChallengeItem.dayFormatter.date(from:)) }

    static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    var isLeaf: Bool { children.isEmpty }
}

struct Requirement: Codable {
    let amount: Int
    let unit: String
    let description: LocalizedText
}

/// A time-limited objective that's live now, with the category it sits in
/// (progress is keyed by category), for the mode tab's Live section.
struct LiveObjective: Identifiable, Hashable {
    let categoryId: Int
    let item: ChallengeItem
    var id: String { "\(categoryId)-\(item.itemId)" }

    static func == (a: LiveObjective, b: LiveObjective) -> Bool { a.id == b.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
