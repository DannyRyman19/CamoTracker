package app.camotrack.android.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.abs
import kotlin.math.ceil

/** Port of the iOS `TrackerViewModelTests` suite (MasteryOverrideTests.swift). */
class TrackerTests {
    private val h = Harness()
    private val mp = "multiplayer"
    private val en = listOf("en")

    private fun anyWeapon(m: GameTracker) = m.catalog!!.categories.first().weapons.first()
    private fun weapons(m: GameTracker) = m.allWeapons
    private fun launchWeapons(m: GameTracker) = weapons(m).filter { it.weaponId < m.baseWeaponCount }

    private fun finishCamos(m: GameTracker, weaponId: Int) {
        for (camo in m.camos(weaponId, mp)) if (!m.isCamoComplete(mp, weaponId, camo)) m.toggleCamo(mp, weaponId, camo)
    }

    private fun harmonicBreak(m: GameTracker, weaponId: Int) {
        finishCamos(m, weaponId)
        for (step in 0 until GameTracker.COMPLETIONIST_STEP_COUNT) {
            if (!m.isCompletionistComplete(mp, weaponId, step)) m.toggleCompletionist(mp, weaponId, step)
        }
    }

    private fun split(m: GameTracker, weaponId: Int): Pair<List<ChallengeItem>, List<ChallengeItem>> {
        val camos = m.camos(weaponId, mp)
        return camos.filter { it.group == "military" } to camos.filter { it.group == "special" }
    }

    private fun unpublishedMilitary(weaponId: Int): String {
        val slots = (0 until 8).joinToString(",") {
            """{"itemId": $it, "name": {"en": "Military ${it + 1}"}, "tier": ${it + 1}, "children": [], "group": "military"}"""
        }
        return """[{"weaponId": $weaponId, "camos": [$slots]}]"""
    }

    @Test fun theModeFilesBlocksReachTheCamos() {
        val configured = h.model(mapOf(
            "mastery" to """{"tier1": {"name": {"en": "Override Drift"}, "weaponsNeeded": 2}}""",
            "completionist" to """{"final": {"name": {"en": "Divergence"}}}""",
        ))
        assertEquals("Override Drift", configured.masteryCamos(mp)[0].dataName(en))
        assertEquals(2, configured.masteryWeaponsNeeded(mp, 1))
        assertEquals("Divergence", configured.completionist(mp).final.dataName(en))
        assertEquals("Divergence", configured.completionist("warzone").final.dataName(en))
        assertNotEquals("Override Drift", h.model().masteryCamos(mp)[0].dataName(en))
    }

    @Test fun masteryDefaultsToThirdsOfTheRoster() {
        val m = h.model()
        val roster = minOf(m.totalWeaponCount, m.baseWeaponCount)
        assertEquals(roster, m.masteryWeaponsNeeded(mp, 3))
        assertEquals(ceil(roster / 3.0).toInt(), m.masteryWeaponsNeeded(mp, 1))
    }

    @Test fun goldOpensOnceTheWeaponsCamoListIsDone() {
        val m = h.model()
        val weapon = anyWeapon(m).weaponId
        assertFalse(m.isCompletionistAvailable(mp, weapon, 0))
        finishCamos(m, weapon)
        assertTrue(m.isCompletionistAvailable(mp, weapon, 0))
    }

    @Test fun platinumWaitsForGoldAcrossTheClass() {
        val m = h.model()
        val category = m.catalog!!.categories.first { it.weapons.size > 1 }
        val first = category.weapons[0].weaponId
        finishCamos(m, first)
        m.toggleCompletionist(mp, first, 0)
        assertFalse(m.isCompletionistAvailable(mp, first, 1))
        for (weapon in category.weapons.drop(1)) {
            finishCamos(m, weapon.weaponId)
            m.toggleCompletionist(mp, weapon.weaponId, 0)
        }
        assertTrue(m.isCompletionistAvailable(mp, first, 1))
        val other = m.catalog!!.categories.first { it.categoryId != category.categoryId }.weapons.first().weaponId
        assertFalse(m.isCompletionistAvailable(mp, other, 1))
    }

    @Test fun platinumCountsTheClassLaunchRoster() {
        java.io.File(h.cache, "weapons.json").writeText(Fixtures.overlaid("weapons", mapOf("baseWeaponCount" to "1")))
        val m = h.model()
        val rifles = m.catalog!!.categories.first { it.categoryId == 0 }
        assertTrue(rifles.weapons.size > 1)
        val dlcStandIn = rifles.weapons[1].weaponId
        finishCamos(m, dlcStandIn)
        m.toggleCompletionist(mp, dlcStandIn, 0)
        assertEquals(Progress(1, 1), m.completionistCategoryGateProgress(rifles, mp, 1))
        assertTrue(m.isCompletionistAvailable(mp, dlcStandIn, 1))
    }

    @Test fun harmonicBreakWaitsForPlatinumOnEveryWeapon() {
        val m = h.model()
        val all = launchWeapons(m).map { it.weaponId }
        for (weapon in all.dropLast(1)) m.toggleCompletionist(mp, weapon, 1)
        assertFalse(m.isCompletionistAvailable(mp, all[0], 2))
        assertEquals(all.size - 1, m.completionistModeGateProgress(mp, 2).done)
        m.toggleCompletionist(mp, all.last(), 1)
        assertTrue(m.isCompletionistAvailable(mp, all[0], 2))
    }

