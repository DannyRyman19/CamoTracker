// store_assets.swift - the two App Store listing images that are not
// screenshots: the search-result tile and the product page header.
//
//   swift Tools/screenshots/store_assets.swift tile <rawDir> <out.png> [lang]
//   swift Tools/screenshots/store_assets.swift header <out.png>
//
// `tile` is the 3:2 creative that replaces the screenshots in search results,
// one per language: 2880x1920 (Apple accepts 1920x1280 up to 3840x2560). It
// uses the iPhone captures make.sh already takes (multiplayer.png and
// weapon.png in build/screenshots-raw/iphone/<lang>/). Built to be read at
// search-result size, roughly a phone's width: a huge headline on the left,
// two screens on the right.
//
// `header` is the 21:9 product page header: 3840x1646. The nebula and the
// app's own lockup, centred. No words beyond the lockup, so one image serves
// every language, and everything that matters sits in the middle third
// because the sides are cropped on narrower screens.
//
// Same nebula, type and colours as frame.swift and the icon. No game name or
// game logo art anywhere: App Review rejected both on the icon.
//
// Run from the MW4CamoTracker directory.

import Foundation
import CoreGraphics
import CoreText
import ImageIO
import UniformTypeIdentifiers
import AppKit

let args = CommandLine.arguments
func usage() -> Never {
    fputs("usage: swift store_assets.swift tile <rawDir> <out.png> [lang]\n       swift store_assets.swift header <out.png>\n", stderr); exit(1)
}
guard args.count >= 3 else { usage() }
let mode = args[1]
guard (mode == "tile" && (4...5).contains(args.count)) || (mode == "header" && args.count == 3) else { usage() }

let (W, H) = mode == "tile" ? (2880, 1920) : (3840, 1646)
let Wf = CGFloat(W), Hf = CGFloat(H)

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}
let appInk = rgb(0xEDEFEA)          // Theme.appInk
let accent = rgb(0xFFD000)          // the mark's own gold
let bezel  = rgb(0x0A0C0B)

func loadCG(_ path: String) -> CGImage? {
    guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(src, 0, nil)
}

// ─── value-noise fBm (same as frame.swift and the icon) ────────────────
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

/// The nebula at half size (it is soft cloud, and a script renders pixels
/// slowly), drawn up to the canvas. `glowX` is where the bright heart sits
/// across the width, `gain` how bright the whole thing runs.
func nebula(glowX: CGFloat, gain: CGFloat) -> CGImage {
    let w = W / 2, h = H / 2
    let n1 = Noise(seed: 20260908), n2 = Noise(seed: 77123)
    var px = [UInt8](repeating: 0, count: w*h*4)
    let aspect = CGFloat(h) / CGFloat(w)
    for y in 0..<h {
        for x in 0..<w {
            // Both axes normalise by HEIGHT here: these canvases are wide, and
            // dividing by width would stretch the billows sideways.
            let fx = CGFloat(x) / CGFloat(h), fy = CGFloat(y) / CGFloat(h)
            let wx = n1.fbm(fx*3.0, fy*3.0) * 1.6
            let wy = n2.fbm(fx*3.0 + 5.2, fy*3.0 + 1.3) * 1.6
            var v = n1.fbm(fx*4.2 + wx, fy*4.2 + wy, octaves: 7)
            v = pow(max(0, min(1, (v - 0.30) / 0.44)), 1.30)
            let dx = (CGFloat(x) / CGFloat(w) - glowX), dy = (CGFloat(y) / CGFloat(h) - 0.5) * aspect
            let r = sqrt(dx*dx + dy*dy) / 0.62
            let vign = max(0, 1 - pow(r, 1.5))
            let t = max(0, min(1, v * (0.30 + 0.70*vign))) * gain
            var rr: CGFloat, gg: CGFloat, bb: CGFloat
            if t < 0.40 {
                let k = t/0.40
                (rr, gg, bb) = (0.030 + k*0.42, 0.014 + k*0.20, 0.004 + k*0.010)
            } else {
                let k = (t-0.40)/0.60
                (rr, gg, bb) = (0.450 + k*0.550, 0.214 + k*0.606, 0.014 + k*0.056)
            }
            let i = (y*w + x)*4
            px[i]   = UInt8(max(0, min(255, rr*255)))
            px[i+1] = UInt8(max(0, min(255, gg*255)))
            px[i+2] = UInt8(max(0, min(255, bb*255)))
            px[i+3] = 255
        }
    }
    return px.withUnsafeMutableBytes { raw in
        CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w*4,
                  space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!.makeImage()!
    }
}

