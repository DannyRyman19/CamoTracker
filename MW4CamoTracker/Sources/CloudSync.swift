import Foundation
import os

/// Progress as flat entries, each with the time it last changed, so two
/// devices merge entry by entry: ticking camos on the iPhone and the iPad
/// keeps both, and un-ticking one wins over an older tick elsewhere.
///
/// A value of `nil` alongside a stamp is a deletion (an un-ticked camo, a
/// cleared count), kept so the other device learns about it.
struct SyncSnapshot: Codable, Equatable {
    var values: [String: Int] = [:]
    var stamps: [String: Double] = [:]

    /// The format this build writes, as a top-level `format` beside
    /// `values` and `stamps`. Builds from before it existed write none,
    /// which reads as 1, and ignore it when reading, so they still sync.
    /// Raise it when the layout changes in a way an older build would
    /// misread: an older build then leaves the newer copy alone
    /// (`.newerFormat`) instead of overwriting it with less.
    static let format = 1

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

    private struct Payload: Codable {
        var format: Int?
        var values: [String: Int]
        var stamps: [String: Double]
    }

    /// The snapshot as iCloud and the local copy keep it, with its format.
    func encoded() -> Data? {
        try? JSONEncoder().encode(Payload(format: Self.format, values: values, stamps: stamps))
    }

    /// What iCloud holds, told apart from a newer format (left alone until
    /// the app is updated) and a blob that can't be read at all (replaced).
    static func read(_ data: Data) -> CloudPayload<SyncSnapshot> {
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: data) else { return .unreadable }
        if (envelope.format ?? 1) > format { return .newerFormat }
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else { return .unreadable }
        return .value(SyncSnapshot(values: payload.values, stamps: payload.stamps))
    }

    private struct Envelope: Decodable { var format: Int? }
}

/// A synced value as read from iCloud.
enum CloudPayload<Value> {
    case value(Value)
    /// Written by a newer build: never overwritten, sync waits for an update.
    case newerFormat
    /// Not a payload of any format this build recognises (a corrupt or
    /// cut-off write): this device's copy replaces it.
    case unreadable

    var value: Value? {
        if case .value(let value) = self { return value }
        return nil
    }
}

/// The parts of `NSUbiquitousKeyValueStore` sync uses, so tests can stand
/// in for iCloud.
protocol CloudKeyValueStore: AnyObject {
    func data(forKey key: String) -> Data?
    func set(_ value: Any?, forKey key: String)
    var dictionaryRepresentation: [String: Any] { get }
    @discardableResult func synchronize() -> Bool
}

extension NSUbiquitousKeyValueStore: CloudKeyValueStore {}

/// One synced blob in iCloud's key-value store, with the local copy and its
/// stamps in UserDefaults. The owner flattens its state into `values`,
/// calls `recordLocal` on every save, and applies whatever `onRemoteChange`
/// hands back.
///
/// Every write to iCloud comes out of a merge pass (`syncNow`): what iCloud
/// holds is merged in first, so a device that was off, signed out or not
/// yet Premium never replaces another device's progress with its own.
@MainActor
final class CloudSync {
    enum Status: Equatable {
        /// Not Premium, or switched off in Customise.
        case off
        /// No iCloud account signed in on this device.
        case noAccount
        /// Signed in to a different iCloud account from the one this device
        /// last synced with. Nothing is read or written until the player
        /// chooses to sync with it (`useCurrentAccount`).
        case accountChanged
        /// iCloud holds a newer format than this build understands; nothing
        /// is written until the app is updated.
        case needsUpdate
        /// iCloud refused a write (over quota), or the progress is too big
        /// to write. Changes stay on this device.
        case full
        case synced
    }

    static let enabledKey = "mw4_icloud_sync"
    /// The iCloud account this device last synced with, archived. One for
    /// every game and the DMZ guide, which share the one store.
    static let identityKey = "mw4_icloud_identity"
    /// Asks every running sync for a merge pass: the app back in front,
    /// Premium starting, sync switched on, or another account chosen.
    static let syncAllNotification = Notification.Name("CloudSync.syncAll")
    /// The key-value store's limit is 1 MB per key and in all; stay under.
    static let maxBytes = 900_000