    @Test fun aModeFileCanChangeAGate() {
        val m = h.model(mapOf("completionist" to """{"steps": [{}, {"unlock": "weapon"}]}"""))
        val weapon = anyWeapon(m).weaponId
        finishCamos(m, weapon)
        m.toggleCompletionist(mp, weapon, 0)
        assertEquals(CompletionistGate.WEAPON, m.completionistGate(mp, 1))
        assertTrue(m.isCompletionistAvailable(mp, weapon, 1))
    }

    @Test fun aCategoryCanHaveItsOwnChallenge() {
        val m = h.model(mapOf("completionist" to """
            {"steps": [{}, {"requirement": {"amount": 20, "unit": "kills", "description": {"en": "Default."}},
                            "byCategory": {"0": {"amount": 50, "unit": "headshots", "description": {"en": "Rifles."}}}}]}
            """))
        val categories = m.catalog!!.categories
        val rifle = categories.first { it.categoryId == 0 }.weapons.first().weaponId
        val other = categories.first { it.categoryId != 0 }.weapons.first().weaponId
        assertEquals(50, m.completionistRequirement(mp, rifle, 1)?.amount)
        assertEquals(20, m.completionistRequirement(mp, other, 1)?.amount)
        assertNull(m.completionistRequirement(mp, rifle, 0))
    }

    @Test fun progressIsCappedOnReadButKeptOnDisk() {
        fun steps(amount: Int) = mapOf("completionist" to
            """{"steps": [{}, {"requirement": {"amount": $amount, "unit": "kills", "description": {"en": "x"}}}]}""")
        val high = h.model(steps(9))
        val weapon = anyWeapon(high).weaponId
        high.setCompletionistAmount(mp, weapon, 1, 8)
        assertEquals(8, high.completionistAmount(mp, weapon, 1))
        assertFalse(high.isCompletionistComplete(mp, weapon, 1))

        val low = h.model(steps(4))
        assertEquals(4, low.completionistAmount(mp, weapon, 1))
        assertTrue(low.isCompletionistComplete(mp, weapon, 1))

        assertEquals(8, h.model(steps(9)).completionistAmount(mp, weapon, 1))
    }

    @Test fun theFinalCamoWaitsForTheModesHarmonicBreakCount() {
        val m = h.model(mapOf("completionist" to """{"final": {"harmonicBreaksNeeded": 3}}"""))
        val ids = weapons(m).take(3).map { it.weaponId }
        harmonicBreak(m, ids[0])
        harmonicBreak(m, ids[1])
        assertFalse(m.hasFinalCamo(mp, ids[0]))
        assertEquals(0, m.finalCamoCount(mp))
        harmonicBreak(m, ids[2])
        assertTrue(ids.all { m.hasFinalCamo(mp, it) })
        assertEquals(3, m.finalCamoCount(mp))
        assertFalse(m.hasFinalCamo(mp, weapons(m)[3].weaponId))
    }

    @Test fun masteryUnlocksAsWeaponsEarnTheFinalCamo() {
        val m = h.model(mapOf(
            "mastery" to """{"tier1": {"weaponsNeeded": 1}, "tier2": {"weaponsNeeded": 2}, "tier3": {"weaponsNeeded": 3}}""",
            "completionist" to """{"final": {"harmonicBreaksNeeded": 0}}""",
        ))
        val ids = weapons(m).take(3).map { it.weaponId }
        assertFalse(m.isMasteryAchieved(mp, 1))
        harmonicBreak(m, ids[0])
        assertTrue(m.isMasteryAchieved(mp, 1))
        assertFalse(m.isMasteryAchieved(mp, 2))
        assertEquals(1, m.masteryProgress(mp, 2).done)
        harmonicBreak(m, ids[1])
        harmonicBreak(m, ids[2])
        assertTrue(m.isMasteryAchieved(mp, 3))
    }

    @Test fun statsCountTheCompletionistTrack() {
        val m = h.model(mapOf("completionist" to """{"final": {"harmonicBreaksNeeded": 0}}"""))
        val category = m.catalog!!.categories.first()
        val weapon = category.weapons.first().weaponId
        finishCamos(m, weapon)
        val afterCamos = m.categoryTrueCompletionFraction(category, mp)
        assertEquals(0, m.completionistCount(mp, 0))
        harmonicBreak(m, weapon)
        assertEquals(1, m.completionistCount(mp, 0))
        assertEquals(1, m.completionistCount(mp, 2))
        assertEquals(1, m.completionistCount(mp, GameTracker.COMPLETIONIST_STEP_COUNT))
        assertTrue(m.categoryTrueCompletionFraction(category, mp) > afterCamos)
    }