guard let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0,
                          space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { exit(1) }
ctx.interpolationQuality = .high

func write(_ path: String) {
    guard let out = ctx.makeImage() else { exit(1) }
    try? FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
    let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, out, nil)
    CGImageDestinationFinalize(dest)
    print("wrote \(path)  \(out.width)x\(out.height)")
}

// ─── header ────────────────────────────────────────────────────────────
if mode == "header" {
    guard let lockup = loadCG("Resources/Assets.xcassets/SplashForeground.imageset/splash-fg.png") else {
        fputs("needs Resources/Assets.xcassets/SplashForeground.imageset/splash-fg.png (run from the MW4CamoTracker dir)\n", stderr); exit(1)
    }
    ctx.draw(nebula(glowX: 0.5, gain: 0.92), in: CGRect(x: 0, y: 0, width: Wf, height: Hf))
    // A soft dark pool behind the lockup so the white type holds against the
    // brightest part of the cloud.
    let pool = CGGradient(colorsSpace: space, colors: [rgb(0x000000, 0.42), rgb(0x000000, 0)] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(pool, startCenter: CGPoint(x: Wf/2, y: Hf/2), startRadius: 0,
                           endCenter: CGPoint(x: Wf/2, y: Hf/2), endRadius: Hf * 0.62, options: [])
    let lockH = Hf * 0.80
    let lockW = lockH * CGFloat(lockup.width) / CGFloat(lockup.height)
    ctx.draw(lockup, in: CGRect(x: (Wf - lockW) / 2, y: (Hf - lockH) / 2, width: lockW, height: lockH))
    write(args[2])
    exit(0)
}

// ─── search tile ───────────────────────────────────────────────────────
let rawDir = args[2], outPath = args[3]
let lang = args.count > 4 ? args[4] : "en"

let fontPath = "Resources/HitmarkerText-VF.ttf"
guard let dp = CGDataProvider(url: URL(fileURLWithPath: fontPath) as CFURL), let cgFont = CGFont(dp) else {
    fputs("cannot load \(fontPath) (run from the MW4CamoTracker dir)\n", stderr); exit(1)
}
func makeFont(_ size: CGFloat) -> CTFont {
    let base = CTFontCreateWithGraphicsFont(cgFont, size, nil, nil)
    let desc = CTFontDescriptorCreateWithAttributes([
        kCTFontVariationAttribute: ["Weight" as CFString: 700] as CFDictionary
    ] as CFDictionary)
    return CTFontCreateCopyWithAttributes(base, size, nil, desc)
}

// Two headline lines and a smaller line under them, upper case like the
// screenshots. The headline is the first screenshot's; the line under it
// names the three modes, which is what sets this tracker apart.
let copy: [String: (lines: [String], sub: String)] = [
    "en": (["EVERY WEAPON", "EVERY CAMO"], "MULTIPLAYER / WARZONE / DMZ"),
    "de": (["JEDE WAFFE", "JEDE TARNUNG"], "MEHRSPIELER / WARZONE / DMZ"),
    "es": (["CADA ARMA", "CADA CAMO"], "MULTIJUGADOR / WARZONE / DMZ"),
    "fr": (["CHAQUE ARME", "CHAQUE CAMO"], "MULTIJOUEUR / WARZONE / DMZ"),
    "nl": (["ELK WAPEN", "ELKE CAMO"], "MULTIPLAYER / WARZONE / DMZ"),
]
guard let text = copy[lang] else {
    fputs("no copy for \(lang) (have: \(copy.keys.sorted().joined(separator: ", ")))\n", stderr); exit(1)
}
// Every character has to exist in Hitmarker, or CoreText silently swaps in
// another face for it.
let glyphProbe = makeFont(96)
for line in text.lines + [text.sub] {
    for ch in line.unicodeScalars where ch != " " {
        var chars = Array(String(ch).utf16)
        var glyphs = [CGGlyph](repeating: 0, count: chars.count)
        if !CTFontGetGlyphsForCharacters(glyphProbe, &chars, &glyphs, chars.count) || glyphs.contains(0) {
            fputs("Hitmarker has no glyph for '\(ch)' (\(lang))\n", stderr); exit(1)
        }
    }
}
guard let front = loadCG("\(rawDir)/weapon.png"), let back = loadCG("\(rawDir)/multiplayer.png") else {
    fputs("needs multiplayer.png and weapon.png in \(rawDir) (run Tools/screenshots/make.sh first)\n", stderr); exit(1)
}

// The glow sits behind the phones, so the type on the left is on the dark.
ctx.draw(nebula(glowX: 0.70, gain: 0.86), in: CGRect(x: 0, y: 0, width: Wf, height: Hf))
let shade = CGGradient(colorsSpace: space, colors: [rgb(0x000000, 0.55), rgb(0x000000, 0)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(shade, start: CGPoint(x: 0, y: 0), end: CGPoint(x: Wf * 0.62, y: 0), options: [])

func width(_ s: String, _ font: CTFont, kern: CGFloat) -> CGFloat {
    let a = NSAttributedString(string: s, attributes: [.font: font, .kern: kern])
    return CTLineGetBoundsWithOptions(CTLineCreateWithAttributedString(a), .useOpticalBounds).width
}
func draw(_ s: String, _ font: CTFont, kern: CGFloat, color: CGColor, x: CGFloat, baseline: CGFloat) {
    let a = NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: color, .kern: kern])
    let line = CTLineCreateWithAttributedString(a)
    let bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 26, color: rgb(0x000000, 0.65))
    ctx.textPosition = CGPoint(x: x - bounds.minX, y: baseline)
    CTLineDraw(line, ctx)
    ctx.restoreGState()
}

