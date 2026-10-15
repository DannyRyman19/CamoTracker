import Testing
import Foundation
import SwiftUI
@testable import MW4CamoTracker

/// The `mastery` and `completionist` blocks a mode file can carry, laid over
/// the built-in camos.
@Suite("Mastery overrides")
struct MasteryOverrideTests {

    private let base = MasteryCamo(nameKey: "mw4.ui.mercurial_drift", color: .red, gradient: [.red, .orange, .yellow])

    private func tier(_ json: String) throws -> MasteryTierConfig {
        try JSONDecoder().decode(MasteryTierConfig.self, from: Data(json.utf8))
    }

    @Test func noConfigLeavesTheCamoAlone() {
        let camo = base.applying(nil)
        #expect(camo.name == base.name)
        #expect(camo.weaponsNeeded == nil)
        #expect(camo.gradient.count == 3)
    }

    @Test func aConfigReplacesOnlyTheFieldsItNames() throws {
        let camo = base.applying(try tier(#"{"weaponsNeeded": 7}"#))
        #expect(camo.weaponsNeeded == 7)
        #expect(camo.name == base.name)
        #expect(camo.gradient.count == 3)
        #expect(base.applying(try tier(#"{"name": {"en": "Override Drift"}}"#)).name == "Override Drift")
    }

    @Test func aThresholdBelowOneIsRaisedToOne() throws {
        #expect(base.applying(try tier(#"{"weaponsNeeded": 0}"#)).weaponsNeeded == 1)
        #expect(base.applying(try tier(#"{"weaponsNeeded": -4}"#)).weaponsNeeded == 1)
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

    @Test func aModeFileDecodesWithOrWithoutTheBlocks() throws {
        let plain = #"{"version": "1", "mode": "multiplayer", "weaponCamos": [], "objectives": []}"#
        let bare = try JSONDecoder().decode(ModeFile.self, from: Data(plain.utf8))
        #expect(bare.mastery == nil)
        #expect(bare.completionist == nil)
        let with = #"""
            {"version": "1", "mode": "multiplayer", "weaponCamos": [], "objectives": [],
             "mastery": {"tier2": {"weaponsNeeded": 9}},
             "completionist": {"steps": [{"requirement": {"amount": 1, "unit": "matches", "description": {"en": "Win."}}}],
                               "final": {"name": {"en": "Divergence"}, "harmonicBreaksNeeded": 5}}}
            """#
        let file = try JSONDecoder().decode(ModeFile.self, from: Data(with.utf8))
        #expect(file.mastery?.tier2?.weaponsNeeded == 9)
        #expect(file.mastery?.tier1 == nil)
        #expect(file.completionist?.final?.harmonicBreaksNeeded == 5)
        #expect(file.completionist?.steps?.first?.requirement?.amount == 1)
    }
}

/// The view model against a private save and a private cache, so nothing here
/// touches the app's real data. Serialized, and each test stays synchronous
/// between building a view model and reading it: the override tables are
/// shared, and the host app's own launch refresh also writes to them.
@MainActor
@Suite("Tracker view model", .serialized)
struct TrackerViewModelTests {

    private let defaults: UserDefaults
    private let cache: URL
    private let mp = "multiplayer"

    init() {
        let name = "TrackerViewModelTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        cache = FileManager.default.temporaryDirectory.appendingPathComponent(name, isDirectory: true)
    }

    /// A view model whose Multiplayer file is the bundled one with `blocks`
    /// (top-level key to JSON) laid over it.
    private func model(_ blocks: [String: String] = [:]) throws -> TrackerViewModel {
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        let target = cache.appendingPathComponent("multiplayer.json")
        try? FileManager.default.removeItem(at: target)
        if !blocks.isEmpty {
            let seed = try #require(Bundle.main.url(forResource: "multiplayer", withExtension: "json"))
            var object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: seed)) as? [String: Any])
            for (key, json) in blocks {
                object[key] = try JSONSerialization.jsonObject(with: Data(json.utf8))
            }
            try JSONSerialization.data(withJSONObject: object).write(to: target)
        }
        return TrackerViewModel(dataService: DataService(cacheDir: cache), defaults: defaults)
    }

    private func anyWeapon(_ model: TrackerViewModel) throws -> WeaponEntry {
        try #require(model.catalog?.categories.first?.weapons.first)
    }

    private func weapons(_ model: TrackerViewModel) -> [WeaponEntry] {
        model.catalog?.categories.flatMap(\.weapons) ?? []
    }

    /// Ticks every camo in the weapon's list, opening its Completionist camos.
    private func finishCamos(_ model: TrackerViewModel, _ weaponId: Int) {
        for camo in model.camos(weaponId: weaponId, mode: mp) where !model.isCamoComplete(mode: mp, weaponId: weaponId, camo: camo) {
            model.toggleCamo(mode: mp, weaponId: weaponId, camo: camo)
        }
    }

    /// Gold, Platinum and Harmonic Break on one weapon.
    private func harmonicBreak(_ model: TrackerViewModel, _ weaponId: Int) {
        finishCamos(model, weaponId)
        for step in 0..<TrackerViewModel.completionistStepCount where !model.isCompletionistComplete(mode: mp, weaponId: weaponId, step: step) {
            model.toggleCompletionist(mode: mp, weaponId: weaponId, step: step)
        }
    }

    @Test func theModeFilesBlocksReachTheCamos() throws {
        let configured = try model([
            "mastery": #"{"tier1": {"name": {"en": "Override Drift"}, "weaponsNeeded": 2}}"#,
            "completionist": #"{"final": {"name": {"en": "Divergence"}}}"#,
        ])
        #expect(AppMode.multiplayer.masteryCamos.tier1.name == "Override Drift")
        #expect(configured.masteryWeaponsNeeded(mode: mp, tier: 1) == 2)
        #expect(AppMode.multiplayer.completionist.final.name == "Divergence")
        // Untouched modes keep what the build ships with.
        #expect(AppMode.warzone.completionist.final.name != "Divergence")

        _ = try model()
        #expect(AppMode.multiplayer.masteryCamos.tier1.name != "Override Drift")
    }

    /// With no published counts, Mastery needs a third, two thirds and all of
    /// the launch roster.
    @Test func masteryDefaultsToThirdsOfTheRoster() throws {
        let model = try model()
        let roster = min(model.totalWeaponCount, model.baseWeaponCount)
        #expect(model.masteryWeaponsNeeded(mode: mp, tier: 3) == roster)
        #expect(model.masteryWeaponsNeeded(mode: mp, tier: 1) == Int((Double(roster) / 3).rounded(.up)))
    }

    @Test func goldOpensOnceTheWeaponsCamoListIsDone() throws {
        let model = try model()
        let weapon = try anyWeapon(model).weaponId
        #expect(model.isCompletionistAvailable(mode: mp, weaponId: weapon, step: 0) == false)
        finishCamos(model, weapon)
        #expect(model.isCompletionistAvailable(mode: mp, weaponId: weapon, step: 0))
    }

    /// Platinum opens once every weapon in the class has Gold, not just this one.
    @Test func platinumWaitsForGoldAcrossTheClass() throws {
        let model = try model()
        let category = try #require(model.catalog?.categories.first { $0.weapons.count > 1 })
        let first = category.weapons[0].weaponId
        finishCamos(model, first)
        model.toggleCompletionist(mode: mp, weaponId: first, step: 0)
        #expect(model.isCompletionistAvailable(mode: mp, weaponId: first, step: 1) == false)

        for weapon in category.weapons.dropFirst() {
            finishCamos(model, weapon.weaponId)
            model.toggleCompletionist(mode: mp, weaponId: weapon.weaponId, step: 0)
        }
        #expect(model.isCompletionistAvailable(mode: mp, weaponId: first, step: 1))
        // Still needs this weapon's own Gold: a class-mate's isn't enough.
        let other = try #require(model.catalog?.categories.first { $0.categoryId != category.categoryId }?.weapons.first).weaponId
        #expect(model.isCompletionistAvailable(mode: mp, weaponId: other, step: 1) == false)
    }

    /// Platinum counts against the class's launch roster, so a DLC weapon
    /// can stand in for a launch one: with only one launch Assault Rifle,
    /// Gold on any one Assault Rifle opens Platinum for the class.
    @Test func platinumCountsTheClassLaunchRoster() throws {
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        let seed = try #require(Bundle.main.url(forResource: "weapons", withExtension: "json"))
        var catalog = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: seed)) as? [String: Any])
        catalog["baseWeaponCount"] = 1
        try JSONSerialization.data(withJSONObject: catalog).write(to: cache.appendingPathComponent("weapons.json"))
        defer { try? FileManager.default.removeItem(at: cache.appendingPathComponent("weapons.json")) }

        let model = try model()
        let rifles = try #require(model.catalog?.categories.first { $0.categoryId == 0 })
        try #require(rifles.weapons.count > 1)
        let dlcStandIn = rifles.weapons[1].weaponId
        finishCamos(model, dlcStandIn)
        model.toggleCompletionist(mode: mp, weaponId: dlcStandIn, step: 0)
        #expect(model.completionistCategoryGateProgress(rifles, mode: mp, step: 1) == (1, 1))
        #expect(model.isCompletionistAvailable(mode: mp, weaponId: dlcStandIn, step: 1))
    }

    /// Harmonic Break opens once the whole launch roster has Platinum.
    @Test func harmonicBreakWaitsForPlatinumOnEveryWeapon() throws {
        let model = try model()
        let all = weapons(model).map(\.weaponId)
        for weapon in all.dropLast() {
            model.toggleCompletionist(mode: mp, weaponId: weapon, step: 1)
        }
        #expect(model.isCompletionistAvailable(mode: mp, weaponId: all[0], step: 2) == false)
        #expect(model.completionistModeGateProgress(mode: mp, step: 2).done == all.count - 1)
        model.toggleCompletionist(mode: mp, weaponId: all.last!, step: 1)
        #expect(model.isCompletionistAvailable(mode: mp, weaponId: all[0], step: 2))
    }

    /// The mode file can loosen a gate, e.g. Platinum on the weapon alone.
    @Test func aModeFileCanChangeAGate() throws {
        let model = try model(["completionist": #"{"steps": [{}, {"unlock": "weapon"}]}"#])
        let weapon = try anyWeapon(model).weaponId
        finishCamos(model, weapon)
        model.toggleCompletionist(mode: mp, weaponId: weapon, step: 0)
        #expect(model.completionistGate(mode: mp, step: 1) == .weapon)
        #expect(model.isCompletionistAvailable(mode: mp, weaponId: weapon, step: 1))
    }

    /// Platinum's challenge can differ by weapon category; a category with
    /// none of its own uses the step's default.
    @Test func aCategoryCanHaveItsOwnChallenge() throws {
        let model = try model(["completionist": #"""
            {"steps": [{}, {"requirement": {"amount": 20, "unit": "kills", "description": {"en": "Default."}},
                            "byCategory": {"0": {"amount": 50, "unit": "headshots", "description": {"en": "Rifles."}}}}]}
            """#])
        let categories = try #require(model.catalog?.categories)
        let rifle = try #require(categories.first { $0.categoryId == 0 }?.weapons.first).weaponId
        let other = try #require(categories.first { $0.categoryId != 0 }?.weapons.first).weaponId
        #expect(model.completionistRequirement(mode: mp, weaponId: rifle, step: 1)?.amount == 50)
        #expect(model.completionistRequirement(mode: mp, weaponId: other, step: 1)?.amount == 20)
        #expect(model.completionistRequirement(mode: mp, weaponId: rifle, step: 0) == nil)
    }

    /// Lower a challenge over the air and saved progress must not read past
    /// it; raise it again and the player's real number comes back.
    @Test func progressIsCappedOnReadButKeptOnDisk() throws {
        func steps(_ amount: Int) -> [String: String] {
            ["completionist": #"{"steps": [{}, {"requirement": {"amount": \#(amount), "unit": "kills", "description": {"en": "x"}}}]}"#]
        }
        let high = try model(steps(9))
        let weapon = try anyWeapon(high).weaponId
        high.setCompletionistAmount(mode: mp, weaponId: weapon, step: 1, amount: 8)
        #expect(high.completionistAmount(mode: mp, weaponId: weapon, step: 1) == 8)
        #expect(high.isCompletionistComplete(mode: mp, weaponId: weapon, step: 1) == false)

        let low = try model(steps(4))
        #expect(low.completionistAmount(mode: mp, weaponId: weapon, step: 1) == 4)
        #expect(low.isCompletionistComplete(mode: mp, weaponId: weapon, step: 1))

        let again = try model(steps(9))
        #expect(again.completionistAmount(mode: mp, weaponId: weapon, step: 1) == 8)
    }

    /// The final camo needs the weapon's own Harmonic Break and enough
    /// Harmonic Breaks across the mode; reaching that count unlocks it on
    /// every weapon that has one.
    @Test func theFinalCamoWaitsForTheModesHarmonicBreakCount() throws {
        let model = try model(["completionist": #"{"final": {"harmonicBreaksNeeded": 3}}"#])
        let ids = weapons(model).prefix(3).map(\.weaponId)
        harmonicBreak(model, ids[0])
        harmonicBreak(model, ids[1])
        #expect(model.hasFinalCamo(mode: mp, weaponId: ids[0]) == false)
        #expect(model.finalCamoCount(mode: mp) == 0)

        harmonicBreak(model, ids[2])
        #expect(ids.allSatisfy { model.hasFinalCamo(mode: mp, weaponId: $0) })
        #expect(model.finalCamoCount(mode: mp) == 3)
        // A weapon without its own Harmonic Break never has it.
        let other = try #require(weapons(model).dropFirst(3).first).weaponId
        #expect(model.hasFinalCamo(mode: mp, weaponId: other) == false)
    }

    /// Mastery tiers unlock in order as weapons earn the final camo.
    @Test func masteryUnlocksAsWeaponsEarnTheFinalCamo() throws {
        let model = try model([
            "mastery": #"{"tier1": {"weaponsNeeded": 1}, "tier2": {"weaponsNeeded": 2}, "tier3": {"weaponsNeeded": 3}}"#,
            "completionist": #"{"final": {"harmonicBreaksNeeded": 0}}"#,
        ])
        let ids = weapons(model).prefix(3).map(\.weaponId)
        #expect(model.isMasteryAchieved(mode: mp, tier: 1) == false)
        harmonicBreak(model, ids[0])
        #expect(model.isMasteryAchieved(mode: mp, tier: 1))
        #expect(model.isMasteryAchieved(mode: mp, tier: 2) == false)
        #expect(model.masteryProgress(mode: mp, tier: 2).done == 1)
        harmonicBreak(model, ids[1])
        harmonicBreak(model, ids[2])
        #expect(model.isMasteryAchieved(mode: mp, tier: 3))
    }

    /// Stats counts each Completionist camo across the mode, and a class's
    /// full-track figure moves with Completionist, not just its camo lists.
    @Test func statsCountTheCompletionistTrack() throws {
        let model = try model(["completionist": #"{"final": {"harmonicBreaksNeeded": 0}}"#])
        let category = try #require(model.catalog?.categories.first)
        let weapon = try #require(category.weapons.first).weaponId
        finishCamos(model, weapon)
        let afterCamos = model.categoryTrueCompletionFraction(category, mode: mp)
        #expect(model.completionistCount(mode: mp, step: 0) == 0)

        harmonicBreak(model, weapon)
        #expect(model.completionistCount(mode: mp, step: 0) == 1)
        #expect(model.completionistCount(mode: mp, step: 2) == 1)
        #expect(model.completionistCount(mode: mp, step: TrackerViewModel.completionistStepCount) == 1)
        #expect(model.categoryTrueCompletionFraction(category, mode: mp) > afterCamos)
    }

    private func split(_ model: TrackerViewModel, _ weaponId: Int) -> (military: [ChallengeItem], special: [ChallengeItem]) {
        let camos = model.camos(weaponId: weaponId, mode: mp)
        return (camos.filter { $0.group == "military" }, camos.filter { $0.group == "special" })
    }

    /// With no published levels, the Military camos are spread up to the
    /// weapon's max level, the last one on max itself.
    @Test func militaryLevelsAreSpreadUpToMaxUntilPublished() throws {
        let model = try model()
        let weapon = try anyWeapon(model)
        let military = split(model, weapon.weaponId).military
        try #require(military.count == 8)
        let max = model.maxLevel(for: weapon)
        #expect(model.militaryLevel(mode: mp, weaponId: weapon.weaponId, camo: military.last!) == max)
        #expect(model.militaryLevel(mode: mp, weaponId: weapon.weaponId, camo: military[0]) == Int((Double(max) / 8).rounded(.up)))
    }

    /// Tapping a Military camo sets the weapon level to it; tapping an earned
    /// one steps the level back to just below it.
    @Test func tappingAMilitaryCamoSetsTheWeaponLevel() throws {
        let model = try model()
        let weapon = try anyWeapon(model)
        let military = split(model, weapon.weaponId).military
        let third = military[2]
        let level = try #require(model.militaryLevel(mode: mp, weaponId: weapon.weaponId, camo: third))
        model.toggleCamo(mode: mp, weaponId: weapon.weaponId, camo: third)
        #expect(model.level(for: weapon.weaponId) == level)
        #expect(military.prefix(3).allSatisfy { model.isCamoComplete(mode: mp, weaponId: weapon.weaponId, camo: $0) })
        #expect(model.isCamoComplete(mode: mp, weaponId: weapon.weaponId, camo: military[3]) == false)

        model.toggleCamo(mode: mp, weaponId: weapon.weaponId, camo: third)
        #expect(model.level(for: weapon.weaponId) == level - 1)
        #expect(model.isCamoComplete(mode: mp, weaponId: weapon.weaponId, camo: third) == false)
    }

    /// Max level earns every Military camo and opens the Specials, which
    /// stay shut until then.
    @Test func maxLevelEarnsMilitaryAndOpensSpecials() throws {
        let model = try model()
        let weapon = try anyWeapon(model)
        let (military, special) = split(model, weapon.weaponId)
        model.setLevel(model.maxLevel(for: weapon) - 1, for: weapon)
        #expect(special.allSatisfy { !model.isCamoAvailable(mode: mp, weaponId: weapon.weaponId, camo: $0) })

        model.setLevel(model.maxLevel(for: weapon), for: weapon)
        #expect(military.allSatisfy { model.isCamoComplete(mode: mp, weaponId: weapon.weaponId, camo: $0) })
        #expect(special.allSatisfy { model.isCamoAvailable(mode: mp, weaponId: weapon.weaponId, camo: $0) })
        // Open, not earned: Specials still need ticking.
        #expect(special.allSatisfy { !model.isCamoComplete(mode: mp, weaponId: weapon.weaponId, camo: $0) })
    }

    /// A prestiged weapon has passed every level, so nothing Military locks
    /// even though its level has gone back to 1, and a tap changes nothing.
    @Test func aPrestigedWeaponKeepsEveryMilitaryCamo() throws {
        let model = try model()
        let weapon = try anyWeapon(model)
        let (military, special) = split(model, weapon.weaponId)
        model.setLevel(model.maxLevel(for: weapon), for: weapon)
        model.prestigeUp(weapon)
        #expect(model.level(for: weapon.weaponId) == 1)
        #expect(military.allSatisfy { model.isCamoComplete(mode: mp, weaponId: weapon.weaponId, camo: $0) })
        #expect(special.allSatisfy { model.isCamoAvailable(mode: mp, weaponId: weapon.weaponId, camo: $0) })
        model.toggleCamo(mode: mp, weaponId: weapon.weaponId, camo: military[4])
        #expect(model.level(for: weapon.weaponId) == 1)
        #expect(model.isCamoComplete(mode: mp, weaponId: weapon.weaponId, camo: military[4]))
    }

    /// A published level wins over the spread.
    @Test func aPublishedMilitaryLevelWins() throws {
        let base = try model()
        let weapon = try anyWeapon(base)
        let camos = #"""
            [{"weaponId": \#(weapon.weaponId), "camos": [
                {"itemId": 0, "name": {"en": "Military 1"}, "tier": 1, "unlockLevel": 5, "children": [], "group": "military"},
                {"itemId": 8, "name": {"en": "Special 1"}, "tier": 9, "children": [], "group": "special"}]}]
            """#
        let model = try model(["weaponCamos": camos])
        let military = try #require(model.camos(weaponId: weapon.weaponId, mode: mp).first)
        #expect(model.militaryLevel(mode: mp, weaponId: weapon.weaponId, camo: military) == 5)
        model.setLevel(5, for: weapon)
        #expect(model.isCamoComplete(mode: mp, weaponId: weapon.weaponId, camo: military))
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
