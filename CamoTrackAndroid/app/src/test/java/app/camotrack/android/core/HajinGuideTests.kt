package app.camotrack.android.core

import app.camotrack.android.core.hajin.GuideText
import app.camotrack.android.core.hajin.HajinGuide
import app.camotrack.android.core.hajin.HajinGuideService
import app.camotrack.android.core.hajin.HajinStore
import app.camotrack.android.core.hajin.HajinVerdict
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.builtins.serializer
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/** Port of the iOS `HajinGuideTests` (the guide, its refresh, and My DMZ's store), less the SF Symbol check. */
class HajinGuideTests {
    private fun service(fetcher: Fetcher = Fixtures.offline) = HajinGuideService(Fixtures.mw4, Fixtures.tempDir(), Fixtures.seeds, fetcher)
    private val guide: HajinGuide by lazy { service().loadSeed()!! }
    private fun store(kv: KeyValueStore = InMemoryKeyValueStore()) = HajinStore(kv, guide)

    @Test fun bundledGuideIsWellFormed() {
        val categories = guide.categories.map { it.id }.toSet()
        assertEquals("marker ids must be unique", guide.markers.size, guide.markers.map { it.id }.toSet().size)
        for (marker in guide.markers) {
            assertTrue("${marker.id} has unknown category ${marker.cat}", marker.cat in categories)
            assertTrue("${marker.id} is off the map", marker.x in 0.0..1.0 && marker.y in 0.0..1.0)
            marker.threat?.let { assertNotNull(guide.threatName(it)) }
        }
        assertTrue(guide.guide.isNotEmpty())
        // Every link lands somewhere: recipe ingredients, guide rows, key markers
        val items = guide.items!!
        val ids = items.map { it.id }.toSet()
        assertEquals("item ids must be unique", items.size, ids.size)
        for (item in items) {
            for (part in item.cost ?: emptyList()) assertTrue("${item.id} needs unknown ${part.item}", part.item in ids)
            item.marker?.let { assertNotNull("${item.id} points at missing marker $it", guide.marker(it)) }
        }
        for (section in guide.guide) for (row in section.rows) row.item?.let { assertTrue("${section.id} row links unknown $it", it in ids) }
        // The Tac Map picture ships with the app
        assertTrue(File("src/main/assets/${guide.map.image}.jpg").isFile)
    }

    @Test fun guideTextTakesAPlainStringOrTranslations() {
        val plain = CamoJson.decodeFromString(GuideText.serializer(), "\"Rice Mill\"")
        assertEquals(mapOf("en" to "Rice Mill"), plain.values)
        val translated = CamoJson.decodeFromString(GuideText.serializer(), """{"en": "Map", "de": "Karte"}""")
        assertEquals("Karte", translated.values["de"])
    }

    /** A manifest from before guides existed still decodes, and simply has nothing to download. */
    @Test fun manifestWithoutGuidesFetchesNothing() = runTest {
        val fetcher = RecordingFetcher(mapOf("manifest.json" to """{"catalog": {"version": "1", "path": "weapons.json"}, "modes": {}}"""))
        assertNull(service(fetcher).refresh(knownVersion = "0.1.0"))
    }

    @Test fun newerGuideIsDownloadedAndCached() = runTest {
        val bundled = guide.version
        val fetcher = RecordingFetcher(mapOf(
            "manifest.json" to """{"catalog": {"version": "1", "path": "weapons.json"}, "modes": {}, "guides": {"hajin": {"version": "9.9.9", "path": "hajin.json"}}}""",
            "hajin.json" to Fixtures.withVersion("hajin", "9.9.9"),
        ))
        val service = service(fetcher)
        assertEquals("9.9.9", service.refresh(knownVersion = bundled)?.version)
        assertEquals("9.9.9", service.loadCached()?.version)
        assertEquals("9.9.9", service.load()?.version)
        // Already up to date: nothing more to fetch
        assertNull(service.refresh(knownVersion = "9.9.9"))
    }

    /** Printing an upgrade takes its cost out of the stash (never below zero), stops tracking it, and Undo puts both back. */
    @Test fun printingSpendsTheStashAndUndoRestoresIt() {
        val store = store()
        // Stash Weapon Upgrade I: 20 Reactive Metals, 10 Stock Rod, 5 Comms Module
        store.setCount(25, "reactive-metals")
        store.setCount(4, "stock-rod")
        store.toggleTracked("stash-weapon-upgrade-i")
        store.toggle("upgrade-stash-weapon-upgrade-i")
        assertEquals(5, store.count("reactive-metals"))
        assertEquals(0, store.count("stock-rod"))
        assertFalse(store.isTracked("stash-weapon-upgrade-i"))
        assertNotNull(store.stashUndo)
        store.undoStash()
        assertEquals(25, store.count("reactive-metals"))
        assertEquals(4, store.count("stock-rod"))
        assertTrue(store.isTracked("stash-weapon-upgrade-i"))
        assertTrue("upgrade-stash-weapon-upgrade-i" in store.checked)
    }

