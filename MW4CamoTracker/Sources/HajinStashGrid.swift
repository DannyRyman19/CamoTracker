import CoreImage
import CoreML
import PhotosUI
import SwiftUI
import Vision

/// Reads the stash grid from a photo. The grid is always 6 tiles wide; the
/// player drags four handles to its corners, the photo is straightened so
/// every tile is a square, then each tile's icon is named by a classifier
/// trained on the guide's item art (HajinStashIcons.mlmodel) and its stack
/// count is read from the top-right corner.
enum HajinStashGrid {
    static let columns = 6
    static let cell: CGFloat = 200

    struct Tile {
        let row: Int, column: Int
        let id: String          // item id, "empty" or "other"
        let confidence: Float
        let count: Int?
    }

    /// Rows that fit the framed area, from its shape (tiles are square).
    static func rows(for corners: [CGPoint], size: CGSize) -> Int {
        let p = corners.map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) }
        func d(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }
        let width = (d(p[0], p[1]) + d(p[3], p[2])) / 2
        let height = (d(p[0], p[3]) + d(p[1], p[2])) / 2
        guard width > 0 else { return 1 }
        return max(1, min(20, Int((CGFloat(columns) * height / width).rounded())))
    }

    /// The framed quad as a flat image of the given size. Corners are
    /// top-left, top-right, bottom-right, bottom-left, as fractions with the
    /// origin at the top left.
    static func straighten(_ image: CGImage, corners: [CGPoint], size: CGSize) -> CGImage? {
        let w = CGFloat(image.width), h = CGFloat(image.height)
        func v(_ p: CGPoint) -> CIVector { CIVector(x: p.x * w, y: (1 - p.y) * h) }
        guard let f = CIFilter(name: "CIPerspectiveCorrection") else { return nil }
        f.setValue(CIImage(cgImage: image), forKey: kCIInputImageKey)
        f.setValue(v(corners[0]), forKey: "inputTopLeft")
        f.setValue(v(corners[1]), forKey: "inputTopRight")
        f.setValue(v(corners[2]), forKey: "inputBottomRight")
        f.setValue(v(corners[3]), forKey: "inputBottomLeft")
        guard var out = f.outputImage, out.extent.width > 0, out.extent.height > 0 else { return nil }
        out = out.transformed(by: CGAffineTransform(translationX: -out.extent.minX, y: -out.extent.minY))
        out = out.transformed(by: CGAffineTransform(scaleX: size.width / out.extent.width, y: size.height / out.extent.height))
        return CIContext().createCGImage(out, from: CGRect(origin: .zero, size: size))
    }

    @available(iOS 17.0, *)
    static func read(_ image: CGImage, corners: [CGPoint]) -> [Tile] {
        let rows = rows(for: corners, size: CGSize(width: image.width, height: image.height))
        // Half a tile of margin all round, so a frame dragged slightly inside
        // the grid still has its borders in the picture
        let margin = expanded(corners, du: 0.5 / CGFloat(columns), dv: 0.5 / CGFloat(rows))
        guard let flat = straighten(image, corners: margin, size: CGSize(width: cell * CGFloat(columns + 1), height: cell * CGFloat(rows + 1))) else {
            HajinGridDebug.log("straighten failed"); return [] }
        let model: VNCoreMLModel
        let config = MLModelConfiguration()
        #if targetEnvironment(simulator)
        config.computeUnits = .cpuOnly   // the simulator has no GPU/Neural Engine context
        #endif
        do { model = try VNCoreMLModel(for: HajinStashIcons(configuration: config).model) } catch {
            HajinGridDebug.log("model \(error)"); return [] }
        HajinGridDebug.log("rows \(rows) flat \(flat.width)x\(flat.height)")
        let lattice = HajinGridLattice.fit(flat, columns: columns, rows: rows, cell: cell)
        let ci = CIContext()
        // Two guesses at each tile: straight from the frame, and from the
        // borders found in the picture. Keep whichever reads more surely.
        func fromFrame(_ row: Int, _ column: Int) -> CGRect? {
            guard row < rows else { return nil }
            return CGRect(x: cell / 2 + CGFloat(column) * cell, y: cell / 2 + CGFloat(row) * cell, width: cell, height: cell)
        }
        func fromBorders(_ row: Int, _ column: Int) -> CGRect? {
            guard row + 1 < lattice.ys.count, column + 1 < lattice.xs.count else { return nil }
            return CGRect(x: lattice.xs[column], y: lattice.ys[row],
                          width: lattice.xs[column + 1] - lattice.xs[column], height: lattice.ys[row + 1] - lattice.ys[row])
        }
        func readTile(_ r: CGRect, _ row: Int, _ column: Int) -> Tile? {
            guard let raw = flat.cropping(to: r.integral), let tile = resized(raw, to: cell, ci) else { return nil }
            let request = VNCoreMLRequest(model: model)
            request.imageCropAndScaleOption = .scaleFill
            #if targetEnvironment(simulator)
            request.usesCPUOnly = true
            #endif
            do { try VNImageRequestHandler(cgImage: tile).perform([request]) } catch { HajinGridDebug.log("classify \(error)") }
            guard let top = (request.results as? [VNClassificationObservation])?.first else { return nil }
            let count = ["empty", "other"].contains(top.identifier) ? nil : HajinStackCount.read(tile)
            return Tile(row: row, column: column, id: top.identifier, confidence: top.confidence, count: count)
        }
        var tiles: [Tile] = []
        for row in 0..<max(rows, lattice.ys.count - 1) {
            for column in 0..<columns {
                let a = fromFrame(row, column), b = fromBorders(row, column)
                var crops = [a, b].compactMap { $0 }
                if let a, let b {   // and one halfway between
                    crops.append(CGRect(x: (a.minX + b.minX) / 2, y: (a.minY + b.minY) / 2,
                                        width: (a.width + b.width) / 2, height: (a.height + b.height) / 2))
                }
                let reads = crops.compactMap { readTile($0, row, column) }
                guard !reads.isEmpty else { continue }
                // The item with the most confidence across the reads, then the
                // count most of its reads agree on (the frame's on a tie)
                var weight: [String: Float] = [:]
                for r in reads { weight[r.id, default: 0] += r.confidence }
                let id = weight.max { $0.value < $1.value }!.key
                let mine = reads.filter { $0.id == id }
                let counts = mine.compactMap(\.count)
                let votes = Dictionary(grouping: counts, by: { $0 }).mapValues(\.count)
                let top = votes.values.max() ?? 0
                let count = counts.first { votes[$0] == top }
                tiles.append(Tile(row: row, column: column, id: id, confidence: weight[id]! / Float(reads.count), count: count))
            }
        }
        HajinGridDebug.log(tiles.filter { $0.id != "empty" }.map { "\($0.row)\($0.column) \($0.id) \(String(format: "%.2f", $0.confidence)) \($0.count.map(String.init) ?? "?")" }.joined(separator: "\n"))
        return tiles
    }

    /// The quad grown outward by fractions of its width and height, along
    /// its own sides (bilinear, close enough for a few percent).
    static func expanded(_ c: [CGPoint], du: CGFloat, dv: CGFloat) -> [CGPoint] {
        func at(_ u: CGFloat, _ v: CGFloat) -> CGPoint {
            let top = CGPoint(x: c[0].x + (c[1].x - c[0].x) * u, y: c[0].y + (c[1].y - c[0].y) * u)
            let bottom = CGPoint(x: c[3].x + (c[2].x - c[3].x) * u, y: c[3].y + (c[2].y - c[3].y) * u)
            return CGPoint(x: top.x + (bottom.x - top.x) * v, y: top.y + (bottom.y - top.y) * v)
        }
        return [at(-du, -dv), at(1 + du, -dv), at(1 + du, 1 + dv), at(-du, 1 + dv)]
    }

    static func resized(_ image: CGImage, to side: CGFloat, _ ci: CIContext) -> CGImage? {
        let input = CIImage(cgImage: image)
        let scaled = input.transformed(by: CGAffineTransform(scaleX: side / input.extent.width, y: side / input.extent.height))
        return ci.createCGImage(scaled, from: CGRect(x: 0, y: 0, width: side, height: side))
    }

    /// Stacks of the same item added together. A stack whose count couldn't
    /// be read counts as 1 and is listed in `unsure`, as is a weak match.
    static func totals(_ tiles: [Tile]) -> (counts: [String: Int], unsure: Set<String>) {
        var counts: [String: Int] = [:], unsure = Set<String>()
        // "other" is anything that isn't an ingredient (gear, keys, valuables
        // on the All tab): not tracked in My stash, so left out
        for t in tiles where t.id != "empty" && t.id != "other" {
            counts[t.id, default: 0] += t.count ?? 1
            if t.count == nil || t.confidence < 0.5 { unsure.insert(t.id) }
        }
        return (counts, unsure)
    }
}