    @Test fun finishedCamoListsAreOneStageOfTheTrack() {
        val m = h.model()
        val category = m.catalog!!.categories.first()
        for (weapon in category.weapons) finishCamos(m, weapon.weaponId)
        val stages = 1 + GameTracker.COMPLETIONIST_STEP_COUNT + (if (m.finalEnabled(mp)) 1 else 0) +
            (1..3).count { m.masteryKind(mp, it) == MasteryKind.CHALLENGE }
        assertTrue(abs(m.categoryTrueCompletionFraction(category, mp) - 1.0 / stages) < 0.0001)
        assertTrue(m.trueCompletionFraction(mp) < 0.25)
    }

    @Test fun aSuggestionShowsProgressTowardTheCamoItNames() {
        val m = h.model()
        val category = m.catalog!!.categories.first()
        for (weapon in category.weapons) {
            finishCamos(m, weapon.weaponId)
            m.toggleCompletionist(mp, weapon.weaponId, 0)
        }
        val next = m.suggestions(mp, limit = 50).filter { it.highlight != null }
        assertTrue(next.isNotEmpty())
        assertTrue(next.all { it.progress == 0.0 })
    }

    @Test fun suggestionsRankCompletionistFirstThenFewestCamosLeft() {
        val m = h.model()
        val (military, _) = split(m, 0)
        finishCamos(m, 1)
        m.setLevel(m.militaryLevel(mp, 0, military.last())!!, 0)
        val list = m.suggestions(mp, limit = 5)
        assertEquals(1, list[0].weaponId)
        assertNotNull(list[0].nextCamo)
        assertEquals(0, list[1].weaponId)
        assertNull(list[1].nextCamo)
        assertTrue(list.drop(1).zipWithNext().all { (a, b) -> a.camosLeft <= b.camosLeft })
    }

    @Test fun militaryLevelsAreSpreadUpToMaxUntilPublished() {
        val weapon = anyWeapon(h.model())
        val m = h.model(mapOf("weaponCamos" to unpublishedMilitary(weapon.weaponId)))
        val military = split(m, weapon.weaponId).first
        assertEquals(8, military.size)
        val max = m.maxLevel(weapon)
        assertEquals(max, m.militaryLevel(mp, weapon.weaponId, military.last()))
        assertEquals(ceil(max / 8.0).toInt(), m.militaryLevel(mp, weapon.weaponId, military[0]))
    }

    @Test fun theHan86HasItsRealLevels() {
        val m = h.model()
        val weapon = anyWeapon(m)
        assertEquals("HAN 86", weapon.name.values["en"])
        val (military, special) = split(m, weapon.weaponId)
        assertEquals(listOf(10, 18, 25, 34, 42, 50, 57, 65), military.mapNotNull { m.militaryLevel(mp, weapon.weaponId, it) })
        assertEquals(listOf("Smoke", "Stormwave", "Red"), special.map { it.name.values["en"] })
        assertEquals(listOf(25, 46, 72), special.map { it.unlockLevel })
        assertEquals(listOf(20, 50, 15), special.map { it.requirement?.amount })
    }

    @Test fun tappingAMilitaryCamoSetsTheWeaponLevel() {
        val m = h.model()
        val weapon = anyWeapon(m)
        val military = split(m, weapon.weaponId).first
        val third = military[2]
        val level = m.militaryLevel(mp, weapon.weaponId, third)!!
        m.toggleCamo(mp, weapon.weaponId, third)
        assertEquals(level, m.level(weapon.weaponId))
        assertTrue(military.take(3).all { m.isCamoComplete(mp, weapon.weaponId, it) })
        assertFalse(m.isCamoComplete(mp, weapon.weaponId, military[3]))
        m.toggleCamo(mp, weapon.weaponId, third)
        assertEquals(level - 1, m.level(weapon.weaponId))
        assertFalse(m.isCamoComplete(mp, weapon.weaponId, third))
    }

    @Test fun specialsOpenAtTheirOwnLevel() {
        val m = h.model()
        val weapon = anyWeapon(m)
        val (military, special) = split(m, weapon.weaponId)
        assertFalse(m.specialsWaitForMilitary(mp))
        m.setLevel(24, weapon)
        assertFalse(m.isCamoAvailable(mp, weapon.weaponId, special[0]))
        m.setLevel(25, weapon)
        assertFalse(m.allMilitaryComplete(mp, weapon.weaponId))
        assertFalse(m.isCamoComplete(mp, weapon.weaponId, military[3]))
        assertTrue(m.isCamoAvailable(mp, weapon.weaponId, special[0]))
        assertFalse(m.isCamoAvailable(mp, weapon.weaponId, special[1]))
        m.setLevel(m.maxLevel(weapon), weapon)
        assertTrue(military.all { m.isCamoComplete(mp, weapon.weaponId, it) })
        assertTrue(special.all { m.isCamoAvailable(mp, weapon.weaponId, it) })
        assertTrue(special.none { m.isCamoComplete(mp, weapon.weaponId, it) })
    }

