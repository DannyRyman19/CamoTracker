import Foundation

/// Progress as flat entries, each with the time it last changed, so two
/// devices merge entry by entry: ticking camos on the iPhone and the iPad
/// keeps both, and un-ticking one wins over an older tick elsewhere.
///
/// A value of `nil` alongside a stamp is a deletion (an un-ticked camo, a
/// cleared count), kept so the other device learns about it.
struct SyncSnapshot: Codable, Equatable {
    var values: [String: Int] = [:]
    var stamps: [String: Double] = [:]

    /// Each entry from whichever side changed it last. An entry neither side
    /// has a stamp for (progress from before sync existed) is kept from
    /// whichever side has it, local first, so turning sync on loses nothing.
    static func merge(local: SyncSnapshot, remote: SyncSnapshot) -> SyncSnapshot {
        var out = SyncSnapshot()
        let keys = Set(local.values.keys).union(remote.values.keys).union(local.stamps.keys).union(remote.stamps.keys)
        for key in keys {
            let l = local.stamps[key] ?? 0, r = remote.stamps[key] ?? 0
            let value: Int?
            let stamp: Double
            if r > l {
                value = remote.values[key]; stamp = r
            } else if l > r {
                value = local.values[key]; stamp = l
            } else {
                value = local.values[key] ?? remote.values[key]; stamp = l
            }
            if let value { out.values[key] = value }
            if stamp > 0 { out.stamps[key] = stamp }
        }
        return out
    }

    /// Stamps every entry that differs from `previous` with `now`, and
    /// returns the new snapshot for `values`.
    func updated(to values: [String: Int], now: Double) -> SyncSnapshot {
        var next = SyncSnapshot(values: values, stamps: stamps)
        for key in Set(values.keys).union(self.values.keys) where values[key] != self.values[key] {
            next.stamps[key] = now
        }
        return next
    }
}

/// One synced blob in iCloud's key-value store, with the local copy and its
/// stamps in UserDefaults. The owner flattens its state into `values`,
/// calls `recordLocal` on every save, and applies whatever `onRemoteChange`
/// hands back.
@MainActor
final class CloudSync {
    static let enabledKey = "mw4_icloud_sync"

    private let cloudKey: String
    private let localKey: String
    private let defaults: UserDefaults
    private let store: NSUbiquitousKeyValueStore?
    private(set) var snapshot: SyncSnapshot
    /// Called with merged values when another device changed something.
    var onRemoteChange: (([String: Int]) -> Void)?

    /// Whether sync is on: a Premium feature, on unless the player turned
    /// it off in Customise. Free, progress stays on the device.
    static var isEnabled: Bool {
        Premium.shared.isPremium && (UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true)
    }

    init(cloudKey: String, defaults: UserDefaults = .standard, store: NSUbiquitousKeyValueStore? = .default) {
        self.cloudKey = cloudKey
        self.localKey = "\(cloudKey)_stamps"
        self.defaults = defaults
        self.store = store
        if let data = defaults.data(forKey: localKey), let saved = try? JSONDecoder().decode(SyncSnapshot.self, from: data) {
            snapshot = saved
        } else {
            snapshot = SyncSnapshot()
        }
    }

    /// Starts listening for other devices and does a first merge.
    func start(current values: [String: Int]) {
        // Progress saved before sync existed has no stamps; adopt it as-is
        if snapshot.values.isEmpty, snapshot.stamps.isEmpty { snapshot.values = values }
        guard let store else { return }
        NotificationCenter.default.addObserver(forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
                                               object: store, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.pull() }
        }
        store.synchronize()
        pull()
    }

    /// Records a local save: stamps what changed and pushes it.
    func recordLocal(_ values: [String: Int]) {
        let next = snapshot.updated(to: values, now: Date().timeIntervalSince1970)
        guard next != snapshot else { return }
        snapshot = next
        persist()
        push()
    }

    /// Merges what iCloud has into the local copy, hands changes to the
    /// owner, and pushes back anything iCloud was missing.
    func pull() {
        guard Self.isEnabled, let store, let data = store.data(forKey: cloudKey),
              let remote = try? JSONDecoder().decode(SyncSnapshot.self, from: data) else {
            push()
            return
        }
        let merged = SyncSnapshot.merge(local: snapshot, remote: remote)
        let changedLocally = merged.values != snapshot.values
        snapshot = merged
        persist()
        if changedLocally { onRemoteChange?(merged.values) }
        if merged != remote { push() }
    }

    private func push() {
        guard Self.isEnabled, let store, let data = try? JSONEncoder().encode(snapshot) else { return }
        // The key-value store holds 1 MB per key; a full tracker is a small
        // fraction of that, but never risk a rejected write
        guard data.count < 900_000 else { return }
        store.set(data, forKey: cloudKey)
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(snapshot) { defaults.set(data, forKey: localKey) }
    }
}
