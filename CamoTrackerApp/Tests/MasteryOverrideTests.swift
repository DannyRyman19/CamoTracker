import Testing
import Foundation
import SwiftUI
@testable import CamoTracker

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
    private func model(_ blocks: [String: String] = [:], warzone: [String: String] = [:]) throws -> TrackerViewModel {
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        try write("multiplayer", blocks)
        try write("warzone", warzone)
        // MW4's data, whatever game the app was last left on
        let mw4 = GameRegistry.game("mw4")!
        GameRegistry.current = mw4
        return TrackerViewModel(game: mw4, dataService: DataService(game: mw4, cacheDir: cache), defaults: defaults)
    }

    /// The bundled mode file with `blocks` (top-level key to JSON) laid
    /// over it in the cache, or no cached copy at all for none.
    private func write(_ mode: String, _ blocks: [String: String]) throws {
        let target = cache.appendingPathComponent("\(mode).json")
        try? FileManager.default.removeItem(at: target)
        guard !blocks.isEmpty else { return }
        let seed = try #require(Bundle.main.url(forResource: "mw4_" + mode, withExtension: "json"))
        var object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: seed)) as? [String: Any])
        for (key, json) in blocks {
            object[key] = try JSONSerialization.jsonObject(with: Data(json.utf8), options: .fragmentsAllowed)
        }
        try JSONSerialization.data(withJSONObject: object).write(to: target)
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
        // Untouched modes keep what the build ships with (Warzone's file
        // names Divergence too since the launch blog)
        #expect(AppMode.warzone.completionist.final.name == "Divergence")

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
        let seed = try #require(Bundle.main.url(forResource: "mw4_weapons", withExtension: "json"))
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

    /// A `weaponCamos` block giving the weapon 8 Military camos with no
    /// published levels, so the spread fallback is what's tested.
    private func unpublishedMilitary(_ weaponId: Int) -> String {
        let slots = (0..<8).map {
            #"{"itemId": \#($0), "name": {"en": "Military \#($0 + 1)"}, "tier": \#($0 + 1), "children": [], "group": "military"}"#
        }
        return #"[{"weaponId": \#(weaponId), "camos": [\#(slots.joined(separator: ","))]}]"#
    }

    private func split(_ model: TrackerViewModel, _ weaponId: Int) -> (military: [ChallengeItem], special: [ChallengeItem]) {
        let camos = model.camos(weaponId: weaponId, mode: mp)
        return (camos.filter { $0.group == "military" }, camos.filter { $0.group == "special" })
    }

    /// With no published levels, the Military camos are spread up to the
    /// weapon's max level, the last one on max itself.
    @Test func militaryLevelsAreSpreadUpToMaxUntilPublished() throws {
        let weapon = try anyWeapon(try model())
        let model = try model(["weaponCamos": unpublishedMilitary(weapon.weaponId)])
        let military = split(model, weapon.weaponId).military
        try #require(military.count == 8)
        let max = model.maxLevel(for: weapon)
        #expect(model.militaryLevel(mode: mp, weaponId: weapon.weaponId, camo: military.last!) == max)
        #expect(model.militaryLevel(mode: mp, weaponId: weapon.weaponId, camo: military[0]) == Int((Double(max) / 8).rounded(.up)))
    }

    /// The HAN 86's levels as seen in game, and its named Specials with a
    /// level and then a challenge.
    @Test func theHan86HasItsRealLevels() throws {
        let model = try model()
        let weapon = try anyWeapon(model)
        try #require(weapon.name.values["en"] == "HAN 86")
        let (military, special) = split(model, weapon.weaponId)
        #expect(military.compactMap { model.militaryLevel(mode: mp, weaponId: weapon.weaponId, camo: $0) } == [10, 18, 25, 34, 42, 50, 57, 65])
        #expect(special.map { $0.name.values["en"] } == ["Smoke", "Stormwave", "Red"])
        #expect(special.map(\.unlockLevel) == [25, 46, 72])
        #expect(special.map { $0.requirement?.amount } == [20, 50, 15])
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

    /// By default each Special opens at its own level, Military or not:
    /// the HAN 86's Smoke at 25 while Military 4 (34) is still to come.
    @Test func specialsOpenAtTheirOwnLevel() throws {
        let model = try model()
        let weapon = try anyWeapon(model)
        let (military, special) = split(model, weapon.weaponId)
        #expect(!model.specialsWaitForMilitary(mode: mp))
        model.setLevel(24, for: weapon)
        #expect(!model.isCamoAvailable(mode: mp, weaponId: weapon.weaponId, camo: special[0]))
        model.setLevel(25, for: weapon)
        #expect(!model.allMilitaryComplete(mode: mp, weaponId: weapon.weaponId))
        #expect(!model.isCamoComplete(mode: mp, weaponId: weapon.weaponId, camo: military[3]))
        #expect(model.isCamoAvailable(mode: mp, weaponId: weapon.weaponId, camo: special[0]))
        #expect(!model.isCamoAvailable(mode: mp, weaponId: weapon.weaponId, camo: special[1]))

        model.setLevel(model.maxLevel(for: weapon), for: weapon)
        #expect(military.allSatisfy { model.isCamoComplete(mode: mp, weaponId: weapon.weaponId, camo: $0) })
        #expect(special.allSatisfy { model.isCamoAvailable(mode: mp, weaponId: weapon.weaponId, camo: $0) })
        // Open, not earned: Specials still need their challenge.
        #expect(special.allSatisfy { !model.isCamoComplete(mode: mp, weaponId: weapon.weaponId, camo: $0) })
    }

    /// `specialsAfterMilitary` keeps every Special shut until the last
    /// Military camo, whatever its own level.
    @Test func theSwitchKeepsSpecialsForAfterMilitary() throws {
        let model = try model(["specialsAfterMilitary": "true"])
        let weapon = try anyWeapon(model)
        let (military, special) = split(model, weapon.weaponId)
        #expect(model.specialsWaitForMilitary(mode: mp))
        let last = try #require(model.militaryLevel(mode: mp, weaponId: weapon.weaponId, camo: military.last!))
        model.setLevel(last - 1, for: weapon)
        #expect(special.allSatisfy { !model.isCamoAvailable(mode: mp, weaponId: weapon.weaponId, camo: $0) })
        model.setLevel(last, for: weapon)
        #expect(special.prefix(2).allSatisfy { model.isCamoAvailable(mode: mp, weaponId: weapon.weaponId, camo: $0) })
        #expect(!model.isCamoAvailable(mode: mp, weaponId: weapon.weaponId, camo: special[2]))
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

    /// A weapon moves Military → Special → Completionist → finished, and the
    /// stage filters follow it.
    @Test func stageFiltersFollowTheTrack() throws {
        let model = try model(["completionist": #"{"final": {"harmonicBreaksNeeded": 0}, "steps": [{"unlock": "weapon"}, {"unlock": "weapon"}, {"unlock": "weapon"}]}"#])
        let weapon = try anyWeapon(model)
        let id = weapon.weaponId
        #expect(model.matches(.onMilitary, mode: mp, weaponId: id))
        model.setLevel(model.maxLevel(for: weapon), for: weapon)
        #expect(model.matches(.onSpecial, mode: mp, weaponId: id))
        finishCamos(model, id)
        #expect(model.matches(.inCompletionist, mode: mp, weaponId: id))
        #expect(model.matches(.complete, mode: mp, weaponId: id))
        harmonicBreak(model, id)
        #expect(model.matches(.hasFinal, mode: mp, weaponId: id))
        #expect(model.matches(.onMilitary, mode: mp, weaponId: id) == false)
    }

    /// "Ready to grind" means an open Special or Completionist challenge,
    /// not just levelling: a fresh weapon isn't ready, a maxed one is.
    @Test func readyToGrindNeedsAnOpenChallenge() throws {
        let model = try model()
        let weapon = try anyWeapon(model)
        #expect(model.matches(.ready, mode: mp, weaponId: weapon.weaponId) == false)
        model.setLevel(model.maxLevel(for: weapon), for: weapon)
        #expect(model.matches(.ready, mode: mp, weaponId: weapon.weaponId))
        // All camos done and Gold open: still something to do.
        finishCamos(model, weapon.weaponId)
        #expect(model.matches(.ready, mode: mp, weaponId: weapon.weaponId))
    }

    @Test func allWeaponsListsEveryWeaponOnce() throws {
        let model = try model()
        let all = try #require(model.allWeaponsCategory)
        #expect(all.weapons.count == model.totalWeaponCount)
        #expect(Set(all.weapons.map(\.weaponId)).count == all.weapons.count)
    }

    /// Prestige stages with their own max (Prestige Master to 250) don't
    /// move the Military levels: they stay on the weapon's normal max.
    @Test func militaryLevelsIgnoreThePrestigeStagesMax() throws {
        let weapon = try anyWeapon(try model())
        let model = try model(["weaponCamos": unpublishedMilitary(weapon.weaponId)])
        let last = try #require(split(model, weapon.weaponId).military.last)
        let before = model.militaryLevel(mode: mp, weaponId: weapon.weaponId, camo: last)
        for _ in 0..<model.prestigeStages.count {
            model.setLevel(model.maxLevel(for: weapon), for: weapon)
            model.prestigeUp(weapon)
        }
        #expect(model.militaryLevel(mode: mp, weaponId: weapon.weaponId, camo: last) == before)
        #expect(before == weapon.maxLevel)
    }

    // MARK: Rule switches

    /// `trackFrom`: Warzone sharing Multiplayer's track sees its camos and
    /// Completionist progress, both ways; Mastery stays Warzone's own.
    @Test func aSharedTrackCountsInEveryModeThatSharesIt() throws {
        let model = try model(warzone: ["trackFrom": #""multiplayer""#])
        let weapon = try anyWeapon(model)
        let id = weapon.weaponId
        #expect(model.trackMode("warzone") == mp)
        model.setLevel(model.maxLevel(for: weapon), for: weapon)
        for camo in model.camos(weaponId: id, mode: "warzone") where !model.isCamoComplete(mode: "warzone", weaponId: id, camo: camo) {
            model.toggleCamo(mode: "warzone", weaponId: id, camo: camo)
        }
        #expect(model.allCamosComplete(weaponId: id, mode: mp))
        model.toggleCompletionist(mode: mp, weaponId: id, step: 0)
        #expect(model.isCompletionistComplete(mode: "warzone", weaponId: id, step: 0))
        // Gold's challenge in Warzone is Multiplayer's.
        #expect(model.completionistRequirement(mode: "warzone", weaponId: id, step: 0)?.amount
                == model.completionistRequirement(mode: mp, weaponId: id, step: 0)?.amount)
        // And in DMZ, which keeps its own track: a camo done in any mode
        // counts in all of them (see SharedCamoTests)
        #expect(model.isCompletionistComplete(mode: "dmz", weaponId: id, step: 0))
    }

    /// `final.enabled: false`: no final camo, and Mastery counts Harmonic Breaks.
    @Test func turningTheFinalCamoOffEndsTheTrackAtHarmonicBreak() throws {
        let model = try model([
            "completionist": #"{"final": {"enabled": false}}"#,
            "mastery": #"{"tier1": {"weaponsNeeded": 1}}"#,
        ])
        let id = try anyWeapon(model).weaponId
        harmonicBreak(model, id)
        #expect(model.hasFinalCamo(mode: mp, weaponId: id) == false)
        #expect(model.hasLastCompletionist(mode: mp, weaponId: id))
        #expect(model.isMasteryAchieved(mode: mp, tier: 1))
        #expect(AppMode.multiplayer.completionistCamos.count == 3)
        #expect(AppMode.multiplayer.lastCompletionist.name == AppMode.multiplayer.completionist.steps[2].name)
    }

    /// `mastery.unlock: "challenge"`: tier 1 is a per-weapon challenge that
    /// opens once the whole launch roster has the last Completionist camo,
    /// and later tiers on the tier before.
    @Test func challengeMasteryOpensOnTheWholeRoster() throws {
        let model = try model([
            "completionist": #"{"final": {"enabled": false}}"#,
            "mastery": #"""
                {"unlock": "challenge",
                 "tier1": {"requirement": {"amount": 30, "unit": "kills", "description": {"en": "Get 30 kills."}},
                           "byCategory": {"0": {"amount": 40, "unit": "kills", "description": {"en": "Rifles."}}}}}
                """#,
        ])
        let all = weapons(model)
        let rifle = try #require(model.catalog?.categories.first { $0.categoryId == 0 }?.weapons.first).weaponId
        let other = try #require(model.catalog?.categories.first { $0.categoryId != 0 }?.weapons.first).weaponId
        #expect(model.masteryRequirement(mode: mp, weaponId: rifle, tier: 1)?.amount == 40)
        #expect(model.masteryRequirement(mode: mp, weaponId: other, tier: 1)?.amount == 30)

        for weapon in all.dropLast() { model.toggleCompletionist(mode: mp, weaponId: weapon.weaponId, step: 2) }
        #expect(model.isWeaponMasteryAvailable(mode: mp, weaponId: rifle, tier: 1) == false)
        model.toggleCompletionist(mode: mp, weaponId: all.last!.weaponId, step: 2)
        #expect(model.isWeaponMasteryAvailable(mode: mp, weaponId: rifle, tier: 1))
        #expect(model.isWeaponMasteryAvailable(mode: mp, weaponId: rifle, tier: 2) == false)

        model.setWeaponMasteryAmount(mode: mp, weaponId: rifle, tier: 1, amount: 40)
        #expect(model.isWeaponMasteryComplete(mode: mp, weaponId: rifle, tier: 1))
        #expect(model.isWeaponMasteryAvailable(mode: mp, weaponId: rifle, tier: 2))
        #expect(model.masteryProgress(mode: mp, tier: 1).done == 1)
        #expect(model.matches(.ready, mode: mp, weaponId: other))
    }

    /// A weapon's own challenge beats its class's (the Warlord's Platinum).
    @Test func aWeaponCanHaveItsOwnChallenge() throws {
        let model = try model(["completionist": #"""
            {"steps": [{}, {"byCategory": {"0": {"amount": 50, "unit": "headshots", "description": {"en": "Rifles."}}},
                            "byWeapon": {"1": {"amount": 7, "unit": "kills", "description": {"en": "Mine."}}}}]}
            """#])
        let rifles = try #require(model.catalog?.categories.first { $0.categoryId == 0 }?.weapons)
        let own = try #require(rifles.first { $0.weaponId == 1 }).weaponId
        let other = try #require(rifles.first { $0.weaponId != 1 }).weaponId
        #expect(model.completionistRequirement(mode: mp, weaponId: own, step: 1)?.amount == 7)
        #expect(model.completionistRequirement(mode: mp, weaponId: other, step: 1)?.amount == 50)
    }

    /// The shipped Multiplayer file gives the Warlord its own Platinum.
    /// Shotgun Platinum in Multiplayer is 50 hipfire kills on every shotgun
    /// (the game's own text; 125 is the DMZ count). The Warlord's own entry
    /// stays and must agree with the class.
    @Test func theWarlordsPlatinumIsItsOwn() throws {
        let model = try model()
        #expect(model.completionistRequirement(mode: mp, weaponId: 24, step: 1)?.amount == 50)
        #expect(model.completionistRequirement(mode: mp, weaponId: 8, step: 1)?.amount == 50)
    }

    /// Mode Mastery: one challenge per tier for the whole mode, tier 1
    /// after the last Completionist camo on any weapon, then in order.
    @Test func modeMasteryIsOneChallengePerTier() throws {
        let model = try model([
            "completionist": #"{"final": {"harmonicBreaksNeeded": 0}}"#,
            "mastery": #"""
                {"unlock": "mode",
                 "tier1": {"requirement": {"amount": 1, "unit": "times", "description": {"en": "Tick."}}},
                 "tier2": {"requirement": {"amount": 5, "unit": "times", "description": {"en": "Five."}}}}
                """#,
        ])
        let ids = weapons(model).prefix(2).map(\.weaponId)
        #expect(model.masteryKind(mode: mp, tier: 1) == .mode)
        #expect(model.isModeMasteryAvailable(mode: mp, tier: 1) == false)
        harmonicBreak(model, ids[0])
        #expect(model.isModeMasteryAvailable(mode: mp, tier: 1))
        #expect(model.isMasteryAchieved(mode: mp, tier: 1) == false)
        #expect(model.isModeMasteryAvailable(mode: mp, tier: 2) == false)

        model.toggleModeMastery(mode: mp, tier: 1, weaponId: ids[0])
        #expect(model.isMasteryAchieved(mode: mp, tier: 1))
        #expect(model.isModeMasteryAvailable(mode: mp, tier: 2))
        model.setModeMasteryAmount(mode: mp, tier: 2, weaponId: ids[1], amount: 4)
        #expect(model.masteryProgress(mode: mp, tier: 2).done == 4)
        #expect(model.masteryProgress(mode: mp, tier: 2).total == 5)
        model.setModeMasteryAmount(mode: mp, tier: 2, weaponId: ids[1], amount: 9)
        #expect(model.isMasteryAchieved(mode: mp, tier: 2))
        // Tier 3 has no requirement: a plain tick box.
        model.toggleModeMastery(mode: mp, tier: 3, weaponId: ids[0])
        #expect(model.isMasteryAchieved(mode: mp, tier: 3))
        // Nothing per weapon.
        #expect(model.isWeaponMasteryAvailable(mode: mp, weaponId: ids[0], tier: 1) == false)
    }

    /// A tier counted in Harmonic Breaks counts itself and can't be ticked.
    @Test func aHarmonicBreakTierCountsItself() throws {
        let model = try model([
            "completionist": #"{"final": {"harmonicBreaksNeeded": 0}}"#,
            "mastery": #"""
                {"unlock": "mode",
                 "tier1": {"requirement": {"amount": 2, "unit": "harmonic_breaks", "description": {"en": "Two."}}}}
                """#,
        ])
        let ids = weapons(model).prefix(2).map(\.weaponId)
        harmonicBreak(model, ids[0])
        model.toggleModeMastery(mode: mp, tier: 1, weaponId: ids[0])
        #expect(model.masteryProgress(mode: mp, tier: 1).done == 1)
        #expect(model.masteryProgress(mode: mp, tier: 1).total == 2)
        harmonicBreak(model, ids[1])
        #expect(model.isMasteryAchieved(mode: mp, tier: 1))
    }

    /// Tiers can differ: tier 1 per weapon, tiers 2 and 3 for the mode.
    @Test func eachTierCanPickItsOwnKind() throws {
        let model = try model([
            "completionist": #"{"final": {"enabled": false}}"#,
            "mastery": #"""
                {"unlock": "mode",
                 "tier1": {"kind": "challenge", "unlock": "weapon",
                           "requirement": {"amount": 1, "unit": "times", "description": {"en": "Per gun."}}},
                 "tier2": {"requirement": {"amount": 1, "unit": "times", "description": {"en": "Mode."}}}}
                """#,
        ])
        let id = try anyWeapon(model).weaponId
        #expect(model.masteryKind(mode: mp, tier: 1) == .challenge)
        #expect(model.masteryKind(mode: mp, tier: 2) == .mode)
        #expect(model.masteryKind(mode: mp, tier: 3) == .mode)
        model.toggleCompletionist(mode: mp, weaponId: id, step: 2)
        #expect(model.isWeaponMasteryAvailable(mode: mp, weaponId: id, tier: 1))
        model.toggleWeaponMastery(mode: mp, weaponId: id, tier: 1)
        // Tier 1 is per gun, so the mode's tier 2 waits for every launch gun.
        #expect(model.isModeMasteryAvailable(mode: mp, tier: 2) == false)
        for weapon in weapons(model) {
            if !model.isCompletionistComplete(mode: mp, weaponId: weapon.weaponId, step: 2) {
                model.toggleCompletionist(mode: mp, weaponId: weapon.weaponId, step: 2)
            }
            if !model.isWeaponMasteryComplete(mode: mp, weaponId: weapon.weaponId, tier: 1) {
                model.toggleWeaponMastery(mode: mp, weaponId: weapon.weaponId, tier: 1)
            }
        }
        #expect(model.isMasteryAchieved(mode: mp, tier: 1))
        #expect(model.isModeMasteryAvailable(mode: mp, tier: 2))
    }

    /// "Complete 2 Gold Camo Challenges using Assault Rifles": a gate can
    /// need fewer than the whole class, capped at the class's size.
    @Test func aGateCanNeedACount() throws {
        let model = try model(["completionist": #"{"steps": [{}, {"needed": 2}]}"#])
        let rifles = try #require(model.catalog?.categories.first { $0.categoryId == 0 })
        let melee = try #require(model.catalog?.categories.first { $0.weapons.count == 1 })
        #expect(model.completionistCategoryGateProgress(rifles, mode: mp, step: 1).total == 2)
        #expect(model.completionistCategoryGateProgress(melee, mode: mp, step: 1).total == 1)
        let ids = rifles.weapons.map(\.weaponId)
        model.toggleCompletionist(mode: mp, weaponId: ids[0], step: 0)
        model.toggleCompletionist(mode: mp, weaponId: ids[1], step: 0)
        #expect(model.isCompletionistAvailable(mode: mp, weaponId: ids[0], step: 1))
        // Its own Gold is still needed.
        #expect(model.isCompletionistAvailable(mode: mp, weaponId: ids[2], step: 1) == false)
    }

    /// A mode tier counted in Platinums counts itself; one can wait for more
    /// than one weapon with the final camo before it opens.
    @Test func aModeTierCanCountPlatinumsAndWaitForWeapons() throws {
        let model = try model([
            "completionist": #"{"final": {"harmonicBreaksNeeded": 0}}"#,
            "mastery": #"""
                {"unlock": "mode",
                 "tier1": {"weaponsNeeded": 2,
                           "requirement": {"amount": 3, "unit": "platinums", "description": {"en": "Three."}}}}
                """#,
        ])
        let ids = weapons(model).prefix(3).map(\.weaponId)
        harmonicBreak(model, ids[0])
        #expect(model.isModeMasteryAvailable(mode: mp, tier: 1) == false)
        harmonicBreak(model, ids[1])
        #expect(model.isModeMasteryAvailable(mode: mp, tier: 1))
        #expect(model.masteryProgress(mode: mp, tier: 1).done == 2)
        model.toggleCompletionist(mode: mp, weaponId: ids[2], step: 1)
        #expect(model.isMasteryAchieved(mode: mp, tier: 1))
    }

    /// Quick tick: Military camos are plain ticks, a tick takes the ones
    /// before it with it, nothing is locked, and switching back keeps every
    /// tick.
    @Test func quickTickTicksWithoutLevels() throws {
        let model = try model()
        let weapon = try anyWeapon(model)
        let (military, special) = split(model, weapon.weaponId)
        #expect(model.isCamoAvailable(mode: mp, weaponId: weapon.weaponId, camo: special[2]) == false)

        model.setQuickTick(true)
        #expect(model.isCamoAvailable(mode: mp, weaponId: weapon.weaponId, camo: special[2]))
        model.toggleCamo(mode: mp, weaponId: weapon.weaponId, camo: military[4])
        #expect(military.prefix(5).allSatisfy { model.isCamoComplete(mode: mp, weaponId: weapon.weaponId, camo: $0) })
        #expect(model.isCamoComplete(mode: mp, weaponId: weapon.weaponId, camo: military[5]) == false)
        #expect(model.level(for: weapon.weaponId) == 0)

        model.setQuickTick(false)
        #expect(model.isCamoComplete(mode: mp, weaponId: weapon.weaponId, camo: military[4]))
        // Unticking clears it and the ones after, leaving the level alone.
        model.toggleCamo(mode: mp, weaponId: weapon.weaponId, camo: military[2])
        #expect(model.isCamoComplete(mode: mp, weaponId: weapon.weaponId, camo: military[1]))
        #expect(military[2...].allSatisfy { !model.isCamoComplete(mode: mp, weaponId: weapon.weaponId, camo: $0) })
        #expect(model.level(for: weapon.weaponId) == 0)
    }

    /// Quick tick: Harmonic Break takes Gold and Platinum with it, nothing
    /// waits for the class, and unticking Gold clears the rest but leaves a
    /// half-done count from full tracking alone.
    @Test func quickTickCascadesTheCompletionistRun() throws {
        let model = try model(["mastery": #"{"unlock": "mode", "tier2": {"requirement": {"amount": 1, "unit": "times", "description": {"en": "x"}}}}"#])
        let ids = weapons(model).prefix(2).map(\.weaponId)
        model.setCompletionistAmount(mode: mp, weaponId: ids[1], step: 0, amount: 1)
        model.setQuickTick(true)
        #expect(model.isCompletionistAvailable(mode: mp, weaponId: ids[0], step: 2))
        #expect(model.isModeMasteryAvailable(mode: mp, tier: 3))

        model.toggleCompletionist(mode: mp, weaponId: ids[0], step: 2)
        #expect((0...2).allSatisfy { model.isCompletionistComplete(mode: mp, weaponId: ids[0], step: $0) })
        model.toggleCompletionist(mode: mp, weaponId: ids[0], step: 0)
        #expect((0...2).allSatisfy { !model.isCompletionistComplete(mode: mp, weaponId: ids[0], step: $0) })

        model.setQuickTick(false)
        model.setCompletionistAmount(mode: mp, weaponId: ids[1], step: 1, amount: 10)
        model.setQuickTick(true)
        model.toggleCompletionist(mode: mp, weaponId: ids[1], step: 0)
        #expect(model.completionistAmount(mode: mp, weaponId: ids[1], step: 1) == 10)

        model.toggleModeMastery(mode: mp, tier: 3, weaponId: ids[0])
        #expect((1...3).allSatisfy { model.isMasteryAchieved(mode: mp, tier: $0) })
    }

    /// In quick tick, unticking a camo earned by level steps the level
    /// below it, as it does with levels on.
    @Test func quickTickUntickingALevelledCamoLowersTheLevel() throws {
        let model = try model()
        let weapon = try anyWeapon(model)
        let military = split(model, weapon.weaponId).military
        let level = try #require(model.militaryLevel(mode: mp, weaponId: weapon.weaponId, camo: military[2]))
        model.setLevel(level, for: weapon)
        model.setQuickTick(true)
        model.toggleCamo(mode: mp, weaponId: weapon.weaponId, camo: military[2])
        #expect(model.isCamoComplete(mode: mp, weaponId: weapon.weaponId, camo: military[2]) == false)
        #expect(model.level(for: weapon.weaponId) == level - 1)
    }

    /// Count Mastery (the default) has no per-weapon challenges.
    @Test func countMasteryHasNoWeaponChallenges() throws {
        let model = try model(["mastery": "{}"])
        let id = try anyWeapon(model).weaponId
        #expect(model.masteryUsesChallenges(mode: mp) == false)
        #expect(model.isWeaponMasteryAvailable(mode: mp, weaponId: id, tier: 1) == false)
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

    /// Weapon Prestige camos: Pyroclast for entering Prestige, then one at
    /// the level after the weapon's own max and two at fixed Prestige Master levels.
    @Test func prestigeCamosTickThemselvesFromPrestigeAndLevel() throws {
        let model = try model()
        let weapon = try anyWeapon(model)
        let id = weapon.weaponId
        #expect(model.prestigeCamos.count == 4)
        #expect(model.prestigeCamoLevel(model.prestigeCamos[1], weaponId: id) == weapon.maxLevel + 1)
        #expect(!model.isPrestigeCamoComplete(weaponId: id, index: 0))

        model.setLevel(weapon.maxLevel, for: weapon)
        model.prestigeUp(weapon)
        #expect(model.isPrestigeCamoComplete(weaponId: id, index: 0))
        #expect(!model.isPrestigeCamoComplete(weaponId: id, index: 1))

        model.setLevel(150, for: weapon)
        #expect(model.isPrestigeCamoComplete(weaponId: id, index: 1))
        #expect(model.isPrestigeCamoComplete(weaponId: id, index: 2))
        #expect(!model.isPrestigeCamoComplete(weaponId: id, index: 3))
    }

    /// Tapping one sets Prestige and level to it; tapping it again steps
    /// back to just below it, and Pyroclast's undo un-prestiges.
    @Test func tappingAPrestigeCamoSetsPrestigeAndLevel() throws {
        let model = try model()
        let weapon = try anyWeapon(model)
        let id = weapon.weaponId
        model.togglePrestigeCamo(weaponId: id, index: 2)
        #expect(model.prestige(for: id) == 1)
        #expect(model.level(for: id) == 150)
        #expect((0...2).allSatisfy { model.isPrestigeCamoComplete(weaponId: id, index: $0) })

        model.togglePrestigeCamo(weaponId: id, index: 2)
        #expect(model.level(for: id) == 149)
        model.togglePrestigeCamo(weaponId: id, index: 0)
        #expect(model.prestige(for: id) == 0)
        #expect(model.level(for: id) == weapon.maxLevel)
    }

    @Test func quickTickTicksAPrestigeRunWithoutLevels() throws {
        let model = try model()
        let weapon = try anyWeapon(model)
        model.setQuickTick(true)
        model.togglePrestigeCamo(weaponId: weapon.weaponId, index: 3)
        #expect((0...3).allSatisfy { model.isPrestigeCamoComplete(weaponId: weapon.weaponId, index: $0) })
        #expect(model.prestige(for: weapon.weaponId) == 0)
        model.togglePrestigeCamo(weaponId: weapon.weaponId, index: 1)
        #expect(model.isPrestigeCamoComplete(weaponId: weapon.weaponId, index: 0))
        #expect(!model.isPrestigeCamoComplete(weaponId: weapon.weaponId, index: 3))
    }

    /// The widgets' snapshot: every played mode with its Completionist and
    /// Mastery steps, and the pinned weapon's next camo.
    @Test func widgetSnapshotCarriesModesAndThePinnedWeapon() throws {
        let model = try model()
        let weapon = try anyWeapon(model)
        model.pin(weaponId: weapon.weaponId)
        let snapshot = try #require(model.widgetSnapshot())
        #expect(snapshot.modes.count == AppMode.played(UserDefaults.standard.string(forKey: AppMode.playedKey) ?? "").count)
        let mp = try #require(snapshot.modes.first { $0.id == "multiplayer" })
        #expect(mp.steps.count == AppMode.multiplayer.completionistCamos.count)
        #expect(mp.mastery.count == 3)
        #expect(mp.steps.allSatisfy { $0.total == mp.weaponCount })
        let pinned = try #require(snapshot.pinned)
        #expect(pinned.weaponId == weapon.weaponId)
        #expect(pinned.nextName != nil)
        #expect(pinned.camosDone == 0)
        #expect(pinned.accentHex.hasPrefix("#") && pinned.accentHex.count == 7)
    }
}

/// The mode tab's Customise layout as `@AppStorage` saves it.
@Suite("Home layout")
struct HomeLayoutTests {

    @Test func nothingSavedIsTheDefaultOrderAllShown() {
        let layout = HomeLayout(order: "", hidden: "")
        #expect(layout.order == HomeSection.allCases)
        #expect(layout.visible == HomeSection.allCases)
    }

    @Test func aSavedOrderAndHiddenSetComeBack() {
        let order: [HomeSection] = [.weapons, .suggested, .summary, .pinned, .objectives]
        let layout = HomeLayout(order: HomeLayout.encode(order), hidden: HomeLayout.encode([.suggested, .pinned]))
        #expect(layout.order == order)
        #expect(layout.visible == [.weapons, .summary, .objectives])
    }

    /// An order saved before a section existed gets it in its default place:
    /// straight after the section it follows by default.
    @Test func aNewSectionSlotsInWhereItBelongs() {
        let layout = HomeLayout(order: "weapons,summary,suggested", hidden: "")
        #expect(layout.order == [.weapons, .objectives, .summary, .pinned, .suggested])
    }

    @Test func weaponsCannotBeHiddenAndJunkIsIgnored() {
        let layout = HomeLayout(order: "weapons,weapons,nonsense,summary", hidden: "weapons,nonsense,summary")
        #expect(layout.order.filter { $0 == .weapons }.count == 1)
        #expect(layout.order.count == HomeSection.allCases.count)
        #expect(layout.visible.contains(.weapons))
        #expect(!layout.visible.contains(.summary))
    }
}
