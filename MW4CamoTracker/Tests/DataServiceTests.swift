import Foundation
import Testing
@testable import MW4CamoTracker

/// Answers every request with a fixed body and records what was asked for.
final class RecordingProtocol: URLProtocol {
    nonisolated(unsafe) static var requests: [URLRequest] = []
    nonisolated(unsafe) static var bodies: [String: String] = [:]
    /// Hosts that fail: with this HTTP status, or 0 for no answer at all.
    nonisolated(unsafe) static var failingHosts: [String: Int] = [:]

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requests.append(request)
        if let status = Self.failingHosts[request.url?.host ?? ""] {
            guard status != 0 else {
                client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
                return
            }
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data("Package size exceeded the configured limit of 50 MB.".utf8))
            client?.urlProtocolDidFinishLoading(self)
            return
        }
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

    /// One file that won't decode doesn't stop the others, and nothing is
    /// kept before every file has been downloaded and decoded.
    @Test func oneBadModeFileDoesntStopTheRest() async throws {
        let cache = newCache()
        RecordingProtocol.requests = []
        RecordingProtocol.bodies = [
            "manifest.json": #"""
                {"catalog": {"version": "999.0.0", "path": "weapons.json"},
                 "modes": {"multiplayer": {"version": "999.0.0", "path": "multiplayer.json"},
                           "warzone": {"version": "999.0.0", "path": "warzone.json"}}}
                """#,
            "weapons.json": try bundled("weapons", version: "999.0.0"),
            "multiplayer.json": try bundled("multiplayer", version: "999.0.0"),
            "warzone.json": #"{"version": "999.0.0", "mode": "warzone"}"#,
        ]
        let service = service(cache: cache)
        let result = try await service.refreshIfNeeded(knownCatalogVersion: "1", knownModeVersions: ["multiplayer": "1", "warzone": "1"])
        #expect(result.catalog?.version == "999.0.0")
        #expect(result.modes.keys.sorted() == ["multiplayer"])
        #expect(service.loadCached(mode: "multiplayer")?.version == "999.0.0")
        #expect(service.loadCached(mode: "warzone") == nil)

        // Nothing came down at all: the error still reaches the app
        RecordingProtocol.bodies["weapons.json"] = "{}"
        RecordingProtocol.bodies["multiplayer.json"] = "{}"
        await #expect(throws: (any Error).self) {
            try await self.service(cache: self.newCache()).refreshIfNeeded(knownCatalogVersion: "1", knownModeVersions: [:])
        }
    }

    /// A check the previous game started can finish after a switch: it
    /// keeps its own data, but the global Mastery and Completionist rules
    /// stay the shown game's.
    @MainActor @Test func aSlowCheckAfterAGameSwitchLeavesTheShownGamesRules() async throws {
        let mw4 = GameRegistry.game("mw4") ?? GameRegistry.fallback
        let defaults = try #require(UserDefaults(suiteName: "DataServiceTests-\(UUID().uuidString)"))
        let url = try #require(Bundle.main.url(forResource: "multiplayer", withExtension: "json"))
        var json = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        json["version"] = "999.0.0"
        json["mastery"] = ["tier1": ["weaponsNeeded": 777]]
        RecordingProtocol.requests = []
        RecordingProtocol.bodies = [
            "manifest.json": #"{"catalog": {"version": "0", "path": "weapons.json"}, "modes": {"multiplayer": {"version": "999.0.0", "path": "multiplayer.json"}}}"#,
            "multiplayer.json": String(decoding: try JSONSerialization.data(withJSONObject: json), as: UTF8.self),
        ]
        let vm = TrackerViewModel(game: mw4, dataService: service(cache: newCache()), defaults: defaults)
        vm.isShown = false
        await vm.refresh()
        #expect(vm.modes["multiplayer"]?.version == "999.0.0")
        #expect(MasteryOverrides.byMode["multiplayer"]?.tier1?.weaponsNeeded != 777)
    }

    /// jsDelivr has answered 403 "Package size exceeded" for this repo's
    /// files: each path it fails is asked of GitHub once, without the
    /// phone's cache, and what arrives goes through the same version checks.
    @Test(arguments: [403, 0])
    func aFailedJsDelivrRequestIsAskedOfGitHubOnce(status: Int) async throws {
        RecordingProtocol.requests = []
        RecordingProtocol.failingHosts = ["cdn.jsdelivr.net": status]
        defer { RecordingProtocol.failingHosts = [:] }
        RecordingProtocol.bodies = [
            "manifest.json": #"{"catalog": {"version": "999.0.0", "path": "weapons.json"}, "modes": {}}"#,
            "weapons.json": try bundled("weapons", version: "999.0.0"),
        ]
        let result = try await service().refreshIfNeeded(knownCatalogVersion: "1", knownModeVersions: [:])
        #expect(result.catalog?.version == "999.0.0")

        let asked = RecordingProtocol.requests.compactMap(\.url?.absoluteString)
        #expect(asked == [
            "https://cdn.jsdelivr.net/gh/DannyRyman19/CamoTracker@master/Data/MW4/manifest.json",
            "https://raw.githubusercontent.com/DannyRyman19/CamoTracker/master/Data/MW4/manifest.json",
            "https://cdn.jsdelivr.net/gh/DannyRyman19/CamoTracker@master/Data/MW4/weapons.json",
            "https://raw.githubusercontent.com/DannyRyman19/CamoTracker/master/Data/MW4/weapons.json",
        ])
        #expect(RecordingProtocol.requests.allSatisfy { $0.cachePolicy == .reloadIgnoringLocalCacheData })
    }

    @Test func gitHubsCopyIsVersionCheckedToo() async throws {
        let cache = newCache()
        try bundled("weapons", version: "9.9.9").write(to: cache.appendingPathComponent("weapons.json"), atomically: true, encoding: .utf8)
        RecordingProtocol.failingHosts = ["cdn.jsdelivr.net": 403]
        defer { RecordingProtocol.failingHosts = [:] }
        RecordingProtocol.bodies = [
            "manifest.json": #"{"catalog": {"version": "5.0.0", "path": "weapons.json"}, "modes": {}}"#,
            "weapons.json": try bundled("weapons", version: "5.0.0"),
        ]
        let service = service(cache: cache)
        #expect(try await service.refreshIfNeeded(knownCatalogVersion: "1", knownModeVersions: [:]).catalog == nil)
        #expect(service.loadCachedCatalog()?.version == "9.9.9")
    }

    @Test func bothFailingIsAnError() async {
        RecordingProtocol.requests = []
        RecordingProtocol.failingHosts = ["cdn.jsdelivr.net": 403, "raw.githubusercontent.com": 404]
        defer { RecordingProtocol.failingHosts = [:] }
        await #expect(throws: (any Error).self) {
            try await self.service().refreshIfNeeded(knownCatalogVersion: "1", knownModeVersions: [:])
        }
        // Once each, no more
        #expect(RecordingProtocol.requests.count == 2)
    }
}
