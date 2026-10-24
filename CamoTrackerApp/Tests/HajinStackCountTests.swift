import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import CamoTracker

private final class TileBundle {}

/// Stack counts read from real stash tiles (straightened, 200 px).
struct HajinStackCountTests {

    private func tile(_ name: String) throws -> CGImage {
        let url = try #require(Bundle(for: TileBundle.self).url(forResource: "stash_tile_\(name)", withExtension: "png"))
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        return try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    }

    @Test(arguments: [("r0c0", 1), ("r0c1", 4), ("r1c2", 8), ("r2c0", 10), ("r3c2", 9), ("r4c3", 10)])
    func readsTheCountInTheTopRightCorner(name: String, count: Int) throws {
        #expect(HajinStackCount.read(try tile(name)) == count)
    }
}
