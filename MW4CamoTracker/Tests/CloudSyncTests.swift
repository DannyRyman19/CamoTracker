import Foundation
import Testing
@testable import MW4CamoTracker

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

/// An in-memory iCloud key-value store.
final class FakeCloud: CloudKeyValueStore {
    var values: [String: Any] = [:]
    func data(forKey key: String) -> Data? { values[key] as? Data }
    func set(_ value: Any?, forKey key: String) { values[key] = value }
    var dictionaryRepresentation: [String: Any] { values }
    func synchronize() -> Bool { true }
}

/// CloudSync's edge cases: a different iCloud account, a newer format, a
/// blob that won't decode, a full store, and merging before every write.
@MainActor
struct CloudSyncPassTests {
    private static let key = "test_sync"

    private func defaults() -> UserDefaults {
        let name = "CloudSyncPassTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    /// `account` is read on every pass, so a test can switch it mid-way.
    private func sync(_ cloud: FakeCloud, defaults: UserDefaults? = nil, account: @escaping () -> NSObject?,
                      enabled: @escaping @MainActor () -> Bool = { true }) -> CloudSync {
        CloudSync(cloudKey: Self.key, defaults: defaults ?? self.defaults(), store: cloud, identity: account, isEnabled: enabled)
    }

    private func remote(_ cloud: FakeCloud) -> SyncSnapshot? {
        cloud.data(forKey: Self.key).flatMap { SyncSnapshot.read($0).value }
    }

    private func blob(_ snapshot: SyncSnapshot) -> Data { snapshot.encoded()! }

    // MARK: Account switch

    @Test func aDifferentAccountIsNeitherReadNorWritten() {
        let cloud = FakeCloud()
        var account: NSObject = "person-a" as NSString
        var pulled: [String: Int]?
        let sync = sync(cloud, account: { account })
        sync.onRemoteChange = { pulled = $0 }
        sync.start(current: ["d|a": 1])
        #expect(sync.status == .synced)
        #expect(remote(cloud)?.values == ["d|a": 1])

        // Signed in as someone else; their store holds their own progress.
        account = "person-b" as NSString
        cloud.values[Self.key] = blob(SyncSnapshot(values: ["d|b": 1], stamps: ["d|b": 5]))
        sync.syncNow()
        #expect(sync.status == .accountChanged)
        // Nothing pushed into their account, nothing pulled into this device.
        #expect(remote(cloud)?.values == ["d|b": 1])
        #expect(pulled == nil)
        sync.recordLocal(["d|a": 1, "d|c": 1])
        sync.syncNow()
        #expect(remote(cloud)?.values == ["d|b": 1])

        // The player chooses to sync with it: a normal merge, nothing lost.
        sync.useCurrentAccount()
        #expect(sync.status == .synced)
        #expect(pulled == ["d|a": 1, "d|b": 1, "d|c": 1])
        #expect(remote(cloud)?.values == ["d|a": 1, "d|b": 1, "d|c": 1])
    }

    @Test func theSameAccountAfterSigningOutKeepsSyncing() {
        let cloud = FakeCloud()
        var account: NSObject? = "person-a" as NSString
        let sync = sync(cloud, account: { account })
        sync.start(current: [:])
        #expect(sync.status == .synced)
        account = nil
        sync.syncNow()
        #expect(sync.status == .noAccount)
        account = "person-a" as NSString
        sync.syncNow()
        #expect(sync.status == .synced)
    }

    @Test func everySyncOnTheDeviceSharesTheAccountItSyncedWith() {
        let cloud = FakeCloud(), shared = defaults()
        var account: NSObject = "person-a" as NSString
        let progress = sync(cloud, defaults: shared, account: { account })
        progress.start(current: [:])
        account = "person-b" as NSString
        // The DMZ guide's sync starts after the switch: it pauses too
        let guide = CloudSync(cloudKey: "guide", defaults: shared, store: cloud, identity: { account }, isEnabled: { true })
        guide.start(current: ["x": 1])
        #expect(guide.status == .accountChanged)
        #expect(cloud.data(forKey: "guide") == nil)
    }

    // MARK: Format

    @Test func aNewerFormatIsLeftAloneUntilAnUpdate() {
        let cloud = FakeCloud()
        let newer = Data(#"{"format":2,"entries":[]}"#.utf8)
        cloud.values[Self.key] = newer
        let sync = sync(cloud, account: { "person-a" as NSString })
        sync.start(current: ["d|a": 1])
        sync.recordLocal(["d|a": 1, "d|b": 1])
        sync.syncNow()
        #expect(sync.status == .needsUpdate)
        #expect(cloud.data(forKey: Self.key) == newer)
    }

    @Test func aCorruptBlobIsReplacedByThisDevicesProgress() {
        let cloud = FakeCloud()
        cloud.values[Self.key] = Data("{".utf8)
        let sync = sync(cloud, account: { "person-a" as NSString })
        sync.start(current: ["d|a": 1])
        #expect(sync.status == .synced)
        #expect(remote(cloud)?.values == ["d|a": 1])
    }

    @Test func payloadsTellNewerFromBroken() {
        let read = { (json: String) in SyncSnapshot.read(Data(json.utf8)) }
        if case .newerFormat = read(#"{"format":2}"#) {} else { Issue.record("expected newer") }
        if case .unreadable = read(#"{"format":1,"values":7}"#) {} else { Issue.record("expected unreadable") }
        if case .unreadable = read("[]") {} else { Issue.record("expected unreadable") }
        // What builds from before the format wrote still reads
        #expect(read(#"{"values":{"d|a":1},"stamps":{"d|a":2}}"#).value == SyncSnapshot(values: ["d|a": 1], stamps: ["d|a": 2]))
        // and what this build writes still reads in them: the same keys
        let written = try? JSONSerialization.jsonObject(with: SyncSnapshot(values: ["d|a": 1], stamps: ["d|a": 2]).encoded()!) as? [String: Any]
        #expect(written?["format"] as? Int == SyncSnapshot.format)
        #expect((written?["values"] as? [String: Int]) == ["d|a": 1])
    }

    // MARK: Quota

    @Test func fullStaysUntilWhatTheStoreHoldsShrinks() {
        let cloud = FakeCloud()
        cloud.values["other"] = Data(count: 50_000)
        let sync = sync(cloud, account: { "person-a" as NSString })
        sync.start(current: ["d|a": 1])
        #expect(sync.status == .synced)

        sync.noteQuotaViolation()
        #expect(sync.status == .full)
        // The next pass doesn't know whether its write landed
        sync.recordLocal(["d|a": 1, "d|b": 1])
        sync.syncNow()
        #expect(sync.status == .full)

        // Another key goes: the store holds less than when it was refused
        cloud.values["other"] = nil
        sync.syncNow()
        #expect(sync.status == .synced)
    }

    @Test func progressTooBigForICloudIsNotWritten() {
        let cloud = FakeCloud()
        let sync = sync(cloud, account: { "person-a" as NSString })
        var huge: [String: Int] = [:]
        for i in 0..<40_000 { huge["a|camo|multiplayer|\(i)|\(i)"] = i }
        sync.start(current: huge)
        #expect(sync.status == .full)
        #expect(cloud.data(forKey: Self.key) == nil)
    }

    // MARK: Merging before writing

    @Test func aDeviceThatWasntSyncingMergesBeforeItWrites() {
        let cloud = FakeCloud()
        // Another device's progress is in iCloud
        cloud.values[Self.key] = blob(SyncSnapshot(values: ["d|other": 1], stamps: ["d|other": 5]))
        var on = false
        var pulled: [String: Int]?
        let sync = sync(cloud, account: { "person-a" as NSString }, enabled: { on })
        sync.onRemoteChange = { pulled = $0 }
        sync.start(current: ["d|mine": 1])
        #expect(sync.status == .off)
        sync.recordLocal(["d|mine": 1, "d|new": 1])

        // Premium starts, or sync is switched on: a pass, not a push
        on = true
        sync.syncNow()
        #expect(remote(cloud)?.values == ["d|mine": 1, "d|new": 1, "d|other": 1])
        #expect(pulled == ["d|mine": 1, "d|new": 1, "d|other": 1])
    }

    @Test func heldWritesStillTakeInOtherDevicesProgress() {
        let cloud = FakeCloud()
        let before = blob(SyncSnapshot(values: ["d|other": 1], stamps: ["d|other": 5]))
        cloud.values[Self.key] = before
        let sync = sync(cloud, account: { "person-a" as NSString })
        sync.holdsWrites = true
        var pulled: [String: Int]?
        sync.onRemoteChange = { pulled = $0 }
        sync.start(current: [:])
        sync.recordLocal(["d|other": 1, "d|mine": 1])
        sync.syncNow()
        #expect(pulled == ["d|other": 1])
        #expect(cloud.data(forKey: Self.key) == before)
    }
}