    @Test fun theSwitchKeepsSpecialsForAfterMilitary() {
        val m = h.model(mapOf("specialsAfterMilitary" to "true"))
        val weapon = anyWeapon(m)
        val (military, special) = split(m, weapon.weaponId)
        assertTrue(m.specialsWaitForMilitary(mp))
        val last = m.militaryLevel(mp, weapon.weaponId, military.last())!!
        m.setLevel(last - 1, weapon)
        assertTrue(special.none { m.isCamoAvailable(mp, weapon.weaponId, it) })
        m.setLevel(last, weapon)
        assertTrue(special.take(2).all { m.isCamoAvailable(mp, weapon.weaponId, it) })
        assertFalse(m.isCamoAvailable(mp, weapon.weaponId, special[2]))
    }

    @Test fun aPrestigedWeaponKeepsEveryMilitaryCamo() {
        val m = h.model()
        val weapon = anyWeapon(m)
        val (military, special) = split(m, weapon.weaponId)
        m.setLevel(m.maxLevel(weapon), weapon)
        m.prestigeUp(weapon)
        assertEquals(1, m.level(weapon.weaponId))
        assertTrue(military.all { m.isCamoComplete(mp, weapon.weaponId, it) })
        assertTrue(special.all { m.isCamoAvailable(mp, weapon.weaponId, it) })
        m.toggleCamo(mp, weapon.weaponId, military[4])
        assertEquals(1, m.level(weapon.weaponId))
        assertTrue(m.isCamoComplete(mp, weapon.weaponId, military[4]))
    }

    @Test fun stageFiltersFollowTheTrack() {
        val m = h.model(mapOf("completionist" to
            """{"final": {"harmonicBreaksNeeded": 0}, "steps": [{"unlock": "weapon"}, {"unlock": "weapon"}, {"unlock": "weapon"}]}"""))
        val weapon = anyWeapon(m)
        val id = weapon.weaponId
        assertTrue(m.matches(WeaponFilter.ON_MILITARY, mp, id))
        m.setLevel(m.maxLevel(weapon), weapon)
        assertTrue(m.matches(WeaponFilter.ON_SPECIAL, mp, id))
        finishCamos(m, id)
        assertTrue(m.matches(WeaponFilter.IN_COMPLETIONIST, mp, id))
        assertTrue(m.matches(WeaponFilter.COMPLETE, mp, id))
        harmonicBreak(m, id)
        assertTrue(m.matches(WeaponFilter.HAS_FINAL, mp, id))
        assertFalse(m.matches(WeaponFilter.ON_MILITARY, mp, id))
    }

    @Test fun readyToGrindNeedsAnOpenChallenge() {
        val m = h.model()
        val weapon = anyWeapon(m)
        assertFalse(m.matches(WeaponFilter.READY, mp, weapon.weaponId))
        m.setLevel(m.maxLevel(weapon), weapon)
        assertTrue(m.matches(WeaponFilter.READY, mp, weapon.weaponId))
        finishCamos(m, weapon.weaponId)
        assertTrue(m.matches(WeaponFilter.READY, mp, weapon.weaponId))
    }

    @Test fun allWeaponsListsEveryWeaponOnce() {
        val m = h.model()
        val all = m.allWeaponsCategory()!!
        assertEquals(m.totalWeaponCount, all.weapons.size)
        assertEquals(all.weapons.size, all.weapons.map { it.weaponId }.toSet().size)
    }

    @Test fun militaryLevelsIgnoreThePrestigeStagesMax() {
        val weapon = anyWeapon(h.model())
        val m = h.model(mapOf("weaponCamos" to unpublishedMilitary(weapon.weaponId)))
        val last = split(m, weapon.weaponId).first.last()
        val before = m.militaryLevel(mp, weapon.weaponId, last)
        repeat(m.prestigeStages.size) {
            m.setLevel(m.maxLevel(weapon), weapon)
            m.prestigeUp(weapon)
        }
        assertEquals(before, m.militaryLevel(mp, weapon.weaponId, last))
        assertEquals(weapon.maxLevel, before)
    }

    // Rule switches

    @Test fun aSharedTrackCountsInEveryModeThatSharesIt() {
        val m = h.model(warzone = mapOf("trackFrom" to "\"multiplayer\""))
        val weapon = anyWeapon(m)
        val id = weapon.weaponId
        assertEquals(mp, m.trackMode("warzone"))
        m.setLevel(m.maxLevel(weapon), weapon)
        for (camo in m.camos(id, "warzone")) if (!m.isCamoComplete("warzone", id, camo)) m.toggleCamo("warzone", id, camo)
        assertTrue(m.allCamosComplete(id, mp))
        m.toggleCompletionist(mp, id, 0)
        assertTrue(m.isCompletionistComplete("warzone", id, 0))
        assertEquals(m.completionistRequirement(mp, id, 0)?.amount, m.completionistRequirement("warzone", id, 0)?.amount)
        assertTrue(m.isCompletionistComplete("dmz", id, 0))
    }

    @Test fun turningTheFinalCamoOffEndsTheTrackAtHarmonicBreak() {
        val m = h.model(mapOf(
            "completionist" to """{"final": {"enabled": false}}""",
            "mastery" to """{"tier1": {"weaponsNeeded": 1}}""",
        ))
        val id = anyWeapon(m).weaponId
        harmonicBreak(m, id)
        assertFalse(m.hasFinalCamo(mp, id))
        assertTrue(m.hasLastCompletionist(mp, id))
        assertTrue(m.isMasteryAchieved(mp, 1))
        assertEquals(3, m.completionistCamos(mp).size)
        assertEquals(m.completionist(mp).steps[2], m.lastCompletionist(mp))
    }