/// Finds where the tile borders really are in a straightened stash grid (with
/// half a tile of margin), so a roughly framed photo still cuts cleanly. The
/// borders are light grey frame lines, so grey pixels counted down each
/// column (and along each row) peak at a regular spacing.
enum HajinGridLattice {
    struct Lattice { let xs: [CGFloat]; let ys: [CGFloat] }

    static func fit(_ image: CGImage, columns: Int, rows: Int, cell: CGFloat) -> Lattice {
        let w = image.width, h = image.height
        var px = [UInt8](repeating: 0, count: w * h * 4)
        let fallback = Lattice(xs: (0...columns).map { cell / 2 + CGFloat($0) * cell }, ys: (0...rows).map { cell / 2 + CGFloat($0) * cell })
        guard let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return fallback }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        // Frame lines are light grey; rarity bars are bright but coloured, so
        // count bright, unsaturated pixels along each column and row
        var colProfile = [Double](repeating: 0, count: w), rowProfile = [Double](repeating: 0, count: h)
        for y in 0..<h {
            for x in 0..<w {
                let i = (y * w + x) * 4
                let r = Int(px[i]), g = Int(px[i + 1]), b = Int(px[i + 2])
                let lo = min(r, g, b), hi = max(r, g, b)
                if lo > 110 && hi - lo < 45 { colProfile[x] += 1; rowProfile[y] += 1 }
            }
        }
        // Each gap has a frame line either side; smoothing turns the pair
        // into one peak centred on the gap
        // White icons add broad humps; keep only the narrow frame lines by
        // taking away the local average first
        colProfile = smoothed(smoothed(narrow(colProfile), 6), 6)
        rowProfile = smoothed(smoothed(narrow(rowProfile), 6), 6)
        let xs = lines(colProfile, count: columns, cell: Double(cell)) ?? fallback.xs.map(Double.init)
        // Rows: the count from the frame's shape could be one off either way;
        // take whichever fits the borders best for its size
        var best: (score: Double, ys: [Double])?
        for n in [rows, rows - 1, rows + 1] where n >= 1 {
            if let ys = lines(rowProfile, count: n, cell: Double(cell)), let sc = score(rowProfile, ys) {
                let perLine = sc / Double(ys.count)
                if best == nil || perLine > best!.score { best = (perLine, ys) }
            }
        }
        return Lattice(xs: xs.map { CGFloat($0) }, ys: (best?.ys ?? fallback.ys.map(Double.init)).map { CGFloat($0) })
    }

    /// The strongest set of count+1 evenly spaced border lines.
    private static func lines(_ profile: [Double], count: Int, cell: Double) -> [Double]? {
        let n = profile.count
        var best: (Double, Double, Double)?   // score, offset, pitch
        for pitch in stride(from: cell * 0.92, through: cell * 1.08, by: 1) {
            let span = pitch * Double(count)
            guard span < Double(n) else { continue }
            // The frame puts the first border half a tile in; trust it to
            // within 0.4 of a tile so the fit can't jump a whole row
            for offset in stride(from: cell * 0.1, through: min(cell * 0.9, Double(n) - span - 1), by: 1) {
                let ys = (0...count).map { offset + Double($0) * pitch }
                if let s = score(profile, ys), best == nil || s > best!.0 { best = (s, offset, pitch) }
            }
        }
        guard let b = best else { return nil }
        return (0...count).map { b.1 + Double($0) * b.2 }
    }

    /// Smoothed edge strength exactly at each line.
    private static func score(_ profile: [Double], _ at: [Double]) -> Double? {
        var total = 0.0
        for a in at {
            let c = Int(a.rounded())
            guard c >= 0 && c < profile.count else { return nil }
            total += profile[c]
        }
        return total
    }

    /// What stands above the surrounding average: thin lines, not wide shapes.
    private static func narrow(_ p: [Double]) -> [Double] {
        let wide = smoothed(p, 40)
        return zip(p, wide).map { max(0, $0 - $1) }
    }

    /// Box blur with the given radius.
    private static func smoothed(_ p: [Double], _ r: Int) -> [Double] {
        var prefix = [0.0]
        for v in p { prefix.append(prefix.last! + v) }
        return p.indices.map { i in
            let lo = max(0, i - r), hi = min(p.count - 1, i + r)
            return (prefix[hi + 1] - prefix[lo]) / Double(hi - lo + 1)
        }
    }
}