    private let cloudKey: String
    private let localKey: String
    private let defaults: UserDefaults
    private let store: CloudKeyValueStore?
    /// The signed-in iCloud account (`ubiquityIdentityToken`), nil when
    /// there is none. Tests hand in their own.
    private let identity: () -> NSObject?
    private let enabled: @MainActor () -> Bool
    private(set) var snapshot: SyncSnapshot
    private(set) var status: Status = .off {
        didSet { if store is NSUbiquitousKeyValueStore { CloudSyncState.shared.set(status, for: cloudKey) } }
    }
    /// Set by the owner while its saved progress couldn't be read: passes
    /// still bring in other devices' changes, but nothing is written to
    /// iCloud until a save loads cleanly on a later launch.
    var holdsWrites = false
    /// How much the store held when iCloud refused a write; while set, the
    /// status stays `.full` until that has shrunk or the account changes.
    private var quotaExceededAt: Int?
    private var pendingPass: Task<Void, Never>?
    /// Called with merged values when another device changed something.
    var onRemoteChange: (([String: Int]) -> Void)?

    private static let log = Logger(subsystem: "com.DannyRyman.MW4CamoTracker", category: "CloudSync")

    /// Whether sync is on: a Premium feature, on unless the player turned
    /// it off in Customise. Free, progress stays on the device.
    static var isEnabled: Bool {
        Premium.shared.isPremium && (UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true)
    }

    nonisolated static func currentIdentity() -> NSObject? {
        FileManager.default.ubiquityIdentityToken as? NSObject
    }

    /// Runs a merge pass in every live sync.
    static func syncAll() {
        NotificationCenter.default.post(name: syncAllNotification, object: nil)
    }

