import Foundation

/// `manifest.json` — one small file the app checks before pulling any mode data.
struct Manifest: Codable {
    struct Entry: Codable { let version: String; let path: String }
    let modes: [String: Entry]
}

/// Fetches mode JSON from the CDN, versioned through `manifest.json`, and caches
/// each mode file to disk so a mode only re-downloads when its version bumps.
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

    /// Loads the bundled seed copy of a mode immediately (so the UI has content
    /// with zero network latency), then callers can refresh from the CDN separately.
    func loadSeed(mode: String) -> ModeFile? {
        decode(from: Bundle.main.url(forResource: mode, withExtension: "json"))
    }

    /// Returns the freshest available copy of a mode: disk cache if present, else nil.
    func loadCached(mode: String) -> ModeFile? {
        decode(from: cacheFileURL(mode: mode))
    }

    /// Fetches the manifest, and for each mode whose version differs from what's
    /// cached on disk, downloads the mode file and writes it to the cache.
    /// Returns the modes that were actually updated.
    func refreshIfNeeded(knownVersions: [String: String]) async throws -> [String: ModeFile] {
        let (data, _) = try await session.data(from: baseURL.appendingPathComponent("manifest.json"))
        let manifest = try JSONDecoder().decode(Manifest.self, from: data)

        var updated: [String: ModeFile] = [:]
        for (mode, entry) in manifest.modes {
            guard entry.version != knownVersions[mode] else { continue }
            let (modeData, _) = try await session.data(from: baseURL.appendingPathComponent(entry.path))
            let modeFile = try JSONDecoder().decode(ModeFile.self, from: modeData)
            try modeData.write(to: cacheFileURL(mode: mode), options: .atomic)
            updated[mode] = modeFile
        }
        return updated
    }

    private func cacheFileURL(mode: String) -> URL {
        cacheDir.appendingPathComponent("\(mode).json")
    }

    private func decode(from url: URL?) -> ModeFile? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(ModeFile.self, from: data)
    }
}
