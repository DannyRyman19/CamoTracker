import Foundation
import CoreGraphics
import CoreText
import ImageIO
import UniformTypeIdentifiers

// ─── SVG path parsing (M/L/H/V/C/S/Z, absolute + relative) ─────────────
func parsePath(_ d: String) -> CGPath {
    let p = CGMutablePath()
    var nums: [CGFloat] = [], cmds: [(Character, [CGFloat])] = []
    var cur: Character = " "
    var buf = ""
    func flushNum() { if !buf.isEmpty, let v = Double(buf) { nums.append(CGFloat(v)) }; buf = "" }
    func flushCmd() { if cur != " " { cmds.append((cur, nums)) }; nums = [] }
    for ch in d {
        if ch.isLetter {
            flushNum(); flushCmd(); cur = ch
        } else if ch == "-" && !buf.isEmpty && !buf.hasSuffix("e") && !buf.hasSuffix("E") {
            flushNum(); buf = "-"
        } else if ch == "," || ch == " " || ch == "\n" || ch == "\t" {
            flushNum()
        } else if ch == "." && buf.contains(".") {
            flushNum(); buf = "."
        } else { buf.append(ch) }
    }
    flushNum(); flushCmd()

    var pt = CGPoint.zero, start = CGPoint.zero, lastC = CGPoint.zero
    var prevCmd: Character = " "
    for (c, a) in cmds {
        let rel = c.isLowercase
        let C = Character(c.uppercased())
        var i = 0
        func nx() -> CGFloat { let v = a[i]; i += 1; return v }
        repeat {
            switch C {
            case "M":
                var x = nx(), y = nx()
                if rel { x += pt.x; y += pt.y }
                pt = CGPoint(x: x, y: y); start = pt; p.move(to: pt)
            case "L":
                var x = nx(), y = nx()
                if rel { x += pt.x; y += pt.y }
                pt = CGPoint(x: x, y: y); p.addLine(to: pt)
            case "H":
                var x = nx(); if rel { x += pt.x }
                pt = CGPoint(x: x, y: pt.y); p.addLine(to: pt)
            case "V":
                var y = nx(); if rel { y += pt.y }
                pt = CGPoint(x: pt.x, y: y); p.addLine(to: pt)
            case "C":
                var x1 = nx(), y1 = nx(), x2 = nx(), y2 = nx(), x = nx(), y = nx()
                if rel { x1 += pt.x; y1 += pt.y; x2 += pt.x; y2 += pt.y; x += pt.x; y += pt.y }
                p.addCurve(to: CGPoint(x: x, y: y), control1: CGPoint(x: x1, y: y1), control2: CGPoint(x: x2, y: y2))
                lastC = CGPoint(x: x2, y: y2); pt = CGPoint(x: x, y: y)
            case "S":
                var x2 = nx(), y2 = nx(), x = nx(), y = nx()
                if rel { x2 += pt.x; y2 += pt.y; x += pt.x; y += pt.y }
                let refl = (prevCmd == "C" || prevCmd == "S")
                    ? CGPoint(x: 2*pt.x - lastC.x, y: 2*pt.y - lastC.y) : pt
                p.addCurve(to: CGPoint(x: x, y: y), control1: refl, control2: CGPoint(x: x2, y: y2))
                lastC = CGPoint(x: x2, y: y2); pt = CGPoint(x: x, y: y)
            case "Z":
                p.closeSubpath(); pt = start
            default: break
            }
            prevCmd = C
            if C == "Z" { break }
        } while i < a.count
    }
    return p
}

