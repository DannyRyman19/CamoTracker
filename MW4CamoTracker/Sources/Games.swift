import SwiftUI

/// One Call of Duty game the app tracks: its own weapons, modes, data
/// folder and saved progress. The list ships in `games.json`; adding a game
/// is a new entry there plus its data files. MW4 came first, so its data
/// and saves keep the names they had before there were other games.
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
    /// false for a game without account-wide Mastery camos after the
    /// per-weapon ones (BO6, BO7): no Mastery tab, column or summary entry
    var hasMastery: Bool? = nil
    /// A camo finished in one mode counts in every mode (MW4's one camo
    /// grind per weapon). Absent: each mode is its own grind.
    var sharedCamos: Bool? = nil
    /// The game's own look: colours, title font and splash. Absent: MW4's.
    var theme: GameTheme? = nil

    static func == (a: Game, b: Game) -> Bool { a.id == b.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    var dataURL: URL {
        URL(string: "https://cdn.jsdelivr.net/gh/DannyRyman19/CamoTracker@master/")!.appendingPathComponent(path, isDirectory: true)
    }

    /// MW4's saves and settings keep their original keys; every other game
    /// gets its own copy of each, named after it.
    var isMW4: Bool { id == "mw4" }
    func key(_ mw4: String, _ name: String) -> String { isMW4 ? mw4 : "ct_\(name)_\(id)" }

    /// The DMZ guide (Hajin) is MW4's
    var hasHajin: Bool { isMW4 }
}

/// How a game looks, so each one feels like its own tracker: the background
/// and card colours, the title font, and the mark in the middle of the
/// splash ("CAMO / BO6 / TRACK"). Every field falls back to MW4's.
struct GameTheme: Codable, Hashable {
    /// "#RRGGBB" for the page, cards and raised cards
    var background: String?
    var surface: String?
    var surface2: String?
    /// The title font's family ("Teko") and how much to scale it so it
    /// reads at Hitmarker's size; `fontWeight` "regular" for a one-weight face
    var font: String?
    var fontScale: Double?
    var fontWeight: String?
    /// The splash: the nebula's tint, and the mark between CAMO and TRACK,
    /// its first `markWhite` characters white and the rest in `markColor`
    var tint: String?
    var mark: String?
    var markWhite: Int?
    var markColor: String?
    /// The game's own colour for buttons and highlights outside a mode
    var accent: String?
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

    /// Where the picked game is kept
    static let key = "ct_game"

    nonisolated(unsafe) static var current: Game = saved {
        didSet {
            Palette.apply(current.theme)
            AppDelegate.configureNavigationBarAppearance()
        }
    }

    /// The game picked last time, else the first (MW4)
    static var saved: Game {
        UserDefaults.standard.string(forKey: key).flatMap(game) ?? games[0]
    }

    static func game(_ id: String) -> Game? { games.first { $0.id == id } }

    /// The current game has account-wide Mastery camos
    static var hasMastery: Bool { current.hasMastery != false }

    /// MW4 as shipped, should `games.json` ever be missing.
    static let fallback = Game(
        id: "mw4", name: LocalizedText("Modern Warfare 4"), shortName: "MW4", path: "Data/MW4/", seedPrefix: "",
        modes: [GameMode(id: "multiplayer"), GameMode(id: "warzone"), GameMode(id: "dmz")],
        countsUnlocks: true, levelCategories: [7, 8], sharedCamos: true)
}

/// The game being tracked and its tracker. Each game has its own
/// `TrackerViewModel` (own data and saved progress); switching makes a new
/// one and the root view rebuilds around it.
@MainActor
final class GameStore: ObservableObject {
    @Published private(set) var game: Game
    @Published private(set) var viewModel: TrackerViewModel

    init() {
        let game = GameRegistry.saved
        GameRegistry.current = game
        Palette.apply(game.theme)
        self.game = game
        viewModel = TrackerViewModel(game: game)
    }

    func select(_ game: Game) {
        guard game != self.game else { return }
        UserDefaults.standard.set(game.id, forKey: GameRegistry.key)
        GameRegistry.current = game
        let model = TrackerViewModel(game: game)
        viewModel = model
        self.game = game
        Task { await model.refresh() }
    }
}
