import SwiftUI
import UIKit

/// Drawn icons for the game modes and weapon classes: white-on-clear
/// template PNGs in Assets › Glyphs, tinted like any SF Symbol. They stand
/// in where a symbol was only a rough stand-in for a Call of Duty idea (three
/// people for Multiplayer, a brain for Zombies). Anything without a drawing
/// keeps its SF Symbol.
enum Glyph {
    // NSCache is thread-safe; Swift just doesn't know it
    nonisolated(unsafe) private static let cache = NSCache<NSString, UIImage>()

    /// The asset drawn `height` points tall, as a template image sized for
    /// a `Label` or a menu (which show an image at its own size). `square`
    /// centres it in a height × height box, so mode icons line up like SF
    /// Symbols; a weapon keeps its width.
    static func image(_ name: String, height: CGFloat, maxWidth: CGFloat? = nil, square: Bool = false) -> UIImage? {
        let key = "\(name)|\(height)|\(maxWidth ?? 0)|\(square)" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        guard let source = UIImage(named: name), source.size.height > 0 else { return nil }
        let aspect = source.size.width / source.size.height
        var drawn = CGSize(width: height * aspect, height: height)
        // A long rifle is held to the width a pistol's height allows
        if let maxWidth, drawn.width > maxWidth { drawn = CGSize(width: maxWidth, height: maxWidth / aspect) }
        var canvas = drawn
        if square {
            // The wider of the two fits the box
            if aspect > 1 { drawn = CGSize(width: height, height: height / aspect) }
            canvas = CGSize(width: height, height: height)
        }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        let image = UIGraphicsImageRenderer(size: canvas, format: format).image { _ in
            source.draw(in: CGRect(x: (canvas.width - drawn.width) / 2, y: (canvas.height - drawn.height) / 2,
                                   width: drawn.width, height: drawn.height))
        }.withRenderingMode(.alwaysTemplate)
        cache.setObject(image, forKey: key)
        return image
    }

    /// The drawing for a mode, by its id. BO7's Endgame is the `campaign` mode.
    static func modeName(_ id: String) -> String { "glyph-mode-\(id == "campaign" ? "endgame" : id)" }

    /// The drawing for a weapon class, from its English name, which is the
    /// same across games ("Pistols" in one, "Handguns" in another).
    static func className(_ category: WeaponCategory) -> String? {
        let en = (category.name.values["en"] ?? "").lowercased()
        let match: [(String, String)] = [
            ("assault", "assault"), ("battle", "battle"), ("smg", "smg"), ("submachine", "smg"),
            ("shotgun", "shotgun"), ("lmg", "lmg"), ("light machine", "lmg"), ("marksman", "marksman"),
            ("sniper", "sniper"), ("pistol", "pistol"), ("handgun", "pistol"), ("launcher", "launcher"),
            ("melee", "melee"), ("special", "special"),
        ]
        return match.first { en.contains($0.0) }.map { "glyph-class-\($0.1)" }
    }
}

/// A mode's icon at `size` points (an SF Symbol's point size): its drawing
/// when there is one, otherwise its SF Symbol in `weight`.
struct ModeIcon: View {
    let id: String
    let symbol: String
    var size: CGFloat
    var weight: Font.Weight = .semibold

    init(_ mode: AppMode, size: CGFloat, weight: Font.Weight = .semibold) {
        self.init(id: mode.rawValue, symbol: mode.symbol, size: size, weight: weight)
    }

    init(id: String, symbol: String, size: CGFloat, weight: Font.Weight = .semibold) {
        self.id = id; self.symbol = symbol; self.size = size; self.weight = weight
    }

    var body: some View {
        // A symbol's glyph is a little taller than its point size
        if let drawn = Glyph.image(Glyph.modeName(id), height: (size * 1.2).rounded(), square: true) {
            Image(uiImage: drawn)
        } else {
            Image(systemName: symbol).font(.system(size: size, weight: weight))
        }
    }
}

/// A `Label` with a mode's icon, for headings, pickers and menus.
struct ModeLabel: View {
    let title: String
    let mode: AppMode
    var size: CGFloat = 17

    var body: some View {
        Label { Text(title) } icon: { ModeIcon(mode, size: size) }
    }
}

