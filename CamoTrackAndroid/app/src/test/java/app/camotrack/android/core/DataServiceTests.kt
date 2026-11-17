package app.camotrack.android.core

import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/** Port of the iOS `DataServiceTests` (versions, seed vs cache, refresh, the GitHub fallback). */
class DataServiceTests {
    private val mw4 = Fixtures.mw4
    private fun service(fetcher: Fetcher, cache: File = Fixtures.tempDir()) = DataService(mw4, cache, Fixtures.seeds, fetcher)

    @Test fun versionsCompareNumberByNumber() {
        val cases = listOf(
            Triple("0.9.12", "0.9.11", true),
            Triple("0.10.0", "0.9.11", true),
            Triple("1", "0.9.11", true),
            Triple("0.9.11.1", "0.9.11", true),
            Triple("0.9.11", "0.9.11", false),
            Triple("0.9.11.0", "0.9.11", false),
            Triple("0.9.1", "0.9.11", false),
            Triple("0.9.11a", "0.9.11", false),
            Triple("1.0.0-hotfix", "1.0.0", false),
            Triple("2026-11-03", "0.9.11", false),
        )
        for ((version, known, newer) in cases) assertEquals("$version vs $known", newer, DataService.isNewer(version, known))
    }

    @Test fun anyVersionBeatsNone() {
        assertTrue(DataService.isNewer("0.0.1", null))
        assertTrue(DataService.canReplace(null, "0.0.1"))
        assertTrue(DataService.canReplace("0.9.11", "0.9.11"))
        assertFalse(DataService.canReplace("0.9.12", "0.9.11"))
    }

    @Test fun newerOfBundledAndDownloadedWins() {
        fun pick(seed: String?, cached: String?) = DataService.newest(seed, cached) { it }
        assertEquals("0.9.12", pick("0.9.12", "0.9.11"))
        assertEquals("0.9.12", pick("0.9.11", "0.9.12"))
        assertEquals("0.9.11", pick("0.9.11", "0.9.11"))
        assertEquals("0.9.11", pick(null, "0.9.11"))
        assertEquals("0.9.11", pick("0.9.11", null))
    }

    @Test fun olderDownloadLosesToNewerBundledData() {
        val seedCatalog = service(Fixtures.offline).loadSeedCatalog()!!.version
        val seedMode = service(Fixtures.offline).loadSeed("warzone")!!.version
        val cache = Fixtures.tempDir()
        File(cache, "weapons.json").writeText(Fixtures.withVersion("weapons", "0.0.1"))
        File(cache, "warzone.json").writeText(Fixtures.withVersion("warzone", "0.0.1"))
        val s = service(Fixtures.offline, cache)
        assertEquals("0.0.1", s.loadCachedCatalog()?.version)
        assertEquals(seedCatalog, s.loadCatalog()?.version)
        assertEquals(seedMode, s.load("warzone")?.version)
        File(cache, "weapons.json").writeText(Fixtures.withVersion("weapons", "999.0.0"))
        assertEquals("999.0.0", s.loadCatalog()?.version)
    }

    @Test fun everyRequestAsksForTheManifestAndNewerFiles() = runTest {
        val fetcher = RecordingFetcher(mapOf("manifest.json" to """{"catalog": {"version": "2", "path": "weapons.json"}, "modes": {}}"""))
        runCatching { service(fetcher).refreshIfNeeded("1", emptyMap()) }
        assertEquals(1, fetcher.count("manifest.json"))
        assertEquals(1, fetcher.count("weapons.json"))
    }

    @Test fun olderDownloadNeverReplacesANewerKeptCopy() = runTest {
        val cache = Fixtures.tempDir()
        File(cache, "weapons.json").writeText(Fixtures.withVersion("weapons", "9.9.9"))
        val fetcher = RecordingFetcher(mapOf(
            "manifest.json" to """{"catalog": {"version": "5.0.0", "path": "weapons.json"}, "modes": {}}""",
            "weapons.json" to Fixtures.withVersion("weapons", "5.0.0"),
        ))
        val s = service(fetcher, cache)
        assertNull(s.refreshIfNeeded("1", emptyMap()).catalog)
        assertEquals("9.9.9", s.loadCachedCatalog()?.version)
    }

    @Test fun overlappingRefreshesShareOneCheck() = runTest {
        val fetcher = RecordingFetcher(mapOf("manifest.json" to """{"catalog": {"version": "0", "path": "weapons.json"}, "modes": {}}"""))
        val tracker = GameTracker(mw4, service(fetcher), InMemoryKeyValueStore(), ioDispatcher = StandardTestDispatcher(testScheduler))
        listOf(async { tracker.refresh() }, async { tracker.refresh() }).awaitAll()
        assertEquals(1, fetcher.count("manifest.json"))
        assertNull(tracker.refreshError)
        tracker.refresh()
        assertEquals(2, fetcher.count("manifest.json"))
    }

    @Test fun aRefreshInstallsNewerFilesAndTheirRules() = runTest {
        val fetcher = RecordingFetcher(mapOf(
            "manifest.json" to """{"catalog": {"version": "0", "path": "weapons.json"}, "modes": {"multiplayer": {"version": "999.0.0", "path": "multiplayer.json"}},
                "notification": {"title": {"en": "Season 1"}, "id": "a1"}}""",
            "multiplayer.json" to Fixtures.overlaid("multiplayer", mapOf("version" to "\"999.0.0\"", "mastery" to """{"tier1": {"weaponsNeeded": 777}}""")),
        ))
        val tracker = GameTracker(mw4, service(fetcher), InMemoryKeyValueStore(), ioDispatcher = StandardTestDispatcher(testScheduler))
        val before = tracker.revision.value
        tracker.refresh()
        assertEquals("999.0.0", tracker.modes["multiplayer"]?.version)
        assertEquals(777, tracker.masteryWeaponsNeeded("multiplayer", 1))
        assertEquals("a1", tracker.lastAnnouncement?.id)
        assertTrue(tracker.revision.value > before)
    }

