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
/// raw.githubusercontent.com is only asked for a file jsDelivr fails on.
final class DataService: Sendable {
    private let baseURL: URL
    /// Asked once for a file jsDelivr didn't serve (`Game.dataMirrorURL`)
    private let mirrorURL: URL
    private let cacheDir: URL
    private let session: URLSession
    /// Bundled seed files are named `<seedPrefix><file>.json` (MW4's have none)
    private let seedPrefix: String

    /// One game's data: its CDN folder, bundled seeds and its own cache.
    init(
        game: Game = GameRegistry.current,
        session: URLSession = .shared,
        cacheDir: URL? = nil
    ) {
        self.baseURL = game.dataURL
        self.mirrorURL = game.dataMirrorURL
        self.seedPrefix = game.seedPrefix
        self.session = session
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        // Tests pass their own directory so they never read or write the
        // app's real cache. MW4's stays where it always was.
        let cacheDir = cacheDir ?? (game.isMW4
            ? support.appendingPathComponent("MW4CamoTracker", isDirectory: true)
            : support.appendingPathComponent("CamoTracker", isDirectory: true).appendingPathComponent(game.id, isDirectory: true))
        self.cacheDir = cacheDir
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    }

    // MARK: - Weapon catalog

    func loadSeedCatalog() -> WeaponCatalog? {
        decode(WeaponCatalog.self, from: Bundle.main.url(forResource: seedPrefix + "weapons", withExtension: "json"))
    }

    func loadCachedCatalog() -> WeaponCatalog? {
        decode(WeaponCatalog.self, from: cacheFileURL(name: "weapons"))
    }

    /// The catalog to start on: the kept download, unless the app bundles a
    /// newer one (an app update can ship newer data than an old download).
    func loadCatalog() -> WeaponCatalog? {
        Self.newest(seed: loadSeedCatalog(), cached: loadCachedCatalog(), version: \.version)
    }

    // MARK: - Mode files

    /// Loads the bundled seed copy of a mode immediately (so the UI has content
    /// with zero network latency); callers refresh from the CDN separately.
    func loadSeed(mode: String) -> ModeFile? {
        decode(ModeFile.self, from: Bundle.main.url(forResource: seedPrefix + mode, withExtension: "json"))
    }

    func loadCached(mode: String) -> ModeFile? {
        decode(ModeFile.self, from: cacheFileURL(name: mode))
    }

    /// A mode to start on, the newer of the kept download and the bundled copy.
    func load(mode: String) -> ModeFile? {
        Self.newest(seed: loadSeed(mode: mode), cached: loadCached(mode: mode), version: \.version)
    }

    /// The bundled seed when it is newer than the kept download, otherwise
    /// the download (or whichever of them there is), as `HajinStore` does.
    static func newest<T>(seed: T?, cached: T?, version: (T) -> String) -> T? {
        if let seed, let cached, isNewer(version(seed), than: version(cached)) { return seed }
        return cached ?? seed
    }