/// Debug builds write what the grid reader saw to Documents/grid_debug.txt,
/// so a run on a device can be checked from the Mac.
enum HajinGridDebug {
    static func log(_ text: String) {
        #if DEBUG
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("grid_debug.txt")
        let line = Data((text + "\n").utf8)
        if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(line); try? h.close() } else { try? line.write(to: url) }
        #endif
    }
}

/// Reads a stack count from a straightened 200 px tile: the white digits in
/// its top-right corner, split into blobs and matched against templates of
/// the game's digits. Ingredient stacks run 1 to 10.
enum HajinStackCount {
    private struct Glyph { var points: [(Int, Int)]; var minX: Int, minY: Int, maxX: Int, maxY: Int
        var width: Int { maxX - minX + 1 }; var height: Int { maxY - minY + 1 } }

    static func read(_ tile: CGImage) -> Int? {
        guard let corner = tile.cropping(to: CGRect(x: 96, y: 0, width: 104, height: 96)) else { return nil }
        let w = corner.width, h = corner.height
        var px = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(corner, in: CGRect(x: 0, y: 0, width: w, height: h))
        var low = [Int](repeating: 0, count: w * h)
        for i in 0..<(w * h) { low[i] = Int(min(px[i * 4], px[i * 4 + 1], px[i * 4 + 2])) }
        // Every brightness cut-off gives a reading; keep the ones that make a
        // real stack count (1 to 10) and take the one that best fits the
        // digit shapes. A digit broken into pieces fits badly, so it loses.
        var best: (value: Int, fit: Double)?
        var fallback: String?
        for threshold in [195, 180, 165, 150, 135] {
            let chain = digitChain(components(low, w, h, threshold), w, h)
            guard !chain.isEmpty else { continue }
            let reads = chain.map { classify($0) }
            let text = reads.map(\.digit).joined()
            if fallback == nil { fallback = text }
            guard let n = Int(text), (1...10).contains(n) else { continue }
            let fit = reads.map(\.distance).reduce(0, +) / Double(reads.count)
            if best == nil || fit < best!.fit { best = (n, fit) }
        }
        if let best { return best.value }
        guard let text = fallback, let last = text.last, let n = Int(String(last)), n > 0 else { return nil }
        return n
    }

    private static func components(_ low: [Int], _ w: Int, _ h: Int, _ threshold: Int) -> [Glyph] {
        var seen = [Bool](repeating: false, count: w * h)
        var out: [Glyph] = []
        for start in 0..<(w * h) where low[start] > threshold && !seen[start] {
            var stack = [start]; seen[start] = true
            var g = Glyph(points: [], minX: w, minY: h, maxX: 0, maxY: 0)
            while let i = stack.popLast() {
                let x = i % w, y = i / w
                g.points.append((x, y))
                g.minX = min(g.minX, x); g.maxX = max(g.maxX, x); g.minY = min(g.minY, y); g.maxY = max(g.maxY, y)
                for (nx, ny) in [(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)] where nx >= 0 && nx < w && ny >= 0 && ny < h {
                    let j = ny * w + nx
                    if !seen[j] && low[j] > threshold { seen[j] = true; stack.append(j) }
                }
            }
            out.append(g)
        }
        return out
    }

    /// The digits: tall-enough blobs on one line, the rightmost and any just
    /// to its left (at most two).
    private static func digitChain(_ all: [Glyph], _ w: Int, _ h: Int) -> [Glyph] {
        // Blobs touching the crop's edge, or hairline-thin, are the tile's
        // border, not digits
        var cs = all.filter { Double($0.height) > Double(h) * 0.28 && Double($0.height) < Double(h) * 0.9 && Double($0.width) < Double(w) * 0.45
            && $0.maxX < w - 2 && $0.minX > 1 && Double($0.width) >= Double($0.height) * 0.18 }
        guard let tallest = cs.max(by: { $0.height < $1.height }) else { return [] }
        let mid = Double(tallest.minY + tallest.maxY) / 2
        cs = cs.filter { abs(Double($0.minY + $0.maxY) / 2 - mid) < Double(tallest.height) * 0.4 }.sorted { $0.minX < $1.minX }
        var chain = [cs.removeLast()]
        while let c = cs.popLast() {
            let last = chain[0]
            guard Double(last.minX - c.maxX) < Double(last.height) * 0.35,
                  abs(Double(c.height - last.height)) < Double(last.height) * 0.25 else { break }
            chain.insert(c, at: 0)
        }
        return Array(chain.suffix(2))
    }

