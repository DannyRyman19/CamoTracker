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

    /// Rows in the framed area, measured: straightened, the horizontal frame
    /// lines repeat once per row, so the repeat length gives the row count.
    /// (The frame's shape alone misleads when the photo is taken at an angle
    /// and the grid looks squashed.) Falls back to the shape estimate.
    static func measureRows(_ image: CGImage, corners: [CGPoint]) -> Int {
        let estimate = rows(for: corners, size: CGSize(width: image.width, height: image.height))
        let cw: CGFloat = 40, height: CGFloat = 640
        guard let flat = straighten(image, corners: corners, size: CGSize(width: cw * CGFloat(columns), height: height)) else { return estimate }
        let w = flat.width, h = flat.height
        var px = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return estimate }
        ctx.draw(flat, in: CGRect(x: 0, y: 0, width: w, height: h))
        let row = HajinFrameLines.profiles(px, w, h).rows
        func smooth(_ p: [Double], _ r: Int) -> [Double] {
            var acc = [0.0]; for v in p { acc.append(acc.last! + v) }
            return p.indices.map { i in let a = max(0, i - r), b = min(p.count - 1, i + r); return (acc[b + 1] - acc[a]) / Double(b - a + 1) }
        }
        let wide = smooth(row, 30)
        let lines = smooth(zip(row, wide).map { max(0, $0 - $1) }, 2)
        // the repeat, for 3 to 14 rows; a double-row repeat scores nearly as
        // well, so take the shortest lag that comes close to the best
        let mean = lines.reduce(0, +) / Double(h)
        var scores: [(lag: Int, score: Double)] = []
        for lag in Int(height / 14)...Int(height / 3) {
            var sc = 0.0
            for y in 0..<(h - lag) { sc += (lines[y] - mean) * (lines[y + lag] - mean) }
            scores.append((lag, sc / Double(h - lag)))
        }
        // local peaks only, so the slope next to a strong peak doesn't count
        let peaks = scores.indices.filter { i in
            (i == 0 || scores[i].score >= scores[i - 1].score) && (i == scores.count - 1 || scores[i].score >= scores[i + 1].score)
        }.map { scores[$0] }
        guard let top = peaks.map(\.score).max(), top > 0,
              let best = peaks.first(where: { $0.score >= top * 0.8 }) else { return estimate }
        let measured = Int((height / CGFloat(best.lag)).rounded())
        HajinGridDebug.log("rows: shape says \(estimate), lines repeat every \(best.lag) of \(Int(height)) -> \(measured)")
        return (1...20).contains(measured) ? measured : estimate
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
    static func read(_ image: CGImage, corners: [CGPoint], rows known: Int? = nil) -> [Tile] {
        let rows = known ?? measureRows(image, corners: corners)
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
    static func totals(_ tiles: [Tile]) -> (counts: [String: Int], unsure: Set<String>, sureness: [String: Float], stacks: [String: Int]) {
        var counts: [String: Int] = [:], unsure = Set<String>(), sureness: [String: Float] = [:], stacks: [String: Int] = [:]
        // "other" is anything that isn't an ingredient (gear, keys, valuables
        // on the All tab): not tracked in My stash, so left out
        for t in tiles where t.id != "empty" && t.id != "other" {
            counts[t.id, default: 0] += t.count ?? 1
            stacks[t.id, default: 0] += 1
            // how sure of the item: its least certain stack
            sureness[t.id] = min(sureness[t.id] ?? 1, t.confidence)
            if t.count == nil || t.confidence < 0.5 { unsure.insert(t.id) }
        }
        return (counts, unsure, sureness, stacks)
    }
}