    init(cloudKey: String, defaults: UserDefaults = .standard,
         store: CloudKeyValueStore? = NSUbiquitousKeyValueStore.default,
         identity: @escaping () -> NSObject? = CloudSync.currentIdentity,
         isEnabled: @escaping @MainActor () -> Bool = { CloudSync.isEnabled }) {
        self.cloudKey = cloudKey
        self.localKey = "\(cloudKey)_stamps"
        self.defaults = defaults
        self.store = store
        self.identity = identity
        self.enabled = isEnabled
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
        if let store = store as? NSUbiquitousKeyValueStore {
            NotificationCenter.default.addObserver(forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
                                                   object: store, queue: .main) { [weak self] note in
                let reason = note.userInfo?[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int
                MainActor.assumeIsolated {
                    if reason == NSUbiquitousKeyValueStoreQuotaViolationChange {
                        self?.noteQuotaViolation()
                    } else {
                        // An account change included: the pass checks which
                        // account it is before reading anything
                        self?.syncNow()
                    }
                }
            }
            NotificationCenter.default.addObserver(forName: .NSUbiquityIdentityDidChange, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.syncNow() }
            }
        }
        NotificationCenter.default.addObserver(forName: Self.syncAllNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.syncNow() }
        }
        store?.synchronize()
        syncNow()
    }

    /// When an entry last changed, here or on another device: nil for one
    /// saved before stamps existed. Stamped for every player, Premium or
    /// not, so it doubles as when a camo was ticked.
    func changedAt(_ key: String) -> Date? {
        snapshot.stamps[key].map(Date.init(timeIntervalSince1970:))
    }

    /// Records a local save: stamps what changed, and merges and pushes it
    /// a moment later, so a burst of taps is one write.
    func recordLocal(_ values: [String: Int]) {
        let next = snapshot.updated(to: values, now: Date().timeIntervalSince1970)
        guard next != snapshot else { return }
        snapshot = next
        persist()
        guard enabled() else { return }
        pendingPass?.cancel()
        pendingPass = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled else { return }
            self?.syncNow()
        }
    }

    /// iCloud refused a write: over the store's quota.
    func noteQuotaViolation() {
        let stored = storedBytes(), key = cloudKey
        quotaExceededAt = stored
        status = .full
        Self.log.error("iCloud refused a write for \(key, privacy: .public): over quota, \(stored) bytes stored")
    }

    /// The player chose to sync with the iCloud account the device is now
    /// signed in to (Customise, after `.accountChanged`). This device's
    /// progress merges with that account's from here on; nothing is
    /// deleted on either side. Every other sync follows.
    func useCurrentAccount() {
        if let current = identity() { rememberAccount(current) }
        quotaExceededAt = nil
        syncNow()
        Self.syncAll()
    }

    /// One merge pass in both directions: what iCloud has comes in, then
    /// the merged copy goes back if iCloud was missing anything. Safe to
    /// call any time.
    func syncNow() {
        pendingPass?.cancel()
        pendingPass = nil
        guard enabled(), let store else { status = .off; return }
        guard let account = identity() else { status = .noAccount; return }
        guard checkAccount(account) else { status = .accountChanged; return }
        var remote = SyncSnapshot()
        var rewrite = false
        if let data = store.data(forKey: cloudKey) {
            switch SyncSnapshot.read(data) {
            case .value(let decoded): remote = decoded
            // A newer build wrote a format this one can't read. Leave it
            // alone rather than overwrite it with less.
            case .newerFormat:
                status = .needsUpdate
                let key = cloudKey
                Self.log.notice("\(key, privacy: .public) in iCloud is a newer format; left alone")
                return
            // Broken, not newer: this device's copy replaces it.
            case .unreadable: rewrite = true
            }
        }
        let merged = SyncSnapshot.merge(local: snapshot, remote: remote)
        if merged != snapshot {
            let changedLocally = merged.values != snapshot.values
            snapshot = merged
            persist()
            if changedLocally { onRemoteChange?(merged.values) }
        }
        if holdsWrites { status = .synced; return }
        if merged != remote || rewrite {
            guard let data = merged.encoded() else { return }
            guard data.count < Self.maxBytes else {
                status = .full
                let key = cloudKey, size = data.count
                Self.log.error("\(key, privacy: .public) is \(size) bytes, too big for iCloud; not written")
                return
            }
            store.set(data, forKey: cloudKey)
        }
        // Still over quota unless what the store holds has shrunk since
        // iCloud refused it: "synced" would claim writes that aren't landing.
        if let limit = quotaExceededAt {
            guard storedBytes() < limit else { status = .full; return }
            quotaExceededAt = nil
        }
        status = .synced
    }

    // MARK: Account

    /// Whether this pass may touch iCloud: the device is signed in to the
    /// account it last synced with. The first pass on a device (or the
    /// first since this check existed) takes whichever account is signed
    /// in. A different account pauses sync: merging would copy one
    /// person's progress into another's iCloud, and pulling theirs down
    /// would mix it into this device's. Local progress is never touched.
    private func checkAccount(_ current: NSObject) -> Bool {
        guard let saved = defaults.data(forKey: Self.identityKey),
              let unarchiver = try? NSKeyedUnarchiver(forReadingFrom: saved) else {
            rememberAccount(current)
            return true
        }
        unarchiver.requiresSecureCoding = false
        let previous = unarchiver.decodeObject(forKey: NSKeyedArchiveRootObjectKey) as? NSObject
        unarchiver.finishDecoding()
        guard let previous else {
            rememberAccount(current)
            return true
        }
        return previous.isEqual(current)
    }

    private func rememberAccount(_ current: NSObject) {
        if let data = try? NSKeyedArchiver.archivedData(withRootObject: current, requiringSecureCoding: false) {
            defaults.set(data, forKey: Self.identityKey)
        }
    }

    /// What the store holds right now, in bytes: every game's progress and
    /// the DMZ guide's share the one quota.
    private func storedBytes() -> Int {
        store?.dictionaryRepresentation.values.reduce(0) { $0 + (($1 as? Data)?.count ?? 0) } ?? 0
    }

    private func persist() {
        if let data = snapshot.encoded() { defaults.set(data, forKey: localKey) }
    }
}

/// The sync problem worth showing under the switch in Customise, across
/// every game's sync and the DMZ guide's.
@MainActor
final class CloudSyncState: ObservableObject {
    static let shared = CloudSyncState()

    @Published private(set) var statuses: [String: CloudSync.Status] = [:]

    func set(_ status: CloudSync.Status, for key: String) {
        if statuses[key] != status { statuses[key] = status }
    }

    /// The one to tell the player about, most pressing first; `nil` when
    /// every sync is fine (or off).
    var problem: CloudSync.Status? {
        [.accountChanged, .needsUpdate, .full].first { problem in statuses.values.contains(problem) }
    }
}