    /// The glyph box-averaged onto a W x H grid: a cell is on when at least
    /// half its source area is.
    private static func grid(_ g: Glyph, _ W: Int, _ H: Int) -> [Bool] {
        var on = Set<Int>()
        for (x, y) in g.points { on.insert((y - g.minY) * g.width + (x - g.minX)) }
        let gw = Double(g.width), gh = Double(g.height)
        var out = [Bool](repeating: false, count: W * H)
        for j in 0..<H {
            let sy0 = Double(j) * gh / Double(H), sy1 = Double(j + 1) * gh / Double(H)
            for i in 0..<W {
                let sx0 = Double(i) * gw / Double(W), sx1 = Double(i + 1) * gw / Double(W)
                var total = 0.0, covered = 0.0
                var yy = Int(sy0)
                while yy < min(g.height, Int(sy1 - 1e-9) + 1) {
                    let fy = min(sy1, Double(yy + 1)) - max(sy0, Double(yy))
                    var xx = Int(sx0)
                    while xx < min(g.width, Int(sx1 - 1e-9) + 1) {
                        let a = (min(sx1, Double(xx + 1)) - max(sx0, Double(xx))) * fy
                        total += a
                        if on.contains(yy * g.width + xx) { covered += a }
                        xx += 1
                    }
                    yy += 1
                }
                out[j * W + i] = total > 0 && covered / total >= 0.5
            }
        }
        return out
    }

    /// Enclosed background areas: 0 has one, 8 has two, 1 has none.
    private static func holes(_ b: [Bool], _ w: Int, _ h: Int) -> Int {
        var seen = [Bool](repeating: false, count: w * h), n = 0
        for start in 0..<(w * h) where !b[start] && !seen[start] {
            var stack = [start]; seen[start] = true
            var edge = false, size = 0
            while let i = stack.popLast() {
                size += 1
                let x = i % w, y = i / w
                if x == 0 || y == 0 || x == w - 1 || y == h - 1 { edge = true }
                for (nx, ny) in [(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)] where nx >= 0 && nx < w && ny >= 0 && ny < h {
                    let j = ny * w + nx
                    if !b[j] && !seen[j] { seen[j] = true; stack.append(j) }
                }
            }
            if !edge && size >= 6 { n += 1 }
        }
        return n
    }

    private static func classify(_ g: Glyph) -> (digit: String, distance: Double) {
        let bits = grid(g, 12, 20)
        let h = holes(grid(g, 24, 40), 24, 40)
        let aspect = Double(g.width) / Double(g.height)
        var best = ("", Double.infinity)
        for t in templates {
            var d = 0.0
            for (a, c) in zip(bits, t.bits) where a != (c == "1") { d += 1 }
            d += abs(aspect - t.aspect) * 60 + (h == t.holes ? 0 : 80)
            if d < best.1 { best = (t.digit, d) }
        }
        return (best.0, best.1)
    }

