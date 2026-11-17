package app.camotrack.android

import app.camotrack.android.core.Fixtures
import app.camotrack.android.core.Harness
import app.camotrack.android.widgets.WidgetSnapshot
import app.camotrack.android.widgets.widgetSnapshot
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** The widgets' snapshot (iOS WidgetSync.widgetSnapshot). */
class WidgetSnapshotTests {
    private val mp = "multiplayer"
    private val keys: (String, Array<out Any?>) -> String = { key, _ -> key }

    @Test fun everyPlayedModeWithItsCountsAndTheOverallRing() {
        val m = Harness().model()
        val s = m.widgetSnapshot(mp, keys)!!
        assertEquals(m.visibleModes, s.modes.map { it.id })
        val mode = s.modes.first { it.id == mp }
        assertEquals(m.completionistCamos(mp).size, mode.steps.size)
        assertTrue(mode.steps.all { it.total == m.launchRoster(mp) && it.colorHex.matches(Regex("#[0-9A-F]{6}")) })
        assertEquals(3, mode.mastery.size)
        assertEquals("mw4.mode.multiplayer", mode.name)
        assertEquals(s.modes.sumOf { it.fraction } / s.modes.size, s.overall, 1e-9)
        assertEquals("mw4", s.game)
        assertEquals(mp, s.startMode)
        assertNull(s.pinned)
        assertEquals("mw4.widget.pin_prompt", s.pinPrompt)
    }

    @Test fun thePinnedWeaponWithItsNextCamo() {
        val m = Harness().model()
        val weapon = m.catalog!!.categories.first().weapons.first()
        m.pin(weapon.weaponId)
        val leaves = m.camos(weapon.weaponId, mp).flatMap(m::leafItems)
        m.toggleCamo(mp, weapon.weaponId, leaves[0])
        val pinned = m.widgetSnapshot(mp, keys)!!.pinned!!
        assertEquals(weapon.weaponId, pinned.weaponId)
        assertEquals(mp, pinned.mode)
        assertEquals(1, pinned.camosDone)
        assertEquals(leaves.size, pinned.camosTotal)
        assertEquals(leaves[1].name.resolved(), pinned.nextName)
        assertTrue(pinned.nextTotal >= 1)
    }

    @Test fun aStartModeNotPlayedFallsBackToTheFirst() {
        val m = Harness().model()
        assertEquals(m.visibleModes.first(), m.widgetSnapshot("nope", keys)!!.startMode)
    }

    @Test fun aGameWithoutAccountMasteryHasNoMasteryBars() {
        val game = Fixtures.games.firstOrNull { !it.hasAccountMastery } ?: return
        val s = Harness(game).plain().widgetSnapshot(game.modeIds.first(), keys)
        assertNotNull(s)
        assertTrue(s!!.modes.all { it.mastery.isEmpty() })
    }

    @Test fun roundTripsAndLinks() {
        val s = Harness().model().widgetSnapshot(mp, keys)!!
        assertEquals(s, WidgetSnapshot.decode(WidgetSnapshot.encode(s)))
        assertEquals("mw4camo://mode/warzone/weapon/12?game=bo7", WidgetSnapshot.link("warzone", 12, "bo7"))
        assertEquals(DeepLink.Target("warzone", Route.Weapon(12), "bo7"), DeepLink.parse(WidgetSnapshot.link("warzone", 12, "bo7")))
        assertEquals("BO7 Warzone", s.copy(gameName = "BO7").titled("Warzone"))
    }
}