    @Test fun unfinishedOrdersKeepWhatTheyPrintWith() {
        val reactive = guide.item("reactive-metals")!!
        // Page 10's Healer: 3 to extract plus the Armor Box's 3
        val open = HajinVerdict(reactive, guide, emptySet())
        assertEquals(HajinVerdict.Kind.KEEP, open.kind)
        assertEquals(6, open.orders.firstOrNull { it.first.check == "op-page-10-healer" }?.second)
        // Every order ticked: nothing left to hold for
        val ticks = guide.section("ops")?.rows?.mapNotNull { it.check }?.toSet() ?: emptySet()
        assertTrue(guide.orderNeeds(ticks).isEmpty())
        assertTrue(HajinVerdict(reactive, guide, ticks).orders.isEmpty())
        // Manuals and dog tags have to be found in the match, so never held
        assertFalse(guide.orderNeeds(emptySet()).any { it.item == "weapon-manual" || it.item.contains("dog-tag") })
    }

    @Test fun operatorsKeepTheirPrestigeAndUpToThreeTraits() {
        val kv = InMemoryKeyValueStore()
        val store = store(kv)
        store.addOperator(" Ghost ")
        store.addOperator("ghost")   // the same operator
        store.addOperator("Roze|")
        assertEquals(listOf("Ghost", "Roze"), store.operators.map { it.name })
        store.setPrestige(2, "Ghost")
        assertEquals(2, store.operators.first { it.name == "Ghost" }.level)
        for (trait in listOf("Possum Pro", "Overwatch Pro", "Die Hard Pro", "Quick Fix Pro")) store.togglePrestigeTrait(trait, "Ghost")
        assertEquals(listOf("Die Hard Pro", "Overwatch Pro", "Possum Pro"), store.prestigeTraits("Ghost"))
        // Kept in the saved ticks, and gone with the operator
        assertEquals(2, store(kv).operators.size)
        store.removeOperator("Ghost")
        assertEquals(listOf("Roze"), store.operators.map { it.name })
        assertTrue(store.prestigeTraits("Ghost").isEmpty())
    }

    /** Prestige set on two devices before they synced leaves two keys: the operator shows once, at the higher level. */
    @Test fun anOperatorSetOnTwoDevicesShowsOnce() {
        val kv = InMemoryKeyValueStore()
        kv.putString(HajinStore.CHECKED_KEY, CamoJson.encodeToString(ListSerializer(String.serializer()),
            listOf("prestige|Ghost|3", "prestige|Ghost|4", "prestige|Roze|1", "prestige-trait|Ghost|Possum Pro")))
        val store = store(kv)
        assertEquals(listOf("Ghost", "Roze"), store.operators.map { it.name })
        assertEquals(4, store.operators.first().level)
        assertFalse("prestige|Ghost|3" in store.checked)
        assertEquals(listOf("Possum Pro"), store.prestigeTraits("Ghost"))
    }

    @Test fun canPrintNeedsTheCashToo() {
        val store = store()
        // An upgrade with a cash price, its ingredients all in the stash
        val upgrade = guide.items!!.first {
            it.kind == "FOB Upgrade" && (it.cash ?: 0) > 0 && !it.cost.isNullOrEmpty() && it.requiredLevel == null &&
                it.effect?.en?.contains("Ingredient Printing") != true
        }
        for (part in upgrade.cost!!) store.setCount(part.qty, part.item)
        val price = upgrade.cash!!
        assertFalse("no cash entered", store.canPrint(upgrade))
        store.setCash(price - 1)
        assertFalse(store.canPrint(upgrade))
        store.setCash(price)
        assertTrue(store.canPrint(upgrade))
    }

    /** My DMZ is saved under the iOS keys, lists and dictionaries as JSON. */
    @Test fun savesUnderTheIOSKeys() {
        val kv = InMemoryKeyValueStore()
        val store = store(kv)
        store.setLevel(12)
        store.setCash(33_050)
        store.setCount(7, "metals")
        store.toggleTracked("stash-weapon-upgrade-i")
        store.toggle("boss-colossus")
        assertEquals(12, kv.getInt("mw4_hajin_dmz_level"))
        assertEquals(33_050, kv.getInt("mw4_hajin_cash"))
        assertEquals("""{"metals":7}""", kv.getString("mw4_hajin_stash"))
        assertEquals("""["stash-weapon-upgrade-i"]""", kv.getString("mw4_hajin_tracked"))
        assertEquals("""["boss-colossus"]""", kv.getString("mw4_hajin_checked"))
        // And read back
        val again = store(kv)
        assertEquals(12, again.dmzLevel)
        assertEquals(7, again.count("metals"))
        assertTrue("boss-colossus" in again.checked)
    }

    /** The map filter starts from each category's default, and a category added later starts from its own. */
    @Test fun mapFilterStartsFromTheDefaults() {
        val kv = InMemoryKeyValueStore()
        val store = store(kv)
        val defaults = guide.categories.filter { !it.visible }.map { it.id }.toSet()
        assertEquals(defaults, store.hiddenCategories)
        store.hiddenCategories = setOf("area")
        assertEquals(setOf("area"), store.hiddenCategories)
        // Saved before "ember" existed: it starts hidden, as its default says
        kv.putString(HajinStore.SEEN_CATEGORIES_KEY, CamoJson.encodeToString(ListSerializer(String.serializer()),
            guide.categories.map { it.id }.filter { it != "ember" }))
        assertEquals(setOf("area", "ember"), store.hiddenCategories)
    }
}