/// The tiles' frame lines, counted along each column and row of a
/// straightened grid (RGBA pixels). A frame pixel is unsaturated and either
/// bright (a photo of a TV) or a thin ridge clearly brighter than the pixels
/// a little either side of it (a console screenshot, where the lines are a
/// dim grey on near black).
enum HajinFrameLines {
    static func profiles(_ px: [UInt8], _ w: Int, _ h: Int) -> (cols: [Double], rows: [Double]) {
        let r = w > 600 ? 4 : 2
        var cols = [Double](repeating: 0, count: w), rows = [Double](repeating: 0, count: h)
        func lum(_ x: Int, _ y: Int) -> Int { let i = (y * w + x) * 4; return (Int(px[i]) + Int(px[i + 1]) + Int(px[i + 2])) / 3 }
        for y in 0..<h {
            for x in 0..<w {
                let i = (y * w + x) * 4
                let lo = min(px[i], px[i + 1], px[i + 2]), hi = max(px[i], px[i + 1], px[i + 2])
                guard hi - lo < 45 else { continue }
                if lo > 110 { cols[x] += 1; rows[y] += 1; continue }
                let l = lum(x, y)
                guard l >= 40 else { continue }
                // a horizontal line: brighter than above and below it
                if y >= r && y < h - r && l - max(lum(x, y - r), lum(x, y + r)) > 15 { rows[y] += 1 }
                // a vertical line: brighter than left and right of it
                if x >= r && x < w - r && l - max(lum(x - r, y), lum(x + r, y)) > 15 { cols[x] += 1 }
            }
        }
        return (cols, rows)
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
        var (colProfile, rowProfile) = HajinFrameLines.profiles(px, w, h)
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
            // crisp screenshot digits sit a little further apart than a photo's
            guard Double(last.minX - c.maxX) < Double(last.height) * 0.6,
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
    /// Digits from stash photos, a console screenshot (its zero has a slash,
    /// so two holes), then the Hitmarker font (12 x 20, holes, width/height)
    private static let raw: [(String, String, Int, Double)] = [
        ("1", "000001111111000111111111001111111111000000001111000000000111000000000111000000000111000000000111000000011111000000000111000000000111000000000111000000000111000000000111000000000111000000000111000000000111000000000111000000000111000000000011", 0, 0.241),
        ("4", "000000111100000001111100000001111100000001111100000011111100000111011100000110001100000100001100001100001100001100001100011000001100110000001100110000001100111000011111111111111111000000111110000000001100000000001100000000001100000000001100", 1, 0.500),
        ("2", "000111111100001110001110011100000111111000000111000000000011000000000011000000000011000000000111000000000111000000011100000000111000000001110000000011100000001110000000001110000000001100000000011000000000111000000000111110000000011111111111", 0, 0.483),
        ("2", "000111111000011100001100011000001110111000000110000000000011000000000011000000000010000000000110000000001100000000011000000000110000000011100000000111000000001110000000011100000000011000000000011000000000011000000000111100000000011111111110", 0, 0.517),
        ("2", "000111111000011110011110011000000110111000000111000000000111000000000111000000000111000000000111000000000110000000011100000000111000000001110000000111000000001110000000001100000000011000000000111000000000111000000000111100000000111111111111", 0, 0.483),
        ("1", "000001111111000011111111000111111111111000001111000000001111000000001111000000001111000000001111000000001111000000001111000000001111000000001111000000001111000000001111000000001111000000001111000000001111000000001111000000001111000000000111", 0, 0.310),
        ("3", "000001000000001111111000011100001100011000000110000000000110000000000110000000000110000000001100000000011000000001111000000000011000000000001100000000000110000000000011000000000011000000000011110000000110011000001110001110011100000011100000", 0, 0.500),
        ("6", "000001110000000001100000000011100000000111000000000110000000001110000000001100000000011100000000011111111100111111111110111000001110111000000111110000000111110000000111110000000111110000000111111000000111011000000110001110011100000001100000", 1, 0.483),
        ("8", "000111110000001100001100011000000110011000000110010000000110010000000110011000000110001100001100000111111100001111111100001100000100011000000110110000000110110000000010110000000011110000000010111000000110011100001110001110011100000001100000", 2, 0.517),
        ("5", "111111111100111000000000110000000000110000000000110000000000110000000000110000000000111100000000111111111100111000001100000000000110000000000111000000000111000000000111000000000111000000000111110000000110111000001100011110111100000111100000", 0, 0.483),
        ("2", "000000001100000000000110000000000011000000000011000000000011000000000011000000000011000000000100000000001100000000011000000000110000000011000000000110000000001100000000001000000000001000000000011000000000111000000000111000000000000000000001", 0, 0.500),
        ("1", "000000111111000011111111000111111111111000001111000000001111000000001111000000001111000000001111000000001111000000001111000000001111000000001111000000001111000000001111000000001111000000001111000000001111000000001111000000001111000000001111", 0, 0.310),
        ("6", "000000110000000001100000000011100000000011000000000110000000000110000000001100000000001100000000011100000000011111111100111100011110110000000111110000000111110000000111110000000111110000000111110000000111111000000110011100011100001111111000", 1, 0.483),
        ("1", "000001111111000111111111011111111111111110111111000000001111000000001111000000001111000000001111000000001111000000001111000000001111000000001111000000001111000000001111000000001111000000011111000001111111000000111100000000010000000000011000", 0, 0.314),
        ("0", "000111111000001111111100011110011110011100001110011100001111011000001111011000011111011000011111111000111111111001101111011111101111011111001111011110001111011100001111011100001111011100001111011100001110011110011110001111111100000111111000", 2, 0.567),
        ("2", "000011100000011110011100110000000100100000000110000000000110000000000110000000000110000000000100000000000100000000001000000000111000000001100000000010000000001100000000001000000000011000000000110000000000110000000000110000000000111111111111", 0, 0.483),
        ("8", "000011110000001111111100011000000100111000000111111000000111111000000111011000000110011000001110001110001100000111111000001110011100001000000100111000000111111000000011110000000011110000000011111000000111111000000111011110011110001111111100", 2, 0.483),
        ("5", "011111111110011100000000011000000000011000000000011000000000111000000000111000000000011111110000011111111110111100001110000000000111000000000011000000000011000000000011000000000011000000000011011000000111011100000110001111111100000000100000", 0, 0.467),
        ("9", "000001100000001110011100001100000111111000000111111000000011111000000011111000000011111000000011111000000011011100000111001111111111000111111111000000001110000000001100000000001100000000011000000000111000000000111000000001100000000001100000", 1, 0.483),
        ("3", "000011110000001110011100011000000110000000000110000000000110000000000110000000000110000000001100000000111100000000111000000000001000000000000110000000000110000000000011000000000011000000000011110000000110011000000110001100001100000111111000", 0, 0.517),
        ("2", "000011110000001110011110001100000111011000000011000000000011000000000011000000000011000000000111000000000111000000001100000000011100000001110000000011000000000111000000001110000000001100000000011000000000011000000000111100000000111111111111", 0, 0.483),
        ("1", "000000011110000001111111001111111111001100001111110000001111000000001111000000001111000000001111000000001111000000001111000000001110000000001110000000001110000000001110000000001110000000001110000000001110000000001110000000001110000000001110", 0, 0.345),
        ("6", "000000110000000001110000000001100000000011000000000011000000000110000000000110000000001100000000001111010000011111111110111100001111111000000111111000000011110000000011110000000011110000000011111000000111011000000110001110011110000011111000", 1, 0.483),
        ("3", "000111111000011110011110011000000110010000000011000000000011000000000011000000000110000000001110000000111100000001111000000000011100000000000110000000000011000000000011000000000011000000000011110000000011011000000110011110011110000111111000", 0, 0.483),
        ("2", "001111111000011110011100111000000110110000000111000000000111000000000111000000000111000000000111000000000100000000011100000000111000000011100000000110000000001110000000001100000000011000000000111000000000111000000000111000000000111111111111", 0, 0.483),
        ("4", "000000011100000000011100000000011100000000111100000001111100000000000100000000000100000000000100000000000100000000000100000000000100000000000100000000000100111000001100000000011111000000001100000000000100000000000100000000000100000000000100", 0, 0.483),
        ("7", "111111111111000000001111000000000110000000000100000000000100000000001100000000001100000000011000000000011000000000011000000000111000000000110000000000110000000001100000000001100000000001100000000011000000000011000000000011000000000010000000", 0, 0.517),
        ("1", "000000111110000001111111000111111111011111111111111100011111000000011111000000011111000000011111000000011111000000011111000000011111000000011111000000011111000000011111000000011111000000011111000000011111000000011111000000011111000000001110", 0, 0.355),
        ("0", "000111111000001111111100011111111110011100001111111000000111111000001111111000001111111000011111111000111111111001111111111111100111111111000111111110000111111110000111111100000111111100000111011100001111011111111110001111111100000011111000", 2, 0.516),
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
    /// The big My DMZ card (demo, headline, button) rather than a row.
    var hero = false
    @EnvironmentObject private var store: HajinStore
    @State private var pick: PhotosPickerItem?
    @State private var photo: HajinPickedPhoto?
    @State private var showsIntro = false
    /// The picked photo, held until the intro sheet has gone
    @State private var pending: HajinPickedPhoto?
    @State private var captured: UIImage?
    /// A 3D Printer screen (no stash grid): read straight to the review
    @State private var textRead: HajinGridResult?
    @State private var reopenIntro = false
    @State private var sorting = false

    var body: some View {
        Button { showsIntro = true } label: {
            if hero { heroLabel } else { rowLabel }
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showsIntro, onDismiss: {
            if let pending { route(pending); self.pending = nil }
        }) {
            HajinStashScanIntro(pick: $pick, captured: $captured)
        }
        .onChange(of: captured) { image in
            guard let image else { return }
            pending = HajinPickedPhoto(image: image.normalisedUp())
            captured = nil
            showsIntro = false
        }
        .onChange(of: pick) { chosen in
            guard let chosen else { return }
            Task {
                if let data = try? await chosen.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    #if DEBUG
                    // Keep the last photo so a run on a device can be checked from the Mac
                    let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                    try? image.normalisedUp().jpegData(compressionQuality: 0.9)?.write(to: docs.appendingPathComponent("last_grid_photo.jpg"))
                    #endif
                    await MainActor.run { pending = HajinPickedPhoto(image: image.normalisedUp()); showsIntro = false }
                }
                await MainActor.run { pick = nil }
            }
        }
        .fullScreenCover(item: $photo, onDismiss: {
            if reopenIntro { reopenIntro = false; showsIntro = true }
        }) { photo in
            HajinStashGridFrameView(image: photo.image, onRetake: { reopenIntro = true })
        }
        .sheet(item: $textRead) { r in
            HajinStashScanReview(found: r.counts, cash: r.cash, level: r.level)
        }
        .overlay(alignment: .trailing) {
            if sorting { ProgressView().padding(.trailing, 14) }
        }
        #if DEBUG
        // SS_GRID_PHOTO=<file> opens that photo in the framing screen;
        // SS_GRID_INTRO=1 opens the intro sheet
        .onAppear {
            if ProcessInfo.processInfo.environment["SS_GRID_INTRO"] == "1" { showsIntro = true }
            if photo == nil, var path = ProcessInfo.processInfo.environment["SS_GRID_PHOTO"] {
                if !path.hasPrefix("/") { path = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(path).path }
                guard let image = UIImage(contentsOfFile: path) else { return }
                photo = HajinPickedPhoto(image: image.normalisedUp())
            }
        }
        #endif
    }

    /// The headline card: what it does, the little demo, and the button.
    private var heroLabel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("mw4.ui.hajin.scan_new".localized().uppercased())
                    .font(.system(size: 10, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(Color.black.opacity(0.85))
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Capsule().fill(Color.accentDMZ))
                Text("mw4.ui.hajin.scan_hero_kicker".localized())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.appInkMuted)
            }
            Text("mw4.ui.hajin.scan_hero_title".localized())
                .font(.hitmarker(22))
                .foregroundStyle(Color.appInk)
                .multilineTextAlignment(.leading)
            Text("mw4.ui.hajin.scan_hero_subtitle".localized())
                .font(.subheadline)
                .foregroundStyle(Color.appInkMuted)
                .multilineTextAlignment(.leading)
            HajinStashScanDemo()
                .frame(maxWidth: .infinity)
                .allowsHitTesting(false)
            Label("mw4.ui.hajin.scan_hero_button".localized(), systemImage: "camera.viewfinder")
                .font(.headline)
                .foregroundStyle(Color.black.opacity(0.85))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.accentDMZ))
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(LinearGradient(colors: [Color.accentDMZ.opacity(0.22), Color.appSurface], startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.accentDMZ.opacity(0.5), lineWidth: 1))
        )
    }

    private var rowLabel: some View {
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
}


