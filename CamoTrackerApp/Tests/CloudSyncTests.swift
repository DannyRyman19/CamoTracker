import Foundation
import Testing
@testable import CamoTracker

/// The merge rules that keep two devices' progress in step.
struct CloudSyncTests {

    @Test func eachEntryComesFromWhicheverSideChangedItLast() {
        let local = SyncSnapshot(values: ["d|a": 1, "l|1": 10], stamps: ["d|a": 5, "l|1": 9])
        let remote = SyncSnapshot(values: ["d|b": 1, "l|1": 20], stamps: ["d|b": 7, "l|1": 12])
        let merged = SyncSnapshot.merge(local: local, remote: remote)
        #expect(merged.values == ["d|a": 1, "d|b": 1, "l|1": 20])
    }

    @Test func unTickingOnOneDeviceBeatsAnOlderTickOnTheOther() {
        // iPad ticked at 5, iPhone un-ticked at 8: the stamp with no value wins
        let iPad = SyncSnapshot(values: ["d|camo": 1], stamps: ["d|camo": 5])
        let iPhone = SyncSnapshot(values: [:], stamps: ["d|camo": 8])
        #expect(SyncSnapshot.merge(local: iPad, remote: iPhone).values["d|camo"] == nil)
        #expect(SyncSnapshot.merge(local: iPhone, remote: iPad).values["d|camo"] == nil)
    }

    @Test func progressFromBeforeSyncIsKeptFromBothDevices() {
        let local = SyncSnapshot(values: ["d|a": 1], stamps: [:])
        let remote = SyncSnapshot(values: ["d|b": 1], stamps: [:])
        #expect(SyncSnapshot.merge(local: local, remote: remote).values == ["d|a": 1, "d|b": 1])
    }

    @Test func savingStampsOnlyWhatChanged() {
        let before = SyncSnapshot(values: ["d|a": 1, "a|x": 3], stamps: ["d|a": 1, "a|x": 1])
        let after = before.updated(to: ["d|a": 1, "a|x": 4, "d|new": 1], now: 50)
        #expect(after.stamps["d|a"] == 1)
        #expect(after.stamps["a|x"] == 50)
        #expect(after.stamps["d|new"] == 50)
        // and a removal is stamped too, so the other device learns about it
        let removed = after.updated(to: ["a|x": 4, "d|new": 1], now: 60)
        #expect(removed.stamps["d|a"] == 60 && removed.values["d|a"] == nil)
    }
}
