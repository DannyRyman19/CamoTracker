// plate.swift - the caption layer the App Store preview video is composited
// under: one transparent PNG per caption, holding the Hitmarker headline over
// a dark gradient that fades into the top of the screen recording.
//
//   swift Tools/preview/plate.swift <outDir> [lang]
//
// Writes <outDir>/<caption>.png at 886x1920 (the App Store 6.9"/6.7" preview
// size). The recording itself fills the whole canvas: App Review rejects a
// preview that frames the app (a backdrop, device or card around it) and
// allows only narration and video or text overlays on top of the capture.
// `lang` (en/de/es/fr/nl, default en) picks the caption set.
//
// Palette and type match Tools/screenshots/frame.swift, scaled to the video
// canvas.

import Foundation
import CoreGraphics
import CoreText
import ImageIO
import UniformTypeIdentifiers
import AppKit

let W = 886, H = 1920
let Wf = CGFloat(W), Hf = CGFloat(H)
let scrimH: CGFloat = 520           // gradient height, from the top of the canvas

guard CommandLine.arguments.count == 2 || CommandLine.arguments.count == 3 else {
    fputs("usage: swift plate.swift <outDir> [lang]\n", stderr); exit(1)
}
let outDir = CommandLine.arguments[1]
let lang = CommandLine.arguments.count == 3 ? CommandLine.arguments[2] : "en"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}
let appInk = rgb(0xEDEFEA)          // Theme.appInk, as in frame.swift
let scrimInk: UInt32 = 0x0B0D0B     // darker than the app's own ground, so the
                                    // headline holds over a bright weapon card

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

// Two lines per caption, upper case, in the order of `captionIDs`.
// assemble.py names these ids in its segment list, so a caption renamed here
// has to be renamed there too. The lines reuse the screenshot headlines
// (frame.swift) where the two say the same thing.
let captionIDs = ["challenges", "tick", "gold", "next", "stats"]
// The app's milestone banner drops in at the top of the screen, so the one
// caption that plays over it sits at the bottom instead of hiding it. The
// bottom band clears the tab bar; the top band covers the status and
// navigation bars.
let captionPositions = ["gold": "bottom"]
let captionSets: [String: [[String]]] = [
    "en": [["EVERY CHALLENGE", "PER GUN"],
           ["TICK CAMOS OFF", "AS YOU GRIND"],
           ["FINISH A GUN,", "TAKE THE GOLD"],
           ["IT POINTS AT", "WHAT IS NEXT"],
           ["WATCH IT", "ALL ADD UP"]],
    "de": [["JEDE AUFGABE", "PRO WAFFE"],
           ["TARNUNGEN", "ABHAKEN"],
           ["WAFFE FERTIG,", "GOLD GEHOLT"],
           ["ES ZEIGT,", "WAS ALS NÄCHSTES"],
           ["SIEH ZU", "WIE ES AUFGEHT"]],
    "es": [["CADA RETO", "POR ARMA"],
           ["MARCA CAMOS", "MIENTRAS JUEGAS"],
           ["ACABA UN ARMA", "Y LOGRA EL ORO"],
           ["TE DICE", "QUE SIGUE"],
           ["MIRA CÓMO", "TODO SUMA"]],
    "fr": [["CHAQUE DÉFI", "PAR ARME"],
           ["COCHEZ LES CAMOS", "EN JOUANT"],
           ["FINISSEZ UNE ARME,", "PRENEZ L'OR"],
           ["IL INDIQUE", "LA SUITE"],
           ["REGARDEZ", "TOUT MONTER"]],
    "nl": [["ELKE UITDAGING", "PER WAPEN"],
           ["VINK CAMOS AF", "TIJDENS HET GRINDEN"],
           ["WAPEN KLAAR,", "GOUD GEPAKT"],
           ["HET WIJST", "WAT HIERNA KOMT"],
           ["ZIE HET", "ALLEMAAL OPTELLEN"]],
]
guard let set = captionSets[lang], set.count == captionIDs.count else {
    fputs("no caption set for \(lang) (have: \(captionSets.keys.sorted().joined(separator: ", ")))\n", stderr)
    exit(1)
}
let captions = Array(zip(captionIDs, set)).map { (id: $0.0, lines: $0.1) }

// Every character has to exist in Hitmarker, or CoreText silently falls back
// to another face for the accented caps (same check as frame.swift).
let glyphProbe = makeFont(72)
for (id, lines) in captions {
    for ch in lines.joined().unicodeScalars where ch != " " {
        var chars = Array(String(ch).utf16)
        var glyphs = [CGGlyph](repeating: 0, count: chars.count)
        if !CTFontGetGlyphsForCharacters(glyphProbe, &chars, &glyphs, chars.count) || glyphs.contains(0) {
            fputs("Hitmarker has no glyph for '\(ch)' in \(id) (\(lang))\n", stderr); exit(1)
        }
    }
}

let space = CGColorSpace(name: CGColorSpace.sRGB)!

func render(_ id: String, _ lines: [String]) {
    let atBottom = captionPositions[id] == "bottom"
    guard let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0,
                              space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }

    // Scrim: dark enough behind the headline to read over a weapon thumbnail,
    // fading out below it so the screen underneath stays visible.
    let scrim = CGGradient(colorsSpace: space,
                           colors: [rgb(scrimInk, 0.94), rgb(scrimInk, 0.92), rgb(scrimInk, 0)] as CFArray,
                           locations: [0.0, 0.6, 1.0])!
    ctx.drawLinearGradient(scrim,
                           start: CGPoint(x: 0, y: atBottom ? 0 : Hf),
                           end: CGPoint(x: 0, y: atBottom ? scrimH : Hf - scrimH),
                           options: [])

    // Headline, sized as a pair and shrunk together only as far as the longest
    // line needs to clear the margin (same rule as frame.swift).
    let baseSize: CGFloat = 66
    let maxTextW = Wf - 2 * 44
    let probe = makeFont(baseSize)
    let widest = lines.map { line -> CGFloat in
        let a = NSAttributedString(string: line, attributes: [.font: probe, .kern: 1.5])
        return CTLineGetBoundsWithOptions(CTLineCreateWithAttributedString(a), .useOpticalBounds).width
    }.max() ?? 0
    let scale = widest > maxTextW ? maxTextW / widest : 1
    let font = makeFont(baseSize * scale)
    // Top band: below the status bar and the dynamic island. Bottom band:
    // above the tab bar.
    var y = atBottom ? 300 : Hf - 196
    for line in lines {
        let attr = NSAttributedString(string: line, attributes: [
            .font: font, .foregroundColor: appInk, .kern: 1.5,
        ])
        let ctLine = CTLineCreateWithAttributedString(attr)
        let bounds = CTLineGetBoundsWithOptions(ctLine, .useOpticalBounds)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -3), blur: 14, color: rgb(0x000000, 0.8))
        ctx.textPosition = CGPoint(x: (Wf - bounds.width) / 2 - bounds.minX, y: y)
        CTLineDraw(ctLine, ctx)
        ctx.restoreGState()
        y -= 74 * scale
    }

    guard let out = ctx.makeImage() else { return }
    let url = URL(fileURLWithPath: "\(outDir)/\(id).png") as CFURL
    let dest = CGImageDestinationCreateWithURL(url, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, out, nil)
    CGImageDestinationFinalize(dest)
}

for (id, lines) in captions { render(id, lines) }
print("wrote \(captions.count) plates to \(outDir)")