// ─── value-noise fBm ───────────────────────────────────────────────────
struct Noise {
    var perm = [Int](repeating: 0, count: 512)
    init(seed: UInt64) {
        var s = seed &* 6364136223846793005 &+ 1442695040888963407
        var t = Array(0..<256)
        for i in stride(from: 255, to: 0, by: -1) {
            s = s &* 6364136223846793005 &+ 1442695040888963407
            let j = Int((s >> 33) % UInt64(i + 1)); t.swapAt(i, j)
        }
        for i in 0..<512 { perm[i] = t[i & 255] }
    }
    func grad(_ x: Int, _ y: Int) -> CGFloat { CGFloat(perm[(perm[x & 255] + y) & 255]) / 255.0 }
    func value(_ x: CGFloat, _ y: CGFloat) -> CGFloat {
        let xi = Int(floor(x)), yi = Int(floor(y))
        let xf = x - floor(x), yf = y - floor(y)
        let u = xf*xf*(3 - 2*xf), v = yf*yf*(3 - 2*yf)
        let a = grad(xi, yi), b = grad(xi+1, yi), c = grad(xi, yi+1), d = grad(xi+1, yi+1)
        return (a*(1-u) + b*u)*(1-v) + (c*(1-u) + d*u)*v
    }
    func fbm(_ x: CGFloat, _ y: CGFloat, octaves: Int = 6) -> CGFloat {
        var f: CGFloat = 0, amp: CGFloat = 0.5, fr: CGFloat = 1, norm: CGFloat = 0
        for _ in 0..<octaves { f += amp * value(x*fr, y*fr); norm += amp; amp *= 0.5; fr *= 2 }
        return f / norm
    }
}

// ─── config ────────────────────────────────────────────────────────────
let W = 1196, H = 1200
// usage: swift tools-mw4-icon.swift <stencil font> <wide font, e.g. SFNS.ttf> <out.png>
let fontPath = CommandLine.arguments[1]
let wideFontPath = CommandLine.arguments[2]
let outPath = CommandLine.arguments[3]
// --transparent: no nebula, for the splash foreground that sits over its own background
let transparent = CommandLine.arguments.contains("--transparent")
// --no-four: leave the 4 out (tools-mw4-brush4.py paints it) and print its box
let hideFour = CommandLine.arguments.contains("--no-four")

let accent = (r: CGFloat(1.0), g: CGFloat(0.816), b: CGFloat(0.0))   // #ffd000

let cs = CGColorSpaceCreateDeviceRGB()
let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0,
                    space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

// ─── background: amber nebula ──────────────────────────────────────────
let n1 = Noise(seed: 20260908), n2 = Noise(seed: 77123)
var px = [UInt8](repeating: 0, count: W*H*4)
for y in 0..<H {
    for x in 0..<W {
        let fx = CGFloat(x) / CGFloat(W), fy = CGFloat(y) / CGFloat(H)
        // warped fBm for a smoky look
        let wx = n1.fbm(fx*3.0, fy*3.0) * 1.6
        let wy = n2.fbm(fx*3.0 + 5.2, fy*3.0 + 1.3) * 1.6
        var v = n1.fbm(fx*4.2 + wx, fy*4.2 + wy, octaves: 7)
        v = pow(max(0, min(1, (v - 0.30) / 0.44)), 1.30)
        // radial falloff — brighter core, dark corners
        let dx = fx - 0.5, dy = fy - 0.48
        let r = sqrt(dx*dx + dy*dy) / 0.72
        let vign = max(0, 1 - pow(r, 1.5))
        let t = max(0, min(1, v * (0.35 + 0.85*vign)))
        // ramp: near-black brown → deep amber → hot gold
        func ramp(_ t: CGFloat) -> (CGFloat, CGFloat, CGFloat) {
            if t < 0.40 {
                let k = t/0.40
                return (0.030 + k*0.42, 0.014 + k*0.20, 0.004 + k*0.010)
            } else {
                let k = (t-0.40)/0.60
                return (0.450 + k*0.550, 0.214 + k*0.606, 0.014 + k*0.056)
            }
        }
        var (rr, gg, bb) = ramp(t)
        let grain = (n2.value(CGFloat(x)*0.7, CGFloat(y)*0.7) - 0.5) * 0.05
        rr += grain; gg += grain; bb += grain
        let i = (y*W + x)*4
        px[i]   = UInt8(max(0, min(255, rr*255)))
        px[i+1] = UInt8(max(0, min(255, gg*255)))
        px[i+2] = UInt8(max(0, min(255, bb*255)))
        px[i+3] = 255
    }
}
if !transparent { px.withUnsafeMutableBytes { raw in
    let c = CGContext(data: raw.baseAddress, width: W, height: H, bitsPerComponent: 8,
                      bytesPerRow: W*4, space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(c.makeImage()!, in: CGRect(x: 0, y: 0, width: W, height: H))
} }

// ─── distress mask: speckles that eat into the white ───────────────────
let dn = Noise(seed: 4242)
func distressAlpha(_ x: Int, _ y: Int) -> CGFloat {
    let a = dn.fbm(CGFloat(x)*0.045, CGFloat(y)*0.045, octaves: 4)
    let b = dn.value(CGFloat(x)*0.34, CGFloat(y)*0.34)
    let s = a*0.55 + b*0.45
    return s < 0.30 ? 0.55 : (s < 0.38 ? 0.55 + (s - 0.30)/0.08*0.45 : 1.0)
}

func drawDistressedWhite(_ body: (CGContext) -> Void) {
    let m = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0,
                      space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    m.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    body(m)
    guard let img = m.makeImage(), let dp = img.dataProvider, let raw = dp.data,
          let base = CFDataGetBytePtr(raw) else { return }
    let bpr = img.bytesPerRow
    var out = [UInt8](repeating: 0, count: W*H*4)
    for y in 0..<H { for x in 0..<W {
        let si = y*bpr + x*4, di = (y*W + x)*4
        let a = CGFloat(base[si+3])/255.0
        if a <= 0.003 { continue }
        let d = distressAlpha(x, y)
        let fa = a * (0.88 + 0.12*d)
        let tint: CGFloat = 0.84 + 0.10*d
        out[di]   = UInt8(255*tint*fa); out[di+1] = UInt8(255*tint*fa)
        out[di+2] = UInt8(255*tint*fa); out[di+3] = UInt8(255*fa)
    }}
    out.withUnsafeMutableBytes { rawb in
        let c = CGContext(data: rawb.baseAddress, width: W, height: H, bitsPerComponent: 8,
                          bytesPerRow: W*4, space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 18,
                      color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.55))
        ctx.draw(c.makeImage()!, in: CGRect(x: 0, y: 0, width: W, height: H))
        ctx.restoreGState()
    }
}

