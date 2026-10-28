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
        /// Missions and ops: where, the steps, and what they pay.
        let place: GuideText?
        let objectives: [GuideText]?
        let cash: Int?
        let rewards: [GuideText]?
        /// DMZ Orders: what the order has you print, and the ingredients it
        /// has you extract (which can be carried in from the stash).
        let prints: [Item.Cost]?
        let extracts: [Item.Cost]?
        /// Tips for doing it.
        let tips: [GuideText]?
        /// What finishing the DMZ Orders page this order is on gives.
        let pageReward: GuideText?

        /// The DMZ level this row needs: a level-unlock row's level, or a
        /// "Lv 12" badge.
        var requiredLevel: Int? {
            if let level { return level }
            guard let text = value?.values["en"], text.hasPrefix("Lv ") else { return nil }
            return Int(text.dropFirst(3))
        }

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
        /// Where it turns up in Hajin, from the printer's Ingredient Locations.
        let found: GuideText?
        /// Tac Map markers for the named places in `found`.
        let foundPlaces: [String]?
        /// Tac Map grid square (keys).
        let grid: String?
        /// The map marker for where it's used (key rooms).
        let marker: String?
        /// "Reach DMZ level 48" as 48.
        var requiredLevel: Int? {
            guard let text = unlock?.values["en"], let range = text.range(of: "level ") else { return nil }
            return Int(text[range.upperBound...].prefix { $0.isNumber })
        }

        /// FOB upgrades: the family ("Bank Upgrade") and this one's tier.
        let family: String?
        let tier: Int?
        /// A recipe found in Hajin (a blueprint): on the "Still to find" list.
        let blueprint: Bool?
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

    /// Sections the player ticks off: they're on My DMZ, not in the guide.
    static let trackedSections: Set<String> = ["ops", "upgrades", "bosses", "gunsmith", "prestige"]

    /// What the DMZ Orders not yet ticked need from the stash: each print's
    /// recipe cost times how many, and the ingredients to extract.
    func orderNeeds(done: Set<String>) -> [(order: Row, item: String, qty: Int)] {
        let orders = guide.first { $0.id == "ops" }?.rows.filter { $0.check.map { !done.contains($0) } ?? false } ?? []
        return orders.flatMap { order in
            let printed = (order.prints ?? []).flatMap { print in
                (item(print.item)?.cost ?? []).map { (order: order, item: $0.item, qty: $0.qty * print.qty) }
            }
            return printed + (order.extracts ?? []).map { (order: order, item: $0.item, qty: $0.qty) }
        }
    }

    /// Every tier of an upgrade family, lowest first.
    func tiers(of item: Item) -> [Item] {
        guard let family = item.family else { return [] }
        return (items ?? []).filter { $0.family == family }.sorted { ($0.tier ?? 0) < ($1.tier ?? 0) }
    }

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
    static let levelKey = "mw4_hajin_dmz_level"
    static let cashKey = "mw4_hajin_cash"
    static let trackedKey = "mw4_hajin_tracked"
    static let stashKey = "mw4_hajin_stash"
    /// The game tracks five things at once; so does the app.
    static let maxTracked = 5
    static let maxLevel = 70
    static let hiddenKey = "mw4_hajin_hidden_categories"
    /// The categories the player's saved filter was set against, so a
    /// category added by a newer guide starts from its own default.
    static let seenCategoriesKey = "mw4_hajin_seen_categories"
    /// The categories before `seenCategoriesKey` was saved.
    private static let firstCategories: Set<String> = ["area", "place", "fortress", "compound", "lieutenant", "uav", "key",
                                                       "cache", "clinic", "fire", "police", "gas", "marine"]

    @Published private(set) var guide: HajinGuide?
    @Published var pins: [HajinPin] = [] {
        didSet { savePins() }
    }
    /// Ticked rows (bosses taken down), synced over iCloud with progress.
    @Published private(set) var checked: Set<String> = []
    /// The player's DMZ level; 0 until they set it, which leaves nothing
    /// shown as locked.
    @Published private(set) var dmzLevel = 0
    /// The player's DMZ Cash, as they last entered it (0 = not set).
    @Published private(set) var cash = 0
    /// Recipes and upgrades being worked towards, in the order tracked.
    @Published private(set) var tracked: [String] = []
    /// How many of each ingredient or resource the player has.
    @Published private(set) var stash: [String: Int] = [:]
    /// The last automatic stash change, offered for undo for a few seconds.
    @Published var stashUndo: StashUndo?

    struct StashUndo: Identifiable, Equatable {
        let id = UUID()
        let message: String
        let previous: [String: Int]
        let previousTracked: [String]
    }
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
        dmzLevel = defaults.integer(forKey: Self.levelKey)
        cash = defaults.integer(forKey: Self.cashKey)
        tracked = defaults.stringArray(forKey: Self.trackedKey) ?? []
        stash = (defaults.dictionary(forKey: Self.stashKey) as? [String: Int]) ?? [:]
        if defaults == .standard {
            let cloud = CloudSync(cloudKey: "mw4_hajin_sync", defaults: defaults)
            cloud.onRemoteChange = { [weak self] values in
                guard let self else { return }
                self.checked = Set(values.keys.filter { $0 != Self.levelSyncKey && $0 != Self.cashSyncKey && !$0.hasPrefix("track:") && !$0.hasPrefix("stash:") })
                self.dmzLevel = values[Self.levelSyncKey] ?? 0
                self.cash = values[Self.cashSyncKey] ?? 0
                self.tracked = values.filter { $0.key.hasPrefix("track:") }.sorted { $0.value < $1.value }.map { String($0.key.dropFirst(6)) }
                self.stash = Dictionary(uniqueKeysWithValues: values.filter { $0.key.hasPrefix("stash:") }.map { (String($0.key.dropFirst(6)), $0.value) })
                self.persistLocal()
            }
            self.cloud = cloud
            cloud.start(current: syncValues())
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

    /// Where My DMZ is kept: the standard defaults (synced with iCloud),
    /// or for the SS_GRID_DEMO screen recording an empty throwaway suite,
    /// so the demo never reads, changes or syncs the player's real data.
    static func launchDefaults() -> UserDefaults {
        #if DEBUG
        if ProcessInfo.processInfo.environment["SS_GRID_DEMO"] != nil, let demo = UserDefaults(suiteName: "mw4_hajin_demo") {
            demo.removePersistentDomain(forName: "mw4_hajin_demo")
            UserDefaults.standard.set(HajinPage.mine.rawValue, forKey: HajinPage.key)
            return demo
        }
        #endif
        return .standard
    }

    private static let levelSyncKey = "dmz-level"
    private static let cashSyncKey = "dmz-cash"

    private func syncValues() -> [String: Int] {
        var values = Dictionary(uniqueKeysWithValues: checked.map { ($0, 1) })
        if dmzLevel > 0 { values[Self.levelSyncKey] = dmzLevel }
        if cash > 0 { values[Self.cashSyncKey] = cash }
        for (index, id) in tracked.enumerated() { values["track:\(id)"] = index + 1 }
        for (id, count) in stash where count > 0 { values["stash:\(id)"] = count }
        return values
    }

    private func persistLocal() {
        defaults.set(Array(checked).sorted(), forKey: Self.checkedKey)
        defaults.set(dmzLevel, forKey: Self.levelKey)
        defaults.set(cash, forKey: Self.cashKey)
        defaults.set(tracked, forKey: Self.trackedKey)
        defaults.set(stash, forKey: Self.stashKey)
    }

    private func saveAndSync() {
        persistLocal()
        cloud?.recordLocal(syncValues())
    }

    func isTracked(_ id: String) -> Bool { tracked.contains(id) }

    /// Track or untrack; returns false when five are already tracked.
    @discardableResult
    func toggleTracked(_ id: String) -> Bool {
        if let index = tracked.firstIndex(of: id) {
            tracked.remove(at: index)
        } else {
            guard tracked.count < Self.maxTracked else { return false }
            tracked.append(id)
        }
        saveAndSync()
        return true
    }

    func count(of id: String) -> Int { stash[id] ?? 0 }

    /// What My stash counts: resources, ingredients and valuables (which
    /// the higher FOB upgrades cost), less dog tags, which are sold as soon
    /// as you extract them.
    nonisolated static func inStash(_ item: HajinGuide.Item) -> Bool {
        ["Resource", "Ingredient", "Valuable"].contains(item.kind) && !item.id.contains("dog-tag")
    }

    /// The recipe is unlocked and the stash covers every part of its cost
    /// (or an upgrade's).
    func canPrint(_ item: HajinGuide.Item) -> Bool {
        guard let cost = item.cost, !cost.isEmpty, !stash.isEmpty, hasRecipe(item) else { return false }
        return cost.allSatisfy { count(of: $0.item) >= $0.qty }
    }

    /// Whether the player can print it at all: a recipe found in Hajin once
    /// it's ticked found, a level one at that level (or no level set), an
    /// Uncommon or Epic ingredient once that Ingredient Printing upgrade is
    /// ticked. Ones unlocked by Orders can't be told, so count as unlocked.
    func hasRecipe(_ item: HajinGuide.Item) -> Bool {
        if item.blueprint == true { return hasBlueprint(item.id) }
        if isLocked(item.requiredLevel) { return false }
        if let needs = item.effect?.values["en"], let r = needs.range(of: #"Needs (\w+) Ingredient Printing"#, options: .regularExpression) {
            let upgrade = needs[r].dropFirst("Needs ".count).lowercased().replacingOccurrences(of: " ", with: "-")
            return checked.contains("upgrade-\(upgrade)")
        }
        return true
    }

    static let printableGreen = Color(red: 0.42, green: 0.80, blue: 0.36)

    /// What to print next: the next unprinted tier of each FOB upgrade,
    /// printable ones first, then by how much of the cost the stash covers,
    /// cheapest first on a tie.
    func buildNext(limit: Int = 3) -> [(item: HajinGuide.Item, covered: Double, missing: [(String, Int)])] {
        guard let guide else { return [] }
        let upgrades = (guide.items ?? []).filter { $0.kind == "FOB Upgrade" }
        var families: [String: [HajinGuide.Item]] = [:]
        for upgrade in upgrades { families[upgrade.family ?? upgrade.id, default: []].append(upgrade) }
        let next = families.values.compactMap { tiers in
            tiers.sorted { ($0.tier ?? 0) < ($1.tier ?? 0) }.first { !checked.contains("upgrade-\($0.id)") }
        }
        return next.map { item -> (item: HajinGuide.Item, covered: Double, missing: [(String, Int)]) in
            let cost = item.cost ?? []
            let need = cost.reduce(0) { $0 + $1.qty }
            let have = cost.reduce(0) { $0 + min(count(of: $1.item), $1.qty) }
            let missing = cost.compactMap { part -> (String, Int)? in
                let short = part.qty - count(of: part.item)
                return short > 0 ? (part.item, short) : nil
            }
            // Cash only: nothing to gather, so it sits just under the printable ones
            return (item, need == 0 ? 0.99 : Double(have) / Double(need), missing)
        }
        .sorted {
            if $0.covered != $1.covered { return $0.covered > $1.covered }
            return ($0.item.cash ?? 0) < ($1.item.cash ?? 0)
        }
        .prefix(limit)
        .map { $0 }
    }

    /// Green card border for a row whose item the stash can print.
    func printableAccent(_ row: HajinGuide.Row) -> Color? {
        guard let id = row.item, let item = guide?.item(id), let next = nextToPrint(item), canPrint(next) else { return nil }
        return Self.printableGreen
    }

    /// The tier of an upgrade still to print (the first not ticked), or the
    /// item itself when it isn't an upgrade; nil once every tier is done.
    func nextToPrint(_ item: HajinGuide.Item) -> HajinGuide.Item? {
        guard item.kind == "FOB Upgrade" else { return item }
        let tiers = guide?.tiers(of: item) ?? []
        return (tiers.isEmpty ? [item] : tiers).first { !checked.contains("upgrade-\($0.id)") }
    }

    func setCount(_ count: Int, of id: String) {
        stash[id] = max(0, min(count, 99_999))
        if stash[id] == 0 { stash[id] = nil }
        saveAndSync()
    }

    /// Sets several stash counts at once (read from photos), keeping the old
    /// stash for Undo.
    func applyScannedCounts(_ counts: [String: Int]) {
        guard !counts.isEmpty else { return }
        let previous = stash, previousTracked = tracked
        for (id, count) in counts {
            stash[id] = max(0, min(count, 99_999))
            if stash[id] == 0 { stash[id] = nil }
        }
        stashUndo = StashUndo(message: String(format: "mw4.ui.hajin.scan_updated".localized(), counts.count),
                              previous: previous, previousTracked: previousTracked)
        saveAndSync()
    }

    /// Everything still missing for the tracked items: ingredient id and
    /// how many more are needed, biggest shortfall first.
    func shortfall(in guide: HajinGuide) -> [(item: HajinGuide.Item, missing: Int)] {
        var need: [String: Int] = [:]
        for id in tracked {
            for part in guide.item(id)?.cost ?? [] { need[part.item, default: 0] += part.qty }
        }
        return need.compactMap { id, qty in
            guard let item = guide.item(id) else { return nil }
            let missing = qty - count(of: id)
            return missing > 0 ? (item, missing) : nil
        }
        .sorted { $0.missing == $1.missing ? $0.item.name.resolved < $1.item.name.resolved : $0.missing > $1.missing }
    }

    func toggle(_ key: String) {
        if checked.contains(key) {
            checked.remove(key)
        } else {
            checked.insert(key)
            // Ticking an upgrade as printed uses up what it cost
            if key.hasPrefix("upgrade-") { spend(on: String(key.dropFirst("upgrade-".count))) }
        }
        saveAndSync()
    }

    /// Takes a printed item's ingredients out of the stash (only what's
    /// there) and stops tracking it, keeping the old state for Undo.
    private func spend(on id: String) {
        guard let item = guide?.item(id) else { return }
        let previous = stash, previousTracked = tracked
        var taken: [String] = []
        for part in item.cost ?? [] {
            let have = count(of: part.item)
            guard have > 0 else { continue }
            let used = min(have, part.qty)
            stash[part.item] = have - used == 0 ? nil : have - used
            taken.append("\(used) \(guide?.item(part.item)?.name.resolved ?? part.item)")
        }
        let wasTracked = tracked.contains(id)
        tracked.removeAll { $0 == id }
        guard !taken.isEmpty || wasTracked else { return }
        let message = taken.isEmpty
            ? String(format: "mw4.ui.hajin.untracked_printed".localized(), item.name.resolved)
            : String(format: "mw4.ui.hajin.took_from_stash".localized(), taken.joined(separator: ", "))
        stashUndo = StashUndo(message: message, previous: previous, previousTracked: previousTracked)
    }

    /// Puts the stash (and tracking) back as it was before the last spend.
    func undoStash() {
        guard let undo = stashUndo else { return }
        stash = undo.previous
        tracked = undo.previousTracked
        stashUndo = nil
        saveAndSync()
    }

    func setCash(_ amount: Int) {
        cash = min(max(amount, 0), 99_999_999)
        saveAndSync()
    }

    func setLevel(_ level: Int) {
        dmzLevel = min(max(level, 0), Self.maxLevel)
        saveAndSync()
    }

    /// Locked only once a level is set and it's below what's needed.
    func isLocked(_ required: Int?) -> Bool {
        guard let required, dmzLevel > 0 else { return false }
        return required > dmzLevel
    }

    /// Categories the player switched off on the map. Starts from each
    /// category's own `visible` default until they touch a filter, and so
    /// does any category added since they last did.
    var hiddenCategories: Set<String> {
        get {
            let categories = guide?.categories ?? []
            guard let saved = defaults.array(forKey: Self.hiddenKey) as? [String] else {
                return Set(categories.filter { !$0.visible }.map(\.id))
            }
            let seen = (defaults.array(forKey: Self.seenCategoriesKey) as? [String]).map(Set.init) ?? Self.firstCategories
            return Set(saved).union(categories.filter { !$0.visible && !seen.contains($0.id) }.map(\.id))
        }
        set {
            objectWillChange.send()
            defaults.set(Array(newValue).sorted(), forKey: Self.hiddenKey)
            defaults.set((guide?.categories ?? []).map(\.id), forKey: Self.seenCategoriesKey)
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

// MARK: - Operator Prestige

/// The player's operators and their Prestige, kept as tick keys so they sync
/// with the rest of My DMZ (and an older app version passes them through):
/// "prestige|<name>|<level>" and "prestige-trait|<name>|<trait>".
extension HajinStore {
    static let maxPrestigeTraits = 3

    var operators: [(name: String, level: Int)] {
        checked.compactMap { key -> (String, Int)? in
            let parts = key.split(separator: "|", omittingEmptySubsequences: false)
            guard parts.count == 3, parts[0] == "prestige", let level = Int(parts[2]) else { return nil }
            return (String(parts[1]), level)
        }
        .sorted { $0.0.localizedCaseInsensitiveCompare($1.0) == .orderedAscending }
    }

    func prestigeTraits(of name: String) -> [String] {
        checked.compactMap { key in
            let parts = key.split(separator: "|", omittingEmptySubsequences: false)
            return parts.count == 3 && parts[0] == "prestige-trait" && parts[1] == name ? String(parts[2]) : nil
        }
        .sorted()
    }

    func addOperator(_ raw: String) {
        let name = raw.replacingOccurrences(of: "|", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !operators.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else { return }
        checked.insert("prestige|\(name)|0")
        saveAndSync()
    }

    func setPrestige(_ level: Int, of name: String) {
        checked = checked.filter { !$0.hasPrefix("prestige|\(name)|") }
        checked.insert("prestige|\(name)|\(max(0, min(level, 99)))")
        saveAndSync()
    }

    func removeOperator(_ name: String) {
        checked = checked.filter { !$0.hasPrefix("prestige|\(name)|") && !$0.hasPrefix("prestige-trait|\(name)|") }
        saveAndSync()
    }

    /// Adds or removes a Prestige trait; an operator holds three at most.
    func togglePrestigeTrait(_ trait: String, of name: String) {
        let key = "prestige-trait|\(name)|\(trait)"
        if checked.contains(key) {
            checked.remove(key)
        } else {
            guard prestigeTraits(of: name).count < Self.maxPrestigeTraits else { return }
            checked.insert(key)
        }
        saveAndSync()
    }
}

