import Foundation

/// `manifest.json` — one small file the app checks before pulling any data.
struct Manifest: Codable {
    struct Entry: Codable { let version: String; let path: String }
    let catalog: Entry
    let modes: [String: Entry]
}

/// Fetches the weapon catalog and mode JSON from the CDN, versioned through
/// `manifest.json`, and caches each file to disk so nothing re-downloads
/// unless its version bumps.
///
/// Data lives in the same GitHub repo as the app, served through jsDelivr's
/// GitHub CDN rather than raw.githubusercontent.com — same $0 cost, but backed
/// by a real CDN with no per-IP rate limit as the install base grows.
final class DataService {
    private let baseURL: URL
    private let cacheDir: URL
    private let session: URLSession

    init(
        baseURL: URL = URL(string: "https://cdn.jsdelivr.net/gh/DannyRyman19/CamoTracker@master/Data/MW4/")!,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.session = session
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.cacheDir = support.appendingPathComponent("MW4CamoTracker", isDirectory: true)
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
    ) async throws -> (catalog: WeaponCatalog?, modes: [String: ModeFile]) {
        let (data, _) = try await session.data(from: baseURL.appendingPathComponent("manifest.json"))
        let manifest = try JSONDecoder().decode(Manifest.self, from: data)

        var newCatalog: WeaponCatalog?
        if manifest.catalog.version != knownCatalogVersion {
            let (catalogData, _) = try await session.data(from: baseURL.appendingPathComponent(manifest.catalog.path))
            newCatalog = try JSONDecoder().decode(WeaponCatalog.self, from: catalogData)
            try catalogData.write(to: cacheFileURL(name: "weapons"), options: .atomic)
        }

        var updatedModes: [String: ModeFile] = [:]
        for (mode, entry) in manifest.modes {
            guard entry.version != knownModeVersions[mode] else { continue }
            let (modeData, _) = try await session.data(from: baseURL.appendingPathComponent(entry.path))
            let modeFile = try JSONDecoder().decode(ModeFile.self, from: modeData)
            try modeData.write(to: cacheFileURL(name: mode), options: .atomic)
            updatedModes[mode] = modeFile
        }
        return (newCatalog, updatedModes)
    }

    private func cacheFileURL(name: String) -> URL {
        cacheDir.appendingPathComponent("\(name).json")
    }

    private func decode<T: Decodable>(_ type: T.Type, from url: URL?) -> T? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}
