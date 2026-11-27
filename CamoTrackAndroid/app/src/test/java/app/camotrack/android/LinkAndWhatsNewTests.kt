package app.camotrack.android

import app.camotrack.android.core.InMemoryKeyValueStore
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** iOS DeepLinkTests and WhatsNewTests, for the Android ports. */
class LinkAndWhatsNewTests {
    private val shipped = WhatsNew.releases
    @After fun reset() { WhatsNew.releases = shipped }

    @Test fun parsesEveryLinkForm() {
        assertEquals(DeepLink.Target("warzone", null, null), DeepLink.parse("mw4camo://mode/warzone"))
        assertEquals(DeepLink.Target("warzone", Route.Weapon(12), null), DeepLink.parse("mw4camo://mode/warzone/weapon/12"))
        assertEquals(DeepLink.Target(null, Route.ObjectiveItem(1, 102), null), DeepLink.parse("mw4camo://mode/current/event/1/102"))
        assertEquals(DeepLink.Target("dmz", Route.ObjectiveCategory(3), "bo7"), DeepLink.parse("mw4camo://mode/dmz/events/3?game=bo7"))
        assertNull(DeepLink.parse("https://camo-track.app/mode/warzone"))
        assertNull(DeepLink.parse("mw4camo://weapon/12"))
        assertNull(DeepLink.parse("mw4camo://mode/"))
    }

    @Test fun whatsNewNeverOnAFreshInstallAndOnceAfterAnUpdate() {
        val store = InMemoryKeyValueStore()
        WhatsNew.releases = mapOf("1.1" to listOf(WhatsNew.Item("overlay", "overlay")), "1.2" to listOf(WhatsNew.Item("push", "bell")))
        // Nothing announced for this version: nothing to show
        assertFalse(WhatsNew.shouldShow(store, hasOnboarded = true, version = "1.0"))
        // Fresh install: onboarding marks it seen
        assertFalse(WhatsNew.shouldShow(store, hasOnboarded = false, version = "1.2"))
        WhatsNew.markSeen(store, "1.0")
        // Updated past two releases: both, newest first
        assertTrue(WhatsNew.shouldShow(store, hasOnboarded = true, version = "1.2"))
        assertEquals(listOf("push", "overlay"), WhatsNew.items(store, "1.2").map { it.id })
        WhatsNew.markSeen(store, "1.2")
        assertFalse(WhatsNew.shouldShow(store, hasOnboarded = true, version = "1.2"))
        // From Customise afterwards: the same list
        assertEquals(listOf("push", "overlay"), WhatsNew.items(store, "1.2").map { it.id })
        assertTrue(WhatsNew.newer("1.0.10", "1.0.9"))
    }
}