@available(iOS 17.0, *)
extension HajinStashGridButton {
    /// A stash grid (its header says ITEMS / STASH) goes to the framing
    /// screen; anything else, like a 3D Printer recipe screen, is read for
    /// its have/need counts and the bank and goes straight to the review.
    fileprivate func route(_ picked: HajinPickedPhoto) {
        guard let cg = picked.image.cgImage else { return }
        let items = (store.guide?.items ?? []).filter { ["Resource", "Ingredient"].contains($0.kind) }
        sorting = true
        Task.detached(priority: .userInitiated) {
            let lines = HajinStashScanner.lines(in: cg)
            let isStash = lines.contains { let t = $0.text.uppercased(); return t.contains("ITEMS") || t.contains("STASH") }
            let counts = isStash ? [:] : HajinStashScanner.counts(in: lines, items: items)
            let cash = HajinStashScanner.bank(in: lines)
            let level = HajinStashScanner.level(in: lines)
            await MainActor.run {
                sorting = false
                if isStash || counts.isEmpty { photo = picked } else { textRead = HajinGridResult(counts: counts, unsure: [], cash: cash, level: level) }
            }
        }
    }
}

/// Whether a photo is good enough to read: sharp, lit, without glare, and
/// big enough. Thresholds from the user's real stash photos against
/// blurred and darkened copies of them.
enum HajinPhotoQuality: String {
    case blurry, dark, glare, small

