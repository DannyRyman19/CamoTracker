package app.camotrack.android.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/** Port of the iOS `SharedCamoTests`: one camo grind per weapon across MW4's modes. */
class SharedCamoTests {
    private val h = Harness()

    /** The HAN 86's first Special (Smoke) in a mode. */
    private fun special(m: GameTracker, mode: String) = m.camos(0, mode).first { it.group != "military" }

    @Test fun aSpecialDoneInDMZIsUnlockedInMultiplayer() {
        val m = h.plain()
        val mp = special(m, "multiplayer")
        assertFalse(m.isCamoComplete("multiplayer", 0, mp))
        m.toggleCamo("dmz", 0, special(m, "dmz"))
        assertTrue(m.isCamoComplete("multiplayer", 0, mp))
        assertTrue(m.isCamoComplete("warzone", 0, special(m, "warzone")))
        assertEquals(0, m.camoAmount("multiplayer", 0, mp))
    }

    @Test fun progressSavedBeforeTheRuleCarriesOver() {
        val m = h.plain()
        m.toggleCamo("dmz", 0, special(m, "dmz"))
        val again = h.plain()
        assertTrue(again.isCamoComplete("multiplayer", 0, special(again, "multiplayer")))
    }

    @Test fun untickingClearsItEverywhere() {
        val m = h.plain()
        m.toggleCamo("dmz", 0, special(m, "dmz"))
        m.toggleCamo("multiplayer", 0, special(m, "multiplayer"))
        assertFalse(m.isCamoComplete("dmz", 0, special(m, "dmz")))
    }

    @Test fun goldDoneInOneModeCountsInAll() {
        val m = h.plain()
        m.toggleCompletionist("dmz", 0, 0)
        assertTrue(m.isCompletionistComplete("multiplayer", 0, 0))
        m.toggleCompletionist("multiplayer", 0, 0)
        assertFalse(m.isCompletionistComplete("dmz", 0, 0))
    }

    private fun warzone(hidden: Boolean) {
        File(h.cache, "warzone.json").writeText(Fixtures.overlaid("warzone", mapOf("version" to "\"999.0.0\"", "hidden" to "$hidden")))
    }

    @Test fun aHiddenModeHasNoTab() {
        warzone(hidden = true)
        val m = h.plain()
        assertEquals("999.0.0", m.modes["warzone"]?.version)
        assertFalse("warzone" in m.visibleModes)
        assertTrue("multiplayer" in m.visibleModes && "dmz" in m.visibleModes)
    }

    @Test fun unhidingAModeBringsItsTabBack() {
        warzone(hidden = false)
        assertTrue("warzone" in h.plain().visibleModes)
    }

    @Test fun theSavedKeysMatchTheIOSFormat() {
        val m = h.plain()
        m.toggleCamo("dmz", 0, special(m, "dmz"))
        m.toggleCompletionist("multiplayer", 0, 1)
        val save = h.store.getString("mw4_progress_v2")!!
        assertTrue(save, "\"camo|dmz|0|8\"" in save || "camo|dmz|0|" in save)
        assertTrue(save, "comp|multiplayer|0|1" in save)
        assertTrue(save.startsWith("{"))
    }
}

/** Port of the iOS objective tests that need a tracker. */
class ObjectiveTests {
    private val h = Harness()
    private fun item(json: String) = CamoJson.decodeFromString(ChallengeItem.serializer(), json)

    @Test fun aFinishedObjectiveLeavesLiveNow() {
        val m = h.plain()
        val now = ChallengeItem.dayStart("2026-11-15")!!.plusSeconds(12 * 3600)
        val live = m.liveObjectives("multiplayer", now)
        val entry = live.first { it.categoryId == 1 && it.item.itemId == 101 }
        for (leaf in m.leafItems(entry.item)) m.setObjectiveAmount("multiplayer", 1, leaf, leaf.requirement?.amount ?: 1)
        assertTrue(m.objectiveProgressFraction(entry.item, "multiplayer", 1) >= 1)
        assertFalse(m.liveObjectives("multiplayer", now).any { it.id == entry.id })
        assertEquals(live.size - 1, m.liveObjectives("multiplayer", now).size)
        // Shared categories keep one track across modes
        assertTrue(m.objectiveProgressFraction(entry.item, "dmz", 1) >= 1)
    }

    @Test fun objectivesSayWhichModesTheyreIn() {
        val m = h.plain()
        assertEquals(ObjectiveScope.AllModes, m.objectiveScope(0, 100))
        assertEquals(ObjectiveScope.AllModes, m.objectiveScope(1, 101))
        assertEquals(ObjectiveScope.Only(listOf("warzone")), m.objectiveScope(1, 103))
        assertNull(m.objectiveScope(1, 999))
        val blackCell = m.modes["warzone"]!!.objectives.first { it.categoryId == 0 }.items.first()
        for (camo in blackCell.children) {
            val byMode = camo.requirement!!.byMode!!
            assertEquals(setOf("multiplayer", "warzone", "dmz"), byMode.map { it.mode }.toSet())
            assertTrue(byMode.all { it.description.values.size == 7 })
        }
    }

    @Test fun unorderedChildrenOpenAtOnceAndAfterSiblingsWaitsForTheRest() {
        val m = h.plain()
        val req = """"requirement": {"amount": 1, "unit": "times", "description": {"en": "x"}}"""
        val kids = listOf(
            item("""{"itemId": 0, "name": {"en": "A"}, "children": [], $req}"""),
            item("""{"itemId": 1, "name": {"en": "B"}, "children": [], $req}"""),
            item("""{"itemId": 2, "name": {"en": "M"}, "children": [], "afterSiblings": true, $req}"""),
        )
        val cat = 9_999
        assertTrue(m.isObjectiveAvailable("multiplayer", cat, kids, kids[1], ordered = false))
        assertFalse(m.isObjectiveAvailable("multiplayer", cat, kids, kids[1], ordered = true))
        assertFalse(m.isObjectiveAvailable("multiplayer", cat, kids, kids[2], ordered = false))
        m.toggleObjective("multiplayer", cat, kids[0])
        m.toggleObjective("multiplayer", cat, kids[1])
        assertTrue(m.isObjectiveAvailable("multiplayer", cat, kids, kids[2], ordered = false))
        assertEquals(1, m.objectiveAmount("multiplayer", cat, kids[0]))
        m.toggleObjective("multiplayer", cat, kids[0])
        assertEquals(0, m.objectiveAmount("multiplayer", cat, kids[0]))
    }
}