// ─── text ──────────────────────────────────────────────────────────────
let fdata = CGDataProvider(url: URL(fileURLWithPath: fontPath) as CFURL)!
let cgFont = CGFont(fdata)!
var variation: [CFString: Any] = ["Weight" as CFString: 700]
let desc = CTFontDescriptorCreateWithAttributes([
    kCTFontVariationAttribute: variation as CFDictionary
] as CFDictionary)
func makeFont(_ size: CGFloat) -> CTFont {
    let base = CTFontCreateWithGraphicsFont(cgFont, size, nil, nil)
    return CTFontCreateCopyWithAttributes(base, size, nil, desc)
}

/// Lays out `s` fitted to `targetW`, centred, with its cap-height baseline placed so
/// the visual block is centred on `centreY` (top-down coords).
func drawText(_ s: String, targetW: CGFloat, centreY: CGFloat, tracking: CGFloat, into c: CGContext) {
    let probe: CGFloat = 200
    let f = makeFont(probe)
    var glyphs = [CGGlyph](repeating: 0, count: s.count)
    var chars = Array(s.utf16)
    CTFontGetGlyphsForCharacters(f, &chars, &glyphs, chars.count)
    var adv = [CGSize](repeating: .zero, count: glyphs.count)
    CTFontGetAdvancesForGlyphs(f, .horizontal, glyphs, &adv, glyphs.count)
    let rawW = adv.reduce(0) { $0 + $1.width } + tracking*probe/1000*CGFloat(glyphs.count - 1)
    let scale = targetW / rawW
    let size = probe * scale
    let ff = makeFont(size)
    var g2 = [CGGlyph](repeating: 0, count: s.count)
    CTFontGetGlyphsForCharacters(ff, &chars, &g2, chars.count)
    var a2 = [CGSize](repeating: .zero, count: g2.count)
    CTFontGetAdvancesForGlyphs(ff, .horizontal, g2, &a2, g2.count)
    let tr = tracking*size/1000
    let total = a2.reduce(0) { $0 + $1.width } + tr*CGFloat(g2.count - 1)
    let capH = CTFontGetCapHeight(ff)
    var x = (CGFloat(W) - total)/2
    let baseline = CGFloat(H) - centreY - capH/2
    var pos = [CGPoint]()
    for i in 0..<g2.count { pos.append(CGPoint(x: x, y: baseline)); x += a2[i].width + tr }
    // Hitmarker's variable axis tops out at 700, so the extra heft comes from
    // stroking the glyph outlines on top of the fill rather than a heavier cut.
    c.setLineWidth(size * 0.045)
    c.setLineJoin(.round)
    c.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    c.setTextDrawingMode(.fillStroke)
    CTFontDrawGlyphs(ff, g2, pos, g2.count, c)
    c.setTextDrawingMode(.fill)
}

