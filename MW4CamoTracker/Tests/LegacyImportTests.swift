import Foundation
import Testing
@testable import MW4CamoTracker

/// The BO6 and BO7 apps' exports share weapon names (the Knife), so each
/// game takes only its own old app's file.
struct LegacyImportTests {
    private let bo6Export: Any = ["multiplayer": [["Weapons": [["WeaponName": "Knife", "CurrentLevel": 5]]]]]
    private let bo7Export: Any = [["Weapons": [["WeaponName": "Knife", "CurrentLevel": 5]]]]

    private func game(_ id: String) throws -> Game { try #require(GameRegistry.game(id)) }

    @Test func eachGameTakesItsOwnExport() throws {
        #expect(LegacyImport.exportGame(bo6Export) == "bo6")
        #expect(LegacyImport.exportGame(bo7Export) == "bo7")
        #expect(LegacyImport.exportGame(["weapons": bo7Export]) == "bo7")
        #expect(LegacyImport.exportGame(["something": 1]) == nil)
        try LegacyImport.check(bo6Export, isFor: game("bo6"))
        try LegacyImport.check(bo7Export, isFor: game("bo7"))
    }

    @Test func theOtherGamesExportIsRefused() throws {
        let bo6 = try game("bo6"), bo7 = try game("bo7")
        do {
            try LegacyImport.check(bo6Export, isFor: bo7)
            Issue.record("BO6's export went into BO7")
        } catch LegacyImport.Failure.otherGame(let other) {
            #expect(other.id == "bo6")
        }
        do {
            try LegacyImport.check(bo7Export, isFor: bo6)
            Issue.record("BO7's export went into BO6")
        } catch LegacyImport.Failure.otherGame(let other) {
            #expect(other.id == "bo7")
        }
    }
}

/// MW3 and MW2 (the MWII guns carried into MW3), each with its own camo
/// chains and the game's unlock counts, and the old MW3 Camo Tracker's
/// export brought into both by position.
@Suite("MW3")
@MainActor
struct MW3Tests {
    private let defaults: UserDefaults
    private let cache: URL

    init() {
        let name = "MW3Tests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: name)!
        cache = FileManager.default.temporaryDirectory.appendingPathComponent(name, isDirectory: true)
    }

    private func model(_ id: String = "mw3") throws -> TrackerViewModel {
        try? FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        let game = try #require(GameRegistry.game(id))
        GameRegistry.current = game
        return TrackerViewModel(game: game, dataService: DataService(game: game, cacheDir: cache), defaults: defaults)
    }

    /// Every base camo on a weapon, earned
    private func finishCamos(_ vm: TrackerViewModel, mode: String, weaponId: Int) {
        for camo in vm.camos(weaponId: weaponId, mode: mode) where !vm.isCamoComplete(mode: mode, weaponId: weaponId, camo: camo) {
            vm.setCamoAmount(mode: mode, weaponId: weaponId, camo: camo, amount: camo.requirement?.amount ?? 1)
        }
    }

    @Test func eachGameHasItsOwnGuns() throws {
        let mw3 = try model()
        #expect(mw3.totalWeaponCount == 60)
        #expect(mw3.launchRoster == 36)
        #expect(!mw3.allWeapons.contains { $0.name.resolved() == "M4" })
        let mw2 = try model("mw2")
        #expect(mw2.totalWeaponCount == 77)
        #expect(mw2.launchRoster == 51)
    }

    @Test func mw2PlatinumWaitsForTheClassAndPolyatomicFor51() throws {
        let vm = try model("mw2")
        let ars = try #require(vm.catalog?.categories.first)
        let launch = ars.weapons.filter { $0.weaponId < vm.baseWeaponCount }
        #expect(launch.count == 8)
        for weapon in launch.dropLast() {
            finishCamos(vm, mode: "multiplayer", weaponId: weapon.weaponId)
            vm.toggleCompletionist(mode: "multiplayer", weaponId: weapon.weaponId, step: 0)
        }
        let first = launch[0].weaponId
        #expect(!vm.isCompletionistAvailable(mode: "multiplayer", weaponId: first, step: 1))
        finishCamos(vm, mode: "multiplayer", weaponId: launch[7].weaponId)
        vm.toggleCompletionist(mode: "multiplayer", weaponId: launch[7].weaponId, step: 0)
        #expect(vm.isCompletionistAvailable(mode: "multiplayer", weaponId: first, step: 1))
        #expect(vm.completionistModeGateProgress(mode: "multiplayer", step: 2).total == 51)
    }

