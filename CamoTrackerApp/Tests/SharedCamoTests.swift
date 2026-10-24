import Testing
import Foundation
@testable import CamoTracker

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
        // MW4's data, whatever game the app was last left on
        let mw4 = GameRegistry.game("mw4")!
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

    @Test func aHiddenModeHasNoTab() {
        // The shipped Warzone file is hidden until Season 1
        let vm = model()
        #expect(!vm.visibleModes.contains(.warzone))
        #expect(vm.visibleModes.contains(.multiplayer) && vm.visibleModes.contains(.dmz))
    }
}

/// BO7 as a second game: its own data, modes and camo track.
@Suite("BO7 in Camo Tracker")
@MainActor
struct BO7GameTests {
    @Test func bo7LoadsItsOwnTrack() throws {
        let name = "BO7GameTests-\(UUID().uuidString)"
        let cache = FileManager.default.temporaryDirectory.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        let bo7 = try #require(GameRegistry.game("bo7"))
        GameRegistry.current = bo7
        defer { GameRegistry.current = GameRegistry.game("mw4")! }
        let model = TrackerViewModel(game: bo7, dataService: DataService(game: bo7, cacheDir: cache), defaults: UserDefaults(suiteName: name)!)

        #expect(model.totalWeaponCount == 60)
        #expect(Set(model.modes.keys) == ["multiplayer", "zombies", "warzone", "campaign"])
        #expect(AppMode.allCases.map(\.rawValue) == ["multiplayer", "zombies", "warzone", "campaign"])
        // 9 Military challenges then 3 Specials, every weapon, every mode
        #expect(model.camos(weaponId: 0, mode: "multiplayer").count == 12)
        #expect(model.camos(weaponId: 0, mode: "multiplayer").first?.requirement?.amount == 5)
        // Shattered Gold: the weapon's own challenge (3 kills without dying, 10 times)
        #expect(model.completionistRequirement(mode: "multiplayer", weaponId: 0, step: 0)?.amount == 10)
        // No account Mastery, and BO7 counts levels, not unlocks
        #expect(!GameRegistry.hasMastery)
        #expect(!model.countsUnlocks(weaponId: 0))
        #expect(!model.isMasteryAchieved(mode: "multiplayer", tier: 1))
    }
}

@Suite("BO6 in Camo Tracker")
@MainActor
struct BO6GameTests {
    @Test func bo6LoadsItsOwnTrack() throws {
        let name = "BO6GameTests-\(UUID().uuidString)"
        let cache = FileManager.default.temporaryDirectory.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        let bo6 = try #require(GameRegistry.game("bo6"))
        GameRegistry.current = bo6
        defer { GameRegistry.current = GameRegistry.game("mw4")! }
        let model = TrackerViewModel(game: bo6, dataService: DataService(game: bo6, cacheDir: cache), defaults: UserDefaults(suiteName: name)!)

        #expect(model.totalWeaponCount == 69)
        #expect(Set(model.modes.keys) == ["multiplayer", "zombies", "warzone"])
        // 9 Military then 2 Specials
        #expect(model.camos(weaponId: 0, mode: "multiplayer").count == 11)
        // Diamond needs Gold on 7 Assault Rifles, Dark Spine Diamond on 33 weapons
        let rifles = try #require(model.catalog?.categories.first { $0.categoryId == 0 })
        #expect(model.completionistCategoryGateProgress(rifles, mode: "multiplayer", step: 1).total == 7)
        #expect(model.completionistModeGateProgress(mode: "multiplayer", step: 2).total == 33)
        #expect(AppMode.multiplayer.completionist.final.name == "Dark Matter")
        #expect(model.allWeapons.count == Set(model.allWeapons.map(\.weaponId)).count)
    }
}