    @Test fun challengeMasteryOpensOnTheWholeRoster() {
        val m = h.model(mapOf(
            "completionist" to """{"final": {"enabled": false}}""",
            "mastery" to """
                {"unlock": "challenge",
                 "tier1": {"requirement": {"amount": 30, "unit": "kills", "description": {"en": "Get 30 kills."}},
                           "byCategory": {"0": {"amount": 40, "unit": "kills", "description": {"en": "Rifles."}}}}}
                """,
        ))
        val all = launchWeapons(m)
        val rifle = m.catalog!!.categories.first { it.categoryId == 0 }.weapons.first().weaponId
        val other = m.catalog!!.categories.first { it.categoryId != 0 }.weapons.first().weaponId
        assertEquals(40, m.masteryRequirement(mp, rifle, 1)?.amount)
        assertEquals(30, m.masteryRequirement(mp, other, 1)?.amount)

        for (weapon in all.dropLast(1)) m.toggleCompletionist(mp, weapon.weaponId, 2)
        assertFalse(m.isWeaponMasteryAvailable(mp, rifle, 1))
        m.toggleCompletionist(mp, all.last().weaponId, 2)
        assertTrue(m.isWeaponMasteryAvailable(mp, rifle, 1))
        assertFalse(m.isWeaponMasteryAvailable(mp, rifle, 2))

        m.setWeaponMasteryAmount(mp, rifle, 1, 40)
        assertTrue(m.isWeaponMasteryComplete(mp, rifle, 1))
        assertTrue(m.isWeaponMasteryAvailable(mp, rifle, 2))
        assertEquals(1, m.masteryProgress(mp, 1).done)
        assertTrue(m.matches(WeaponFilter.READY, mp, other))
    }

    @Test fun aWeaponCanHaveItsOwnChallenge() {
        val m = h.model(mapOf("completionist" to """
            {"steps": [{}, {"byCategory": {"0": {"amount": 50, "unit": "headshots", "description": {"en": "Rifles."}}},
                            "byWeapon": {"1": {"amount": 7, "unit": "kills", "description": {"en": "Mine."}}}}]}
            """))
        val rifles = m.catalog!!.categories.first { it.categoryId == 0 }.weapons
        assertEquals(7, m.completionistRequirement(mp, rifles.first { it.weaponId == 1 }.weaponId, 1)?.amount)
        assertEquals(50, m.completionistRequirement(mp, rifles.first { it.weaponId != 1 }.weaponId, 1)?.amount)
    }

    @Test fun theWarlordsPlatinumIsItsOwn() {
        val m = h.model()
        assertEquals(50, m.completionistRequirement(mp, 24, 1)?.amount)
        assertEquals(50, m.completionistRequirement(mp, 8, 1)?.amount)
    }

    @Test fun modeMasteryIsOneChallengePerTier() {
        val m = h.model(mapOf(
            "completionist" to """{"final": {"harmonicBreaksNeeded": 0}}""",
            "mastery" to """
                {"unlock": "mode",
                 "tier1": {"requirement": {"amount": 1, "unit": "times", "description": {"en": "Tick."}}},
                 "tier2": {"requirement": {"amount": 5, "unit": "times", "description": {"en": "Five."}}}}
                """,
        ))
        val ids = weapons(m).take(2).map { it.weaponId }
        assertEquals(MasteryKind.MODE, m.masteryKind(mp, 1))
        assertFalse(m.isModeMasteryAvailable(mp, 1))
        harmonicBreak(m, ids[0])
        assertTrue(m.isModeMasteryAvailable(mp, 1))
        assertFalse(m.isMasteryAchieved(mp, 1))
        assertFalse(m.isModeMasteryAvailable(mp, 2))

        m.toggleModeMastery(mp, 1, ids[0])
        assertTrue(m.isMasteryAchieved(mp, 1))
        assertTrue(m.isModeMasteryAvailable(mp, 2))
        m.setModeMasteryAmount(mp, 2, ids[1], 4)
        assertEquals(Progress(4, 5), m.masteryProgress(mp, 2))
        m.setModeMasteryAmount(mp, 2, ids[1], 9)
        assertTrue(m.isMasteryAchieved(mp, 2))
        m.toggleModeMastery(mp, 3, ids[0])
        assertTrue(m.isMasteryAchieved(mp, 3))
        assertFalse(m.isWeaponMasteryAvailable(mp, ids[0], 1))
    }

    @Test fun globalMasteryCountsEveryModesTiers() {
        val m = h.model(mapOf(
            "completionist" to """{"final": {"harmonicBreaksNeeded": 0}}""",
            "mastery" to """{"unlock": "mode"}""",
        ))
        val id = weapons(m).first().weaponId
        assertEquals(9, m.globalMasteryProgress.total)
        assertEquals(0, m.globalMasteryProgress.done)
        harmonicBreak(m, id)
        for (tier in 1..3) m.toggleModeMastery(mp, tier, id)
        assertEquals(3, m.globalMasteryProgress.done)
        assertEquals("Flashpoint", m.game.capstone?.name?.resolved(en))
    }