// Type block: left edge at 170, as wide as the space before the phones.
let left: CGFloat = 170, maxTextW: CGFloat = 1230
let baseSize: CGFloat = 300
let widest = text.lines.map { width($0, makeFont(baseSize), kern: 3) }.max() ?? 1
let size = baseSize * min(1, maxTextW / widest)
let headFont = makeFont(size)
let lineH = size * 1.10
let subBase: CGFloat = 92
let subSize = subBase * min(1, maxTextW / width(text.sub, makeFont(subBase), kern: 5))
let subFont = makeFont(subSize)
let gap = size * 0.42
let blockH = lineH + size * 0.74 + gap + subSize * 0.74      // cap heights, roughly
var baseline = (Hf + blockH) / 2 - size * 0.74
for (i, line) in text.lines.enumerated() {
    draw(line, headFont, kern: 3, color: i == 0 ? appInk : accent, x: left, baseline: baseline)
    baseline -= lineH
}
baseline += lineH
draw(text.sub, subFont, kern: 5, color: rgb(0xEDEFEA, 0.82), x: left, baseline: baseline - gap - subSize * 0.74)

/// A capture in a plain dark bezel. `top` is measured down from the top of
/// the canvas; a phone may run off the bottom.
func phone(_ image: CGImage, x: CGFloat, top: CGFloat, screenW: CGFloat) {
    let screenH = screenW * CGFloat(image.height) / CGFloat(image.width)
    let rim: CGFloat = 26
    let body = CGRect(x: x - rim, y: Hf - top - screenH - rim, width: screenW + 2*rim, height: screenH + 2*rim)
    let bodyPath = CGPath(roundedRect: body, cornerWidth: 118, cornerHeight: 118, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -30), blur: 80, color: rgb(0x000000, 0.7))
    ctx.addPath(bodyPath); ctx.setFillColor(bezel); ctx.fillPath()
    ctx.restoreGState()
    ctx.addPath(bodyPath); ctx.setStrokeColor(rgb(0x8B958D, 0.45)); ctx.setLineWidth(3); ctx.strokePath()
    let screen = CGRect(x: x, y: Hf - top - screenH, width: screenW, height: screenH)
    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: screen, cornerWidth: 94, cornerHeight: 94, transform: nil)); ctx.clip()
    ctx.draw(image, in: screen)
    ctx.restoreGState()
}
// The list behind and higher, the weapon screen in front and lower, both
// running off the bottom so they read as large as the tile allows.
phone(back, x: 1500, top: 150, screenW: 760)
phone(front, x: 2010, top: 330, screenW: 760)

write(outPath)
