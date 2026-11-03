import Foundation
import Testing
@testable import MW4CamoTracker

/// A save that won't decode (corrupt, or a format a newer build wrote) is
/// kept aside, progress picks up from sync's copy of the last save, and
/// nothing reaches iCloud until a save loads cleanly.
@MainActor
struct UnreadableSaveTests {
    private let defaults: UserDefaults
    private let cache: URL
    private let mw4 = GameRegistry.game("mw4") ?? GameRegistry.fallback

    init() {
        let name = "UnreadableSaveTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: name)!
        cache = FileManager.default.temporaryDirectory.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
    }

    private func model(_ cloud: FakeCloud) -> (TrackerViewModel, CloudSync) {
        GameRegistry.current = mw4
        let sync = CloudSync(cloudKey: "mw4_progress_sync", defaults: defaults, store: cloud,
                             identity: { "person-a" as NSString }, isEnabled: { true })
        let vm = TrackerViewModel(game: mw4, dataService: DataService(game: mw4, cacheDir: cache), defaults: defaults, cloud: sync)
        return (vm, sync)
    }

    @Test func anUnreadableSaveIsKeptAsideAndNeverSyncedAsAWipe() throws {
        let bad = Data(#"{"weaponLevels": "a format this build can't read"}"#.utf8)
        defaults.set(bad, forKey: "mw4_progress_v2")
        // What sync kept of the last save, also in iCloud
        let last = SyncSnapshot(values: ["l|0": 30, "d|camo|multiplayer|0|1": 1], stamps: ["l|0": 10, "d|camo|multiplayer|0|1": 10])
        defaults.set(last.encoded(), forKey: "mw4_progress_sync_stamps")
        let cloud = FakeCloud()
        cloud.values["mw4_progress_sync"] = last.encoded()
        let before = cloud.data(forKey: "mw4_progress_sync")

        let (vm, sync) = model(cloud)
        // Kept aside, with a timestamped copy
        #expect(defaults.data(forKey: "mw4_progress_v2_unreadable") == bad)
        let copies = defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix("mw4_progress_v2_unreadable_") }
        #expect(copies.count == 1)
        #expect(copies.first.flatMap { defaults.data(forKey: $0) } == bad)
        // Progress picks up where the last save left it, not at zero
        #expect(vm.level(for: 0) == 30)
        #expect(sync.holdsWrites)

        // A change is saved and recorded, but iCloud's copy is untouched
        // and nothing the save lost is stamped as deleted
        let weapon = try #require(vm.weapon(id: 0))
        vm.setLevel(31, for: weapon)
        sync.syncNow()
        #expect(cloud.data(forKey: "mw4_progress_sync") == before)
        #expect(sync.snapshot.values["d|camo|multiplayer|0|1"] == 1)
        #expect(sync.snapshot.stamps["d|camo|multiplayer|0|1"] == 10)

        // The next launch reads the save written since: writes resume
        let (again, nextSync) = model(cloud)
        #expect(!nextSync.holdsWrites)
        #expect(again.level(for: 0) == 31)
        #expect(SyncSnapshot.read(try #require(cloud.data(forKey: "mw4_progress_sync"))).value?.values["l|0"] == 31)
        // and the unreadable save is still kept
        #expect(defaults.data(forKey: "mw4_progress_v2_unreadable") == bad)
    }

    @Test func theSameUnreadableSaveIsKeptOnce() {
        defaults.set(Data("{".utf8), forKey: "mw4_progress_v2")
        _ = model(FakeCloud())
        _ = model(FakeCloud())
        #expect(defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix("mw4_progress_v2_unreadable_") }.count == 1)
    }

    @Test func noSaveYetIsACleanStart() {
        let (_, sync) = model(FakeCloud())
        #expect(!sync.holdsWrites)
    }
}
