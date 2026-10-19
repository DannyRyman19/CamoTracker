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
        return TrackerViewModel(dataService: DataService(cacheDir: cache), defaults: defaults)
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
}