    @Test func forgedWaitsForGildedAcrossTheClass() throws {
        let vm = try model()
        // SVA 545 (0), the first of MW3's six launch Assault Rifles
        finishCamos(vm, mode: "multiplayer", weaponId: 0)
        #expect(vm.isCompletionistAvailable(mode: "multiplayer", weaponId: 0, step: 0))
        vm.toggleCompletionist(mode: "multiplayer", weaponId: 0, step: 0)
        #expect(!vm.isCompletionistAvailable(mode: "multiplayer", weaponId: 0, step: 1))
        for id in 1...5 {
            finishCamos(vm, mode: "multiplayer", weaponId: id)
            vm.toggleCompletionist(mode: "multiplayer", weaponId: id, step: 0)
        }
        #expect(vm.isCompletionistAvailable(mode: "multiplayer", weaponId: 0, step: 1))
        // Priceless needs Forged on 36 weapons
        vm.toggleCompletionist(mode: "multiplayer", weaponId: 0, step: 1)
        #expect(!vm.isCompletionistAvailable(mode: "multiplayer", weaponId: 0, step: 2))
        #expect(vm.completionistModeGateProgress(mode: "multiplayer", step: 2).total == 36)
    }

    @Test func zombiesStepsOpenOnTheWeaponAlone() throws {
        let vm = try model()
        finishCamos(vm, mode: "zombies", weaponId: 0)
        vm.toggleCompletionist(mode: "zombies", weaponId: 0, step: 0)
        #expect(vm.isCompletionistAvailable(mode: "zombies", weaponId: 0, step: 1))
        #expect(vm.harmonicBreaksNeeded(mode: "zombies") == 36)
        #expect(try model("mw2").harmonicBreaksNeeded(mode: "zombies") == 51)
    }

    @Test func badgesAndPrestigeWaitTheirTurn() throws {
        let vm = try model()
        let all = vm.allCamos(weaponId: 0, mode: "multiplayer")
        let gildedKills = try #require(all.first { $0.itemId == 100 })
        let oneTrick = try #require(all.first { $0.itemId == 200 })
        let molten = try #require(all.first { $0.itemId == 201 })
        #expect(!vm.isCamoAvailable(mode: "multiplayer", weaponId: 0, camo: gildedKills))
        finishCamos(vm, mode: "multiplayer", weaponId: 0)
        vm.toggleCompletionist(mode: "multiplayer", weaponId: 0, step: 0)
        #expect(vm.isCamoAvailable(mode: "multiplayer", weaponId: 0, camo: gildedKills))
        // Prestige camos: max level first, then each after the one before
        #expect(!vm.isCamoAvailable(mode: "multiplayer", weaponId: 0, camo: oneTrick))
        let weapon = try #require(vm.weapon(id: 0))
        vm.setLevel(weapon.maxLevel, for: weapon)
        #expect(vm.isCamoAvailable(mode: "multiplayer", weaponId: 0, camo: oneTrick))
        #expect(!vm.isCamoAvailable(mode: "multiplayer", weaponId: 0, camo: molten))
        vm.toggleCamo(mode: "multiplayer", weaponId: 0, camo: oneTrick)
        #expect(vm.isCamoAvailable(mode: "multiplayer", weaponId: 0, camo: molten))
    }

    /// A whole export as the old app writes one: its own four lists
    /// (Data/MW3/Updated_*.json, what it downloaded and saved), every weapon
    /// on level picker index 9 with its first camo at 7.
    @Test func aFullExportSetsEveryWeaponsLevel() throws {
        let data = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../Data/MW3").standardized
        var lists: [Any] = []
        for name in ["Updated_MultiplayerWeapons", "Updated_ZombiesWeapons", "Updated_MW2MultiplayerWeapons", "Updated_MW2ZombiesWeapons"] {
            var raw = try Data(contentsOf: data.appendingPathComponent("\(name).json"))
            if raw.starts(with: [0xEF, 0xBB, 0xBF]) { raw = raw.dropFirst(3) }
            var categories = try #require(try JSONSerialization.jsonObject(with: raw) as? [[String: Any]])
            for c in categories.indices {
                var weapons = try #require(categories[c]["Weapons"] as? [[String: Any]])
                for w in weapons.indices {
                    weapons[w]["CurrentLevel"] = 9
                    var camos = try #require(weapons[w]["Camos"] as? [[String: Any]])
                    camos[0]["CurrentAmount"] = 7
                    weapons[w]["Camos"] = camos
                }
                categories[c]["Weapons"] = weapons
            }
            lists.append(categories)
        }
        let export = try JSONSerialization.data(withJSONObject: lists)
        for (id, count) in [("mw3", 60), ("mw2", 77)] {
            let vm = try model(id)
            let progress = try LegacyImport.read(export, into: vm)
            // Every weapon found by name, none left behind
            #expect(progress.weapons.count == count)
            vm.applyImport(progress)
            for weapon in vm.allWeapons {
                #expect(vm.level(for: weapon.weaponId) == min(10, weapon.maxLevel), "\(id) \(weapon.name.resolved())")
                let first = try #require(vm.camos(weaponId: weapon.weaponId, mode: "multiplayer").first)
                #expect(vm.camoAmount(mode: "multiplayer", weaponId: weapon.weaponId, camo: first) == min(7, first.requirement?.amount ?? 7))
            }
        }
    }