    private struct Template { let digit: String; let bits: [Character]; let holes: Int; let aspect: Double }
    private static let templates: [Template] = raw.map { Template(digit: $0.0, bits: Array($0.1), holes: $0.2, aspect: $0.3) }
    /// Digits from stash photos, then the Hitmarker font (12 x 20, holes, width/height)
    private static let raw: [(String, String, Int, Double)] = [
        ("1", "000001111000000000111111000111111111001111111111011111111111011111111111000000111111000000111111000000111111000000111111000000111111000000111111000000111111000000111111000000111111000000111111000000111111000000111111000000111111000000001111", 0, 0.375),
        ("4", "000000111100000001111110000001111110000001111110000001111110000011111110000111111110000111001110000111011110011111011110011110011110011110011110011110111110111111111111011111111111000000011110000000011110000000011110000000011110000000000110", 1, 0.562),
        ("2", "000011111000001111111100011111111110011110001111111100001111000000001111000000001111000000001111000000001110000000111110000001111100000011111000000111100000000111000000011110000000011110000000011100000000011111111111011111111111000000000011", 0, 0.531),
        ("2", "000111111000001111111100011111111110011110001111111100001111001000001111000000001111000000001111000000001110000000111110000001111100000011111000000111110000001111000000011110000000011110000000011100000000011101111111011111111111011001111111", 0, 0.531),
        ("2", "000111100000001111111100011111111100011110111111111100001111011000001111000000001111000000001111000000001110000000111110000001111100000111111000001111100000011111000000011111000000011110000000111100000000111111111110111111111111011111001111", 0, 0.531),
        ("1", "000000111100000001111110000111111110011111111100111111111110011000111110000000111110000000111110000000111110000000111110000000111110000000111110000000111110000000111110000000111110000000111110000000111110000000111111000000111110000000011100", 0, 0.406),
        ("3", "000111111100001111111100011110111100011110011110011110001110000000001110000000001110000000001110000001111100000001111000000001111000000000011100000000001110000000000110000000000111011000001111111100001111111110011110011111111100001111111100", 0, 0.581),
        ("6", "000001110000000001111000000011110000000111100000000111100000000111100000001111000000011110000000011111111100011111111100011111111110011110011110011000001111111000001111111000001111011000001111011100001111011110001110001111111100000111111100", 1, 0.581),
        ("8", "000111100000000111111000011111111100011110111110011100001111011100001111011100001111011100001110001111111110000111111100001111111100011111111110011100001111011000001111011000001111111000001111111100001111011100001111011111111110001111111100", 2, 0.548),
        ("5", "111111111000111111111100111110000000111100000000111000000000111000000000111000000000111100000000111111111000111111111100111100011111111000001111000000001111000000001111000000001111010000001111011100001111111110011110011111111100000111111000", 0, 0.516),
        ("2", "001111111100011111111100111111111110111100001111111000001111000000001111000000001111000000001111000000011110000001111110000011111100001111110000001111100000011111000000011110000000111110000000111100000000111111111111111111111111011000000000", 0, 0.500),
        ("1", "000000111111000011111111001111111111011111111110111111111110011000111110000000111110000000111110000000111111000000111110000000111110000000111111000000111111000000111111000000111111000000111111000000111111000000111111000000111111000000000110", 0, 0.375),
        ("1", "000001111100000111111100000111111100011111111100111100111110000000111110000000111111000000111110000000111110000000111110000000111110000000011110000000011110000000011110000000111110000000111110000000111110000000111111000000111111000000011110", 0, 0.419),
        ("0", "000111110000001111111100011111111110011100001110011000000111011000001111111000111111111000111111111000111111111001111111111001101111111111000111111111000111111110001111111110001111111000001111111100001111011110001111011111111100001111111100", 2, 0.581),
        ("6", "000000110000000001111000000001111000000011110000000111100000000111100000000111000000001110000000001111111100011111111100011111011110011110001111011100001111111000000111011000000111011100000111011100001111011110001110001111111100001111111100", 1, 0.581),
        ("1", "000000111110000011111110001111111110011111011110000000011110000000011110000000111110000000111110000000011110000000011110000000011110000000111110000000111110000000111111000000111111000010111111000111111111000000011000000000011000000000011000", 0, 0.371),
        ("0", "000111110000001111001100011110011110011100001111111100001111111100001111111100001111111100011111111000111111111000111011011001100001011111100001111111000111111110001111111110001111111100001111011100001111011110001111011111111110001111111100", 2, 0.567),
        ("2", "000111111000001111111100111111111110111000011111111000001111000000001111000000001111000000001111000000011110000000111110000001111100000111110000001111000000011110000000111110000000111110000000111100000000111111111111111111111111000000000000", 0, 0.485),
        ("8", "000111111000001111111100011111111100011100001110111100001110111000001110011100001110011100011100000111111000001111111000011111111100011000011110111000001110111000001111111000001111111000001111011100001110011110111110011111111100000011100000", 2, 0.548),
        ("5", "000001101000011111111110011110111110111110111100111000000000111100000000011100000000011111100000011111111110011111111110011110001111011000001111000000001111000000001111000000001111011000001111011100001111011111111111011111111110000011111000", 0, 0.531),
        ("1", "000000111110000011111111000111111111011111111111011111111111000000011111000000111110000000111110000000011110000000011110000000011110000000011110000000011110000000011110000000011110000000111110000000111110000000111111000000111111000000011100", 0, 0.438),
        ("0", "000111110000001111111100011111111110011110011111011100001111111000001111111000011111111000111111111000111111111001111111111111100111111111100111111111001111111110001111111100001111111100001111011100011111011111111110011111111100000001110000", 2, 0.562),
        ("1", "000001111110000111111110001111111111111111111110111111111110000000111110000000111110000000111110000000111111000000111111000000111110000000111111000000111111000000111111000000111110000000111110000000111110000000111110000000111111000000011100", 0, 0.419),
        ("0", "000111111000001111111100011111111110011100001110011100001110011100001110011100011111011100111111011100111111011101111111011101100111011111100111011111001111111110001111011100001111011100001111011100001110011110011110001111111100000111111000", 2, 0.613),
        ("9", "000111111000001111111100011111111100011000001111111000001111111100001111111100001111111000001111011100001111011000001111011001111110000000111110000000111110000000111110000000111100000000111000000001110000000001110000000001110000000001000000", 1, 0.567),
        ("1", "000001111111000111111110000111111110111110011110111110011110000000011000000000011000000000011110000000011110000000011110000000011110000000011110000000011110000000011110000000011000000000011110000000011110000000011111000000111111000000001100", 0, 0.387),
        ("0", "000111111000001111011100011111011110011000001110011000001111011000001110001000011110011000011111111000111111111100111111111111100111111111100111111111000111111110000111001000000111011000001111011000001110001100111110001111111100000001110000", 2, 0.581),
        ("1", "000000111100000011111000001111111000111110011110111110111110000000111110000000111110000000111110000000111110000000011110000000011000000000011000000000111110000000111110000000111111000000111111000000111111000000111111000000111111000000011110", 0, 0.419),
        ("0", "000111111000000100011000011110011110011000001110111000001110111000001111111000011111111000111111111000111111111000111111111001101111111111000111111111000111111110000111111110001111111000001111011100001111011110001111011111111100000001111100", 2, 0.581),
        ("3", "000111111000001111111000011111111100011100011110011100001110000000001110000000001110000000011110000011111100000011111000000001111000000000011110000000001110000000001110001000001110111000001111011100001110011111011110011111111100000011110000", 0, 0.594),
        ("1", "000000111110000111111110001111111111011111111110111111111110000000111110000000111110000000111110000000111110000000111110000000111110000000111110000000111110000000111110000001111110000001111110000000111110000000111110000001111110000000011000", 0, 0.424),
        ("0", "000111111000001111111110011111111110111110011111111100001111011100001111111100011111111100111111111100111111111101111111111111101111111111001111111111001111111110001111111100001111011100001110011110011110011111111110011111111100000001110000", 2, 0.576),
        ("1", "000000111111000011111111000111111111011111111111111111011111000000011111000000111111000000111111000000111111000000111111000000111111000000111111000000111111000000111111000000111111000000111111000000111111000000111111000000011111000000001100", 0, 0.394),
        ("0", "000111111100001111111110011111111111011100001111011100001111111100001111111100011111111100011111111100111111111101111111111111100111011111100111111111000111111110000111111100000111011100001111011110001111001111111110001111111100000001100000", 2, 0.545),
        ("2", "000111110000001111111100011111111110111110011111011100001111010000001111000000001111000000001111000000011110000000111100000001111100000111111000000111110000001111000000011110000000011110000000011100000000111111111111111111111111011111011110", 0, 0.515),
        ("1", "000001111110000111111110001111111110111111111100011110111110000000111110000000111110000000111110000000111110000000111110000000111110000000111110000000111110000000111110000000111111000000111111000000111110000000111110000000011111000000011100", 0, 0.406),
        ("0", "000111111000011111111110011111111110011100001110011000001110111000001111111000011111111000111111111000111111111001111111111111100111111111100111111111000111111110001111111100001111111100001111011110001111011111111110011111111110000011110000", 2, 0.562),
        ("0", "011111111100111111111110111111111111111100011111111100011111111100011111111100011111111100111111111100111111111101101111111101101111111111001111111111001111111111001111111110001111111110001111111110001111111111111111011111111110001111111100", 2, 0.630),
        ("1", "001111110000111111110000111111110000111111110000110111110000000011110000000011110000000011110000000011110000000011110000000011110000000011110000000011110000000011110000000011110000000011110000000111111000111111111111111111111111111111111111", 0, 0.500),
        ("2", "011111111110111111111111111111111111111100001111111100001111000000001111000000001111000000011111000000111111000001111110000011111100000111111000001111110000011111100000111111000000111110000000111111111111111111111111111111111111111111111111", 0, 0.609),
        ("3", "001111111110111111111111111111111111111100001111111100001111000000001111000000001111000000001111000011111111000011111110000011111110000011111111000000001111000000001111000000001111111100001111111100001111111111111111111111111111001111111110", 0, 0.630),
        ("4", "000011111100000011111100000011111100000111111100000111111100000111011100001111011100001110011100001110011100011110011100011100011100011100011100111100011100111111111111111111111111111111111111111111111111000000011100000000011100000000011100", 1, 0.761),
        ("5", "111111111111111111111111111111111111111100000000111100000000111100000000111100000000111101111110111111111111111111111111111100001111000000001111000000001111000000001111000000001111111100001111111110001111111111111111111111111111001111111110", 0, 0.630),
        ("6", "011111111110111111111111111111111111111100001111111100001111111100000000111100000000111100111110111111111111111111111111111100001111111100001111111100001111111100001111111100001111111100001111111111111111111111111111111111111111001111111110", 1, 0.630),
        ("7", "111111111111111111111111111111111111111111111111111100001111000000011110000000011110000000011110000000111100000000111100000001111100000001111000000001111000000011111000000011110000000011110000000111110000000111100000001111100000001111100000", 0, 0.630),
        ("8", "001111111110111111111111111111111111111110001111111100001111111100001111111100001111111100001111111111111111011111111110011111111110111111111111111100001111111100001111111100001111111100001111111110001111111111111111111111111111011111111110", 2, 0.630),
        ("9", "001111111110111111111111111111111111111111111111111100001111111100001111111100001111111100001111111100001111111100001111111111111111111111111111011111101111000000001111000000001111111100001111111110001111111111111111011111111111001111111110", 1, 0.630),
    ]
}

