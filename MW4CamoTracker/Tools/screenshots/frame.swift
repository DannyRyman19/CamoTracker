// frame.swift - composite raw simulator screenshots into App Store marketing
// shots: a Hitmarker headline over the logo's own amber nebula, with the screen
// floated on a rounded card.
//
//   swift Tools/screenshots/frame.swift <rawDir> <outDir> [lang]
//
// `lang` (en/de/es/fr/nl, default en) picks the headline set. Hitmarker is
// condensed but not infinitely so, and the translated lines run longer than
// the English, so each shot is measured and its pair scaled down together
// when either line would otherwise cross the margin.
//
// Expects <rawDir>/{multiplayer,warzone,dmz,stats}.png from an iPhone 17 Pro
// Max. Writes 1284x2778 PNGs (App Store 6.7"), exact pixels.
//
// The backdrop is generated here rather than loaded from Assets.xcassets: the
// shipped SplashBackground is square and would need cropping to a 1:2.16
// canvas, and regenerating from the same fBm keeps the marketing art at native
// resolution. Seeds match tools-mw4-logo.swift so it is visibly the same cloud.

import Foundation
import CoreGraphics
import CoreText
import ImageIO
import UniformTypeIdentifiers
import AppKit

/// App Store canvases. `iphone` is the 6.7" slot; `ipad` is the 12.9"
/// (3rd gen) slot Apple demands for a universal app. The iPad raw captures
/// come off a 13-inch simulator at 2064x2752 - these are composites, so the
/// capture is fitted onto the required canvas rather than having to match it.
let device = ProcessInfo.processInfo.environment["SS_DEVICE"] ?? "iphone"
let (W, H) = device == "ipad" ? (2048, 2732) : (1284, 2778)
let Wf = CGFloat(W), Hf = CGFloat(H)
/// Layout is tuned against the 6.7" canvas; everything scales off its width
/// so the iPad shot is the same design rather than the same absolute sizes.
let uiScale = Wf / 1284

let args = CommandLine.arguments
guard args.count == 3 || args.count == 4 else {
    fputs("usage: swift frame.swift <rawDir> <outDir> [lang]\n", stderr); exit(1)
}
let rawDir = args[1], outDir = args[2]
let lang = args.count == 4 ? args[3] : "en"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}
let appInk = rgb(0xEDEFEA)          // Theme.appInk
let accent = rgb(0xFFD000)          // the mark's own gold
let rule   = rgb(0x8B958D, 0.35)    // Theme.appInkMuted, card edge

let fontPath = "Resources/HitmarkerText-VF.ttf"
guard let dp = CGDataProvider(url: URL(fileURLWithPath: fontPath) as CFURL), let cgFont = CGFont(dp) else {
    fputs("cannot load \(fontPath) (run from the MW4CamoTracker dir)\n", stderr); exit(1)
}

func loadCG(_ path: String) -> CGImage? {
    guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(src, 0, nil)
}

// ─── value-noise fBm (same as tools-mw4-logo.swift) ────────────────────
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

let space = CGColorSpace(name: CGColorSpace.sRGB)!