    static func issues(_ cg: CGImage) -> [HajinPhotoQuality] {
        var out: [HajinPhotoQuality] = []
        if min(cg.width, cg.height) < 900 { out.append(.small) }
        // A greyscale copy, at most 800 px, middle of the photo only
        let scale = min(1, 800 / CGFloat(max(cg.width, cg.height)))
        let w = Int(CGFloat(cg.width) * scale), h = Int(CGFloat(cg.height) * scale)
        var px = [UInt8](repeating: 0, count: w * h)
        guard w > 10, h > 10, let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                                                  space: CGColorSpaceCreateDeviceGray(), bitmapInfo: 0) else { return out }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        let x0 = Int(Double(w) * 0.15), x1 = Int(Double(w) * 0.85), y0 = Int(Double(h) * 0.15), y1 = Int(Double(h) * 0.8)
        var sum = 0.0, sumSq = 0.0, n = 0.0, total = 0.0, bright = 0.0
        for y in max(1, y0)..<min(h - 1, y1) {
            for x in max(1, x0)..<min(w - 1, x1) {
                let c = Double(px[y * w + x])
                // Laplacian: how sharply each pixel differs from its neighbours
                let lap = Double(px[(y - 1) * w + x]) + Double(px[(y + 1) * w + x]) + Double(px[y * w + x - 1]) + Double(px[y * w + x + 1]) - 4 * c
                sum += lap; sumSq += lap * lap; n += 1
                total += c
                if c >= 245 { bright += 1 }
            }
        }
        guard n > 0 else { return out }
        let variance = sumSq / n - (sum / n) * (sum / n)
        if variance < 250 { out.append(.blurry) }
        if total / n < 45 { out.append(.dark) }
        if bright / n > 0.08 { out.append(.glare) }
        return out
    }

    var message: String { "mw4.ui.hajin.quality_\(rawValue)".localized() }
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
    /// Choose another photo: the caller reopens the photo picker after this closes.
    var onRetake: (() -> Void)? = nil
    @State private var quality: [HajinPhotoQuality] = []
    @EnvironmentObject private var store: HajinStore
    @Environment(\.dismiss) private var dismiss
    @State private var corners: [CGPoint] = [CGPoint(x: 0.15, y: 0.25), CGPoint(x: 0.85, y: 0.25), CGPoint(x: 0.85, y: 0.75), CGPoint(x: 0.15, y: 0.75)]
    @State private var reading = false
    @State private var finding = false
    /// Set once the player drags a handle, so a late guess doesn't move it back
    @State private var moved = false
    /// Rows measured from the photo for the current frame (nil until known)
    @State private var rowCount: Int?
    @State private var result: HajinGridResult?

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                if !quality.isEmpty {
                    // The photo looks poor: say why and offer another
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color(red: 0.96, green: 0.66, blue: 0.24))
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(quality, id: \.self) { issue in
                                Text(issue.message).font(.subheadline).foregroundStyle(Color.appInk)
                            }
                            if onRetake != nil {
                                Button("mw4.ui.hajin.quality_retake".localized()) { onRetake?(); dismiss() }
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Color.accentDMZ)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.appSurface))
                    .padding(.horizontal, 12)
                }
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
                                .gesture(DragGesture().onEnded { _ in remeasure() }.simultaneously(with: DragGesture().onChanged { g in
                                    moved = true
                                    corners[i] = CGPoint(x: min(max(g.location.x / fit.width, 0), 1), y: min(max(g.location.y / fit.height, 0), 1))
                                }))
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
                HajinStashScanReview(found: r.counts, unsure: r.unsure, cash: r.cash, level: r.level,
                                     sureness: r.sureness, stacks: r.stacks, onDone: { dismiss() })
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
                let issues = await Task.detached(priority: .userInitiated) { HajinPhotoQuality.issues(cg) }.value
                withAnimation(.snappy) { quality = issues }
                finding = true
                let guess = await Task.detached(priority: .userInitiated) { HajinStashGridFinder.guess(cg) }.value
                finding = false
                if let guess, !moved { withAnimation(.snappy) { corners = guess } }
                remeasure()
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
        let rows = rowCount ?? HajinStashGrid.rows(for: corners, size: image.size)
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

    /// Counts the rows for the current frame in the background.
    private func remeasure() {
        guard let cg = image.cgImage else { return }
        let frame = corners
        Task.detached(priority: .utility) {
            let n = HajinStashGrid.measureRows(cg, corners: frame)
            await MainActor.run { if frame == corners { rowCount = n } }
        }
    }

    private func read() {
        guard let cg = image.cgImage else { return }
        reading = true
        let frame = corners
        let resources = (store.guide?.items ?? []).filter { $0.kind == "Resource" }
        Task.detached(priority: .userInitiated) {
            let tiles = HajinStashGrid.read(cg, corners: frame)
            var totals = HajinStashGrid.totals(tiles)
            // The same photo's text: the resource totals beside the grid and
            // the bank balance at the top
            let lines = HajinStashScanner.lines(in: cg)
            for (id, n) in HajinStashScanner.counts(in: lines, items: resources) { totals.counts[id] = n }
            let cash = HajinStashScanner.bank(in: lines)
            let level = HajinStashScanner.level(in: lines)
            await MainActor.run {
                reading = false
                result = HajinGridResult(counts: totals.counts, unsure: totals.unsure, cash: cash, level: level,
                                         sureness: totals.sureness, stacks: totals.stacks)
            }
        }
    }
}