// ─── layout ────────────────────────────────────────────────────────────
drawDistressedWhite { c in drawText("CAMO",    targetW: 700, centreY: 262, tracking: 10, into: c) }
drawDistressedWhite { c in drawText("TRACKER", targetW: 880, centreY: 942, tracking: 10, into: c) }

// "MW4" is typed, not the game's logo art: Apple rejected the SVG lockup (the
// MW glyphs + brushstroke 4) as another developer's brand. Same approach as the
// BO6/BO7 icons: a heavy wide face, white "MW", accent "4".
let wideDesc = CTFontDescriptorCreateWithAttributes([
    kCTFontVariationAttribute: ["Weight" as CFString: 1000, "Width" as CFString: 150] as CFDictionary
] as CFDictionary)
let wideFont = CGFont(CGDataProvider(url: URL(fileURLWithPath: wideFontPath) as CFURL)!)!
func wide(_ size: CGFloat) -> CTFont {
    CTFontCreateCopyWithAttributes(CTFontCreateWithGraphicsFont(wideFont, size, nil, nil), size, nil, wideDesc)
}

func drawLockup(targetW: CGFloat, centreY: CGFloat, gap: CGFloat) {
    let parts: [(String, CGColor)] = [("MW", white), ("4", gold)]
    /// Ink extent of `s` set on one line: (left bearing, ink width).
    func ink(_ f: CTFont, _ s: String) -> (CGFloat, CGFloat) {
        var chars = Array(s.utf16), g = [CGGlyph](repeating: 0, count: chars.count)
        CTFontGetGlyphsForCharacters(f, &chars, &g, chars.count)
        var adv = [CGSize](repeating: .zero, count: g.count), r = [CGRect](repeating: .zero, count: g.count)
        CTFontGetAdvancesForGlyphs(f, .horizontal, g, &adv, g.count)
        CTFontGetBoundingRectsForGlyphs(f, .horizontal, g, &r, g.count)
        let lastX = adv.dropLast().reduce(0) { $0 + $1.width }
        return (r[0].minX, lastX + r[g.count - 1].maxX - r[0].minX)
    }
    func width(_ f: CTFont, _ s: String) -> CGFloat { ink(f, s).1 }
    let probe = wide(200)
    let rawW = parts.reduce(0) { $0 + width(probe, $1.0) } + gap
    let f = wide(200 * targetW / rawW)
    let capH = CTFontGetCapHeight(f)
    let baseline = CGFloat(H) - centreY - capH/2
    var x = (CGFloat(W) - targetW)/2
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -7), blur: 20,
                  color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.6))
    for (s, col) in parts {
        var chars = Array(s.utf16), g = [CGGlyph](repeating: 0, count: chars.count)
        CTFontGetGlyphsForCharacters(f, &chars, &g, chars.count)
        var adv = [CGSize](repeating: .zero, count: g.count)
        CTFontGetAdvancesForGlyphs(f, .horizontal, g, &adv, g.count)
        let (left, inkW) = ink(f, s)
        var pos = [CGPoint](), px = x - left
        for a in adv { pos.append(CGPoint(x: px, y: baseline)); px += a.width }
        if s == "4" && hideFour {
            // The brush-painted 4 is composited afterwards; report where it goes.
            print("four: \(x) \(CGFloat(H) - baseline - capH) \(inkW) \(capH)")
        } else {
            ctx.setFillColor(col)
            CTFontDrawGlyphs(f, g, pos, g.count, ctx)
        }
        x += inkW + gap
    }
    ctx.restoreGState()
}

let white = CGColor(red: 1, green: 1, blue: 1, alpha: 1)
let gold  = CGColor(red: accent.r, green: accent.g, blue: accent.b, alpha: 1)
drawLockup(targetW: 980, centreY: 600, gap: 34)

let out = URL(fileURLWithPath: outPath)
let dest = CGImageDestinationCreateWithURL(out as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
CGImageDestinationFinalize(dest)
print("wrote \(outPath)")
