import Foundation
import Testing
@testable import MW4CamoTracker

/// Answers every request with a fixed body and records what was asked for.
final class RecordingProtocol: URLProtocol {
    nonisolated(unsafe) static var requests: [URLRequest] = []
    nonisolated(unsafe) static var bodies: [String: String] = [:]

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requests.append(request)
        let body = Self.bodies[request.url?.lastPathComponent ?? ""] ?? "{}"
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
                                       headerFields: ["Cache-Control": "public, max-age=604800"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .allowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// jsDelivr sends `max-age=604800`; the app must still ask the server every
/// time, or a phone keeps a week-old manifest and misses every update.
@Suite(.serialized)
struct DataServiceTests {

    private func service(cache: URL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)) -> DataService {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [RecordingProtocol.self]
        let mw4 = GameRegistry.game("mw4") ?? GameRegistry.fallback
        return DataService(game: mw4, session: URLSession(configuration: config), cacheDir: cache)
    }

    /// The bundled MW4 file `name` with its version swapped for `version`.
    private func bundled(_ name: String, version: String) throws -> String {
        let url = try #require(Bundle.main.url(forResource: name, withExtension: "json"))
        var json = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        json["version"] = version
        return String(decoding: try JSONSerialization.data(withJSONObject: json), as: UTF8.self)
    }

    private func newCache() -> URL {
        let cache = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        return cache
    }

    @Test func everyRequestSkipsThePhonesOwnCache() async throws {
        RecordingProtocol.requests = []
        RecordingProtocol.bodies = ["manifest.json": #"""
            {"catalog": {"version": "2", "path": "weapons.json"}, "modes": {}}
            """#]
        _ = try? await service().refreshIfNeeded(knownCatalogVersion: "1", knownModeVersions: [:])

        let paths = RecordingProtocol.requests.compactMap { $0.url?.lastPathComponent }
        #expect(paths.contains("manifest.json"))
        #expect(paths.contains("weapons.json"))
        #expect(RecordingProtocol.requests.allSatisfy { $0.cachePolicy == .reloadIgnoringLocalCacheData })
    }

    /// The app fetches only a higher version, number by number. A version
    /// with letters in a part, or a typo that drops a digit, is never
    /// fetched, which is why `publish_data.py` refuses them (its own copy of
    /// this table is in `Tools/test_publish_data.py`).
    @Test(arguments: [
        ("0.9.12", "0.9.11", true),
        ("0.10.0", "0.9.11", true),
        ("1", "0.9.11", true),
        ("0.9.11.1", "0.9.11", true),
        ("0.9.11", "0.9.11", false),
        ("0.9.11.0", "0.9.11", false),
        ("0.9.1", "0.9.11", false),
        ("0.9.11a", "0.9.11", false),
        ("1.0.0-hotfix", "1.0.0", false),
        ("2026-11-03", "0.9.11", false),
    ])
    func versionsCompareNumberByNumber(version: String, known: String, newer: Bool) {
        #expect(DataService.isNewer(version, than: known) == newer)
    }

    @Test func anyVersionBeatsNone() {
        #expect(DataService.isNewer("0.0.1", than: nil))
        #expect(DataService.canReplace(nil, with: "0.0.1"))
        #expect(DataService.canReplace("0.9.11", with: "0.9.11"))
        #expect(!DataService.canReplace("0.9.12", with: "0.9.11"))
    }

    /// After an app update the bundled copy can be newer than the one kept
    /// from an earlier download; the newer of the two wins, as in HajinStore.
    @Test func newerOfBundledAndDownloadedWins() {
        let pick = { (seed: String?, cached: String?) in DataService.newest(seed: seed, cached: cached, version: { $0 }) }
        #expect(pick("0.9.12", "0.9.11") == "0.9.12")
        #expect(pick("0.9.11", "0.9.12") == "0.9.12")
        #expect(pick("0.9.11", "0.9.11") == "0.9.11")
        #expect(pick(nil, "0.9.11") == "0.9.11")
        #expect(pick("0.9.11", nil) == "0.9.11")
    }

    @Test func olderDownloadLosesToNewerBundledData() throws {
        let seedCatalog = try #require(service().loadSeedCatalog()).version
        let seedMode = try #require(service().loadSeed(mode: "warzone")).version
        let cache = newCache()
        try bundled("weapons", version: "0.0.1").write(to: cache.appendingPathComponent("weapons.json"), atomically: true, encoding: .utf8)
        try bundled("warzone", version: "0.0.1").write(to: cache.appendingPathComponent("warzone.json"), atomically: true, encoding: .utf8)
        let service = service(cache: cache)
        #expect(service.loadCachedCatalog()?.version == "0.0.1")
        #expect(service.loadCatalog()?.version == seedCatalog)
        #expect(service.load(mode: "warzone")?.version == seedMode)

        // A download newer than the bundle still wins
        try bundled("weapons", version: "999.0.0").write(to: cache.appendingPathComponent("weapons.json"), atomically: true, encoding: .utf8)
        #expect(service.loadCatalog()?.version == "999.0.0")
    }

    /// Two checks overlapping right after a push can get different versions
    /// from different CDN edges: the older download never replaces a newer
    /// kept copy, and isn't reported as an update.
    @Test func olderDownloadNeverReplacesANewerKeptCopy() async throws {
        let cache = newCache()
        try bundled("weapons", version: "9.9.9").write(to: cache.appendingPathComponent("weapons.json"), atomically: true, encoding: .utf8)
        RecordingProtocol.requests = []
        RecordingProtocol.bodies = [
            "manifest.json": #"{"catalog": {"version": "5.0.0", "path": "weapons.json"}, "modes": {}}"#,
            "weapons.json": try bundled("weapons", version: "5.0.0"),
        ]
        let service = service(cache: cache)
        let result = try await service.refreshIfNeeded(knownCatalogVersion: "1", knownModeVersions: [:])
        #expect(result.catalog == nil)
        #expect(service.loadCachedCatalog()?.version == "9.9.9")
    }

    /// Launch and the first trip to the foreground both ask at once on a
    /// cold start: the second joins the first, so the manifest is fetched once.
    @MainActor @Test func overlappingRefreshesShareOneCheck() async throws {
        let mw4 = GameRegistry.game("mw4") ?? GameRegistry.fallback
        GameRegistry.current = mw4
        let defaults = try #require(UserDefaults(suiteName: "DataServiceTests-\(UUID().uuidString)"))
        RecordingProtocol.requests = []
        RecordingProtocol.bodies = ["manifest.json": #"{"catalog": {"version": "0", "path": "weapons.json"}, "modes": {}}"#]
        let vm = TrackerViewModel(game: mw4, dataService: service(cache: newCache()), defaults: defaults)
        async let first: Void = vm.refresh()
        async let second: Void = vm.refresh()
        _ = await (first, second)
        #expect(RecordingProtocol.requests.filter { $0.url?.lastPathComponent == "manifest.json" }.count == 1)
        #expect(vm.refreshError == nil)

        // Once it has finished, the next one asks again
        await vm.refresh()
        #expect(RecordingProtocol.requests.filter { $0.url?.lastPathComponent == "manifest.json" }.count == 2)
    }
}