    /// The older MW2 Camo Tracker's file: one list of MWII Multiplayer guns,
    /// as its exports look (the level picker's index, mastery kill counts
    /// beside the camos).
    @Test func theMW2AppsExportImportsIntoMW2() throws {
        let export: [[String: Any]] = [["WeaponCategoryID": 0, "Weapons": [[
            "WeaponName": "M4", "WeaponPlatform": 1, "MaxLevel": 20, "CurrentLevel": 19,
            "Camos": [["CurrentAmount": 50], ["CurrentAmount": 50]],
            "MasteryCamos": [["CurrentAmount": 10], ["CurrentAmount": 25], ["CurrentAmount": 4]],
            "GoldMasteryCurrentAmount": 60, "PlatinumMasteryCurrentAmount": 0,
            "PolyatomicMasteryCurrentAmount": 0, "OrionMasteryCurrentAmount": 0,
        ]]]]
        #expect(LegacyImport.exportGame(export) == "mw2")
        // Not BO7's one list, and not for MW3
        #expect(throws: LegacyImport.Failure.self) { try LegacyImport.check(export, isFor: try #require(GameRegistry.game("mw3"))) }
        let vm = try model("mw2")
        try LegacyImport.check(export, isFor: vm.game)
        vm.applyImport(try LegacyImport.read(try JSONSerialization.data(withJSONObject: export), into: vm))
        let m4 = try #require(vm.allWeapons.first { $0.name.resolved() == "M4" })
        #expect(vm.level(for: m4.weaponId) == 20)
        let scales = try #require(vm.camos(weaponId: m4.weaponId, mode: "multiplayer").first)
        #expect(vm.camoAmount(mode: "multiplayer", weaponId: m4.weaponId, camo: scales) == 50)
        #expect(vm.isCompletionistComplete(mode: "multiplayer", weaponId: m4.weaponId, step: 1))
        #expect(vm.completionistAmount(mode: "multiplayer", weaponId: m4.weaponId, step: 2) == 4)
        let goldKills = try #require(vm.allCamos(weaponId: m4.weaponId, mode: "multiplayer").first { $0.itemId == 100 })
        #expect(vm.camoAmount(mode: "multiplayer", weaponId: m4.weaponId, camo: goldKills) == 60)
    }

    /// An old app's counts can trail its own requirements (BO7's raised
    /// Hunter); a Mastery camo it has means the camo list was done.
    @Test func anEarnedMasteryCamoFinishesTheCamoList() throws {
        let vm = try model()
        let export: [[[String: Any]]] = [
            [["Weapons": [["WeaponName": "SVA 545", "CurrentLevel": 29,
                           "Camos": [["CurrentAmount": 50], ["CurrentAmount": 10]],
                           "CompletionistCamos": [["CurrentAmount": 99]]]]]],
            [], [], [],
        ]
        vm.applyImport(try LegacyImport.read(try JSONSerialization.data(withJSONObject: export), into: vm))
        #expect(vm.allCamosComplete(weaponId: 0, mode: "multiplayer"))
        #expect(vm.isCompletionistComplete(mode: "multiplayer", weaponId: 0, step: 0))
        #expect(!vm.allCamosComplete(weaponId: 0, mode: "zombies"))
    }

    @Test func theOldAppsExportImports() throws {
        let vm = try model()
        func weapon(_ name: String, level: Int, camo: Int) -> [String: Any] {
            ["WeaponName": name, "CurrentLevel": level,
             "Camos": [["CurrentAmount": camo]], "CompletionistCamos": [["CurrentAmount": 3]],
             "MasteryChallenges": [["CurrentAmount": 40]], "PrestigeChallenges": [["CurrentAmount": 0]]]
        }
        let export: [[[String: Any]]] = [
            [["Weapons": [weapon("SVA 545", level: 9, camo: 50)]]],
            [["Weapons": [weapon("SVA 545", level: 3, camo: 20)]]],
            [["Weapons": [weapon("M4", level: 4, camo: 12)]]],
            [],
        ]
        #expect(LegacyImport.exportGame(export) == "mw3")
        try LegacyImport.check(export, isFor: try #require(GameRegistry.game("mw2")))
        let data = try JSONSerialization.data(withJSONObject: export)
        vm.applyImport(try LegacyImport.read(data, into: vm))
        // The level picker's index, so level 10; the highest copy wins
        #expect(vm.level(for: 0) == 10)
        let blueTones = try #require(vm.camos(weaponId: 0, mode: "multiplayer").first)
        #expect(vm.camoAmount(mode: "multiplayer", weaponId: 0, camo: blueTones) == 50)
        #expect(vm.completionistAmount(mode: "multiplayer", weaponId: 0, step: 0) == 3)
        // The MWII lists go to MW2, not onto MW3's guns
        let mw2 = try model("mw2")
        mw2.applyImport(try LegacyImport.read(data, into: mw2))
        let m4 = try #require(mw2.allWeapons.first { $0.name.resolved() == "M4" })
        #expect(mw2.level(for: m4.weaponId) == 5)
        let scales = try #require(mw2.camos(weaponId: m4.weaponId, mode: "multiplayer").first)
        #expect(mw2.camoAmount(mode: "multiplayer", weaponId: m4.weaponId, camo: scales) == 12)
    }
}
