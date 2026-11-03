import Testing
import Foundation
@testable import MW4CamoTracker

/// One camo grind per weapon across modes: a camo or Completionist step
/// finished in one mode is unlocked in all of them, each mode keeping its
/// own count.
@Suite("Camos shared across modes")
@MainActor
struct SharedCamoTests {
    private let defaults: UserDefaults
    private let cache: URL

    init() {
        let name = "SharedCamoTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: name)!
        cache = FileManager.default.temporaryDirectory.appendingPathComponent(name, isDirectory: true)
    }

    private func model() -> TrackerViewModel {
        try? FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        // MW4's rules and data, whichever game the simulator last had open
        let mw4 = GameRegistry.game("mw4") ?? GameRegistry.fallback
        GameRegistry.current = mw4
        return TrackerViewModel(game: mw4, dataService: DataService(game: mw4, cacheDir: cache), defaults: defaults)
    }

    /// The HAN 86's first Special (Smoke) in a mode.
    private func special(_ vm: TrackerViewModel, _ mode: String) throws -> ChallengeItem {
        try #require(vm.camos(weaponId: 0, mode: mode).first { $0.group != "military" })
    }

    @Test func aSpecialDoneInDMZIsUnlockedInMultiplayer() throws {
        let vm = model()
        let dmz = try special(vm, "dmz"), mp = try special(vm, "multiplayer")
        #expect(!vm.isCamoComplete(mode: "multiplayer", weaponId: 0, camo: mp))
        vm.toggleCamo(mode: "dmz", weaponId: 0, camo: dmz)
        #expect(vm.isCamoComplete(mode: "multiplayer", weaponId: 0, camo: mp))
        #expect(vm.isCamoComplete(mode: "warzone", weaponId: 0, camo: try special(vm, "warzone")))
        // Multiplayer's own count is untouched
        #expect(vm.camoAmount(mode: "multiplayer", weaponId: 0, camo: mp) == 0)
    }

    @Test func progressSavedBeforeTheRuleCarriesOver() throws {
        let vm = model()
        vm.toggleCamo(mode: "dmz", weaponId: 0, camo: try special(vm, "dmz"))
        // A fresh launch reads the same saved progress
        let again = model()
        #expect(again.isCamoComplete(mode: "multiplayer", weaponId: 0, camo: try special(again, "multiplayer")))
    }

    @Test func untickingClearsItEverywhere() throws {
        let vm = model()
        vm.toggleCamo(mode: "dmz", weaponId: 0, camo: try special(vm, "dmz"))
        vm.toggleCamo(mode: "multiplayer", weaponId: 0, camo: try special(vm, "multiplayer"))
        #expect(!vm.isCamoComplete(mode: "dmz", weaponId: 0, camo: try special(vm, "dmz")))
    }

    @Test func goldDoneInOneModeCountsInAll() {
        let vm = model()
        vm.toggleCompletionist(mode: "dmz", weaponId: 0, step: 0)
        #expect(vm.isCompletionistComplete(mode: "multiplayer", weaponId: 0, step: 0))
        vm.toggleCompletionist(mode: "multiplayer", weaponId: 0, step: 0)
        #expect(!vm.isCompletionistComplete(mode: "dmz", weaponId: 0, step: 0))
    }

    /// A downloaded Warzone file, newer than the bundled one so the app
    /// starts on it, with `hidden` set as given.
    private func warzone(hidden: Bool) throws {
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        let url = try #require(Bundle.main.url(forResource: "warzone", withExtension: "json"))
        var json = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        json["version"] = "999.0.0"
        json["hidden"] = hidden
        try JSONSerialization.data(withJSONObject: json).write(to: cache.appendingPathComponent("warzone.json"))
    }

    @Test func aHiddenModeHasNoTab() throws {
        // As Warzone was until Season 1, from a fixture rather than the
        // shipped file, which the data can unhide at any time
        try warzone(hidden: true)
        let vm = model()
        #expect(vm.modes["warzone"]?.version == "999.0.0")
        #expect(!vm.visibleModes.contains(.warzone))
        #expect(vm.visibleModes.contains(.multiplayer) && vm.visibleModes.contains(.dmz))
    }

    @Test func unhidingAModeBringsItsTabBack() throws {
        try warzone(hidden: false)
        #expect(model().visibleModes.contains(.warzone))
    }
}
