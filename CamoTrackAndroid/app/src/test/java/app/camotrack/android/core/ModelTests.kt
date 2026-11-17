package app.camotrack.android.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant

/** Port of the iOS "Mastery overrides" suite, plus decoding of every bundled file. */
class ModelTests {
    private val base = MasteryCamo("mw4.ui.mercurial_drift", 0xFFFF0000.toInt(), listOf(1, 2, 3))
    private fun tier(json: String) = CamoJson.decodeFromString(MasteryTierConfig.serializer(), json)

    @Test fun noConfigLeavesTheCamoAlone() {
        val camo = base.applying(null)
        assertEquals(base, camo)
        assertNull(camo.weaponsNeeded)
        assertEquals(3, camo.gradient.size)
    }

    @Test fun aConfigReplacesOnlyTheFieldsItNames() {
        val camo = base.applying(tier("""{"weaponsNeeded": 7}"""))
        assertEquals(7, camo.weaponsNeeded)
        assertEquals(base.nameKey, camo.nameKey)
        assertNull(camo.nameOverride)
        assertEquals(3, camo.gradient.size)
        assertEquals("Override Drift", base.applying(tier("""{"name": {"en": "Override Drift"}}""")).dataName(listOf("en")))
    }

    @Test fun aThresholdBelowOneIsRaisedToOne() {
        assertEquals(1, base.applying(tier("""{"weaponsNeeded": 0}""")).weaponsNeeded)
        assertEquals(1, base.applying(tier("""{"weaponsNeeded": -4}""")).weaponsNeeded)
    }

    @Test fun coloursComeFromHexAndBadHexFallsBack() {
        assertEquals(0xFF22CC88.toInt(), HexColor.parse("#22CC88"))
        assertNotNull(HexColor.parse("22CC88"))
        assertNull(HexColor.parse("nope"))
        assertNull(HexColor.parse("#FFF"))
        assertEquals(2, base.applying(tier("""{"colors": ["#22CC88", "#0088FF"]}""")).gradient.size)
        assertEquals(0xFF22CC88.toInt(), base.applying(tier("""{"colors": ["#22CC88", "#0088FF"]}""")).color)
        assertEquals(3, base.applying(tier("""{"colors": ["nope", ""]}""")).gradient.size)
        assertEquals("#D4AF37", HexColor.toHex(BuiltInColors.gold))
    }

    @Test fun aModeFileDecodesWithOrWithoutTheBlocks() {
        val bare = CamoJson.decodeFromString(ModeFile.serializer(),
            """{"version": "1", "mode": "multiplayer", "weaponCamos": [], "objectives": []}""")
        assertNull(bare.mastery)
        assertNull(bare.completionist)
        val file = CamoJson.decodeFromString(ModeFile.serializer(), """
            {"version": "1", "mode": "multiplayer", "weaponCamos": [], "objectives": [],
             "mastery": {"tier2": {"weaponsNeeded": 9}},
             "completionist": {"steps": [{"requirement": {"amount": 1, "unit": "matches", "description": {"en": "Win."}}}],
                               "final": {"name": {"en": "Divergence"}, "harmonicBreaksNeeded": 5}}}
            """)
        assertEquals(9, file.mastery?.tier2?.weaponsNeeded)
        assertNull(file.mastery?.tier1)
        assertEquals(5, file.completionist?.final?.harmonicBreaksNeeded)
        assertEquals(1, file.completionist?.steps?.first()?.requirement?.amount)
    }

    @Test fun aModeFileMissingItsListsDoesNotDecode() {
        assertTrue(runCatching { CamoJson.decodeFromString(ModeFile.serializer(), """{"version": "999.0.0", "mode": "warzone"}""") }.isFailure)
        assertTrue(runCatching { CamoJson.decodeFromString(WeaponCatalog.serializer(), "{}") }.isFailure)
    }

    @Test fun everyBundledGameAndFileDecodes() {
        assertEquals(listOf("mw4", "bo7", "bo6", "mw3", "mw2"), Fixtures.games.map { it.id })
        for (game in Fixtures.games) {
            val service = DataService(game, Fixtures.tempDir(), Fixtures.seeds, Fixtures.offline)
            val catalog = service.loadSeedCatalog()
            assertNotNull("${game.id} weapons", catalog)
            assertTrue(catalog!!.categories.isNotEmpty())
            for (mode in game.modeIds) assertNotNull("${game.id} $mode", service.loadSeed(mode))
        }
    }