    /// Fetches the manifest, and for the catalog plus each mode whose version
    /// is higher than the app's, downloads and writes it to disk. A file that
    /// isn't kept (a newer copy already is) isn't returned either.
    ///
    /// Every file is downloaded and decoded before any is kept, and one that
    /// fails is skipped, not the rest: a bad mode file used to stop the whole
    /// refresh after `weapons.json` had already been replaced on disk. Only
    /// when nothing at all came down does the error reach the caller.
    func refreshIfNeeded(
        knownCatalogVersion: String?,
        knownModeVersions: [String: String]
    ) async throws -> (catalog: WeaponCatalog?, modes: [String: ModeFile], notification: Manifest.Announcement?) {
        let data = try await fetch("manifest.json")
        let manifest = try JSONDecoder().decode(Manifest.self, from: data)

        // Only ever forward: the CDN can serve an older manifest or file for
        // a while after a push, and an app update ships newer data than the
        // CDN may have yet, so an older copy never replaces a newer one.
        var failure: Error?
        var catalogDownload: (catalog: WeaponCatalog, data: Data)?
        if Self.isNewer(manifest.catalog.version, than: knownCatalogVersion) {
            do {
                let catalogData = try await fetch(manifest.catalog.path)
                let catalog = try JSONDecoder().decode(WeaponCatalog.self, from: catalogData)
                if Self.isNewer(catalog.version, than: knownCatalogVersion) { catalogDownload = (catalog, catalogData) }
            } catch {
                failure = error
            }
        }

        var modeDownloads: [String: (file: ModeFile, data: Data)] = [:]
        for (mode, entry) in manifest.modes where Self.isNewer(entry.version, than: knownModeVersions[mode]) {
            do {
                let modeData = try await fetch(entry.path)
                let modeFile = try JSONDecoder().decode(ModeFile.self, from: modeData)
                if Self.isNewer(modeFile.version, than: knownModeVersions[mode]) { modeDownloads[mode] = (modeFile, modeData) }
            } catch {
                failure = failure ?? error
            }
        }
        if let failure, catalogDownload == nil, modeDownloads.isEmpty { throw failure }
        // A check stopped part-way (a game switch) keeps nothing
        try Task.checkCancellation()

        var newCatalog: WeaponCatalog?
        if let catalogDownload, try keep(catalogDownload.data, name: "weapons", version: catalogDownload.catalog.version) {
            newCatalog = catalogDownload.catalog
        }
        var updatedModes: [String: ModeFile] = [:]
        for (mode, download) in modeDownloads {
            if try keep(download.data, name: mode, version: download.file.version) { updatedModes[mode] = download.file }
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
        guard Self.isNewer(guide.version, than: knownVersion),
              try keep(data, name: "guide-\(name)", version: guide.version) else { return nil }
        return guide
    }

    /// Dotted versions compared number by number ("0.8.12" > "0.8.9"); any
    /// version beats none. A part that isn't a number counts as 0, so
    /// "0.9.11a" is not newer than "0.9.11". `Tools/publish_data.py` refuses
    /// to publish a version this wouldn't fetch, with the same comparison
    /// (`is_newer`): change one, change both.
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

    /// Whether a downloaded `version` may replace `current`: anything but an
    /// older one (the same version again is harmless).
    static func canReplace(_ current: String?, with version: String) -> Bool {
        guard let current else { return true }
        return !isNewer(current, than: version)
    }

    /// Writes a download to the cache unless a newer copy is already kept.
    /// The launch, foreground and background checks can each be downloading
    /// at once, right after a push two CDN edges can answer with different
    /// versions, and the slower check must not leave the older file behind.
    private func keep(_ data: Data, name: String, version: String) throws -> Bool {
        Self.keepLock.lock()
        defer { Self.keepLock.unlock() }
        let url = cacheFileURL(name: name)
        guard Self.canReplace(decode(Versioned.self, from: url)?.version, with: version) else { return false }
        try data.write(to: url, options: .atomic)
        return true
    }

    private static let keepLock = NSLock()
    private struct Versioned: Decodable { let version: String }

    /// Always asks the server. jsDelivr sends `max-age=604800`, and a plain
    /// `session.data(from:)` honours it, so a phone that had fetched the
    /// manifest once kept reading its own week-old copy and missed every
    /// update published in between. The files are tiny; the CDN still
    /// answers from its edge cache, so this costs nothing.
    ///
    /// When jsDelivr fails (an error status, such as its 403 for a repo
    /// over its size limit, or no answer) the same path is asked of GitHub
    /// once. Whichever copy arrives goes through the same version checks.
    private func fetch(_ path: String) async throws -> Data {
        do {
            return try await fetch(path, from: baseURL)
        } catch {
            // A check stopped on purpose (a game switch) stays stopped
            if Task.isCancelled { throw error }
            return try await fetch(path, from: mirrorURL)
        }
    }

    private func fetch(_ path: String, from base: URL) async throws -> Data {
        var request = URLRequest(url: base.appendingPathComponent(path))
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await session.data(for: request)
        if let status = (response as? HTTPURLResponse)?.statusCode, !(200...299).contains(status) {
            throw URLError(.badServerResponse, userInfo: [NSURLErrorFailingURLErrorKey: request.url as Any, "status": status])
        }
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
