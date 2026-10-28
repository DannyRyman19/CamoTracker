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

/// Where a straightened tile sits back on the photo.
struct HajinOnPhotoTests {
    @Test func cornersMapToCorners() {
        let q = [CGPoint(x: 0.1, y: 0.2), CGPoint(x: 0.9, y: 0.15), CGPoint(x: 0.85, y: 0.8), CGPoint(x: 0.12, y: 0.9)]
        for (u, v, p) in [(0.0, 0.0, q[0]), (1.0, 0.0, q[1]), (1.0, 1.0, q[2]), (0.0, 1.0, q[3])] {
            let m = HajinStashGrid.onPhoto(q, u: u, v: v)
            #expect(abs(m.x - p.x) < 1e-9 && abs(m.y - p.y) < 1e-9)
        }
    }

    @Test func aRectangleIsEvenlySplit() {
        let q = [CGPoint(x: 0.2, y: 0.2), CGPoint(x: 0.6, y: 0.2), CGPoint(x: 0.6, y: 0.8), CGPoint(x: 0.2, y: 0.8)]
        let m = HajinStashGrid.onPhoto(q, u: 0.25, v: 0.5)
        #expect(abs(m.x - 0.3) < 1e-9 && abs(m.y - 0.5) < 1e-9)
    }
}

/// The review's highlight moved onto a tile's own outline.
struct HajinSnapTests {
    @Test func aBoxOffTheTileSnapsOntoItsOutline() {
        let w = 300, h = 300
        var grey = [UInt8](repeating: 30, count: w * h)
        // The tile's outline: 100...200 both ways
        for i in 100...200 {
            for k in [100, 200] { grey[k * w + i] = 120; grey[i * w + k] = 120 }
        }
        let r = HajinStashGrid.snapped(CGRect(x: 88, y: 92, width: 104, height: 104), grey, width: w, height: h)
        #expect(r == CGRect(x: 100, y: 100, width: 100, height: 100))
    }

    @Test func noOutlineLeavesTheBox() {
        let grey = [UInt8](repeating: 30, count: 300 * 300)
        let box = CGRect(x: 88, y: 92, width: 104, height: 104)
        #expect(HajinStashGrid.snapped(box, grey, width: 300, height: 300) == box)
    }
}

/// A bright patch beside the tile (white space round the grid) isn't its outline.
struct HajinSnapEdgeTests {
    @Test func theEdgeOfABrightPatchIsNotAnOutline() {
        let w = 300, h = 300
        var grey = [UInt8](repeating: 30, count: w * h)
        // White from x 190 rightwards: its edge is bright on one side only
        for y in 0..<h { for x in 190..<w { grey[y * w + x] = 220 } }
        let box = CGRect(x: 96, y: 96, width: 104, height: 104)
        #expect(HajinStashGrid.snapped(box, grey, width: w, height: h) == box)
    }
}