    @Test fun oneBadModeFileDoesntStopTheRest() = runTest {
        val cache = Fixtures.tempDir()
        val fetcher = RecordingFetcher(mapOf(
            "manifest.json" to """
                {"catalog": {"version": "999.0.0", "path": "weapons.json"},
                 "modes": {"multiplayer": {"version": "999.0.0", "path": "multiplayer.json"},
                           "warzone": {"version": "999.0.0", "path": "warzone.json"}}}
                """,
            "weapons.json" to Fixtures.withVersion("weapons", "999.0.0"),
            "multiplayer.json" to Fixtures.withVersion("multiplayer", "999.0.0"),
            "warzone.json" to """{"version": "999.0.0", "mode": "warzone"}""",
        ))
        val s = service(fetcher, cache)
        val result = s.refreshIfNeeded("1", mapOf("multiplayer" to "1", "warzone" to "1"))
        assertEquals("999.0.0", result.catalog?.version)
        assertEquals(listOf("multiplayer"), result.modes.keys.sorted())
        assertEquals("999.0.0", s.loadCached("multiplayer")?.version)
        assertNull(s.loadCached("warzone"))

        fetcher.bodies = fetcher.bodies + mapOf("weapons.json" to "{}", "multiplayer.json" to "{}")
        assertTrue(runCatching { service(fetcher).refreshIfNeeded("1", emptyMap()) }.isFailure)
    }

    @Test fun aFailedJsDelivrRequestIsAskedOfGitHubOnce() = runTest {
        for (status in listOf(403, 0)) {
            val fetcher = RecordingFetcher(mapOf(
                "manifest.json" to """{"catalog": {"version": "999.0.0", "path": "weapons.json"}, "modes": {}}""",
                "weapons.json" to Fixtures.withVersion("weapons", "999.0.0"),
            ))
            fetcher.failingHosts = mapOf("cdn.jsdelivr.net" to status)
            assertEquals("999.0.0", service(fetcher).refreshIfNeeded("1", emptyMap()).catalog?.version)
            assertEquals(listOf(
                "https://cdn.jsdelivr.net/gh/DannyRyman19/CamoTracker@master/Data/MW4/manifest.json",
                "https://raw.githubusercontent.com/DannyRyman19/CamoTracker/master/Data/MW4/manifest.json",
                "https://cdn.jsdelivr.net/gh/DannyRyman19/CamoTracker@master/Data/MW4/weapons.json",
                "https://raw.githubusercontent.com/DannyRyman19/CamoTracker/master/Data/MW4/weapons.json",
            ), fetcher.requests)
        }
    }

    @Test fun gitHubsCopyIsVersionCheckedToo() = runTest {
        val cache = Fixtures.tempDir()
        File(cache, "weapons.json").writeText(Fixtures.withVersion("weapons", "9.9.9"))
        val fetcher = RecordingFetcher(mapOf(
            "manifest.json" to """{"catalog": {"version": "5.0.0", "path": "weapons.json"}, "modes": {}}""",
            "weapons.json" to Fixtures.withVersion("weapons", "5.0.0"),
        ))
        fetcher.failingHosts = mapOf("cdn.jsdelivr.net" to 403)
        val s = service(fetcher, cache)
        assertNull(s.refreshIfNeeded("1", emptyMap()).catalog)
        assertEquals("9.9.9", s.loadCachedCatalog()?.version)
    }

    @Test fun bothFailingIsAnError() = runTest {
        val fetcher = RecordingFetcher()
        fetcher.failingHosts = mapOf("cdn.jsdelivr.net" to 403, "raw.githubusercontent.com" to 404)
        assertTrue(runCatching { service(fetcher).refreshIfNeeded("1", emptyMap()) }.isFailure)
        assertEquals(2, fetcher.requests.size)
        // And a tracker reports it without losing its data
        val tracker = GameTracker(mw4, service(fetcher), InMemoryKeyValueStore(), ioDispatcher = StandardTestDispatcher(testScheduler))
        tracker.refresh()
        assertTrue(tracker.refreshError != null)
        assertTrue(tracker.modes.isNotEmpty())
    }

    @Test fun theManifestCarriesTheAnnouncementsIdAndLinkAndOldManifestsStillRead() {
        val new = """{"catalog":{"version":"1","path":"w.json"},"modes":{},"notification":{"title":{"en":"Hi"},"id":"mw4-20261116T1900Z","link":"mw4camo://mode/current/event/1/102"}}"""
        val old = """{"catalog":{"version":"1","path":"w.json"},"modes":{},"notification":{"title":{"en":"Hi"}}}"""
        val decoded = CamoJson.decodeFromString(Manifest.serializer(), new).notification
        assertEquals("mw4-20261116T1900Z", decoded?.id)
        assertEquals("mw4camo://mode/current/event/1/102", decoded?.link)
        assertNull(CamoJson.decodeFromString(Manifest.serializer(), old).notification?.id)
    }
}
