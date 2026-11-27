package app.camotrack.android.core

import app.camotrack.android.core.hajin.HajinStore
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class SyncTests {
    private fun snap(values: Map<String, Int>, stamps: Map<String, Double> = emptyMap()) = SyncSnapshot(values, stamps)

    @Test fun eachEntryComesFromWhicheverSideChangedItLast() {
        val local = snap(mapOf("a" to 1, "b" to 5), mapOf("a" to 10.0, "b" to 30.0))
        val remote = snap(mapOf("a" to 2, "b" to 9, "c" to 3), mapOf("a" to 20.0, "b" to 5.0, "c" to 1.0))
        val merged = SyncSnapshot.merge(local, remote)
        assertEquals(mapOf("a" to 2, "b" to 5, "c" to 3), merged.values)
        assertEquals(mapOf("a" to 20.0, "b" to 30.0, "c" to 1.0), merged.stamps)
        assertEquals(merged, SyncSnapshot.merge(remote, local))
    }

    @Test fun anUntickWinsOverAnOlderTickAndProgressFromBeforeSyncIsKept() {
        // "a" was un-ticked here after the other device ticked it; "old" has no stamp anywhere
        val local = snap(mapOf("old" to 1), mapOf("a" to 50.0))
        val remote = snap(mapOf("a" to 1, "theirs" to 1), mapOf("a" to 40.0))
        val merged = SyncSnapshot.merge(local, remote)
        assertEquals(mapOf("old" to 1, "theirs" to 1), merged.values)
        assertEquals(50.0, merged.stamps["a"]!!, 0.0)
    }

    @Test fun aSaveStampsOnlyWhatChanged() {
        val before = snap(mapOf("a" to 1, "b" to 2), mapOf("a" to 1.0))
        val after = before.updated(mapOf("a" to 1, "b" to 3, "c" to 1), 99.0)
        assertEquals(mapOf("a" to 1.0, "b" to 99.0, "c" to 99.0), after.stamps)
        assertEquals(mapOf("a" to 1.0, "b" to 99.0), before.updated(mapOf("a" to 1), 99.0).stamps)
    }

    @Test fun theStoredTextIsTheIphoneLayoutAndReadsBack() {
        val s = snap(mapOf("d|camo|multiplayer|3|7" to 1), mapOf("d|camo|multiplayer|3|7" to 1795790926.5))
        val text = s.encoded()
        assertTrue(text.contains("\"format\":1") && text.contains("\"values\"") && text.contains("\"stamps\""))
        assertEquals(SyncSnapshot.Read.Value(s), SyncSnapshot.read(text))
        // What an iPhone build from before formats existed wrote
        assertEquals(SyncSnapshot.Read.Value(snap(mapOf("a" to 1), mapOf("a" to 2.0))), SyncSnapshot.read("""{"values":{"a":1},"stamps":{"a":2}}"""))
        assertEquals(SyncSnapshot.Read.NewerFormat, SyncSnapshot.read("""{"format":2,"values":{},"stamps":{}}"""))
        assertEquals(SyncSnapshot.Read.Unreadable, SyncSnapshot.read("""{"values":"""))
        assertEquals(SyncSnapshot.Read.Unreadable, SyncSnapshot.read("not json"))
    }

    @Test fun theFirstPassUploadsWhatThisDeviceHasAndASecondHasNothingToDo() {
        val store = InMemoryKeyValueStore()
        val engine = SyncEngine("k", store) { 100.0 }
        engine.start(mapOf("a" to 1))
        val first = engine.merge(emptyList())
        assertEquals(SyncStatus.SYNCED, first.status)
        assertNull(first.applied)
        val uploaded = first.upload!!
        val again = engine.merge(listOf(uploaded))
        assertNull(again.upload)
        assertNull(again.applied)
        // Kept across launches
        assertEquals(engine.snapshot, SyncEngine("k", store).snapshot)
    }

    @Test fun anotherDevicesChangesComeInAndOursGoOut() {
        var now = 100.0
        val phone = SyncEngine("k", InMemoryKeyValueStore()) { now }
        val tablet = SyncEngine("k", InMemoryKeyValueStore()) { now }
        phone.start(emptyMap()); tablet.start(emptyMap())
        phone.recordLocal(mapOf("a" to 1))
        var cloud = phone.merge(emptyList()).upload!!
        now = 200.0
        tablet.recordLocal(mapOf("b" to 1))
        val pass = tablet.merge(listOf(cloud))
        assertEquals(mapOf("a" to 1, "b" to 1), pass.applied)
        cloud = pass.upload!!
        // The phone un-ticks "a" later, then syncs: the tablet loses it too
        now = 300.0
        phone.recordLocal(emptyMap())
        val back = phone.merge(listOf(cloud))
        assertEquals(mapOf("b" to 1), back.applied)
        assertEquals(mapOf("b" to 1), tablet.merge(listOf(back.upload!!)).applied)
    }

    @Test fun nothingRecordedMeansNothingStamped() {
        val engine = SyncEngine("k", InMemoryKeyValueStore()) { 5.0 }
        engine.start(mapOf("a" to 1))
        assertFalse(engine.recordLocal(mapOf("a" to 1)))
        assertTrue(engine.recordLocal(mapOf("a" to 2)))
        assertEquals(mapOf("a" to 5.0), engine.snapshot.stamps)
    }

    @Test fun aNewerFormatIsLeftAloneAndABrokenCopyIsReplaced() {
        val engine = SyncEngine("k", InMemoryKeyValueStore()) { 5.0 }
        engine.start(mapOf("a" to 1))
        val newer = engine.merge(listOf("""{"format":9,"values":{},"stamps":{}}"""))
        assertEquals(SyncStatus.NEEDS_UPDATE, newer.status)
        assertNull(newer.upload)
        assertEquals(engine.snapshot.encoded(), engine.merge(listOf("{broken")).upload)
    }

    @Test fun twoFirstCopiesBecomeOneAndAnUnreadableSaveWritesNothing() {
        val engine = SyncEngine("k", InMemoryKeyValueStore()) { 5.0 }
        val a = snap(mapOf("a" to 1), mapOf("a" to 1.0)).encoded()
        val b = snap(mapOf("b" to 1), mapOf("b" to 2.0)).encoded()
        val pass = engine.merge(listOf(a, b))
        assertEquals(mapOf("a" to 1, "b" to 1), pass.applied)
        assertEquals(SyncSnapshot.Read.Value(engine.snapshot), SyncSnapshot.read(pass.upload!!))
        val held = SyncEngine("k", InMemoryKeyValueStore()) { 5.0 }
        val taken = held.merge(listOf(a), holdsWrites = true)
        assertEquals(mapOf("a" to 1), taken.applied)
        assertNull(taken.upload)
        assertNull(held.merge(emptyList(), holdsWrites = true).upload)
    }

    @Test fun myDmzGoesThroughTheSameEntriesAsOnIphone() {
        val one = HajinStore(InMemoryKeyValueStore(), null) { key, _ -> key }
        one.applySynced(mapOf("order|a" to 1, "prestige|ghost|1" to 1, "prestige|ghost|2" to 1, "dmz-level" to 12, "dmz-cash" to 5000,
            "track:x" to 2, "track:y" to 1, "stash:scrap" to 4))
        assertEquals(setOf("order|a", "prestige|ghost|2"), one.checked)
        assertEquals(12, one.dmzLevel)
        assertEquals(5000, one.cash)
        assertEquals(listOf("y", "x"), one.tracked)
        assertEquals(mapOf("scrap" to 4), one.stash)
        assertEquals(mapOf("order|a" to 1, "prestige|ghost|2" to 1, "dmz-level" to 12, "dmz-cash" to 5000, "track:y" to 1, "track:x" to 2, "stash:scrap" to 4),
            one.syncValues())
    }
}
