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

    func category(_ id: String) -> Category? { categories.first { $0.id == id } }

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
    static let hiddenKey = "mw4_hajin_hidden_categories"

    @Published private(set) var guide: HajinGuide?
    @Published var pins: [HajinPin] = [] {
        didSet { savePins() }
    }

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