    @Test fun gameKeysKeepMW4sOriginalNames() {
        assertEquals("mw4_progress_v2", Fixtures.mw4.key("mw4_progress_v2", "progress"))
        assertEquals("ct_progress_bo7", Fixtures.game("bo7").key("mw4_progress_v2", "progress"))
        assertEquals("https://cdn.jsdelivr.net/gh/DannyRyman19/CamoTracker@master/Data/CT/BO7/", Fixtures.game("bo7").dataURL)
        assertEquals(listOf(GameRegistry.fallback), GameRegistry.parse("not json"))
    }

    @Test fun weaponUnlockLevelComesFromTheSentence() {
        val w = WeaponEntry(1, LocalizedText("X"), null, 30, LocalizedText(mapOf("en" to "Unlock at level 9.", "de" to "Stufe 12")))
        assertEquals(9, w.unlockLevel(listOf("en")))
        assertEquals(12, w.unlockLevel(listOf("de")))
        assertNull(w.copy(acquiredBy = "battlePass").unlockLevel(listOf("en")))
        assertNull(w.copy(unlockRequirement = LocalizedText("Unlocked by default.")).unlockLevel(listOf("en")))
    }

    @Test fun localizedTextFallsBackToEnglishThenAnything() {
        val t = LocalizedText(mapOf("en" to "Hi", "de" to "Hallo"))
        assertEquals("Hallo", t.resolved(listOf("de")))
        assertEquals("Hi", t.resolved(listOf("fr")))
        assertEquals("Ciao", LocalizedText(mapOf("it" to "Ciao")).resolved(listOf("fr")))
    }

    @Test fun playedModesNeverEmptyAndTheLastCantBeSwitchedOff() {
        val all = listOf("multiplayer", "warzone", "dmz")
        assertEquals(all, ModeSelection.played("", all))
        assertEquals(listOf("multiplayer", "dmz"), ModeSelection.played("dmz,multiplayer", all))
        assertEquals("dmz", ModeSelection.start("dmz", "dmz,multiplayer", all))
        assertEquals("multiplayer", ModeSelection.start("warzone", "dmz,multiplayer", all))
        assertEquals("multiplayer,dmz", ModeSelection.toggling("warzone", "", all))
        assertEquals("", ModeSelection.toggling("warzone", "multiplayer,dmz", all))
        assertEquals("dmz", ModeSelection.toggling("dmz", "dmz", all))
    }

    // Time-limited objectives (iOS ObjectiveWindowTests)

    private fun item(json: String) = CamoJson.decodeFromString(ChallengeItem.serializer(), json)
    private fun day(s: String, hour: Double = 12.0): Instant = ChallengeItem.dayStart(s)!!.plusMillis((hour * 3_600_000).toLong())

    @Test fun aSeasonIsLiveFromItsStartAndAnEventUntilTheEndOfItsLastDay() {
        val season = item("""{"itemId": 100, "name": {"en": "S1"}, "children": [], "starts": "2026-11-05"}""")
        assertEquals(ChallengeItem.Window.UPCOMING, season.window(day("2026-11-04")))
        assertEquals(ChallengeItem.Window.LIVE, season.window(day("2026-11-05", 0.0)))
        assertEquals(ChallengeItem.Window.LIVE, season.window(day("2027-03-01")))
        val event = item("""{"itemId": 1, "name": {"en": "E"}, "children": [], "starts": "2026-11-06", "ends": "2026-11-13"}""")
        assertEquals(ChallengeItem.Window.LIVE, event.window(day("2026-11-13", 23.9)))
        assertEquals(ChallengeItem.Window.ENDED, event.window(day("2026-11-14", 0.0)))
        assertEquals(ChallengeItem.Window.UNDATED, item("""{"itemId": 2, "name": {"en": "P"}, "children": []}""").window())
        assertFalse(event.isLeaf && event.children.isNotEmpty())
    }
}