struct HajinGridResult: Identifiable {
    let id = UUID()
    let counts: [String: Int]
    let unsure: Set<String>
    var cash: Int? = nil
    var level: Int? = nil
    var sureness: [String: Float] = [:]
    var stacks: [String: Int] = [:]
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
        rects.minimumSize = 0.03
        rects.minimumAspectRatio = 0.7
        rects.maximumAspectRatio = 1.0
        rects.quadratureTolerance = 20
        rects.minimumConfidence = 0.3
        let text = VNRecognizeTextRequest()
        text.recognitionLevel = .accurate
        text.usesLanguageCorrection = false
        try? VNImageRequestHandler(cgImage: cg).perform([rects, text])
        // The header ("ALL ... 79/94 ITEMS") pins the grid's top and width;
        // walking down its frame lines finds the bottom. Works for any
        // stash, full or not. The tiles the rectangle finder sees are the
        // fallback for photos where the header can't be read.
        // Three ways in; keep the frame that lines up best with the tiles'
        // frame lines. A straight screenshot is solved exactly by the first.
        let candidates: [(String, [CGPoint])] = [
            ("straight", fromStraightLattice(cg, text.results ?? [])),
            ("header", fromHeader(cg, text.results ?? [])),
            ("tiles", fromTiles(cg, rects.results ?? [], text.results ?? [])),
        ].compactMap { name, q in q.map { (name, $0) } }
        let scored = candidates.map { ($0.0, $0.1, frameScore(cg, $0.1)) }
        HajinGridDebug.log("guess: " + scored.map { "\($0.0) \(String(format: "%.3f", $0.2))" }.joined(separator: ", "))
        return scored.max { $0.2 < $1.2 }?.1
    }

    /// For a straight-on screenshot (no perspective): the column lines and
    /// evenly spaced row lines found directly in the strip under the header,
    /// between "ALL" and "ITEMS". Tiles are square, so rows share the
    /// column spacing; rows are counted until the lines stop.
    static func fromStraightLattice(_ cg: CGImage, _ observations: [VNRecognizedTextObservation]) -> [CGPoint]? {
        let W = CGFloat(cg.width), H = CGFloat(cg.height)
        func px(_ v: CGPoint) -> CGPoint { CGPoint(x: v.x * W, y: (1 - v.y) * H) }
        let words = observations.compactMap { o -> (String, VNRecognizedTextObservation)? in
            guard let t = o.topCandidates(1).first?.string.uppercased() else { return nil }
            return (t.trimmingCharacters(in: .whitespaces), o)
        }
        guard let itemsWord = words.first(where: { $0.0.contains("ITEMS") })?.1,
              let allWord = words.filter({ $0.0 == "ALL" })
                .min(by: { abs(px($0.1.bottomLeft).y - px(itemsWord.bottomLeft).y) < abs(px($1.1.bottomLeft).y - px(itemsWord.bottomLeft).y) })?.1 else { return nil }
        let a = px(allWord.bottomLeft), b = px(itemsWord.bottomRight)
        // Straight only: the header must be level
        guard abs(a.y - b.y) < (b.x - a.x) * 0.02, b.x - a.x > W * 0.1 else { return nil }
        // Work on a copy about 1200 px wide
        let scale = min(1, 1200 / W)
        let pitch0 = (b.x - a.x) / CGFloat(HajinStashGrid.columns) * scale
        let x0 = max(0, Int((a.x * scale) - pitch0)), x1 = min(Int(W * scale) - 1, Int(b.x * scale + pitch0))
        let y0 = max(0, Int(a.y * scale)), y1 = Int(H * scale) - 1
        let w = x1 - x0, h = y1 - y0
        guard w > 20, h > 20 else { return nil }
        var buf = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        // draw the crop: shift so (x0, y0) lands at the origin (CG's origin is bottom left)
        let fullW = W * scale, fullH = H * scale
        ctx.draw(cg, in: CGRect(x: -CGFloat(x0), y: CGFloat(y0) - (fullH - CGFloat(h)), width: fullW, height: fullH))
        var (cols, rows) = HajinFrameLines.profiles(buf, w, h)
        func smooth(_ p: [Double], _ r: Int) -> [Double] {
            var acc = [0.0]; for v in p { acc.append(acc.last! + v) }
            return p.indices.map { i in let lo = max(0, i - r), hi = min(p.count - 1, i + r); return (acc[hi + 1] - acc[lo]) / Double(hi - lo + 1) }
        }
        cols = smooth(zip(cols, smooth(cols, 20)).map { max(0, $0 - $1) }, 2)
        rows = smooth(zip(rows, smooth(rows, 20)).map { max(0, $0 - $1) }, 2)
        // the 7 column lines
        var bestCol = (score: -1.0, x: 0.0, p: 0.0)
        for p in stride(from: Double(pitch0) * 0.9, through: Double(pitch0) * 1.1, by: 0.5) {
            for x in stride(from: Double(pitch0) * 0.6, through: Double(pitch0) * 1.4, by: 1) {
                guard Int(x + 6 * p) < w else { continue }
                var sc = 0.0
                for k in 0...HajinStashGrid.columns { sc += cols[Int(x + Double(k) * p)] }
                if sc > bestCol.score { bestCol = (sc, x, p) }
            }
        }
        guard bestCol.p > 0 else { return nil }
        let p = bestCol.p
        // the top row line just under the header, then rows while lines continue
        var bestTop = (score: -1.0, y: 0.0)
        for y in stride(from: p * 0.2, through: p * 1.2, by: 1) where Int(y) < h { if rows[Int(y)] > bestTop.score { bestTop = (rows[Int(y)], y) } }
        var strengths = [bestTop.score]
        var count = 0
        for j in 1...14 {
            let y = bestTop.y + Double(j) * p
            guard Int(y) + 3 < h else { break }
            let lo = max(0, Int(y) - 3), hi = min(h - 1, Int(y) + 3)
            let st = rows[lo...hi].max() ?? 0
            let ref = strengths.sorted()[strengths.count / 2]
            if j > 1 && st < ref * 0.35 { break }
            strengths.append(st); count = j
        }
        guard count >= 1 else { return nil }
        HajinGridDebug.log("guess: straight lattice pitch \(Int(p)) px, \(count) rows")
        let left = (CGFloat(x0) + CGFloat(bestCol.x)) / scale, right = (CGFloat(x0) + CGFloat(bestCol.x + 6 * p)) / scale
        let top = (CGFloat(y0) + CGFloat(bestTop.y)) / scale, bottom = (CGFloat(y0) + CGFloat(bestTop.y + Double(count) * p)) / scale
        return [CGPoint(x: left, y: top), CGPoint(x: right, y: top), CGPoint(x: right, y: bottom), CGPoint(x: left, y: bottom)]
            .map { CGPoint(x: min(max($0.x / W, 0), 1), y: min(max($0.y / H, 0), 1)) }
    }

    /// The frame from the tiles the rectangle detector finds (mostly empty
    /// ones), with the header words for the top when they're there.
    static func fromTiles(_ cg: CGImage, _ rectObservations: [VNRectangleObservation], _ textObservations: [VNRecognizedTextObservation]) -> [CGPoint]? {
        let W = CGFloat(cg.width), H = CGFloat(cg.height)
        func px(_ v: CGPoint) -> CGPoint { CGPoint(x: v.x * W, y: (1 - v.y) * H) }
        func mid(_ a: CGPoint, _ b: CGPoint) -> CGPoint { CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2) }

        // Tiles: rectangles of the common size that have a neighbour at a
        // tile's spacing (drops menu boxes and other strays)
        struct Q { let tl, tr, br, bl: CGPoint; var c: CGPoint { CGPoint(x: (tl.x + br.x) / 2, y: (tl.y + br.y) / 2) }; var size: CGFloat { (hypot(tr.x - tl.x, tr.y - tl.y) + hypot(bl.x - tl.x, bl.y - tl.y)) / 2 } }
        let all = rectObservations.map { Q(tl: px($0.topLeft), tr: px($0.topRight), br: px($0.bottomRight), bl: px($0.bottomLeft)) }
        guard !all.isEmpty else { HajinGridDebug.log("guess: no rectangles"); return nil }
        let median = all.map(\.size).sorted()[all.count / 2]
        let sized = all.filter { $0.size > median * 0.7 && $0.size < median * 1.4 }
        let tiles = sized.filter { q in sized.contains { o in
            let d = hypot(o.c.x - q.c.x, o.c.y - q.c.y); return d > median * 0.8 && d < median * 1.8 } }
        HajinGridDebug.log("guess: photo \(cg.width)x\(cg.height), \(all.count) rectangles, \(tiles.count) tiles, size \(Int(median))")
        guard tiles.count >= 3 else { HajinGridDebug.log("guess: too few tiles"); return nil }

        // Spacing along a row and down a column, from neighbouring tiles
        var across: [CGPoint] = [], down: [CGPoint] = []
        for q in tiles { for o in tiles {
            let d = CGPoint(x: o.c.x - q.c.x, y: o.c.y - q.c.y)
            let len = hypot(d.x, d.y)
            guard len > median * 0.8 && len < median * 1.8 else { continue }
            if d.x > 0 && abs(d.y) < len * 0.4 { across.append(d) }
            if d.y > 0 && abs(d.x) < len * 0.4 { down.append(d) }
        } }
        func medianVector(_ v: [CGPoint]) -> CGPoint? {
            guard !v.isEmpty else { return nil }
            return CGPoint(x: v.map(\.x).sorted()[v.count / 2], y: v.map(\.y).sorted()[v.count / 2])
        }
        let hx = medianVector(across) ?? CGPoint(x: median * 1.25, y: 0)
        let vy = medianVector(down) ?? CGPoint(x: -hx.y, y: hx.x)
        let pitch = hypot(hx.x, hx.y)

        // The bottom: the lowest row of tiles (measured down the columns)
        let vyLen = hypot(vy.x, vy.y)
        func depth(_ p: CGPoint) -> CGFloat { (p.x * vy.x + p.y * vy.y) / vyLen }
        let lowest = tiles.map { depth($0.c) }.max()!
        let bottomRow = tiles.filter { depth($0.c) > lowest - vyLen * 0.5 }
        let bottomPoint = bottomRow.map { mid($0.bl, $0.br) }.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x / CGFloat(bottomRow.count), y: $0.y + $1.y / CGFloat(bottomRow.count)) }

        // The header words: "ALL" starts over the grid's left edge, "ITEMS"
        // ends over its right edge, and the grid starts just under them
        let words = textObservations.compactMap { o -> (String, VNRecognizedTextObservation)? in
            guard let t = o.topCandidates(1).first?.string.uppercased() else { return nil }
            return (t, o)
        }.filter { px($0.1.bottomLeft).y < bottomPoint.y - pitch }
        let itemsWord = words.first { $0.0.contains("ITEMS") }?.1
        // The header's "ALL", not the side menu's: the one level with "ITEMS"
        let allWord = words.filter { $0.0.trimmingCharacters(in: .whitespaces) == "ALL" }
            .min { a, b in
                let y = itemsWord.map { px($0.bottomLeft).y } ?? 0
                return abs(px(a.1.bottomLeft).y - y) < abs(px(b.1.bottomLeft).y - y)
            }?.1
        // Header words only: the side menu has its own WEAPONS further down
        let itemsY = itemsWord.map { px($0.bottomLeft).y }
        let headerPts = words.filter { word in
            (word.0.contains("WEAPON") || word.0.contains("ITEMS")) && (itemsY.map { abs(px(word.1.bottomLeft).y - $0) < H * 0.03 } ?? true)
        }.flatMap { [px($0.1.bottomLeft), px($0.1.bottomRight)] }
        HajinGridDebug.log("guess: ALL \(allWord != nil), ITEMS \(itemsWord != nil), header points \(headerPts.count), across \(hx), down \(vy)")

        var topLeft: CGPoint, topRight: CGPoint
        if let allWord, let itemsWord, headerPts.count >= 2 {
            let mx = headerPts.map(\.x).reduce(0, +) / CGFloat(headerPts.count), my = headerPts.map(\.y).reduce(0, +) / CGFloat(headerPts.count)
            let num = headerPts.reduce(0) { $0 + ($1.x - mx) * ($1.y - my) }, den = headerPts.reduce(0) { $0 + ($1.x - mx) * ($1.x - mx) }
            let slope = den > 1 ? num / den : 0
            func baseline(_ x: CGFloat) -> CGFloat { my + slope * (x - mx) }
            let lx = px(allWord.bottomLeft).x, rx = px(itemsWord.bottomRight).x
            let gap = (rx - lx) / CGFloat(HajinStashGrid.columns) * 0.58
            topLeft = CGPoint(x: lx, y: baseline(lx) + gap)
            topRight = CGPoint(x: rx, y: baseline(rx) + gap)
        } else {
            // No header: the leftmost and rightmost tiles' columns, a few rows up
            let leftmost = tiles.min { $0.c.x < $1.c.x }!, rightmost = tiles.max { $0.c.x < $1.c.x }!
            let rows: CGFloat = 5
            topLeft = CGPoint(x: leftmost.bl.x - vy.x * rows, y: bottomPoint.y - vy.y * rows)
            topRight = CGPoint(x: rightmost.br.x - vy.x * rows, y: bottomPoint.y - vy.y * rows)
        }
        // Bottom corners: down each side (along the columns) to the bottom row
        func meet(_ p: CGPoint, _ d: CGPoint, _ q: CGPoint, _ e: CGPoint) -> CGPoint {
            let den = d.x * e.y - d.y * e.x
            guard abs(den) > 1e-6 else { return p }
            let t = ((q.x - p.x) * e.y - (q.y - p.y) * e.x) / den
            return CGPoint(x: p.x + d.x * t, y: p.y + d.y * t)
        }
        let bottomLeft = meet(topLeft, vy, bottomPoint, hx), bottomRight = meet(topRight, vy, bottomPoint, hx)
        let quad = [topLeft, topRight, bottomRight, bottomLeft]
        guard quad.allSatisfy({ $0.x > -W * 0.05 && $0.x < W * 1.05 && $0.y > -H * 0.05 && $0.y < H * 1.05 }),
              bottomLeft.y - topLeft.y > pitch, topRight.x - topLeft.x > pitch * 3 else {
            HajinGridDebug.log("guess: quad implausible \(quad)"); return nil }
        HajinGridDebug.log("guess: before refine \(quad)")
        let fractions = quad.map { CGPoint(x: min(max($0.x / W, 0), 1), y: min(max($0.y / H, 0), 1)) }
        let refined = refine(cg, fractions)
        HajinGridDebug.log("guess: refined \(refined)")
        return refined
    }

    /// The frame from the header alone: top corners under "ALL" and "ITEMS",
    /// sides square to the header line, and the bottom where the frame
    /// lines stop when walking down the grid a row at a time.
    static func fromHeader(_ cg: CGImage, _ observations: [VNRecognizedTextObservation]) -> [CGPoint]? {
        let W = CGFloat(cg.width), H = CGFloat(cg.height)
        func px(_ v: CGPoint) -> CGPoint { CGPoint(x: v.x * W, y: (1 - v.y) * H) }
        let words = observations.compactMap { o -> (String, VNRecognizedTextObservation)? in
            guard let t = o.topCandidates(1).first?.string.uppercased() else { return nil }
            return (t.trimmingCharacters(in: .whitespaces), o)
        }
        guard let itemsWord = words.first(where: { $0.0.contains("ITEMS") })?.1,
              let allWord = words.filter({ $0.0 == "ALL" })
                .min(by: { abs(px($0.1.bottomLeft).y - px(itemsWord.bottomLeft).y) < abs(px($1.1.bottomLeft).y - px(itemsWord.bottomLeft).y) })?.1,
              abs(px(allWord.bottomLeft).y - px(itemsWord.bottomLeft).y) < H * 0.06 else {
            HajinGridDebug.log("guess: no header words"); return nil }
        let a = px(allWord.bottomLeft), b = px(itemsWord.bottomRight)
        let across = CGPoint(x: b.x - a.x, y: b.y - a.y)
        let width = hypot(across.x, across.y)
        guard width > W * 0.2 else { return nil }
        let down = CGPoint(x: -across.y / width, y: across.x / width)
        let pitch = width / CGFloat(HajinStashGrid.columns)
        let tl = CGPoint(x: a.x + down.x * pitch * 0.58, y: a.y + down.y * pitch * 0.58)
        let tr = CGPoint(x: b.x + down.x * pitch * 0.58, y: b.y + down.y * pitch * 0.58)
        // Straighten from the top line down to the bottom of the photo
        let reach = min((H - tl.y) / max(down.y, 0.1), (H - tr.y) / max(down.y, 0.1)) * 0.98
        guard reach > pitch * 1.5 else { return nil }
        let quad = [tl, tr, CGPoint(x: tr.x + down.x * reach, y: tr.y + down.y * reach), CGPoint(x: tl.x + down.x * reach, y: tl.y + down.y * reach)]
        let scale: CGFloat = 240 / width
        let outH = reach * scale
        let fractions = quad.map { CGPoint(x: $0.x / W, y: $0.y / H) }
        guard let flat = HajinStashGrid.straighten(cg, corners: fractions, size: CGSize(width: 240, height: outH)) else { return nil }
        let w = flat.width, h = flat.height
        var buf = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(flat, in: CGRect(x: 0, y: 0, width: w, height: h))
        let row = HajinFrameLines.profiles(buf, w, h).rows
        func smooth(_ p: [Double], _ r: Int) -> [Double] {
            var acc = [0.0]; for v in p { acc.append(acc.last! + v) }
            return p.indices.map { i in let lo = max(0, i - r), hi = min(p.count - 1, i + r); return (acc[hi + 1] - acc[lo]) / Double(hi - lo + 1) }
        }
        let lines = smooth(zip(row, smooth(row, 20)).map { max(0, $0 - $1) }, 2)
        // Row spacing: the repeat of the lines, around a tile's width (40 px here)
        let mean = lines.reduce(0, +) / Double(h)
        var best = (score: -Double.infinity, lag: 40)
        for lag in 26...70 where lag < h / 2 {
            var sc = 0.0
            for y in 0..<(h - lag) { sc += (lines[y] - mean) * (lines[y + lag] - mean) }
            sc /= Double(h - lag)
            if sc > best.score { best = (sc, lag) }
        }
        // Walk down while there's a border line about a row further on
        func peak(near y: Double) -> Double {
            let lo = max(0, Int(y - Double(best.lag) * 0.2)), hi = min(h - 1, Int(y + Double(best.lag) * 0.2))
            return lo < hi ? (lines[lo...hi].max() ?? 0) : 0
        }
        var strengths: [Double] = []
        var rows = 0
        for k in 1...20 {
            let y = Double(k * best.lag)
            guard y < Double(h - 2) else { break }
            let p = peak(near: y)
            strengths.append(p)
            let ref = strengths.prefix(3).sorted()[strengths.prefix(3).count / 2]
            if k > 1 && p < ref * 0.35 { break }
            rows = k
        }
        HajinGridDebug.log("guess: from header, row every \(best.lag) px of 40, \(rows) rows")
        guard rows >= 1 else { return nil }
        let depth = CGFloat(rows * best.lag) / scale
        let bl = CGPoint(x: tl.x + down.x * depth, y: tl.y + down.y * depth), br = CGPoint(x: tr.x + down.x * depth, y: tr.y + down.y * depth)
        let start = [tl, tr, br, bl].map { CGPoint(x: min(max($0.x / W, 0), 1), y: min(max($0.y / H, 0), 1)) }
        HajinGridDebug.log("guess: from header start \([tl, tr, br, bl])")
        // The walk already counted the rows; re-measuring can lock onto a
        // two- or three-row repeat
        let refined = refine(cg, start, rows: rows)
        HajinGridDebug.log("guess: from header refined \(refined)")
        return refined
    }

    /// Nudges each corner (coordinate descent on a quarter-size copy) to
    /// where the straightened grid's frame lines fall exactly on its 7
    /// column and row borders.
    static func refine(_ cg: CGImage, _ start: [CGPoint], rows known: Int? = nil) -> [CGPoint] {
        let score = scorer(cg, rows: known ?? HajinStashGrid.measureRows(cg, corners: start))
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

    /// How well a frame lines up with the tiles' frame lines (higher is
    /// better), for choosing between two guesses.
    static func frameScore(_ cg: CGImage, _ q: [CGPoint]) -> Double {
        scorer(cg, rows: HajinStashGrid.measureRows(cg, corners: q))(q)
    }

    /// Scores frames on a quarter-size copy: straightened with the given
    /// rows, the mean frame-line strength at the 7 column and row borders.
    static func scorer(_ cg: CGImage, rows: Int) -> ([CGPoint]) -> Double {
        let scale: CGFloat = 0.25
        let small = CIImage(cgImage: cg).transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let size = CGSize(width: CGFloat(cg.width) * scale, height: CGFloat(cg.height) * scale)
        let ci = CIContext()
        return { q in
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
            let (col, row) = HajinFrameLines.profiles(px, w, h)
            // Frame lines sit just inside each border: look 3 px either side
            func at(_ p: [Double], _ c: Int) -> Double { p[max(0, c - 3)...min(p.count - 1, c + 3)].max() ?? 0 }
            var total = 0.0
            for k in 0...HajinStashGrid.columns { total += at(col, Int(CGFloat(k) * cell)) / Double(h) }
            for j in 0...rows { total += at(row, Int(CGFloat(j) * cell)) / Double(w) }
            return total / Double(HajinStashGrid.columns + rows + 2)
        }
    }
}
