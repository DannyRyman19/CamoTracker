import Testing
import Foundation
import SwiftUI
@testable import MW4CamoTracker

/// The `mastery` block a mode file can carry, laid over the built-in trio.
@Suite("Mastery overrides")
struct MasteryOverrideTests {

    private let base = MasteryCamo(
        nameKey: "mw4.ui.mercurial_drift",
        color: .red,
        gradient: [.red, .orange, .yellow],
        requirement: MasteryRequirement(amount: 3)
    )

    private func tier(_ json: String) throws -> MasteryTierConfig {
        try JSONDecoder().decode(MasteryTierConfig.self, from: Data(json.utf8))
    }

    @Test func noConfigLeavesTheCamoAlone() {
        let camo = base.applying(nil)
        #expect(camo.name == base.name)
        #expect(camo.requirement?.amount == 3)
        #expect(camo.requirement?.unit == "headshots")
        #expect(camo.gradient.count == 3)
    }

    @Test func aConfigReplacesOnlyTheFieldsItNames() throws {
        let camo = base.applying(try tier(#"{"amount": 7}"#))
        #expect(camo.requirement?.amount == 7)
        #expect(camo.requirement?.unit == "headshots")
        #expect(camo.name == base.name)
        #expect(camo.gradient.count == 3)
    }

    @Test func nameUnitAndDescriptionCanAllChange() throws {
        let camo = base.applying(try tier(#"{"name": {"en": "Override Drift"}, "unit": "longshots", "description": {"en": "Get 2 longshot kills."}}"#))
        #expect(camo.name == "Override Drift")
        #expect(camo.requirement?.unit == "longshots")
        #expect(camo.requirement?.description(camoName: camo.name) == "Get 2 longshot kills.")
    }

    @Test func anAmountBelowOneIsRaisedToOne() throws {
        #expect(base.applying(try tier(#"{"amount": 0}"#)).requirement?.amount == 1)
        #expect(base.applying(try tier(#"{"amount": -4}"#)).requirement?.amount == 1)
    }

    /// tier3 is an aggregate gate with no challenge of its own, so an amount
    /// in its config must not invent one.
    @Test func aCamoWithNoRequirementNeverGainsOne() throws {
        let capstone = MasteryCamo(nameKey: "mw4.ui.orion_reforged", color: .blue, gradient: [.blue], requirement: nil)
        #expect(capstone.applying(try tier(#"{"amount": 5}"#)).requirement == nil)
    }

    @Test func coloursComeFromHexAndBadHexFallsBack() throws {
        #expect(Color(hex: "#22CC88") != nil)
        #expect(Color(hex: "22CC88") != nil)
        #expect(Color(hex: "nope") == nil)
        #expect(Color(hex: "#FFF") == nil)
        #expect(base.applying(try tier(##"{"colors": ["#22CC88", "#0088FF"]}"##)).gradient.count == 2)
        // Every entry unreadable: keep the built-in gradient rather than none.
        #expect(base.applying(try tier(#"{"colors": ["nope", ""]}"#)).gradient.count == 3)
    }

    @Test func aModeFileDecodesWithOrWithoutTheBlock() throws {
        let plain = #"{"version": "1", "mode": "multiplayer", "weaponCamos": [], "objectives": []}"#
        #expect(try JSONDecoder().decode(ModeFile.self, from: Data(plain.utf8)).mastery == nil)
        let with = #"{"version": "1", "mode": "multiplayer", "weaponCamos": [], "objectives": [], "mastery": {"tier2": {"amount": 9}}}"#
        let file = try JSONDecoder().decode(ModeFile.self, from: Data(with.utf8))
        #expect(file.mastery?.tier2?.amount == 9)
        #expect(file.mastery?.tier1 == nil)
    }
}

/// The view model against a private save and a private cache, so nothing here
/// touches the app's real data. Serialized, and each test stays synchronous
/// between building a view model and reading it: `MasteryOverrides` is one
/// shared table, and the host app's own launch refresh also writes to it.
@MainActor
@Suite("Tracker view model", .serialized)
struct TrackerViewModelTests {

    private let defaults: UserDefaults
    private let cache: URL

    init() {
        let name = "TrackerViewModelTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        cache = FileManager.default.temporaryDirectory.appendingPathComponent(name, isDirectory: true)
    }

    /// A view model whose Multiplayer file is the bundled one plus `mastery`.
    private func model(mastery: String? = nil) throws -> TrackerViewModel {
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        let target = cache.appendingPathComponent("multiplayer.json")
        try? FileManager.default.removeItem(at: target)
        if let mastery {
            let seed = try #require(Bundle.main.url(forResource: "multiplayer", withExtension: "json"))
            var object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: seed)) as? [String: Any])
            object["mastery"] = try JSONSerialization.jsonObject(with: Data(mastery.utf8))
            try JSONSerialization.data(withJSONObject: object).write(to: target)
        }
        return TrackerViewModel(dataService: DataService(cacheDir: cache), defaults: defaults)
    }

    private func anyWeapon(_ model: TrackerViewModel) throws -> WeaponEntry {
        try #require(model.catalog?.categories.first?.weapons.first)
    }

    @Test func theModeFilesBlockReachesTheMasteryTrio() throws {
        _ = try model(mastery: #"{"tier1": {"name": {"en": "Override Drift"}, "amount": 2}}"#)
        #expect(AppMode.multiplayer.masteryCamos.tier1.name == "Override Drift")
        #expect(AppMode.multiplayer.masteryCamos.tier1.requirement?.amount == 2)
        // Untouched tiers and modes keep what the build ships with.
        #expect(AppMode.multiplayer.masteryCamos.tier2.requirement?.amount == 5)
        #expect(AppMode.warzone.masteryCamos.tier1.requirement?.amount == 3)

        _ = try model()
        #expect(AppMode.multiplayer.masteryCamos.tier1.requirement?.amount == 3)
    }

    /// Lower a requirement over the air and saved progress must not read
    /// past it; raise it again and the player's real number comes back.
    @Test func progressIsCappedOnReadButKeptOnDisk() throws {
        let high = try model(mastery: #"{"tier2": {"amount": 9}}"#)
        let weapon = try anyWeapon(high).weaponId
        high.setWeaponMasteryAmount(mode: "multiplayer", weaponId: weapon, tier: 2, amount: 8)
        #expect(high.weaponMasteryAmount(mode: "multiplayer", weaponId: weapon, tier: 2) == 8)
        #expect(high.isWeaponMasteryComplete(mode: "multiplayer", weaponId: weapon, tier: 2) == false)

        let low = try model(mastery: #"{"tier2": {"amount": 4}}"#)
        #expect(low.weaponMasteryAmount(mode: "multiplayer", weaponId: weapon, tier: 2) == 4)
        #expect(low.isWeaponMasteryComplete(mode: "multiplayer", weaponId: weapon, tier: 2))

        let again = try model(mastery: #"{"tier2": {"amount": 9}}"#)
        #expect(again.weaponMasteryAmount(mode: "multiplayer", weaponId: weapon, tier: 2) == 8)
    }

    @Test func prestigeNeedsAMaxedStageAndResetsTheLevel() throws {
        let model = try model()
        let weapon = try anyWeapon(model)
        let stages = model.prestigeStages.count
        try #require(stages > 0)

        model.setLevel(weapon.maxLevel - 1, for: weapon)
        #expect(model.canPrestige(weapon) == false)
        model.prestigeUp(weapon)
        #expect(model.prestige(for: weapon.weaponId) == 0)

        model.setLevel(weapon.maxLevel, for: weapon)
        #expect(model.canPrestige(weapon))
        model.prestigeUp(weapon)
        #expect(model.prestige(for: weapon.weaponId) == 1)
        #expect(model.level(for: weapon.weaponId) == 1)
        #expect(model.prestigeName(for: weapon.weaponId) != nil)
    }

    @Test func undoingAPrestigeLandsOnThePreviousStageMaxed() throws {
        let model = try model()
        let weapon = try anyWeapon(model)
        model.setLevel(weapon.maxLevel, for: weapon)
        model.prestigeUp(weapon)
        model.prestigeDown(weapon)
        #expect(model.prestige(for: weapon.weaponId) == 0)
        #expect(model.level(for: weapon.weaponId) == weapon.maxLevel)
        // Nothing below zero.
        model.prestigeDown(weapon)
        #expect(model.prestige(for: weapon.weaponId) == 0)
    }

    @Test func theLastStageCannotBePrestigedPast() throws {
        let model = try model()
        let weapon = try anyWeapon(model)
        for _ in 0..<(model.prestigeStages.count + 2) {
            model.setLevel(model.maxLevel(for: weapon), for: weapon)
            model.prestigeUp(weapon)
        }
        #expect(model.prestige(for: weapon.weaponId) == model.prestigeStages.count)
        model.setLevel(model.maxLevel(for: weapon), for: weapon)
        #expect(model.canPrestige(weapon) == false)
    }

    @Test func progressSurvivesANewViewModelOnTheSameSave() throws {
        let first = try model()
        let weapon = try anyWeapon(first)
        first.setLevel(weapon.maxLevel, for: weapon)
        first.prestigeUp(weapon)
        first.setLevel(7, for: weapon)

        let second = try model()
        #expect(second.prestige(for: weapon.weaponId) == 1)
        #expect(second.level(for: weapon.weaponId) == 7)
    }
}
