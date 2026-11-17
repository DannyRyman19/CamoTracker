package app.camotrack.android.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Port of the iOS `UnreadableSaveTests` (without iCloud), plus save compatibility and unlock dates. */
class SaveTests {
    private val h = Harness()
    private fun unreadableCopies() = h.store.keys().filter { it.startsWith("mw4_progress_v2_unreadable_") }

    @Test fun anUnreadableSaveIsKeptAsideAndTheSyncCopyStandsIn() {
        val bad = """{"weaponLevels": "a format this build can't read"}"""
        h.store.putString("mw4_progress_v2", bad)
        val m = GameTracker(h.game, DataService(h.game, h.cache, Fixtures.seeds, Fixtures.offline), h.store,
            clock = { h.now }, syncFallback = mapOf("l|0" to 30, "d|camo|multiplayer|0|1" to 1))
        assertFalse(m.loadedCleanly)
        assertEquals(bad, h.store.getString("mw4_progress_v2_unreadable"))
        assertEquals(1, unreadableCopies().size)
        assertEquals(bad, h.store.getString(unreadableCopies().first()))
        assertEquals(30, m.level(0))

        m.setLevel(31, m.weapon(0)!!)
        val again = h.plain()
        assertTrue(again.loadedCleanly)
        assertEquals(31, again.level(0))
        assertEquals(bad, h.store.getString("mw4_progress_v2_unreadable"))
    }

    @Test fun theSameUnreadableSaveIsKeptOnce() {
        h.store.putString("mw4_progress_v2", "{")
        h.plain()
        h.now += 5
        h.plain()
        assertEquals(1, unreadableCopies().size)
    }

    @Test fun noSaveYetIsACleanStart() {
        assertTrue(h.plain().loadedCleanly)
    }

    @Test fun anIOSSaveReadsAndWritesBackInTheSameShape() {
        val ios = """{"weaponLevels":{"0":30,"5":12},"weaponPrestige":{"0":0},"amounts":{"camo|multiplayer|0|8":20,"comp|multiplayer|0|0":1},
            "completed":["camo|multiplayer|1|0","obj|shared|1|5","mastery|multiplayer|3|1","modemastery|warzone|2"]}"""
        h.store.putString("mw4_progress_v2", ios)
        val m = h.plain()
        assertTrue(m.loadedCleanly)
        assertEquals(30, m.level(0))
        assertTrue(m.isCamoComplete("dmz", 0, m.camos(0, "multiplayer").first { it.itemId == 8 }))
        assertTrue(m.isCompletionistComplete("warzone", 0, 0))
        m.setLevel(31, m.weapon(0)!!)
        val written = CamoJson.decodeFromString(ProgressStore.serializer(), h.store.getString("mw4_progress_v2")!!)
        assertEquals(31, written.weaponLevels[0])
        assertEquals(12, written.weaponLevels[5])
        assertEquals(20, written.amounts["camo|multiplayer|0|8"])
        assertTrue("obj|shared|1|5" in written.completed)
        assertTrue("\"weaponLevels\":{\"0\":31" in h.store.getString("mw4_progress_v2")!!)
        // A save from before Weapon Prestige still reads
        h.store.putString("mw4_progress_v2", """{"weaponLevels":{"2":4},"amounts":{},"completed":[]}""")
        assertEquals(4, h.plain().level(2))
    }

    @Test fun syncValuesRoundTrip() {
        val m = h.plain()
        m.setLevel(40, m.weapon(0)!!)
        m.toggleCompletionist("multiplayer", 0, 0)
        val values = m.syncValues()
        assertEquals(40, values["l|0"])
        val other = Harness().plain()
        other.applySynced(values)
        assertEquals(40, other.level(0))
        assertTrue(other.isCompletionistComplete("multiplayer", 0, 0))
    }

    @Test fun eachGameKeepsItsOwnSave() {
        val bo7 = Harness(Fixtures.game("bo7"))
        val m = bo7.plain()
        val weapon = m.allWeapons.first()
        m.setLevel(10, weapon)
        assertNotNull(bo7.store.getString("ct_progress_bo7"))
        assertNull(bo7.store.getString("mw4_progress_v2"))
    }