/// The nebula, rendered once and reused for every shot.
let backdrop: CGImage = {
    let n1 = Noise(seed: 20260908), n2 = Noise(seed: 77123)
    var px = [UInt8](repeating: 0, count: W*H*4)
    for y in 0..<H {
        for x in 0..<W {
            // Both axes normalise by WIDTH, not by their own dimension. Using
            // y/H on a 1:2.16 canvas halves the vertical frequency and smears
            // the clouds into vertical streaks; dividing both by W keeps the
            // noise isotropic, so the billows are the same shape and scale as
            // the logo's.
            let fx = CGFloat(x) / CGFloat(W), fy = CGFloat(y) / CGFloat(W)
            let wx = n1.fbm(fx*3.0, fy*3.0) * 1.6
            let wy = n2.fbm(fx*3.0 + 5.2, fy*3.0 + 1.3) * 1.6
            var v = n1.fbm(fx*4.2 + wx, fy*4.2 + wy, octaves: 7)
            v = pow(max(0, min(1, (v - 0.30) / 0.44)), 1.30)
            let aspect = CGFloat(H) / CGFloat(W)
            let dx = fx - 0.5, dy = (fy / aspect) - 0.42
            let r = sqrt(dx*dx + dy*dy) / 0.72
            let vign = max(0, 1 - pow(r, 1.5))
            // Held darker than the logo's: a screenshot card and a headline
            // both sit on top, and the busier the cloud the worse they read.
            let t = max(0, min(1, v * (0.30 + 0.70*vign))) * 0.78
            var rr: CGFloat, gg: CGFloat, bb: CGFloat
            if t < 0.40 {
                let k = t/0.40
                (rr, gg, bb) = (0.030 + k*0.42, 0.014 + k*0.20, 0.004 + k*0.010)
            } else {
                let k = (t-0.40)/0.60
                (rr, gg, bb) = (0.450 + k*0.550, 0.214 + k*0.606, 0.014 + k*0.056)
            }
            let grain = (n2.value(CGFloat(x)*0.7, CGFloat(y)*0.7) - 0.5) * 0.05
            rr += grain; gg += grain; bb += grain
            let i = (y*W + x)*4
            px[i]   = UInt8(max(0, min(255, rr*255)))
            px[i+1] = UInt8(max(0, min(255, gg*255)))
            px[i+2] = UInt8(max(0, min(255, bb*255)))
            px[i+3] = 255
        }
    }
    return px.withUnsafeMutableBytes { raw in
        CGContext(data: raw.baseAddress, width: W, height: H, bitsPerComponent: 8, bytesPerRow: W*4,
                  space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!.makeImage()!
    }
}()

struct Shot {
    let name: String
    var cropTop: CGFloat = 0     // fraction trimmed off the top of the raw shot
    var cropBot: CGFloat = 0     // fraction trimmed off the bottom
}
let shots = [
    Shot(name: "multiplayer"),
    Shot(name: "stats"),
    Shot(name: "warzone"),
    Shot(name: "dmz"),
    Shot(name: "category"),
    Shot(name: "weapon"),
]

// Two lines per shot, upper case, kept as short as each language allows so
// the type stays at full size. Same order as `shots`.
let headlines: [String: [[String]]] = [
    "en": [["EVERY WEAPON", "EVERY CAMO"],
           ["WATCH IT", "ALL ADD UP"],
           ["ONE APP", "ALL THREE MODES"],
           ["DMZ OBJECTIVES", "COVERED TOO"],
           ["BROWSE BY", "WEAPON CLASS"],
           ["EVERY CHALLENGE", "PER GUN"]],
    "de": [["JEDE WAFFE", "JEDE TARNUNG"],
           ["SIEH ZU", "WIE ES AUFGEHT"],
           ["EINE APP", "ALLE DREI MODI"],
           ["DMZ-ZIELE", "AUCH DABEI"],
           ["NACH KLASSE", "STÖBERN"],
           ["JEDE AUFGABE", "PRO WAFFE"]],
    "es": [["CADA ARMA", "CADA CAMO"],
           ["MIRA CÓMO", "TODO SUMA"],
           ["UNA APP", "LOS TRES MODOS"],
           ["OBJETIVOS DMZ", "TAMBIÉN"],
           ["EXPLORA POR", "CLASE DE ARMA"],
           ["CADA RETO", "POR ARMA"]],
    "fr": [["CHAQUE ARME", "CHAQUE CAMO"],
           ["REGARDEZ", "TOUT MONTER"],
           ["UNE APP", "LES TROIS MODES"],
           ["OBJECTIFS DMZ", "AUSSI"],
           ["PARCOURIR PAR", "CLASSE D'ARME"],
           ["CHAQUE DÉFI", "PAR ARME"]],
    "nl": [["ELK WAPEN", "ELKE CAMO"],
           ["ZIE HET", "ALLEMAAL OPTELLEN"],
           ["ÉÉN APP", "ALLE DRIE MODI"],
           ["DMZ-DOELEN", "OOK ERBIJ"],
           ["BLADER PER", "WAPENKLASSE"],
           ["ELKE UITDAGING", "PER WAPEN"]],
]
guard let langHeadlines = headlines[lang], langHeadlines.count == shots.count else {
    fputs("no headline set for \(lang) (have: \(headlines.keys.sorted().joined(separator: ", ")))\n", stderr)
    exit(1)
}

func makeFont(_ size: CGFloat) -> CTFont {
    let base = CTFontCreateWithGraphicsFont(cgFont, size, nil, nil)
    let desc = CTFontDescriptorCreateWithAttributes([
        kCTFontVariationAttribute: ["Weight" as CFString: 700] as CFDictionary
    ] as CFDictionary)
    return CTFontCreateCopyWithAttributes(base, size, nil, desc)
}

/// Every character has to exist in Hitmarker: CoreText would otherwise
/// silently substitute another face for the accented caps and one word would
/// come out in the wrong type. Cheaper to catch here than on the upload.
func checkGlyphs() {
    let probe = makeFont(96)
    for (i, lines) in langHeadlines.enumerated() {
        for line in lines {
            for ch in line.unicodeScalars where ch != " " {
                var chars = Array(String(ch).utf16)
                var glyphs = [CGGlyph](repeating: 0, count: chars.count)
                let ok = CTFontGetGlyphsForCharacters(probe, &chars, &glyphs, chars.count)
                if !ok || glyphs.contains(0) {
                    fputs("Hitmarker has no glyph for '\(ch)' in \(shots[i].name) (\(lang))\n", stderr)
                    exit(1)
                }
            }
        }
    }
}
checkGlyphs()

func render(_ shot: Shot, _ headline: [String]) {
    guard let rawFull = loadCG("\(rawDir)/\(shot.name).png") else {
        fputs("missing \(shot.name).png\n", stderr); return
    }
    guard let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0,
                              space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }

    ctx.draw(backdrop, in: CGRect(x: 0, y: 0, width: Wf, height: Hf))

    // Headline: Hitmarker at 700, centred, with the second line in gold so the
    // pair reads as one lockup rather than two equal-weight lines.
    // Sized as a pair so both lines keep the same type size, shrunk together
    // only as far as the longest needs to clear the margin.
    let baseSize: CGFloat = 96 * uiScale
    let maxTextW = Wf - 2 * 72 * uiScale
    let probe = makeFont(baseSize)
    let widest = headline.map { line -> CGFloat in
        let a = NSAttributedString(string: line, attributes: [.font: probe, .kern: 1.5])
        return CTLineGetBoundsWithOptions(CTLineCreateWithAttributedString(a), .useOpticalBounds).width
    }.max() ?? 0
    let scale = widest > maxTextW ? maxTextW / widest : 1
    let font = makeFont(baseSize * scale)
    let lineH: CGFloat = 108 * uiScale * scale
    var y = Hf - 210 * uiScale
    for (index, line) in headline.enumerated() {
        let attr = NSAttributedString(string: line, attributes: [
            .font: font,
            .foregroundColor: index == 0 ? appInk : accent,
            .kern: 1.5,
        ])
        let ctLine = CTLineCreateWithAttributedString(attr)
        let bounds = CTLineGetBoundsWithOptions(ctLine, .useOpticalBounds)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -5 * uiScale), blur: 16 * uiScale, color: rgb(0x000000, 0.6))
        ctx.textPosition = CGPoint(x: (Wf - bounds.width) / 2 - bounds.minX, y: y)
        CTLineDraw(ctLine, ctx)
        ctx.restoreGState()
        y -= lineH
    }
    let headlineBottom = y + lineH - 34 * uiScale

    var src = rawFull
    var srcW = CGFloat(rawFull.width), srcH = CGFloat(rawFull.height)
    let cutTop = Int(srcH * shot.cropTop)
    let cutBot = Int(srcH * shot.cropBot)
    if cutTop > 0 || cutBot > 0 {
        let keptH = rawFull.height - cutTop - cutBot
        if let c = rawFull.cropping(to: CGRect(x: 0, y: cutTop, width: rawFull.width, height: keptH)) {
            src = c; srcH = CGFloat(keptH); srcW = CGFloat(c.width)
        }
    }
    // Fit the capture inside the box under the headline, constrained by both
    // width and height. The 6.7" capture is tall and narrow so width always
    // binds; an iPad capture is nearly 4:3 and would run off the bottom if
    // width were the only constraint.
    let boxTop = headlineBottom - 84 * uiScale
    let boxBottom = 96 * uiScale
    let maxCardW = 1040 * uiScale
    let maxCardH = boxTop - boxBottom
    let fit = min(maxCardW / srcW, maxCardH / srcH)
    let cardW = srcW * fit
    let cardH = srcH * fit
    let cardX = (Wf - cardW) / 2
    let cardY = boxTop - cardH
    let cardRect = CGRect(x: cardX, y: cardY, width: cardW, height: cardH)
    let corner = 52 * uiScale
    let clip = CGPath(roundedRect: cardRect, cornerWidth: corner, cornerHeight: corner, transform: nil)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -22 * uiScale), blur: 55 * uiScale, color: rgb(0x000000, 0.6))
    ctx.addPath(clip); ctx.setFillColor(rgb(0x000000)); ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(clip); ctx.clip()
    ctx.draw(src, in: cardRect)
    ctx.restoreGState()

    ctx.addPath(clip); ctx.setStrokeColor(rule); ctx.setLineWidth(2); ctx.strokePath()

    guard let out = ctx.makeImage() else { return }
    let url = URL(fileURLWithPath: "\(outDir)/\(shot.name).png") as CFURL
    let dest = CGImageDestinationCreateWithURL(url, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, out, nil)
    CGImageDestinationFinalize(dest)
    print("wrote \(outDir)/\(shot.name).png  \(out.width)x\(out.height)")
}

for (i, s) in shots.enumerated() { render(s, langHeadlines[i]) }
