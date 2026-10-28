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

    /// Printing an upgrade takes its cost out of the stash (never below
    /// zero), stops tracking it, and Undo puts both back.
    @MainActor @Test func printingSpendsTheStashAndUndoRestoresIt() throws {
        let defaults = try #require(UserDefaults(suiteName: "hajin-spend-\(UUID().uuidString)"))
        let store = HajinStore(defaults: defaults)
        // Stash Weapon Upgrade I: 20 Reactive Metals, 10 Stock Rod, 5 Comms Module
        store.setCount(25, of: "reactive-metals")
        store.setCount(4, of: "stock-rod")
        store.toggleTracked("stash-weapon-upgrade-i")
        store.toggle("upgrade-stash-weapon-upgrade-i")
        #expect(store.count(of: "reactive-metals") == 5)
        #expect(store.count(of: "stock-rod") == 0)
        #expect(!store.isTracked("stash-weapon-upgrade-i"))
        #expect(store.stashUndo != nil)
        store.undoStash()
        #expect(store.count(of: "reactive-metals") == 25)
        #expect(store.count(of: "stock-rod") == 4)
        #expect(store.isTracked("stash-weapon-upgrade-i"))
        #expect(store.checked.contains("upgrade-stash-weapon-upgrade-i"))
    }

    @Test func unfinishedOrdersKeepWhatTheyPrintWith() throws {
        let guide = try #require(DataService().loadSeedGuide(name: "hajin"))
        let reactive = try #require(guide.item("reactive-metals"))
        // Page 10's Healer: 3 to extract plus the Armor Box's 3
        let open = HajinVerdict(item: reactive, guide: guide, done: [])
        #expect(open.kind == .keep)
        #expect(open.orders.first { $0.order.check == "op-page-10-healer" }?.qty == 6)
        // Every order ticked: nothing left to hold for
        let ticks = Set(guide.guide.first { $0.id == "ops" }?.rows.compactMap(\.check) ?? [])
        #expect(guide.orderNeeds(done: ticks).isEmpty)
        #expect(HajinVerdict(item: reactive, guide: guide, done: ticks).orders.isEmpty)
        // Manuals and dog tags have to be found in the match, so never held
        #expect(!guide.orderNeeds(done: []).contains { $0.item == "weapon-manual" || $0.item.contains("dog-tag") })
    }

    @MainActor @Test func operatorsKeepTheirPrestigeAndUpToThreeTraits() throws {
        let defaults = try #require(UserDefaults(suiteName: "hajin-prestige-\(UUID().uuidString)"))
        let store = HajinStore(defaults: defaults)
        store.addOperator(" Ghost ")
        store.addOperator("ghost")   // the same operator
        store.addOperator("Roze|")
        #expect(store.operators.map(\.name) == ["Ghost", "Roze"])
        store.setPrestige(2, of: "Ghost")
        #expect(store.operators.first { $0.name == "Ghost" }?.level == 2)
        for trait in ["Possum Pro", "Overwatch Pro", "Die Hard Pro", "Quick Fix Pro"] { store.togglePrestigeTrait(trait, of: "Ghost") }
        #expect(store.prestigeTraits(of: "Ghost") == ["Die Hard Pro", "Overwatch Pro", "Possum Pro"])
        // Kept in the synced ticks, and gone with the operator
        #expect(HajinStore(defaults: defaults).operators.count == 2)
        store.removeOperator("Ghost")
        #expect(store.operators.map(\.name) == ["Roze"])
        #expect(store.prestigeTraits(of: "Ghost").isEmpty)
    }
}