    @Test fun aHarmonicBreakTierCountsItself() {
        val m = h.model(mapOf(
            "completionist" to """{"final": {"harmonicBreaksNeeded": 0}}""",
            "mastery" to """
                {"unlock": "mode",
                 "tier1": {"requirement": {"amount": 2, "unit": "harmonic_breaks", "description": {"en": "Two."}}}}
                """,
        ))
        val ids = weapons(m).take(2).map { it.weaponId }
        harmonicBreak(m, ids[0])
        m.toggleModeMastery(mp, 1, ids[0])
        assertEquals(Progress(1, 2), m.masteryProgress(mp, 1))
        harmonicBreak(m, ids[1])
        assertTrue(m.isMasteryAchieved(mp, 1))
        assertEquals(m.completionist(mp).steps[2], m.modeMasteryCountedCamo(mp, 1))
    }

    @Test fun eachTierCanPickItsOwnKind() {
        val m = h.model(mapOf(
            "completionist" to """{"final": {"enabled": false}}""",
            "mastery" to """
                {"unlock": "mode",
                 "tier1": {"kind": "challenge", "unlock": "weapon",
                           "requirement": {"amount": 1, "unit": "times", "description": {"en": "Per gun."}}},
                 "tier2": {"requirement": {"amount": 1, "unit": "times", "description": {"en": "Mode."}}}}
                """,
        ))
        val id = anyWeapon(m).weaponId
        assertEquals(MasteryKind.CHALLENGE, m.masteryKind(mp, 1))
        assertEquals(MasteryKind.MODE, m.masteryKind(mp, 2))
        assertEquals(MasteryKind.MODE, m.masteryKind(mp, 3))
        m.toggleCompletionist(mp, id, 2)
        assertTrue(m.isWeaponMasteryAvailable(mp, id, 1))
        m.toggleWeaponMastery(mp, id, 1)
        assertFalse(m.isModeMasteryAvailable(mp, 2))
        for (weapon in weapons(m)) {
            if (!m.isCompletionistComplete(mp, weapon.weaponId, 2)) m.toggleCompletionist(mp, weapon.weaponId, 2)
            if (!m.isWeaponMasteryComplete(mp, weapon.weaponId, 1)) m.toggleWeaponMastery(mp, weapon.weaponId, 1)
        }
        assertTrue(m.isMasteryAchieved(mp, 1))
        assertTrue(m.isModeMasteryAvailable(mp, 2))
    }

    @Test fun aGateCanNeedACount() {
        val m = h.model(mapOf("completionist" to """{"steps": [{}, {"needed": 2}]}"""))
        val rifles = m.catalog!!.categories.first { it.categoryId == 0 }
        val melee = m.catalog!!.categories.first { it.weapons.size == 1 }
        assertEquals(2, m.completionistCategoryGateProgress(rifles, mp, 1).total)
        assertEquals(1, m.completionistCategoryGateProgress(melee, mp, 1).total)
        val ids = rifles.weapons.map { it.weaponId }
        m.toggleCompletionist(mp, ids[0], 0)
        m.toggleCompletionist(mp, ids[1], 0)
        assertTrue(m.isCompletionistAvailable(mp, ids[0], 1))
        assertFalse(m.isCompletionistAvailable(mp, ids[2], 1))
    }

    @Test fun aModeTierCanCountPlatinumsAndWaitForWeapons() {
        val m = h.model(mapOf(
            "completionist" to """{"final": {"harmonicBreaksNeeded": 0}}""",
            "mastery" to """
                {"unlock": "mode",
                 "tier1": {"weaponsNeeded": 2,
                           "requirement": {"amount": 3, "unit": "platinums", "description": {"en": "Three."}}}}
                """,
        ))
        val ids = weapons(m).take(3).map { it.weaponId }
        harmonicBreak(m, ids[0])
        assertFalse(m.isModeMasteryAvailable(mp, 1))
        harmonicBreak(m, ids[1])
        assertTrue(m.isModeMasteryAvailable(mp, 1))
        assertEquals(2, m.masteryProgress(mp, 1).done)
        m.toggleCompletionist(mp, ids[2], 1)
        assertTrue(m.isMasteryAchieved(mp, 1))
    }

    @Test fun quickTickTicksWithoutLevels() {
        val m = h.model()
        val weapon = anyWeapon(m)
        val (military, special) = split(m, weapon.weaponId)
        assertFalse(m.isCamoAvailable(mp, weapon.weaponId, special[2]))
        m.quickTick = true
        assertTrue(m.isCamoAvailable(mp, weapon.weaponId, special[2]))
        m.toggleCamo(mp, weapon.weaponId, military[4])
        assertTrue(military.take(5).all { m.isCamoComplete(mp, weapon.weaponId, it) })
        assertFalse(m.isCamoComplete(mp, weapon.weaponId, military[5]))
        assertEquals(0, m.level(weapon.weaponId))

        m.quickTick = false
        assertTrue(m.isCamoComplete(mp, weapon.weaponId, military[4]))
        m.toggleCamo(mp, weapon.weaponId, military[2])
        assertTrue(m.isCamoComplete(mp, weapon.weaponId, military[1]))
        assertTrue(military.drop(2).none { m.isCamoComplete(mp, weapon.weaponId, it) })
        assertEquals(0, m.level(weapon.weaponId))
    }