    @Test fun firstEarnedDatesAreExactForNewTicksAndUnknownForOldOnes() {
        h.store.putString("mw4_progress_v2", """{"weaponLevels":{"0":72},"amounts":{},"completed":[]}""")
        val m = h.plain()
        val military = m.camos(0, "multiplayer").first { it.group == "military" }
        // Done before this device tracked dates: no date
        assertTrue(m.isCamoComplete("multiplayer", 0, military))
        assertNull(m.camoUnlockedDate("multiplayer", 0, military))

        h.now += 100
        val special = m.camos(0, "multiplayer").first { it.group == "special" }
        m.toggleCamo("multiplayer", 0, special)
        assertEquals(UnlockDate(h.now, UnlockDate.Kind.EXACT), m.camoUnlockedDate("multiplayer", 0, special))
        // Taken back within ten minutes: a mis-tap, its date goes
        h.now += 60
        m.toggleCamo("multiplayer", 0, special)
        h.now += 1_000
        m.toggleCamo("multiplayer", 0, special)
        assertEquals(h.now, m.camoUnlockedDate("multiplayer", 0, special)?.epochSeconds)
        // And it survives a relaunch
        assertEquals(h.now, h.plain().camoUnlockedDate("multiplayer", 0, special)?.epochSeconds)
    }
}

class MilestoneTests {
    private val h = Harness()
    private val mp = "multiplayer"

    private fun record(m: GameTracker): MutableList<Milestone> = mutableListOf<Milestone>().also { list -> m.milestoneListener = { list += it } }

    @Test fun finishingTheCamoListAnnouncesItOnceWithoutNamingAMode() {
        val m = h.plain()
        val heard = record(m)
        m.setLevel(m.weapon(0)!!.maxLevel, m.weapon(0)!!)
        for (camo in m.camos(0, mp)) if (!m.isCamoComplete(mp, 0, camo)) m.toggleCamo(mp, 0, camo)
        val done = heard.filterIsInstance<Milestone.CamosComplete>()
        // Each MW4 mode's list finishes with the same shared camos
        assertTrue(done.isNotEmpty())
        assertTrue(done.all { it.weaponId == 0 && it.shareMode == null })
        assertEquals(done.size, done.map { it.mode }.toSet().size)
    }

    @Test fun completionistAndFinalAndMasteryAreAnnouncedInOrder() {
        val m = h.model(mapOf(
            "completionist" to """{"final": {"harmonicBreaksNeeded": 0}}""",
            "mastery" to """{"tier1": {"weaponsNeeded": 1}}""",
        ))
        val heard = record(m)
        m.toggleCompletionist(mp, 0, 0)
        assertEquals(0, (heard.single() as Milestone.CompletionistUnlocked).step)
        heard.clear()
        m.toggleCompletionist(mp, 0, 2)
        assertEquals(
            listOf(Milestone.CompletionistUnlocked::class, Milestone.FinalUnlocked::class, Milestone.MasteryUnlocked::class),
            heard.map { it::class },
        )
        val final = heard[1] as Milestone.FinalUnlocked
        assertEquals(0, final.weaponId)
        val tier = heard[2] as Milestone.MasteryUnlocked
        assertEquals(1, tier.tier)
        assertEquals(mp, tier.shareMode)
    }
}

/** A game without account Mastery: Prestige camos earned across weapons (BO7's Cold Snap). */
class BO7Tests {
    private val h = Harness(Fixtures.game("bo7"))

    @Test fun weaponsNeededPrestigeCamosCountAcrossWeapons() {
        val m = h.plain()
        assertFalse(m.isMasteryAchieved("multiplayer", 1))
        val index = m.prestigeCamos.indexOfFirst { it.weaponsNeeded != null }
        assertTrue(index >= 0)
        val camo = m.prestigeCamos[index]
        val needed = camo.weaponsNeeded!!
        val row = m.gameCamoProgress.first { it.name == camo.name }
        assertEquals(Progress(0, needed), Progress(row.done, row.total))
        // Not by hand outside quick tick
        val first = m.allWeapons.first().weaponId
        m.togglePrestigeCamo(first, index)
        assertFalse(m.isPrestigeCamoComplete(first, index))
        // Reaching it on enough weapons earns it on every weapon
        for (weapon in m.allWeapons.take(needed)) {
            while (true) {
                m.setLevel(m.maxLevel(weapon), weapon)
                if (!m.canPrestige(weapon)) break
                m.prestigeUp(weapon)
            }
            assertTrue(m.hasReachedPrestigeCamo(camo, weapon.weaponId))
        }
        assertEquals(needed, m.prestigeCamoWeaponCount(camo))
        assertTrue(m.isPrestigeCamoComplete(m.allWeapons.last().weaponId, index))
    }

    @Test fun capstoneCountsEveryModesFinalCamo() {
        val m = h.plain()
        val parts = m.capstoneModes
        assertEquals(m.game.modeIds.filter { m.finalEnabled(it) && m.modes[it] != null }, parts.map { it.first })
        assertTrue(parts.none { it.second })
        assertEquals("Nexus Horizon", m.gameCamoProgress.last().name.resolved(listOf("en")))
    }
}
