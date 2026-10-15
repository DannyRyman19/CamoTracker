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

    private func service() -> DataService {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [RecordingProtocol.self]
        let cache = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        return DataService(session: URLSession(configuration: config), cacheDir: cache)
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
}
