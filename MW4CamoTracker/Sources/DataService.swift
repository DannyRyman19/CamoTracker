import Foundation

/// `manifest.json` — one small file the app checks before pulling any data.
struct Manifest: Codable {
    struct Entry: Codable { let version: String; let path: String }
    /// What the "new content" notification says for the update the manifest
    /// currently describes, per language, so a season can be announced in
    /// its own words without an app update:
    ///
    ///     "notification": {
    ///       "title": { "en": "Season 1 is live", "de": "Season 1 ist da" },
    ///       "body":  { "en": "New weapons and camos to track." }
    ///     }
    ///
    /// Either field can be left out, and so can the whole block: whatever is
    /// missing falls back to the app's built-in wording.
    ///
    /// For an update nobody needs telling about (a corrected challenge, a
    /// typo), `"notification": { "silent": true }` lets the data go out with
    /// no notification at all.
    ///
    /// The block is read at the moment an update is detected, so it describes
    /// whatever update is live: change or remove it with the next one, or
    /// that one is announced in these words (or kept silent) too.
    struct Announcement: Codable {
        let title: LocalizedText?
        let body: LocalizedText?
        let silent: Bool?
    }
    let catalog: Entry
    let modes: [String: Entry]
    let notification: Announcement?
    /// Reference guides (the Hajin Tac Map and DMZ tables). A block of its
    /// own, not part of `modes`: older app versions decode every `modes`
    /// entry as a camo file, so a guide there would break their refresh.
    let guides: [String: Entry]?
}

/// Fetches the weapon catalog and mode JSON from the CDN, versioned through
/// `manifest.json`, and caches each file to disk so nothing re-downloads
/// unless its version bumps.
///
/// Data lives in the same GitHub repo as the app, served through jsDelivr's
/// GitHub CDN rather than raw.githubusercontent.com — same $0 cost, but backed
/// by a real CDN with no per-IP rate limit as the install base grows.
final class DataService: Sendable {
    private let baseURL: URL
    private let cacheDir: URL
    private let session: URLSession

    init(
        baseURL: URL = URL(string: "https://cdn.jsdelivr.net/gh/DannyRyman19/CamoTracker@master/Data/MW4/")!,
        session: URLSession = .shared,
        cacheDir: URL? = nil
    ) {
        self.baseURL = baseURL
        self.session = session
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        // Tests pass their own directory so they never read or write the
        // app's real cache.
        let cacheDir = cacheDir ?? support.appendingPathComponent("MW4CamoTracker", isDirectory: true)
        self.cacheDir = cacheDir
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    }

    // MARK: - Weapon catalog

    func loadSeedCatalog() -> WeaponCatalog? {
        decode(WeaponCatalog.self, from: Bundle.main.url(forResource: "weapons", withExtension: "json"))
    }

    func loadCachedCatalog() -> WeaponCatalog? {
        decode(WeaponCatalog.self, from: cacheFileURL(name: "weapons"))
    }

    // MARK: - Mode files

    /// Loads the bundled seed copy of a mode immediately (so the UI has content
    /// with zero network latency); callers refresh from the CDN separately.
    func loadSeed(mode: String) -> ModeFile? {
        decode(ModeFile.self, from: Bundle.main.url(forResource: mode, withExtension: "json"))
    }

    func loadCached(mode: String) -> ModeFile? {
        decode(ModeFile.self, from: cacheFileURL(name: mode))
    }

    /// Fetches the manifest, and for the catalog plus each mode whose version
    /// differs from what's cached, downloads and writes it to disk.
    func refreshIfNeeded(
        knownCatalogVersion: String?,
        knownModeVersions: [String: String]
    ) async throws -> (catalog: WeaponCatalog?, modes: [String: ModeFile], notification: Manifest.Announcement?) {
        let data = try await fetch("manifest.json")
        let manifest = try JSONDecoder().decode(Manifest.self, from: data)

        // Only ever forward: the CDN can serve an older manifest or file for
        // a while after a push, and an app update ships newer data than the
        // CDN may have yet, so an older copy never replaces a newer one.
        var newCatalog: WeaponCatalog?
        if Self.isNewer(manifest.catalog.version, than: knownCatalogVersion) {
            let catalogData = try await fetch(manifest.catalog.path)
            let catalog = try JSONDecoder().decode(WeaponCatalog.self, from: catalogData)
            if Self.isNewer(catalog.version, than: knownCatalogVersion) {
                newCatalog = catalog
                try catalogData.write(to: cacheFileURL(name: "weapons"), options: .atomic)
            }
        }

        var updatedModes: [String: ModeFile] = [:]
        for (mode, entry) in manifest.modes {
            guard Self.isNewer(entry.version, than: knownModeVersions[mode]) else { continue }
            let modeData = try await fetch(entry.path)
            let modeFile = try JSONDecoder().decode(ModeFile.self, from: modeData)
            guard Self.isNewer(modeFile.version, than: knownModeVersions[mode]) else { continue }
            try modeData.write(to: cacheFileURL(name: mode), options: .atomic)
            updatedModes[mode] = modeFile
        }
        return (newCatalog, updatedModes, manifest.notification)
    }

    // MARK: - Guides

    func loadSeedGuide(name: String) -> HajinGuide? {
        decode(HajinGuide.self, from: Bundle.main.url(forResource: name, withExtension: "json"))
    }

    func loadCachedGuide(name: String) -> HajinGuide? {
        decode(HajinGuide.self, from: cacheFileURL(name: "guide-\(name)"))
    }

    /// Downloads the named guide when the manifest lists a newer version
    /// than the one the app has. `nil` when there is nothing newer.
    func refreshGuide(name: String, knownVersion: String?) async throws -> HajinGuide? {
        let manifest = try JSONDecoder().decode(Manifest.self, from: try await fetch("manifest.json"))
        guard let entry = manifest.guides?[name], Self.isNewer(entry.version, than: knownVersion) else { return nil }
        let data = try await fetch(entry.path)
        let guide = try JSONDecoder().decode(HajinGuide.self, from: data)
        guard Self.isNewer(guide.version, than: knownVersion) else { return nil }
        try data.write(to: cacheFileURL(name: "guide-\(name)"), options: .atomic)
        return guide
    }

    /// Dotted versions compared number by number ("0.8.12" > "0.8.9"); any
    /// version beats none.
    static func isNewer(_ version: String, than known: String?) -> Bool {
        guard let known else { return true }
        let a = version.split(separator: ".").map { Int($0) ?? 0 }
        let b = known.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    /// Always asks the server. jsDelivr sends `max-age=604800`, and a plain
    /// `session.data(from:)` honours it, so a phone that had fetched the
    /// manifest once kept reading its own week-old copy and missed every
    /// update published in between. The files are tiny; the CDN still
    /// answers from its edge cache, so this costs nothing.
    private func fetch(_ path: String) async throws -> Data {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, _) = try await session.data(for: request)
        return data
    }

    private func cacheFileURL(name: String) -> URL {
        cacheDir.appendingPathComponent("\(name).json")
    }

    private func decode<T: Decodable>(_ type: T.Type, from url: URL?) -> T? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}