/// "Read a stash photo": pick one photo of the stash grid (Ingredients tab),
/// frame the grid, read it, review. iOS 17+: the icon model needs it.
@available(iOS 17.0, *)
struct HajinStashGridButton: View {
    @EnvironmentObject private var store: HajinStore
    @State private var pick: PhotosPickerItem?
    @State private var photo: HajinPickedPhoto?

    var body: some View {
        PhotosPicker(selection: $pick, matching: .images) {
            HStack(spacing: 10) {
                Image(systemName: "square.grid.3x3.fill")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.accentDMZ)
                VStack(alignment: .leading, spacing: 2) {
                    Text("mw4.ui.hajin.grid_scan".localized())
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.appInk)
                    Text("mw4.ui.hajin.grid_scan_hint".localized())
                        .font(.caption)
                        .foregroundStyle(Color.appInkMuted)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.appSurface))
        }
        .buttonStyle(.plain)
        .onChange(of: pick) { chosen in
            guard let chosen else { return }
            Task {
                if let data = try? await chosen.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    await MainActor.run { photo = HajinPickedPhoto(image: image.normalisedUp()) }
                }
                await MainActor.run { pick = nil }
            }
        }
        .fullScreenCover(item: $photo) { photo in
            HajinStashGridFrameView(image: photo.image)
        }
        #if DEBUG
        // SS_GRID_PHOTO=<file> opens that photo in the framing screen
        .onAppear {
            if photo == nil, var path = ProcessInfo.processInfo.environment["SS_GRID_PHOTO"] {
                if !path.hasPrefix("/") { path = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(path).path }
                guard let image = UIImage(contentsOfFile: path) else { return }
                photo = HajinPickedPhoto(image: image.normalisedUp())
            }
        }
        #endif
    }
}

struct HajinPickedPhoto: Identifiable {
    let id = UUID()
    let image: UIImage
}

extension UIImage {
    /// Pixels the right way up, so crops and corners agree with what's shown.
    func normalisedUp() -> UIImage {
        guard imageOrientation != .up else { return self }
        return UIGraphicsImageRenderer(size: size, format: { let f = UIGraphicsImageRendererFormat(); f.scale = 1; return f }())
            .image { _ in draw(in: CGRect(origin: .zero, size: size)) }
    }
}