    @Test fun quickTickCascadesTheCompletionistRun() {
        val m = h.model(mapOf("mastery" to
            """{"unlock": "mode", "tier2": {"requirement": {"amount": 1, "unit": "times", "description": {"en": "x"}}}}"""))
        val ids = weapons(m).take(2).map { it.weaponId }
        m.setCompletionistAmount(mp, ids[1], 0, 1)
        m.quickTick = true
        assertTrue(m.isCompletionistAvailable(mp, ids[0], 2))
        assertTrue(m.isModeMasteryAvailable(mp, 3))

        m.toggleCompletionist(mp, ids[0], 2)
        assertTrue((0..2).all { m.isCompletionistComplete(mp, ids[0], it) })
        m.toggleCompletionist(mp, ids[0], 0)
        assertTrue((0..2).none { m.isCompletionistComplete(mp, ids[0], it) })

        m.quickTick = false
        m.setCompletionistAmount(mp, ids[1], 1, 10)
        m.quickTick = true
        m.toggleCompletionist(mp, ids[1], 0)
        assertEquals(10, m.completionistAmount(mp, ids[1], 1))

        m.toggleModeMastery(mp, 3, ids[0])
        assertTrue((1..3).all { m.isMasteryAchieved(mp, it) })
    }

    @Test fun quickTickCompletionistTicksTheCamoList() {
        val m = h.model()
        val id = weapons(m).first().weaponId
        m.quickTick = true
        assertFalse(m.allCamosComplete(id, mp))
        m.toggleCompletionist(mp, id, 0)
        assertTrue(m.allCamosComplete(id, mp))
        assertTrue(m.isCompletionistComplete(mp, id, 0))
        assertTrue(m.allCamosComplete(id, "dmz"))
        val first = m.camos(id, "dmz").first { it.group == "military" }
        m.toggleCamo("dmz", id, first)
        assertFalse(m.isCamoComplete(mp, id, first))
    }

    @Test fun quickTickUntickingALevelledCamoLowersTheLevel() {
        val m = h.model()
        val weapon = anyWeapon(m)
        val military = split(m, weapon.weaponId).first
        val level = m.militaryLevel(mp, weapon.weaponId, military[2])!!
        m.setLevel(level, weapon)
        m.quickTick = true
        m.toggleCamo(mp, weapon.weaponId, military[2])
        assertFalse(m.isCamoComplete(mp, weapon.weaponId, military[2]))
        assertEquals(level - 1, m.level(weapon.weaponId))
    }

    @Test fun countMasteryHasNoWeaponChallenges() {
        val m = h.model(mapOf("mastery" to "{}"))
        val id = anyWeapon(m).weaponId
        assertFalse(m.masteryUsesChallenges(mp))
        assertFalse(m.isWeaponMasteryAvailable(mp, id, 1))
    }

    @Test fun aPublishedMilitaryLevelWins() {
        val weapon = anyWeapon(h.model())
        val camos = """
            [{"weaponId": ${weapon.weaponId}, "camos": [
                {"itemId": 0, "name": {"en": "Military 1"}, "tier": 1, "unlockLevel": 5, "children": [], "group": "military"},
                {"itemId": 8, "name": {"en": "Special 1"}, "tier": 9, "children": [], "group": "special"}]}]
            """
        val m = h.model(mapOf("weaponCamos" to camos))
        val military = m.camos(weapon.weaponId, mp).first()
        assertEquals(5, m.militaryLevel(mp, weapon.weaponId, military))
        m.setLevel(5, weapon)
        assertTrue(m.isCamoComplete(mp, weapon.weaponId, military))
    }

    @Test fun prestigeNeedsAMaxedStageAndResetsTheLevel() {
        val m = h.model()
        val weapon = anyWeapon(m)
        assertTrue(m.prestigeStages.isNotEmpty())
        m.setLevel(weapon.maxLevel - 1, weapon)
        assertFalse(m.canPrestige(weapon))
        m.prestigeUp(weapon)
        assertEquals(0, m.prestige(weapon.weaponId))
        m.setLevel(weapon.maxLevel, weapon)
        assertTrue(m.canPrestige(weapon))
        m.prestigeUp(weapon)
        assertEquals(1, m.prestige(weapon.weaponId))
        assertEquals(1, m.level(weapon.weaponId))
        assertNotNull(m.prestigeName(weapon.weaponId))
    }

    @Test fun undoingAPrestigeLandsOnThePreviousStageMaxed() {
        val m = h.model()
        val weapon = anyWeapon(m)
        m.setLevel(weapon.maxLevel, weapon)
        m.prestigeUp(weapon)
        m.prestigeDown(weapon)
        assertEquals(0, m.prestige(weapon.weaponId))
        assertEquals(weapon.maxLevel, m.level(weapon.weaponId))
        m.prestigeDown(weapon)
        assertEquals(0, m.prestige(weapon.weaponId))
    }

