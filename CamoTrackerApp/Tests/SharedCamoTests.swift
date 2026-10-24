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

@MainActor
@Suite(.serialized)
struct MW3GameTests {
    private func model(_ id: String) throws -> TrackerViewModel {
        let name = "MW3GameTests-\(UUID().uuidString)"
        let cache = FileManager.default.temporaryDirectory.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        let game = try #require(GameRegistry.game(id))
        GameRegistry.current = game
        return TrackerViewModel(game: game, dataService: DataService(game: game, cacheDir: cache), defaults: UserDefaults(suiteName: name)!)
    }

    @Test func mw3LoadsItsOwnTrack() throws {
        defer { GameRegistry.current = GameRegistry.game("mw4")! }
        let model = try model("mw3")
        #expect(model.totalWeaponCount == 60)
        #expect(Set(model.modes.keys) == ["multiplayer", "zombies"])
        // 4 base camos opening at weapon levels
        #expect(model.camos(weaponId: 0, mode: "multiplayer").map(\.unlockLevel) == [2, 13, 15, 30])
        // Forged needs Gilded on the class's 6 launch Assault Rifles, Priceless on 36
        let rifles = try #require(model.catalog?.categories.first { $0.categoryId == 0 })
        #expect(model.completionistCategoryGateProgress(rifles, mode: "multiplayer", step: 1).total == 6)
        #expect(model.completionistModeGateProgress(mode: "multiplayer", step: 2).total == 36)
        #expect(AppMode.multiplayer.completionist.final.name == "Interstellar")
        #expect(AppMode.zombies.completionist.final.name == "Borealis")
        #expect(model.allWeapons.count == Set(model.allWeapons.map(\.weaponId)).count)
    }

    @Test func mwiiLoadsItsOwnTrack() throws {
        defer { GameRegistry.current = GameRegistry.game("mw4")! }
        let model = try model("mw2")
        #expect(model.totalWeaponCount == 77)
        #expect(model.completionistModeGateProgress(mode: "multiplayer", step: 2).total == 51)
        #expect(AppMode.multiplayer.completionist.final.name == "Orion")
        #expect(AppMode.zombies.completionist.final.name == "Bioluminescent")
    }
}

@MainActor
@Suite(.serialized)
struct VanguardGameTests {
    private func model() throws -> TrackerViewModel {
        let name = "VanguardGameTests-\(UUID().uuidString)"
        let cache = FileManager.default.temporaryDirectory.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        let game = try #require(GameRegistry.game("vg"))
        GameRegistry.current = game
        return TrackerViewModel(game: game, dataService: DataService(game: game, cacheDir: cache), defaults: UserDefaults(suiteName: name)!)
    }

    @Test func aCategorySharesOneCount() throws {
        defer { GameRegistry.current = GameRegistry.game("mw4")! }
        let model = try model()
        #expect(model.totalWeaponCount == 56)
        let camos = model.camos(weaponId: 0, mode: "multiplayer")
        #expect(camos.count == 100)
        let (first, second, last) = (camos[0], camos[1], camos[9])
        // 120 eliminations earns the first three Pack Tactics camos, not the rest
        model.setCamoAmount(mode: "multiplayer", weaponId: 0, camo: last, amount: 120)
        #expect(model.isCamoComplete(mode: "multiplayer", weaponId: 0, camo: first))
        #expect(model.isCamoComplete(mode: "multiplayer", weaponId: 0, camo: camos[2]))
        #expect(!model.isCamoComplete(mode: "multiplayer", weaponId: 0, camo: camos[3]))
        #expect(model.camoAmount(mode: "multiplayer", weaponId: 0, camo: last) == 120)
        // Unticking the second steps the count back to the first's 40
        model.toggleCamo(mode: "multiplayer", weaponId: 0, camo: second)
        #expect(model.camoAmount(mode: "multiplayer", weaponId: 0, camo: last) == 40)
        #expect(model.isCamoComplete(mode: "multiplayer", weaponId: 0, camo: first))
        // Ticking the last fills the category
        model.toggleCamo(mode: "multiplayer", weaponId: 0, camo: last)
        #expect(camos[0..<10].allSatisfy { model.isCamoComplete(mode: "multiplayer", weaponId: 0, camo: $0) })
    }

