import Foundation

/// Progress to merge in from another tracker (see `TrackerViewModel.applyImport`).
struct ProgressImport {
    var levels: [Int: (prestige: Int, level: Int)] = [:]
    var camos: [(mode: String, weaponId: Int, itemId: Int, amount: Int)] = []
    var steps: [(mode: String, weaponId: Int, step: Int, amount: Int)] = []
    /// Weapons the file had progress for
    var weapons = Set<Int>()
}

/// Reads the file the old BO6, BO7 and MW3 Camo Tracker apps export: every
/// weapon with each camo's `CurrentAmount`, its `CurrentLevel` and, in
/// BO7, `PrestigeLevel`. BO6's is `{"multiplayer": [...], "zombies": [...],
/// "warzone": [...]}`; BO7's is one list with a block per mode on each
/// weapon. Weapons are matched by name and camos by their place, which is
/// how this app's BO6 and BO7 data was made from theirs. The MW3 app's is
/// four lists in a row (MW3 Multiplayer, MW3 Zombies, MWII Multiplayer,
/// MWII Zombies), each weapon with its `Camos`, `CompletionistCamos`,
/// `MasteryChallenges` and `PrestigeChallenges`, kept here at the same
/// places: MW3 takes the first two, MW2 the last two.
enum LegacyImport {
    enum Failure: Error {
        case notAnExport
        /// The other old app's export (BO6's file while BO7 is open): its
        /// weapons share names (the Knife), so it would land on the wrong
        /// game's progress, and an import can't be undone.
        case otherGame(Game)
    }

    /// Which game's old app wrote this shape of file: BO6's keeps a list
    /// of weapons per mode, BO7's one list with a block per mode.
    private static let modeListsGame = "bo6", weaponListGame = "bo7", fourListsGame = "mw3"

    /// The MW3 app's four lists, in the order it exported them: each one's
    /// game here and mode in it
    private static let fourLists = [("mw3", "multiplayer"), ("mw3", "zombies"), ("mw2", "multiplayer"), ("mw2", "zombies")]

    private static func isFourLists(_ json: Any) -> Bool {
        guard let lists = json as? [Any], lists.count == fourLists.count else { return false }
        return lists.allSatisfy { $0 is [[String: Any]] }
    }

    /// The old apps spelt a few weapons differently
    private static let aliases = ["gravemark": "gravemark .357", "nuncahku": "nunchaku", "ps-21": "pu-21"]

    private static func key(_ name: String) -> String {
        let plain = name.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return aliases[plain] ?? plain
    }

    /// The game whose old app wrote `json`, by its shape; `nil` for neither.
    static func exportGame(_ json: Any) -> String? {
        if isFourLists(json) { return fourListsGame }
        if let modes = json as? [String: Any], modes.keys.contains(where: { ["multiplayer", "zombies", "warzone"].contains($0.lowercased()) }) {
            return modeListsGame
        }
        if (json as? [[String: Any]] ?? (json as? [String: Any])?["weapons"] as? [[String: Any]]) != nil { return weaponListGame }
        return nil
    }

    /// Refuses the other game's export rather than merge it by name.
    static func check(_ json: Any, isFor game: Game) throws {
        guard let owner = exportGame(json), owner != game.id else { return }
        // The MW3 app's file holds the MWII guns too
        if owner == fourListsGame, fourLists.contains(where: { $0.0 == game.id }) { return }
        throw Failure.otherGame(GameRegistry.game(owner) ?? game)
    }

    @MainActor
    static func read(_ data: Data, into viewModel: TrackerViewModel) throws -> ProgressImport {
        let json = try JSONSerialization.jsonObject(with: data)
        try check(json, isFor: viewModel.game)
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

        /// `offset`: the MW3 app kept the level picker's index (level 1 is 0)
        func level(_ weapon: [String: Any], _ weaponId: Int, offset: Int = 0) {
            let level = ((weapon["CurrentLevel"] as? Int) ?? 0) + offset
            let prestige = (weapon["PrestigeLevel"] as? Int) ?? 0
            // BO6 keeps a copy of each weapon per mode: the highest wins
            guard level > 1 || prestige > 0 else { return }
            if let known = result.levels[weaponId], (known.prestige, known.level) >= (prestige, level) { return }
            result.levels[weaponId] = (prestige, level)
        }

        if isFourLists(json), let lists = json as? [[[String: Any]]] {
            // The MW3 app: a list per tab, this game's two of them
            for ((game, mode), categories) in zip(fourLists, lists) where game == viewModel.game.id {
                let names = byName
                for weapon in weapons(categories) {
                    guard let id = names[key((weapon["WeaponName"] as? String) ?? "")] else { continue }
                    result.weapons.insert(id)
                    level(weapon, id, offset: 1)
                    for (index, value) in amounts(weapon["Camos"]).enumerated() {
                        result.camos.append((mode, id, index, value))
                    }
                    for (step, value) in amounts(weapon["CompletionistCamos"]).prefix(TrackerViewModel.completionistStepCount).enumerated() {
                        result.steps.append((mode, id, step, value))
                    }
                    for (index, value) in amounts(weapon["MasteryChallenges"]).prefix(4).enumerated() {
                        result.camos.append((mode, id, 100 + index, value))
                    }
                    for (index, value) in amounts(weapon["PrestigeChallenges"]).prefix(4).enumerated() {
                        result.camos.append((mode, id, 200 + index, value))
                    }
                }
            }
        } else if let modes = json as? [String: Any], modes.keys.contains(where: { ["multiplayer", "zombies", "warzone"].contains($0.lowercased()) }) {
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
