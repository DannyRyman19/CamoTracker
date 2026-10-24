import Foundation

/// One Call of Duty game the app tracks: its own weapons, modes, data
/// folder and saved progress. The list ships in `games.json`; adding a game
/// is a new entry there plus its data files.
struct Game: Codable, Identifiable, Hashable {
    let id: String
    let name: LocalizedText
    /// "MW4", "BO7": the short name in the game switcher
    let shortName: String
    /// Folder on the CDN under the repo root, e.g. "Data/MW4/"
    let path: String
    /// Bundled seed files are named `<seedPrefix><file>.json`
    let seedPrefix: String
    /// The modes this game has, in the order they show
    let modes: [GameMode]
    /// The game counts weapon progress in unlocks rather than levels (MW4)
    var countsUnlocks: Bool? = nil
    /// Weapon categories that keep counting levels in a game that counts
    /// unlocks (MW4: launchers and melee have no shared attachments)
    var levelCategories: [Int]? = nil

    static func == (a: Game, b: Game) -> Bool { a.id == b.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    var dataURL: URL {
        URL(string: "https://cdn.jsdelivr.net/gh/DannyRyman19/CamoTracker@master/")!.appendingPathComponent(path, isDirectory: true)
    }
}

/// A mode as a game defines it. Name, symbol and colour fall back to the
/// app's built-in ones for the usual modes (see `AppMode`).
struct GameMode: Codable, Hashable {
    let id: String
    var name: LocalizedText? = nil
    var symbol: String? = nil
    /// Hex colour, e.g. "#E0575B"
    var accent: String? = nil

    static func == (a: GameMode, b: GameMode) -> Bool { a.id == b.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// The games the app knows and the one being tracked. `current` is what
/// `AppMode` and the mode-wide camo overrides read, so it changes only
/// through `GameStore` when the player switches game.
enum GameRegistry {
    static let games: [Game] = {
        guard let url = Bundle.main.url(forResource: "games", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let games = try? JSONDecoder().decode([Game].self, from: data), !games.isEmpty else { return [fallback] }
        return games
    }()

    nonisolated(unsafe) static var current: Game = games[0]

    static func game(_ id: String) -> Game? { games.first { $0.id == id } }

    /// MW4 as shipped, should `games.json` ever be missing.
    static let fallback = Game(
        id: "mw4", name: LocalizedText("Modern Warfare 4"), shortName: "MW4", path: "Data/MW4/", seedPrefix: "mw4_",
        modes: [GameMode(id: "multiplayer"), GameMode(id: "warzone"), GameMode(id: "dmz")],
        countsUnlocks: true, levelCategories: [7, 8])
}
