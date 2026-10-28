import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import MW4CamoTracker

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

/// Blueprint tiles told from blue-tinted ones, on tiles from a backpack
/// photo (read from beside this file, so they need no bundle).
struct HajinBlueprintTileTests {

    private func tile(_ name: String) throws -> CGImage {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("backpack_tile_\(name).png")
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        return try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    }

    @Test func aBlueprintIsBlue() throws {
        #expect(HajinStashGrid.blueFraction(try tile("blueprint")) > 0.5)
    }

    /// A key's blue fob on a rare item's purple-blue tile was read as a blueprint
    @Test(arguments: ["key", "rare"])
    func aBlueTintIsNot(name: String) throws {
        #expect(HajinStashGrid.blueFraction(try tile(name)) < 0.25)
    }
}