    @Test func goldAndDiamondAreEarnedByThemselves() throws {
        defer { GameRegistry.current = GameRegistry.game("mw4")! }
        let model = try model()
        let rifles = try #require(model.catalog?.categories.first { $0.categoryId == 0 })
        let launch = rifles.weapons.filter { $0.weaponId < 38 }
        #expect(launch.count == 7)
        func finish(_ weaponId: Int) {
            for camo in model.camos(weaponId: weaponId, mode: "multiplayer") where !model.isCamoComplete(mode: "multiplayer", weaponId: weaponId, camo: camo) {
                model.toggleCamo(mode: "multiplayer", weaponId: weaponId, camo: camo)
            }
        }
        finish(launch[0].weaponId)
        #expect(model.isCompletionistComplete(mode: "multiplayer", weaponId: launch[0].weaponId, step: 0))
        #expect(!model.isCompletionistComplete(mode: "multiplayer", weaponId: launch[0].weaponId, step: 1))
        // Ticking an automatic step does nothing
        model.toggleCompletionist(mode: "multiplayer", weaponId: launch[0].weaponId, step: 1)
        #expect(!model.isCompletionistComplete(mode: "multiplayer", weaponId: launch[0].weaponId, step: 1))
        launch.dropFirst().forEach { finish($0.weaponId) }
        #expect(model.isCompletionistComplete(mode: "multiplayer", weaponId: launch[0].weaponId, step: 1))
        #expect(!model.isCompletionistComplete(mode: "multiplayer", weaponId: launch[0].weaponId, step: 2))
        #expect(AppMode.multiplayer.completionist.steps.map(\.name) == ["Gold", "Diamond", "Atomic"])
    }
}

@MainActor
@Suite(.serialized)
struct ColdWarGameTests {
    @Test func darkMatterNeedsDiamondInEveryMainClass() throws {
        defer { GameRegistry.current = GameRegistry.game("mw4")! }
        let name = "ColdWarGameTests-\(UUID().uuidString)"
        let cache = FileManager.default.temporaryDirectory.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        let game = try #require(GameRegistry.game("cw"))
        GameRegistry.current = game
        let model = TrackerViewModel(game: game, dataService: DataService(game: game, cacheDir: cache), defaults: UserDefaults(suiteName: name)!)
        #expect(model.totalWeaponCount == 63)
        #expect(model.camos(weaponId: 0, mode: "zombies").count == 35)
        func finish(_ weaponId: Int) {
            for camo in model.camos(weaponId: weaponId, mode: "multiplayer") where !model.isCamoComplete(mode: "multiplayer", weaponId: weaponId, camo: camo) {
                model.toggleCamo(mode: "multiplayer", weaponId: weaponId, camo: camo)
            }
        }
        let categories = try #require(model.catalog?.categories)
        // Two Golds per main class: Diamond on both, Dark Matter once all seven have it
        let main = categories.filter { $0.weapons.count >= 2 && ![7, 8].contains($0.categoryId) }
        #expect(main.count == 7)
        #expect(model.completionistModeGateProgress(mode: "multiplayer", step: 2) == (0, 7))
        for (index, category) in main.enumerated() {
            category.weapons.prefix(2).forEach { finish($0.weaponId) }
            #expect(model.isCompletionistComplete(mode: "multiplayer", weaponId: category.weapons[0].weaponId, step: 1))
            #expect(model.isCompletionistComplete(mode: "multiplayer", weaponId: category.weapons[0].weaponId, step: 2) == (index == main.count - 1))
        }
        #expect(AppMode.zombies.completionist.steps.map(\.name) == ["Golden Viper", "Plague Diamond", "Dark Aether"])
    }
}

@MainActor
@Suite(.serialized)
struct MW2019GameTests {
    @Test func freeCamosAndDamascus() throws {
        defer { GameRegistry.current = GameRegistry.game("mw4")! }
        let name = "MW2019GameTests-\(UUID().uuidString)"
        let cache = FileManager.default.temporaryDirectory.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        let game = try #require(GameRegistry.game("mw19"))
        GameRegistry.current = game
        let model = TrackerViewModel(game: game, dataService: DataService(game: game, cacheDir: cache), defaults: UserDefaults(suiteName: name)!)
        #expect(model.totalWeaponCount == 62)
        #expect(Set(model.modes.keys) == ["multiplayer"])
        let camos = model.camos(weaponId: 0, mode: "multiplayer")
        // The first camo of each category is free, and tapping it changes nothing
        #expect(model.isCamoComplete(mode: "multiplayer", weaponId: 0, camo: camos[0]))
        model.setCamoAmount(mode: "multiplayer", weaponId: 0, camo: camos[9], amount: 60)
        model.toggleCamo(mode: "multiplayer", weaponId: 0, camo: camos[0])
        #expect(model.isCamoComplete(mode: "multiplayer", weaponId: 0, camo: camos[0]))
        #expect(model.camoAmount(mode: "multiplayer", weaponId: 0, camo: camos[9]) == 60)
        #expect(model.isCamoComplete(mode: "multiplayer", weaponId: 0, camo: camos[2]))
        #expect(!model.isCamoComplete(mode: "multiplayer", weaponId: 0, camo: camos[3]))
        #expect(model.completionistModeGateProgress(mode: "multiplayer", step: 2) == (0, 8))
        #expect(AppMode.multiplayer.completionist.steps.map(\.name) == ["Gold", "Platinum", "Damascus"])
    }
}
