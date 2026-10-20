import Foundation
import SwiftUI

/// Text in `hajin.json` can be a plain English string or, once a line is
/// translated, `{ "en": ..., "de": ... }`. Either way it resolves to the
/// player's language with English as the fallback, like `LocalizedText`.
struct GuideText: Codable, Hashable {
    let values: [String: String]

    init(_ value: String) { values = ["en": value] }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let plain = try? container.decode(String.self) {
            values = ["en": plain]
        } else {
            values = try container.decode([String: String].self)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if values.count == 1, let en = values["en"] { try container.encode(en) } else { try container.encode(values) }
    }

    var resolved: String {
        for code in AppLanguage.preferred {
            if let value = values[code] { return value }
        }
        return values["en"] ?? values.values.first ?? ""
    }
}

/// The DMZ guide: the Hajin Tac Map's markers plus the reference tables
/// (level unlocks, recipes, stations...). Bundled as `hajin.json` and
/// refreshed over the air through the manifest's `guides` block, so a
/// newly confirmed recipe cost reaches everyone without an app update.
struct HajinGuide: Codable {
    struct Category: Codable, Identifiable, Hashable {
        let id: String
        let name: GuideText
        let symbol: String
        let color: String
        /// Shown when the map first opens; the busy ones start hidden.
        let visible: Bool
        /// What every marker in this category is, shown in its sheet.
        let blurb: GuideText?

        var tint: Color { Color(hex: color) ?? .appInk }
        /// Areas and places are drawn as names, not pins.
        var isLabel: Bool { id == "area" || id == "place" }
    }

    struct Marker: Codable, Identifiable, Hashable {
        let id: String
        let cat: String
        let name: GuideText
        /// 0...1 across and down the map image.
        let x: Double
        let y: Double
        /// 1 (Low) to 5 (Extreme), for areas and Fortresses.
        let threat: Int?
        let note: GuideText?
        /// The named places inside an area, each with its own threat.
        let parts: [Part]?

        struct Part: Codable, Hashable {
            let name: GuideText
            let threat: Int?
        }
    }

    struct Row: Codable, Hashable {
        let title: GuideText
        let value: GuideText?
        let subtitle: GuideText?
        let level: Int?
        /// The item's picture, when there is one.
        let image: String?
        /// A heading the row sits under within its section ("Backpacks").
        let group: GuideText?
        /// The item this row is about, for its own screen and links.
        let item: String?
        /// Items the row mentions (a boss's drop, a mission's reward).
        let links: [String]?
        /// A weapon in the camo catalog (`weaponId`), for its picture and
        /// a link to its camos.
        let weapon: Int?
        /// Gives the row a checkbox, saved (and synced) under this key.
        let check: String?

        /// Whether any of its text contains `needle` (already lowercased).
        func matches(_ needle: String) -> Bool {
            [title, value, subtitle].contains { $0?.resolved.lowercased().contains(needle) ?? false }
        }
    }

    struct Section: Codable, Identifiable, Hashable {
        let id: String
        let title: GuideText
        let symbol: String
        let intro: GuideText?
        let rows: [Row]
    }

    /// Anything the game lets you print, loot, spend or open: recipes,
    /// ingredients, resources, FOB upgrades, valuables and keys. Recipes
    /// point at their ingredients by id, so every mention is a link.
    struct Item: Codable, Identifiable, Hashable {
        struct Cost: Codable, Hashable {
            let item: String
            let qty: Int
        }
        let id: String
        let name: GuideText
        /// The printer tab or kind: "Consumables", "Ingredient", "Key"...
        let kind: String
        let rarity: String?
        let image: String?
        /// SF Symbol for the four base resources, which have no picture.
        let symbol: String?
        let unlock: GuideText?
        let cost: [Cost]?
        /// DMZ Cash on top of `cost` (FOB upgrades).
        let cash: Int?
        let effect: GuideText?
        /// Sell value in DMZ Cash.
        let value: Int?
        let note: GuideText?
        /// Tac Map grid square (keys).
        let grid: String?
        /// The map marker for where it's used (key rooms).
        let marker: String?
    }

    /// One of the three trait trees, laid out like the game: rows top to
    /// bottom (two fixed choices or three random ones), emblem last.
    struct TraitTree: Codable, Identifiable, Hashable {
        let id: String
        let name: GuideText
        let color: String
        /// "hexagon", "circle" or "square", the node shape in game.
        let shape: String
        /// Trait ids; `nil` is a random slot not revealed yet.
        let rows: [[String?]]
        let emblem: String?

        var tint: Color { Color(hex: color) ?? .appInk }
    }

    struct Trait: Codable, Identifiable, Hashable {
        let id: String
        /// `nil` when the trait's icon is known but not its name yet.
        let name: GuideText?
        let tree: String?
        let effect: GuideText?
        let icon: String?
    }

    struct MapInfo: Codable {
        let image: String
        let credit: String?
    }

    let version: String
    let updated: String?
    let map: MapInfo
    let threatLevels: [GuideText]
    let categories: [Category]
    let markers: [Marker]
    let guide: [Section]
    let items: [Item]?
    let traitTrees: [TraitTree]?
    let traits: [Trait]?

    func trait(_ id: String) -> Trait? { traits?.first { $0.id == id } }

    func category(_ id: String) -> Category? { categories.first { $0.id == id } }