/// A weapon class's silhouette `height` points tall, or nothing when the
/// class has no drawing.
struct ClassIcon: View {
    let category: WeaponCategory
    var height: CGFloat = 16
    var maxWidth: CGFloat = 52

    var body: some View {
        if let name = Glyph.className(category), let drawn = Glyph.image(name, height: height, maxWidth: maxWidth) {
            Image(uiImage: drawn).accessibilityHidden(true)
        }
    }
}

extension AppMode {
    /// The mode's icon as one `Image`, for menus and pickers (which take an
    /// image, not a view): its drawing at a menu's size, else its symbol.
    var menuIcon: Image {
        if let drawn = Glyph.image(Glyph.modeName(rawValue), height: 20, square: true) {
            return Image(uiImage: drawn)
        }
        return Image(systemName: symbol)
    }
}

extension Glyph {
    /// A tab bar icon: the drawing in a tab-sized square, else the SF Symbol.
    static func tab(_ name: String, fallback: String) -> Image {
        if let drawn = image("glyph-tab-\(name)", height: 26, square: true) { return Image(uiImage: drawn) }
        return Image(systemName: fallback)
    }
}

extension Glyph {
    /// A Tac Map category's drawing, by its id ("glyph-map-fortress").
    static func mapName(_ category: HajinGuide.Category) -> String { "glyph-map-\(category.id)" }

    /// A map marker's icon at `size` points: a marker's own symbol (a key
    /// room's number) first, then its category's drawing, then the
    /// category's SF Symbol.
    static func marker(_ symbol: String?, _ category: HajinGuide.Category?, size: CGFloat) -> Image {
        if symbol == nil, let category,
           let drawn = image(mapName(category), height: (size * 1.2).rounded(), square: true) {
            return Image(uiImage: drawn)
        }
        return Image(systemName: symbol ?? category?.symbol ?? "mappin")
    }
}

extension Glyph {
    /// `glyph`'s drawing at `size` points when it's bundled, else `symbol`.
    static func icon(_ glyph: String?, symbol: String, size: CGFloat) -> Image {
        if let glyph, let drawn = image(glyph, height: (size * 1.2).rounded(), square: true) {
            return Image(uiImage: drawn)
        }
        return Image(systemName: symbol)
    }

    /// The DMZ guide's sections, by id. Several share the Tac Map's art: a
    /// boss is the same skull on the map and in the guide.
    static let dmzSection: [String: String] = [
        "levels": "glyph-dmz-levels", "recipes": "glyph-dmz-recipes", "resources": "glyph-dmz-resources",
        "stations": "glyph-dmz-stations", "upgrades": "glyph-dmz-upgrades", "gunsmith": "glyph-dmz-gunsmith",
        "bosses": "glyph-map-boss", "enemies": "glyph-dmz-enemies", "keys": "glyph-map-key",
        "valuables": "glyph-dmz-valuables", "kits": "glyph-dmz-kits", "threat": "glyph-dmz-threat",
        "infil": "glyph-map-spawn", "vehicles": "glyph-map-vehicle", "ops": "glyph-dmz-ops",
        "dynamic-ops": "glyph-map-phone", "rules": "glyph-dmz-rules", "prestige": "glyph-dmz-prestige",
        "traits": "glyph-dmz-traits",
    ]
}

extension HajinGuide.Section {
    var glyph: String? { Glyph.dmzSection[id] }
}

extension HajinMineCard {
    /// The My DMZ card's drawing. Reading the stash from a photo keeps its
    /// camera: it's an action, not a thing in the game.
    var glyph: String? {
        switch self {
        case .scan: return nil
        case .postMatch: return "glyph-map-loot"
        case .tracking: return "glyph-dmz-tracking"
        case .buildNext: return "glyph-dmz-build"
        case .shopping: return "glyph-dmz-shopping"
        case .blueprints: return "glyph-dmz-blueprints"
        case .stash: return "glyph-map-cache"
        case .keepSell: return "glyph-dmz-keepsell"
        case .orders: return Glyph.dmzSection["ops"]
        case .upgrades: return Glyph.dmzSection["upgrades"]
        case .bosses: return Glyph.dmzSection["bosses"]
        case .prestige: return Glyph.dmzSection["prestige"]
        }
    }
}