/// The photo with four handles: drag them to the outside corners of the
/// tile grid. A preview of the 6-wide grid follows them.
@available(iOS 17.0, *)
struct HajinStashGridFrameView: View {
    let image: UIImage
    @EnvironmentObject private var store: HajinStore
    @Environment(\.dismiss) private var dismiss
    @State private var corners: [CGPoint] = [CGPoint(x: 0.15, y: 0.25), CGPoint(x: 0.85, y: 0.25), CGPoint(x: 0.85, y: 0.75), CGPoint(x: 0.15, y: 0.75)]
    @State private var reading = false
    @State private var finding = false
    /// Set once the player drags a handle, so a late guess doesn't move it back
    @State private var moved = false
    @State private var result: HajinGridResult?

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Text("mw4.ui.hajin.grid_frame".localized())
                    .font(.subheadline)
                    .foregroundStyle(Color.appInkMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                GeometryReader { geo in
                    let fit = fitted(image.size, in: geo.size)
                    ZStack(alignment: .topLeading) {
                        Image(uiImage: image).resizable().frame(width: fit.width, height: fit.height)
                        overlay(fit)
                        ForEach(0..<4, id: \.self) { i in
                            Circle()
                                .fill(Color.accentDMZ.opacity(0.35))
                                .overlay(Circle().strokeBorder(Color.white, lineWidth: 2))
                                .frame(width: 34, height: 34)
                                .position(x: corners[i].x * fit.width, y: corners[i].y * fit.height)
                                .gesture(DragGesture().onChanged { g in
                                    moved = true
                                    corners[i] = CGPoint(x: min(max(g.location.x / fit.width, 0), 1), y: min(max(g.location.y / fit.height, 0), 1))
                                })
                        }
                    }
                    .frame(width: fit.width, height: fit.height)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .padding(.horizontal, 8)
            }
            .background(Color.appBackground)
            .navigationTitle("mw4.ui.hajin.grid_scan".localized())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("mw4.ui.hajin.cancel".localized()) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if reading { ProgressView() } else {
                        Button("mw4.ui.hajin.grid_read".localized()) { read() }.font(.headline)
                    }
                }
            }
            .sheet(item: $result, onDismiss: { if result == nil { } }) { r in
                HajinStashScanReview(found: r.counts, unsure: r.unsure, onDone: { dismiss() })
            }
            .overlay(alignment: .bottom) {
                if finding {
                    Label("mw4.ui.hajin.grid_finding".localized(), systemImage: "viewfinder")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(Capsule().fill(Color.appSurface2))
                        .padding(.bottom, 24)
                }
            }
            .task {
                // The guess reads the photo (a second or two), off the main thread
                guard let cg = image.cgImage else { return }
                finding = true
                let guess = await Task.detached(priority: .userInitiated) { HajinStashGridFinder.guess(cg) }.value
                finding = false
                if let guess, !moved { withAnimation(.snappy) { corners = guess } }
            }
            .onAppear {
                #if DEBUG
                // SS_GRID_CORNERS=x,y,... (fractions, TL TR BR BL) sets the
                // frame and reads straight away, for screenshots
                let v = (ProcessInfo.processInfo.environment["SS_GRID_CORNERS"] ?? "").split(separator: ",").compactMap { Double($0) }
                if v.count == 8 {
                    moved = true
                    corners = stride(from: 0, to: 8, by: 2).map { CGPoint(x: v[$0], y: v[$0 + 1]) }
                    if ProcessInfo.processInfo.environment["SS_GRID_READ"] == "1" { read() }
                }
                #endif
            }
        }
    }

    private func fitted(_ size: CGSize, in box: CGSize) -> CGSize {
        let s = min(box.width / size.width, box.height / size.height)
        return CGSize(width: size.width * s, height: size.height * s)
    }

    /// The framed quad with the column lines and estimated row lines.
    private func overlay(_ fit: CGSize) -> some View {
        let rows = HajinStashGrid.rows(for: corners, size: image.size)
        return Path { p in
            func at(_ u: CGFloat, _ v: CGFloat) -> CGPoint {
                let top = CGPoint(x: corners[0].x + (corners[1].x - corners[0].x) * u, y: corners[0].y + (corners[1].y - corners[0].y) * u)
                let bottom = CGPoint(x: corners[3].x + (corners[2].x - corners[3].x) * u, y: corners[3].y + (corners[2].y - corners[3].y) * u)
                return CGPoint(x: (top.x + (bottom.x - top.x) * v) * fit.width, y: (top.y + (bottom.y - top.y) * v) * fit.height)
            }
            for c in 0...HajinStashGrid.columns {
                let u = CGFloat(c) / CGFloat(HajinStashGrid.columns)
                p.move(to: at(u, 0)); p.addLine(to: at(u, 1))
            }
            for r in 0...rows {
                let v = CGFloat(r) / CGFloat(rows)
                p.move(to: at(0, v)); p.addLine(to: at(1, v))
            }
        }
        .stroke(Color.accentDMZ, lineWidth: 1.5)
    }

    private func read() {
        guard let cg = image.cgImage else { return }
        reading = true
        let frame = corners
        Task.detached(priority: .userInitiated) {
            let tiles = HajinStashGrid.read(cg, corners: frame)
            let totals = HajinStashGrid.totals(tiles)
            await MainActor.run {
                reading = false
                result = HajinGridResult(counts: totals.counts, unsure: totals.unsure)
            }
        }
    }
}

struct HajinGridResult: Identifiable {
    let id = UUID()
    let counts: [String: Int]
    let unsure: Set<String>
}

/// A first guess at the grid's corners, for the player to adjust:
/// - bottom corners and the sides from the tiles the rectangle detector finds
///   (empty ones mostly, which sit at the bottom of a stash)
/// - the top from the stash's header line ("9/18 WEAPONS  79/94 ITEMS"),
///   which sits just over half a tile above the grid
/// Nil when there's too little to go on.
enum HajinStashGridFinder {
    static func guess(_ image: UIImage) -> [CGPoint]? {
        guard let cg = image.cgImage else { return nil }
        return guess(cg)
    }