    func item(_ id: String) -> Item? { items?.first { $0.id == id } }

    /// Everything whose recipe or upgrade needs this item.
    func usedIn(_ id: String) -> [Item] {
        (items ?? []).filter { $0.cost?.contains { $0.item == id } ?? false }
    }

    func marker(_ id: String) -> Marker? { markers.first { $0.id == id } }

    /// Guide rows that mention this item: where it drops, what rewards it.
    func mentions(_ id: String) -> [(section: Section, row: Row)] {
        guide.flatMap { section in
            section.rows.filter { $0.links?.contains(id) ?? false }.map { (section, $0) }
        }
    }

    func threatName(_ level: Int) -> String? {
        threatLevels.indices.contains(level - 1) ? threatLevels[level - 1].resolved : nil
    }
}

/// A pin the player drops on the map themselves: a key spawn, a stash of
/// loot, a good exfil. Kept on this device only.
struct HajinPin: Codable, Identifiable, Hashable {
    var id = UUID()
    var x: Double
    var y: Double
    var title: String
    var note: String
}

/// Threat colours, Low (green) to Extreme (deep red).
enum HajinThreat {
    static func color(_ level: Int) -> Color {
        switch level {
        case 1: return Color(red: 0.24, green: 0.84, blue: 0.55)
        case 2: return Color(red: 1.00, green: 0.77, blue: 0.24)
        case 3: return Color(red: 0.97, green: 0.42, blue: 0.08)
        case 4: return Color(red: 0.90, green: 0.28, blue: 0.30)
        default: return Color(red: 0.62, green: 0.10, blue: 0.20)
        }
    }
}

@MainActor
final class HajinStore: ObservableObject {
    static let pinsKey = "mw4_hajin_pins"
    static let checkedKey = "mw4_hajin_checked"
    static let hiddenKey = "mw4_hajin_hidden_categories"

    @Published private(set) var guide: HajinGuide?
    @Published var pins: [HajinPin] = [] {
        didSet { savePins() }
    }
    /// Ticked rows (bosses taken down), synced over iCloud with progress.
    @Published private(set) var checked: Set<String> = []
    private var cloud: CloudSync?

    private let dataService: DataService
    private let defaults: UserDefaults
    private var refreshed = false

    init(dataService: DataService = DataService(), defaults: UserDefaults = .standard) {
        self.dataService = dataService
        self.defaults = defaults
        let seed = dataService.loadSeedGuide(name: "hajin")
        let cached = dataService.loadCachedGuide(name: "hajin")
        // An app update can ship newer data than an old cached download
        if let cached, let seed, DataService.isNewer(seed.version, than: cached.version) {
            guide = seed
        } else {
            guide = cached ?? seed
        }
        if let data = defaults.data(forKey: Self.pinsKey),
           let saved = try? JSONDecoder().decode([HajinPin].self, from: data) {
            pins = saved
        }
        checked = Set(defaults.stringArray(forKey: Self.checkedKey) ?? [])
        if defaults == .standard {
            let cloud = CloudSync(cloudKey: "mw4_hajin_sync", defaults: defaults)
            cloud.onRemoteChange = { [weak self] values in
                guard let self else { return }
                self.checked = Set(values.keys)
                self.defaults.set(Array(self.checked).sorted(), forKey: Self.checkedKey)
            }
            self.cloud = cloud
            cloud.start(current: Dictionary(uniqueKeysWithValues: checked.map { ($0, 1) }))
            #if DEBUG
            // One-shot wipe like the progress store's, with its own file
            let wipe = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("mw4_wipe_hajin")
            if FileManager.default.fileExists(atPath: wipe.path) {
                try? FileManager.default.removeItem(at: wipe)
                checked = []
                defaults.set([String](), forKey: Self.checkedKey)
                cloud.recordLocal([:])
            }
            #endif
        }
    }

    func toggle(_ key: String) {
        if checked.contains(key) { checked.remove(key) } else { checked.insert(key) }
        defaults.set(Array(checked).sorted(), forKey: Self.checkedKey)
        cloud?.recordLocal(Dictionary(uniqueKeysWithValues: checked.map { ($0, 1) }))
    }

    /// Categories the player switched off on the map. Starts from each
    /// category's own `visible` default until they touch a filter.
    var hiddenCategories: Set<String> {
        get {
            if let saved = defaults.array(forKey: Self.hiddenKey) as? [String] { return Set(saved) }
            return Set(guide?.categories.filter { !$0.visible }.map(\.id) ?? [])
        }
        set {
            objectWillChange.send()
            defaults.set(Array(newValue).sorted(), forKey: Self.hiddenKey)
        }
    }

    /// Makes sure a marker's category is showing before flying to it.
    func reveal(_ marker: HajinGuide.Marker) {
        if hiddenCategories.contains(marker.cat) { hiddenCategories.remove(marker.cat) }
    }

    /// Checks the CDN once per launch for a newer guide.
    func refresh() async {
        guard !refreshed else { return }
        refreshed = true
        if let newer = try? await dataService.refreshGuide(name: "hajin", knownVersion: guide?.version) {
            guide = newer
        }
    }

    private func savePins() {
        if let data = try? JSONEncoder().encode(pins) { defaults.set(data, forKey: Self.pinsKey) }
    }
}
