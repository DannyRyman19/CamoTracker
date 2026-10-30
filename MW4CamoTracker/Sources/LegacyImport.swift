import Foundation

/// Progress to merge in from another tracker (see `TrackerViewModel.applyImport`).
struct ProgressImport {
    var levels: [Int: (prestige: Int, level: Int)] = [:]
    var camos: [(mode: String, weaponId: Int, itemId: Int, amount: Int)] = []
    var steps: [(mode: String, weaponId: Int, step: Int, amount: Int)] = []
    /// Weapons the file had progress for
    var weapons = Set<Int>()
}

/// Reads the file the old BO6 and BO7 Camo Tracker apps export: every
/// weapon with each camo's `CurrentAmount`, its `CurrentLevel` and, in
/// BO7, `PrestigeLevel`. BO6's is `{"multiplayer": [...], "zombies": [...],
/// "warzone": [...]}`; BO7's is one list with a block per mode on each
/// weapon. Weapons are matched by name and camos by their place, which is
/// how this app's BO6 and BO7 data was made from theirs.
enum LegacyImport {
    enum Failure: Error { case notAnExport }

    /// The old apps spelt a few weapons differently
    private static let aliases = ["gravemark": "gravemark .357", "nuncahku": "nunchaku", "ps-21": "pu-21"]

    private static func key(_ name: String) -> String {
        let plain = name.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return aliases[plain] ?? plain
    }

    @MainActor
    static func read(_ data: Data, into viewModel: TrackerViewModel) throws -> ProgressImport {
        let json = try JSONSerialization.jsonObject(with: data)
        let byName = Dictionary(viewModel.allWeapons.map { (key($0.name.resolved()), $0.weaponId) }, uniquingKeysWith: { a, _ in a })
        var result = ProgressImport()

        func weapons(_ categories: Any?) -> [[String: Any]] {
            ((categories as? [[String: Any]]) ?? []).flatMap { ($0["Weapons"] as? [[String: Any]]) ?? [] }
        }
        func amounts(_ list: Any?) -> [Int] {
            ((list as? [[String: Any]]) ?? []).map { ($0["CurrentAmount"] as? Int) ?? 0 }
        }

        /// One weapon's camos in one mode, from the old app's lists
        func take(mode: String, weaponId: Int, military: [Int], specials: [Int], mastery: [Int], badges: [Int]) {
            let ours = viewModel.allCamos(weaponId: weaponId, mode: mode)
            // Camos on a running count read its total: the old apps kept
            // each step's share of it
            func put(_ camos: [ChallengeItem], _ values: [Int]) {
                if let counter = camos.first?.counter {
                    result.camos.append((mode, weaponId, counter, values.reduce(0, +)))
                } else {
                    for (camo, value) in zip(camos, values) { result.camos.append((mode, weaponId, camo.itemId, value)) }
                }
            }
            put(ours.filter { $0.group == "military" }, military)
            put(ours.filter { $0.group == "special" }, specials)
            put(ours.filter { $0.extra == true }, badges)
            for (step, value) in mastery.prefix(TrackerViewModel.completionistStepCount).enumerated() {
                result.steps.append((mode, weaponId, step, value))
            }
        }

        func level(_ weapon: [String: Any], _ weaponId: Int) {
            let level = (weapon["CurrentLevel"] as? Int) ?? 0
            let prestige = (weapon["PrestigeLevel"] as? Int) ?? 0
            if level > 1 || prestige > 0 { result.levels[weaponId] = (prestige, level) }
        }

        if let modes = json as? [String: Any], modes.keys.contains(where: { ["multiplayer", "zombies", "warzone"].contains($0.lowercased()) }) {
            // BO6: a list of weapons per mode
            for (rawMode, categories) in modes {
                guard let mode = AppMode(rawValue: rawMode.lowercased())?.rawValue else { continue }
                for weapon in weapons(categories) {
                    guard let id = byName[key((weapon["WeaponName"] as? String) ?? "")] else { continue }
                    result.weapons.insert(id)
                    level(weapon, id)
                    let mastery = amounts(weapon["MasteryCamos"])
                    // Gold, Diamond and Dark Spine, Dark Matter (earned by
                    // itself here), then the three badges
                    take(mode: mode, weaponId: id, military: amounts(weapon["MilitaryCamos"]),
                         specials: amounts(weapon["UniqueCamos"] ?? weapon["SpecialCamos"]),
                         mastery: Array(mastery.prefix(3)), badges: Array(mastery.dropFirst(4)))
                }
            }
        } else if let categories = json as? [[String: Any]] ?? (json as? [String: Any])?["weapons"] as? [[String: Any]] {
            // BO7: one list, a block per mode on each weapon
            for weapon in weapons(categories) {
                guard let id = byName[key((weapon["WeaponName"] as? String) ?? "")] else { continue }
                result.weapons.insert(id)
                level(weapon, id)
                for mode in AppMode.allCases {
                    guard let block = weapon[mode.rawValue.capitalized] as? [String: Any] else { continue }
                    take(mode: mode.rawValue, weaponId: id, military: amounts(block["MilitaryCamos"]),
                         specials: amounts(block["SpecialCamos"]), mastery: amounts(block["MasteryCamos"]),
                         badges: amounts(block["MasteryBadges"]))
                }
            }
        }
        guard !result.weapons.isEmpty else { throw Failure.notAnExport }
        return result
    }
}