    static func guess(_ cg: CGImage) -> [CGPoint]? {
        let W = CGFloat(cg.width), H = CGFloat(cg.height)
        let rects = VNDetectRectanglesRequest()
        rects.maximumObservations = 0
        rects.minimumSize = 0.04
        rects.minimumAspectRatio = 0.75
        rects.maximumAspectRatio = 1.0
        rects.quadratureTolerance = 20
        rects.minimumConfidence = 0.3
        let text = VNRecognizeTextRequest()
        text.recognitionLevel = .accurate
        text.usesLanguageCorrection = false
        try? VNImageRequestHandler(cgImage: cg).perform([rects, text])
        // pixels, origin top left
        func px(_ v: CGPoint) -> CGPoint { CGPoint(x: v.x * W, y: (1 - v.y) * H) }
        let quads = (rects.results ?? []).filter { $0.boundingBox.width < 0.25 }
        guard quads.count >= 3 else { return nil }
        let br = quads.map { px($0.bottomRight) }.max { $0.x + $0.y < $1.x + $1.y }!
        let bl = quads.map { px($0.bottomLeft) }.min { $0.x - $0.y < $1.x - $1.y }!
        guard br.x - bl.x > W * 0.3, abs(br.y - bl.y) < H * 0.15 else { return nil }
        let pitch = (br.x - bl.x) / CGFloat(HajinStashGrid.columns)

        // The sides: a line (x as a function of y) through the outer edges of
        // the tiles in the first and last columns
        func side(_ points: [CGPoint], through base: CGPoint) -> (CGFloat) -> CGFloat {
            let pts = points + [base]
            let my = pts.map(\.y).reduce(0, +) / CGFloat(pts.count), mx = pts.map(\.x).reduce(0, +) / CGFloat(pts.count)
            let num = pts.reduce(0) { $0 + ($1.y - my) * ($1.x - mx) }, den = pts.reduce(0) { $0 + ($1.y - my) * ($1.y - my) }
            let slope = den > 1 ? num / den : 0
            return { y in mx + slope * (y - my) }
        }
        let leftEdge = quads.filter { px($0.bottomLeft).x < bl.x + pitch * 0.5 }.flatMap { [px($0.topLeft), px($0.bottomLeft)] }
        let rightEdge = quads.filter { px($0.bottomRight).x > br.x - pitch * 0.5 }.flatMap { [px($0.topRight), px($0.bottomRight)] }
        let leftX = side(leftEdge, through: bl), rightX = side(rightEdge, through: br)

        // The top: the header's baseline, if the words are found
        let header = (text.results ?? []).filter { obs in
            let t = obs.topCandidates(1).first?.string.uppercased() ?? ""
            return (t.contains("WEAPON") || t.contains("ITEMS")) && px(obs.bottomLeft).y < min(bl.y, br.y) - pitch
        }
        var topAt: (CGFloat) -> CGFloat
        if !header.isEmpty {
            let pts = header.flatMap { [px($0.bottomLeft), px($0.bottomRight)] }
            let mx = pts.map(\.x).reduce(0, +) / CGFloat(pts.count), my = pts.map(\.y).reduce(0, +) / CGFloat(pts.count)
            let num = pts.reduce(0) { $0 + ($1.x - mx) * ($1.y - my) }, den = pts.reduce(0) { $0 + ($1.x - mx) * ($1.x - mx) }
            let slope = den > 1 ? num / den : 0
            topAt = { x in my + slope * (x - mx) }
        } else {
            // No header: start a few rows up for the player to drag
            let up = min(max(bl.y, br.y) - H * 0.05, (br.x - bl.x) * 0.8)
            topAt = { _ in max(H * 0.02, max(bl.y, br.y) - up) - pitch * 0.58 }
        }
        // Top corners where each side meets the line just under the header,
        // the gap scaled to the tile size up there
        func corner(_ sideX: (CGFloat) -> CGFloat) -> CGPoint {
            var y = topAt(sideX(bl.y))
            for _ in 0..<3 {
                let topPitch = (rightX(y) - leftX(y)) / CGFloat(HajinStashGrid.columns)
                y = topAt(sideX(y)) + topPitch * 0.58
            }
            return CGPoint(x: sideX(y), y: y)
        }
        let tl = corner(leftX), tr = corner(rightX)
        let quad = [tl, tr, CGPoint(x: rightX(br.y), y: br.y), CGPoint(x: leftX(bl.y), y: bl.y)]
        guard quad.allSatisfy({ $0.x > -W * 0.05 && $0.x < W * 1.05 && $0.y > -H * 0.05 && $0.y < H * 1.05 }),
              quad[3].y - quad[0].y > pitch else { return nil }
        let fractions = quad.map { CGPoint(x: min(max($0.x / W, 0), 1), y: min(max($0.y / H, 0), 1)) }
        return refine(cg, fractions)
    }

    /// Nudges each corner (coordinate descent on a quarter-size copy) to
    /// where the straightened grid's frame lines fall exactly on its 7
    /// column and row borders.
    static func refine(_ cg: CGImage, _ start: [CGPoint]) -> [CGPoint] {
        let scale: CGFloat = 0.25
        let small = CIImage(cgImage: cg).transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let size = CGSize(width: CGFloat(cg.width) * scale, height: CGFloat(cg.height) * scale)
        let ci = CIContext()
        func score(_ q: [CGPoint]) -> Double {
            let rows = HajinStashGrid.rows(for: q, size: size)
            let cell: CGFloat = 40
            guard let f = CIFilter(name: "CIPerspectiveCorrection") else { return 0 }
            func v(_ p: CGPoint) -> CIVector { CIVector(x: p.x * size.width, y: (1 - p.y) * size.height) }
            f.setValue(small, forKey: kCIInputImageKey)
            f.setValue(v(q[0]), forKey: "inputTopLeft"); f.setValue(v(q[1]), forKey: "inputTopRight")
            f.setValue(v(q[2]), forKey: "inputBottomRight"); f.setValue(v(q[3]), forKey: "inputBottomLeft")
            guard var o = f.outputImage, o.extent.width > 1 else { return 0 }
            let ow = cell * CGFloat(HajinStashGrid.columns), oh = cell * CGFloat(rows)
            o = o.transformed(by: CGAffineTransform(translationX: -o.extent.minX, y: -o.extent.minY))
            o = o.transformed(by: CGAffineTransform(scaleX: ow / o.extent.width, y: oh / o.extent.height))
            guard let g = ci.createCGImage(o, from: CGRect(x: 0, y: 0, width: ow, height: oh)) else { return 0 }
            let w = g.width, h = g.height
            var px = [UInt8](repeating: 0, count: w * h * 4)
            guard let c = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return 0 }
            c.draw(g, in: CGRect(x: 0, y: 0, width: w, height: h))
            var col = [Double](repeating: 0, count: w), row = [Double](repeating: 0, count: h)
            for y in 0..<h { for x in 0..<w {
                let i = (y * w + x) * 4
                let lo = min(px[i], px[i + 1], px[i + 2]), hi = max(px[i], px[i + 1], px[i + 2])
                if lo > 110 && hi - lo < 45 { col[x] += 1; row[y] += 1 }
            } }
            // Frame lines sit just inside each border: look 3 px either side
            func at(_ p: [Double], _ c: Int) -> Double { p[max(0, c - 3)...min(p.count - 1, c + 3)].max() ?? 0 }
            var total = 0.0
            for k in 0...HajinStashGrid.columns { total += at(col, Int(CGFloat(k) * cell)) / Double(h) }
            for j in 0...rows { total += at(row, Int(CGFloat(j) * cell)) / Double(w) }
            return total / Double(HajinStashGrid.columns + rows + 2)
        }
        var q = start
        var best = score(q)
        for step in [0.012, 0.006, 0.003] {
            var improved = true, rounds = 0
            while improved && rounds < 6 {
                improved = false; rounds += 1
                for i in 0..<4 {
                    for d in [CGPoint(x: step, y: 0), CGPoint(x: -step, y: 0), CGPoint(x: 0, y: step), CGPoint(x: 0, y: -step)] {
                        var t = q
                        t[i] = CGPoint(x: q[i].x + d.x, y: q[i].y + d.y)
                        let sc = score(t)
                        if sc > best { best = sc; q = t; improved = true }
                    }
                }
            }
        }
        return q
    }
}
