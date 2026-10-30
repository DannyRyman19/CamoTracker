import Foundation

/// What the home-screen widgets show, written by the app into the shared App
/// Group whenever progress changes, and read as is by the widget extension.
/// Every string is already in the app's language (including a language picked
/// in Customise), so the widgets carry no translations of their own beyond
/// their gallery names.
struct WidgetSnapshot: Codable, Equatable {
    struct Mode: Codable, Equatable, Identifiable {
        /// `AppMode.rawValue`: "multiplayer", "warzone" or "dmz".
        let id: String
        let name: String
        /// "#RRGGBB", the mode's accent.
        let accentHex: String
        /// The mode's full-track completion, 0...1 (Stats' ring).
        let fraction: Double
        let weaponCount: Int
        /// Weapons with each Completionist camo, in order (Gold, Platinum,
        /// Harmonic Break, then the final camo when the mode has one).
        let steps: [Step]
        /// The three Mastery camos and whether each is earned.
        let mastery: [Step]
    }

    struct Step: Codable, Equatable {
        let name: String
        let done: Int
        let total: Int
        /// "#RRGGBB" for its pip.
        let colorHex: String
    }

    /// The pinned weapon, as it stands in the mode the app opens on.
    struct Pinned: Codable, Equatable {
        let weaponId: Int
        let name: String
        let category: String
        let mode: String
        let modeName: String
        let accentHex: String
        let camosDone: Int
        let camosTotal: Int
        /// The next camo to earn, its challenge, and how far through it is.
        let nextName: String?
        let nextDetail: String?
        let nextDone: Int
        let nextTotal: Int
    }

    let modes: [Mode]
    let pinned: Pinned?
    /// Average of the played modes' fractions (Stats' overall ring).
    let overall: Double
    /// Labels in the app's language.
    let overallLabel: String
    let pinPrompt: String
    let allDoneLabel: String
    /// "Mastery", over the three Mastery bars. Optional so a snapshot
    /// written before it existed still reads.
    var masteryLabel: String? = nil
    /// The game it's for ("bo7") and its short name ("BO7"). Optional so a
    /// snapshot written before there were games still reads (as MW4).
    var game: String? = nil
    var gameName: String? = nil

    static let appGroup = "group.com.DannyRyman.MW4CamoTracker"
    static let fileName = "widget-snapshot.json"

    /// The current game's snapshot, or one game's own: each game keeps its
    /// own, written whenever it's the game open in the app, so a widget can
    /// follow one game whatever the app has open.
    static func fileURL(game: String? = nil) -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appendingPathComponent(game.map { "widget-snapshot-\($0).json" } ?? fileName)
    }

    static var fileURL: URL? { fileURL() }

    static func load(game: String? = nil) -> WidgetSnapshot? {
        guard let url = fileURL(game: game), let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    /// The URL a widget opens: a mode tab, or one weapon in a mode, in the
    /// game the widget shows (the app switches to it first).
    static func link(mode: String, weaponId: Int? = nil, game: String? = nil) -> URL {
        var string = "mw4camo://mode/\(mode)"
        if let weaponId { string += "/weapon/\(weaponId)" }
        if let game { string += "?game=\(game)" }
        return URL(string: string)!
    }

    /// "BO7 Multiplayer": a mode's name after its game's
    func titled(_ name: String) -> String {
        gameName.map { "\($0) \(name)" } ?? name
    }
}
