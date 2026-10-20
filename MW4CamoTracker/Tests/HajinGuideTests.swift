import Foundation
import UIKit
import Testing
@testable import MW4CamoTracker

/// Serves a fixed manifest and guide, so the guide refresh can be checked
/// without the network. Its own class, so it never races DataServiceTests.
final class GuideProtocol: URLProtocol {
    nonisolated(unsafe) static var bodies: [String: String] = [:]

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let body = Self.bodies[request.url?.lastPathComponent ?? ""] ?? "{}"
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite(.serialized)
struct HajinGuideTests {

    private func service() -> DataService {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [GuideProtocol.self]
        let cache = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        return DataService(session: URLSession(configuration: config), cacheDir: cache)
    }

    @Test func bundledGuideIsWellFormed() throws {
        let guide = try #require(DataService().loadSeedGuide(name: "hajin"))
        let categories = Set(guide.categories.map(\.id))
        #expect(Set(guide.markers.map(\.id)).count == guide.markers.count, "marker ids must be unique")
        for marker in guide.markers {
            #expect(categories.contains(marker.cat), "\(marker.id) has unknown category \(marker.cat)")
            #expect((0...1).contains(marker.x) && (0...1).contains(marker.y), "\(marker.id) is off the map")
            if let threat = marker.threat { #expect(guide.threatName(threat) != nil) }
        }
        #expect(!guide.guide.isEmpty)
        // Every link lands somewhere: recipe ingredients, guide rows, key markers
        let items = try #require(guide.items)
        let ids = Set(items.map(\.id))
        #expect(ids.count == items.count, "item ids must be unique")
        for item in items {
            for part in item.cost ?? [] { #expect(ids.contains(part.item), "\(item.id) needs unknown \(part.item)") }
            if let marker = item.marker { #expect(guide.marker(marker) != nil, "\(item.id) points at missing marker \(marker)") }
        }
        for section in guide.guide {
            for row in section.rows { if let id = row.item { #expect(ids.contains(id), "\(section.id) row links unknown \(id)") } }
        }
        #expect(Bundle.main.url(forResource: guide.map.image, withExtension: "jpg") != nil)
    }

    /// Every SF Symbol the guide names must exist, or its tile shows blank.
    @Test func everySymbolExists() throws {
        let guide = try #require(DataService().loadSeedGuide(name: "hajin"))
        let symbols = (guide.items ?? []).compactMap(\.symbol) + guide.categories.map(\.symbol) + guide.guide.map(\.symbol)
        for symbol in Set(symbols) {
            #expect(UIImage(systemName: symbol) != nil, "missing SF Symbol \(symbol)")
        }
    }

    @Test func guideTextTakesAPlainStringOrTranslations() throws {
        let plain = try JSONDecoder().decode(GuideText.self, from: Data(#""Rice Mill""#.utf8))
        #expect(plain.values == ["en": "Rice Mill"])
        let translated = try JSONDecoder().decode(GuideText.self, from: Data(#"{"en": "Map", "de": "Karte"}"#.utf8))
        #expect(translated.values["de"] == "Karte")
    }

    /// A manifest from before guides existed still decodes, and simply has
    /// nothing to download.
    @Test func manifestWithoutGuidesFetchesNothing() async throws {
        GuideProtocol.bodies = ["manifest.json": #"{"catalog": {"version": "1", "path": "weapons.json"}, "modes": {}}"#]
        let newer = try await service().refreshGuide(name: "hajin", knownVersion: "0.1.0")
        #expect(newer == nil)
    }

    @Test func newerGuideIsDownloadedAndCached() async throws {
        let url = try #require(Bundle.main.url(forResource: "hajin", withExtension: "json"))
        var json = try #require(String(data: Data(contentsOf: url), encoding: .utf8))
        let bundled = try #require(DataService().loadSeedGuide(name: "hajin")).version
        json = json.replacingOccurrences(of: #""version": "\#(bundled)""#, with: #""version": "9.9.9""#)
        GuideProtocol.bodies = [
            "manifest.json": #"{"catalog": {"version": "1", "path": "weapons.json"}, "modes": {}, "guides": {"hajin": {"version": "9.9.9", "path": "hajin.json"}}}"#,
            "hajin.json": json,
        ]
        let service = service()
        let newer = try await service.refreshGuide(name: "hajin", knownVersion: bundled)
        #expect(newer?.version == "9.9.9")
        #expect(service.loadCachedGuide(name: "hajin")?.version == "9.9.9")
        // Already up to date: nothing more to fetch
        #expect(try await service.refreshGuide(name: "hajin", knownVersion: "9.9.9") == nil)
    }
}