    @Test fun theLastStageCannotBePrestigedPast() {
        val m = h.model()
        val weapon = anyWeapon(m)
        repeat(m.prestigeStages.size + 2) {
            m.setLevel(m.maxLevel(weapon), weapon)
            m.prestigeUp(weapon)
        }
        assertEquals(m.prestigeStages.size, m.prestige(weapon.weaponId))
        m.setLevel(m.maxLevel(weapon), weapon)
        assertFalse(m.canPrestige(weapon))
    }

    @Test fun progressSurvivesANewTrackerOnTheSameSave() {
        val first = h.model()
        val weapon = anyWeapon(first)
        first.setLevel(weapon.maxLevel, weapon)
        first.prestigeUp(weapon)
        first.setLevel(7, weapon)
        val second = h.model()
        assertEquals(1, second.prestige(weapon.weaponId))
        assertEquals(7, second.level(weapon.weaponId))
    }

    @Test fun prestigeCamosTickThemselvesFromPrestigeAndLevel() {
        val m = h.model()
        val weapon = anyWeapon(m)
        val id = weapon.weaponId
        assertEquals(4, m.prestigeCamos.size)
        assertEquals(weapon.maxLevel + 1, m.prestigeCamoLevel(m.prestigeCamos[1], id))
        assertFalse(m.isPrestigeCamoComplete(id, 0))
        m.setLevel(weapon.maxLevel, weapon)
        m.prestigeUp(weapon)
        assertTrue(m.isPrestigeCamoComplete(id, 0))
        assertFalse(m.isPrestigeCamoComplete(id, 1))
        m.setLevel(150, weapon)
        assertTrue(m.isPrestigeCamoComplete(id, 1))
        assertTrue(m.isPrestigeCamoComplete(id, 2))
        assertFalse(m.isPrestigeCamoComplete(id, 3))
    }

    @Test fun tappingAPrestigeCamoSetsPrestigeAndLevel() {
        val m = h.model()
        val weapon = anyWeapon(m)
        val id = weapon.weaponId
        m.togglePrestigeCamo(id, 2)
        assertEquals(1, m.prestige(id))
        assertEquals(150, m.level(id))
        assertTrue((0..2).all { m.isPrestigeCamoComplete(id, it) })
        m.togglePrestigeCamo(id, 2)
        assertEquals(149, m.level(id))
        m.togglePrestigeCamo(id, 0)
        assertEquals(0, m.prestige(id))
        assertEquals(weapon.maxLevel, m.level(id))
    }

    @Test fun quickTickingAPrestigeCamoSetsPrestigeAndLevel() {
        val m = h.model()
        val weapon = anyWeapon(m)
        val id = weapon.weaponId
        m.quickTick = true
        m.togglePrestigeCamo(id, 2)
        assertTrue((0..2).all { m.isPrestigeCamoComplete(id, it) })
        assertEquals(1, m.prestige(id))
        assertEquals(150, m.level(id))
        m.togglePrestigeCamo(id, 3)
        assertEquals(250, m.level(id))
        m.togglePrestigeCamo(id, 1)
        assertTrue(m.isPrestigeCamoComplete(id, 0))
        assertFalse(m.isPrestigeCamoComplete(id, 1))
        assertFalse(m.isPrestigeCamoComplete(id, 3))
        assertEquals(1, m.prestige(id))
        assertEquals(weapon.maxLevel, m.level(id))
        m.quickTick = false
        assertTrue(m.isPrestigeCamoComplete(id, 0))
        assertFalse(m.isPrestigeCamoComplete(id, 1))
    }

    @Test fun earlierQuickTicksLiftPrestigeOnce() {
        h.store.putString("mw4_progress_v2",
            """{"weaponLevels": {}, "weaponPrestige": {}, "amounts": {}, "completed": ["prestigecamo|0|0", "prestigecamo|0|2"]}""")
        val m = h.model()
        assertEquals(1, m.prestige(0))
        assertEquals(150, m.level(0))
        m.setLevel(20, m.weapon(0)!!)
        assertEquals(20, h.model().level(0))
    }

    @Test fun pinsKeepOneForFreeAndFiveForPremium() {
        val m = h.model()
        m.pin(3); m.pin(4)
        assertEquals(listOf(4), m.pinnedWeaponIds)
        assertEquals("[4]", h.store.getString("mw4_pinned_weapons_v2"))
        assertEquals(4, h.store.getInt("mw4_pinned_weapon_v1"))
        m.isPremium = true
        for (id in 0..6) m.pin(id)
        assertEquals(listOf(6, 5, 4, 3, 2), m.visiblePinnedWeaponIds)
        assertEquals(listOf(6, 5, 4, 3, 2), h.model().pinnedWeaponIds)
        m.unpin(6)
        assertEquals(5, m.pinnedWeaponId)
    }

    @Test fun everyChangeBumpsTheRevision() {
        val m = h.model()
        var heard = 0
        m.changeListener = { heard = it }
        val before = m.revision.value
        m.setLevel(10, anyWeapon(m))
        assertTrue(m.revision.value > before)
        assertEquals(m.revision.value, heard)
    }
}
