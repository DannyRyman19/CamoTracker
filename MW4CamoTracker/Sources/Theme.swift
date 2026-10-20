import SwiftUI

/// Modes each carry their own accent so the shared component shell (row, chip, tab)
/// reads as a different mode without any layout changes. See design-system v0.1.
enum AppMode: String, CaseIterable, Identifiable {
    case multiplayer, warzone, dmz
    var id: String { rawValue }

    /// The modes the player picked in onboarding or Customise, as a
    /// comma-separated list. Empty means all of them.
    static let playedKey = "mw4_played_modes"

    /// The modes that get a tab and count in Stats, in their usual order.
    /// Never empty: a list that names none of them means all.
    static func played(_ raw: String) -> [AppMode] {
        let picked = Set(raw.split(separator: ",").map(String.init))
        let modes = allCases.filter { picked.contains($0.rawValue) }
        return modes.isEmpty ? allCases : modes
    }

    /// The mode the app opens on (a raw value; empty means the first one
    /// played). Only offered when more than one mode is played.
    static let startKey = "mw4_start_mode"

    /// Where the app opens: the picked mode if it's still played, else the
    /// first played one.
    static func start(_ raw: String, played playedRaw: String) -> AppMode {
        let played = played(playedRaw)
        return AppMode(rawValue: raw).flatMap { played.contains($0) ? $0 : nil } ?? played[0]
    }

    /// The same list after switching `mode` on or off; the last one left
    /// can't be switched off.
    static func toggling(_ mode: AppMode, in raw: String) -> String {
        var modes = Set(played(raw))
        if modes.contains(mode) {
            guard modes.count > 1 else { return raw }
            modes.remove(mode)
        } else {
            modes.insert(mode)
        }
        return modes.count == allCases.count ? "" : allCases.filter(modes.contains).map(\.rawValue).joined(separator: ",")
    }

    var displayNameKey: String {
        switch self {
        case .multiplayer: return "mw4.mode.multiplayer"
        case .warzone:     return "mw4.mode.warzone"
        case .dmz:         return "mw4.mode.dmz"
        }
    }

    var symbol: String {
        switch self {
        // One idea each, distinct in silhouette at 13pt: team play, the
        // collapsing BR circle, and the loot you exfil with. `scope` is
        // deliberately not reused here — it's `WeaponThumbnail`'s
        // missing-image placeholder, so a mode sharing it read as a
        // broken image rather than a mode.
        case .multiplayer: return "person.3.fill"
        case .warzone:     return "circle.dashed"
        case .dmz:         return "shippingbox.fill"
        }
    }

    var accent: Color {
        switch self {
        case .multiplayer: return .accentMultiplayer
        case .warzone:     return .accentWarzone
        case .dmz:         return .accentDMZ
        }
    }

    /// This mode's own 3-tier Mastery camo progression — the real MW4 names
    /// and colors, not invented (see Theme.swift's `Color` extension for how
    /// each color was sampled). Mastery is mode-wide, not per weapon: the
    /// tiers unlock one after another as more weapons earn this mode's final
    /// Completionist camo (Divergence in Multiplayer), at the counts in
    /// `weaponsNeeded` (see `TrackerViewModel`'s Mastery section).
    var masteryCamos: (tier1: MasteryCamo, tier2: MasteryCamo, tier3: MasteryCamo) {
        let base = builtInMasteryCamos
        guard let config = MasteryOverrides.byMode[rawValue] else { return base }
        return (base.tier1.applying(config.tier1), base.tier2.applying(config.tier2), base.tier3.applying(config.tier3))
    }

    /// The trio as shipped in this build — what `masteryCamos` falls back to
    /// wherever the mode JSON has no `mastery` override.
    private var builtInMasteryCamos: (tier1: MasteryCamo, tier2: MasteryCamo, tier3: MasteryCamo) {
        switch self {
        case .multiplayer:
            return (
                MasteryCamo(nameKey: "mw4.ui.mercurial_drift", color: .camoMercurialDrift, gradient: .mercurialDrift),
                MasteryCamo(nameKey: "mw4.ui.polyatomic_reforged", color: .camoPolyatomicReforged, gradient: .polyatomicReforged),
                MasteryCamo(nameKey: "mw4.ui.orion_reforged", color: .camoOrionReforged, gradient: .orionReforged)
            )
        case .warzone:
            return (
                MasteryCamo(nameKey: "mw4.ui.parallax", color: .camoParallax, gradient: .parallax),
                MasteryCamo(nameKey: "mw4.ui.damascus_reforged", color: .camoDamascusReforged, gradient: .damascusReforged),
                MasteryCamo(nameKey: "mw4.ui.empyros", color: .camoEmpyros, gradient: .empyros)
            )
        case .dmz:
            return (
                MasteryCamo(nameKey: "mw4.ui.chiral", color: .camoChiral, gradient: .chiral),
                MasteryCamo(nameKey: "mw4.ui.ripple_tide", color: .camoRippleTide, gradient: .rippleTide),
                MasteryCamo(nameKey: "mw4.ui.helio", color: .camoHelio, gradient: .helio)
            )
        }
    }

    /// This mode's Completionist camos for every weapon: Gold, Platinum and
    /// Harmonic Break, then the final camo. Names and colors come from the
    /// mode file's `completionist` block where it sets them.
    var completionist: (steps: [MasteryCamo], final: MasteryCamo) {
        // A mode sharing another's track shows that track's camos.
        let source = AppMode(rawValue: TrackSharing.byMode[rawValue] ?? rawValue) ?? self
        let config = CompletionistOverrides.byMode[source.rawValue]
        let builtIn = [
            MasteryCamo(nameKey: "mw4.ui.completionist.gold", color: .camoGold, gradient: .gold),
            MasteryCamo(nameKey: "mw4.ui.completionist.platinum", color: .camoPlatinum, gradient: .platinum),
            MasteryCamo(nameKey: "mw4.ui.completionist.harmonic_break", color: .camoHarmonicBreak, gradient: .harmonicBreak),
        ]
        let steps = builtIn.enumerated().map { index, camo in
            let step = config?.steps.flatMap { $0.indices.contains(index) ? $0[index] : nil }
            return camo.overriding(name: step?.name, colors: step?.colors, imageURL: step?.imageURL)
        }
        // Multiplayer's is Divergence; the other modes' haven't been shown,
        // so they read "Final camo" until their mode file names them.
        let builtInFinal = MasteryCamo(nameKey: "mw4.ui.completionist.final", color: .camoDivergence, gradient: .divergence,
                                       nameOverride: source == .multiplayer ? LocalizedText("Divergence") : nil)
        let final = builtInFinal.overriding(name: config?.final?.name, colors: config?.final?.colors, imageURL: config?.final?.imageURL)
        return (steps, final)
    }
}

extension AppMode {
    /// Whether the track has the final camo after Harmonic Break.
    var hasFinalCamo: Bool {
        let source = TrackSharing.byMode[rawValue] ?? rawValue
        return CompletionistOverrides.byMode[source]?.final?.enabled ?? true
    }

    /// Gold, Platinum, Harmonic Break, and the final camo when there is one.
    var completionistCamos: [MasteryCamo] {
        let track = completionist
        return track.steps + (hasFinalCamo ? [track.final] : [])
    }

    /// The end of the Completionist track: what Mastery builds on.
    var lastCompletionist: MasteryCamo { completionistCamos.last ?? completionist.final }
}

/// One named camo with its colors: a Mastery tier or a Completionist step.
/// A localization key (camo names are proper nouns and aren't translated,
/// same convention as weapon names), the single color-matched swatch used
/// for badges/pips, and a multi-stop `gradient` for the animated title
/// treatment (see `AnimatedGradientText`).
struct MasteryCamo {
    let nameKey: String
    let color: Color
    let gradient: [Color]
    var nameOverride: LocalizedText? = nil
    /// Mastery only: weapons with the final Completionist camo this tier
    /// needs, when the mode file sets it.
    var weaponsNeeded: Int? = nil
    /// The camo's picture, when its mode file gives one.
    var imageURL: String? = nil
    var name: String { nameOverride?.resolved() ?? nameKey.localized() }

    /// This camo with a mode JSON's `MasteryTierConfig` laid over it — only
    /// the fields the config actually sets change.
    func applying(_ config: MasteryTierConfig?) -> MasteryCamo {
        guard let config else { return self }
        var camo = overriding(name: config.name, colors: config.colors, imageURL: config.imageURL)
        camo.weaponsNeeded = config.weaponsNeeded.map { max(1, $0) } ?? weaponsNeeded
        return camo
    }

    func overriding(name: LocalizedText?, colors: [String]?, imageURL: String? = nil) -> MasteryCamo {
        let parsed = (colors ?? []).compactMap(Color.init(hex:))
        return MasteryCamo(
            nameKey: nameKey,
            color: parsed.first ?? color,
            gradient: parsed.isEmpty ? gradient : parsed,
            nameOverride: name ?? nameOverride,
            weaponsNeeded: weaponsNeeded,
            imageURL: imageURL ?? self.imageURL
        )
    }
}

/// The `mastery` block of each loaded mode file, keyed by mode. `AppMode` is a
/// plain enum with no route to the view model, so `TrackerViewModel` pushes
/// the overrides here whenever it (re)loads mode files — always *before* it
/// publishes the new `modes`, so the redraw that follows already sees them.
enum MasteryOverrides {
    nonisolated(unsafe) static var byMode: [String: MasteryConfig] = [:]
}

/// Which modes share another's camo track (`trackFrom`), kept the same way
/// as `MasteryOverrides`. A name that isn't a loaded mode, or a mode that
/// itself shares, is ignored rather than chained.
enum TrackSharing {
    nonisolated(unsafe) static var byMode: [String: String] = [:]

    static func update(from files: [String: ModeFile]) {
        byMode = files.compactMapValues(\.trackFrom).filter { mode, source in
            source != mode && files[source] != nil && files[source]?.trackFrom == nil
        }
    }
}

/// The modes whose Specials wait for every Military camo
/// (`specialsAfterMilitary`), kept the same way as `MasteryOverrides`.
enum SpecialRule {
    nonisolated(unsafe) static var afterMilitary: Set<String> = []

    static func update(from files: [String: ModeFile]) {
        afterMilitary = Set(files.filter { $0.value.specialsAfterMilitary == true }.keys)
    }
}

/// The `completionist` block of each loaded mode file, kept the same way as
/// `MasteryOverrides`.
enum CompletionistOverrides {
    nonisolated(unsafe) static var byMode: [String: CompletionistConfig] = [:]
}

extension Color {
    /// "#RRGGBB" or "RRGGBB"; nil for anything else, so a typo in the mode
    /// JSON falls back to the built-in color instead of rendering black.
    init?(hex: String) {
        let digits = hex.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "#", with: "")
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        self.init(red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255, blue: Double(value & 0xFF) / 255)
    }
}

extension [Color] {
    /// Each trio is the base sampled swatch (see `Color` extension below)
    /// plus the companion tones actually visible in that camo's art —
    /// Mercurial Drift's orange flame streaks, Orion's brass-gold nebula
    /// glow, Parallax's mint-to-gold color-shift, and so on.
    static let mercurialDrift: [Color]     = [.camoMercurialDrift, Color(red: 1.00, green: 0.70, blue: 0.28), Color(red: 1.00, green: 0.31, blue: 0.64)]
    static let polyatomicReforged: [Color] = [.camoPolyatomicReforged, Color(red: 0.31, green: 0.85, blue: 0.91), Color(red: 0.64, green: 0.36, blue: 0.88)]
    static let orionReforged: [Color]      = [.camoOrionReforged, Color(red: 0.89, green: 0.61, blue: 0.75), Color(red: 0.35, green: 0.13, blue: 0.25)]
    static let parallax: [Color]           = [.camoParallax, Color(red: 0.94, green: 0.87, blue: 0.95), Color(red: 0.55, green: 0.42, blue: 0.56)]
    static let damascusReforged: [Color]   = [.camoDamascusReforged, Color(red: 1.00, green: 0.54, blue: 0.36), Color(red: 0.88, green: 0.28, blue: 0.62)]
    static let empyros: [Color]            = [.camoEmpyros, Color(red: 0.94, green: 0.42, blue: 0.66), Color(red: 0.31, green: 0.88, blue: 0.82)]
    static let chiral: [Color]             = [.camoChiral, Color(red: 1.00, green: 0.25, blue: 0.21), Color(red: 0.48, green: 0.0, blue: 0.0)]
    static let rippleTide: [Color]         = [.camoRippleTide, Color(red: 1.00, green: 0.83, blue: 0.31), Color(red: 0.55, green: 0.27, blue: 0.07)]
    static let helio: [Color]              = [.camoHelio, Color(red: 1.00, green: 0.42, blue: 0.51), Color(red: 0.48, green: 0.06, blue: 0.11)]

    /// Plain weapon Gold — not a Mastery camo, but real CoD Gold is itself a
    /// shifting polished-metal finish, so it earns the same shimmer treatment.
    static let gold: [Color] = [.camoGold, Color(red: 1.00, green: 0.93, blue: 0.66), Color(red: 0.60, green: 0.46, blue: 0.09)]

    /// The "100%+" flex milestone past a mode's real tier3 capstone (every
    /// weapon that currently exists, DLC included, at Mastery tier2) — not
    /// tied to any one mode's own camo art, so it gets a distinct
    /// mode-agnostic platinum/chrome sweep instead of borrowing another
    /// tier's colors.
    static let platinum: [Color] = [.camoPlatinum, Color(red: 0.96, green: 0.98, blue: 1.00), Color(red: 0.62, green: 0.68, blue: 0.74)]

    /// Harmonic Break (coral red over black carbon) and Divergence (dark,
    /// flecked with blue, yellow and orange), from the in-game tiles. A mode
    /// file's `colors` still replaces them.
    static let harmonicBreak: [Color] = [.camoHarmonicBreak, Color(red: 0.95, green: 0.61, blue: 0.60), Color(red: 0.48, green: 0.21, blue: 0.20)]
    static let divergence: [Color] = [.camoDivergence, Color(red: 0.91, green: 0.78, blue: 0.29), Color(red: 0.90, green: 0.51, blue: 0.25)]

    /// The four Weapon Prestige camos, in order: Pyroclast's charcoal and
    /// silver, then more olive and green at each step up to Cascade's lime,
    /// from the in-game tiles. Data `colors` on a prestige camo replaces its
    /// set.
    static let prestige: [[Color]] = [
        [Color(red: 0.61, green: 0.61, blue: 0.59), Color(red: 0.85, green: 0.84, blue: 0.82), Color(red: 0.36, green: 0.36, blue: 0.33)],
        [Color(red: 0.60, green: 0.58, blue: 0.47), Color(red: 0.85, green: 0.82, blue: 0.63), Color(red: 0.37, green: 0.35, blue: 0.28)],
        [Color(red: 0.61, green: 0.59, blue: 0.44), Color(red: 0.78, green: 0.76, blue: 0.49), Color(red: 0.43, green: 0.48, blue: 0.29)],
        [Color(red: 0.61, green: 0.77, blue: 0.42), Color(red: 0.85, green: 0.94, blue: 0.66), Color(red: 0.33, green: 0.45, blue: 0.23)]
    ]
}

extension Color {
    /// Each mode's accent is that mode's own ultimate Mastery camo color
    /// (tier3 — Orion Reforged / Empyros / Helio) rather than an arbitrary
    /// brand pick, so the whole mode is visually "about" the camo it's
    /// building toward, not just a generic red/green/gold wash.
    static let accentMultiplayer = Color(red: 0.788, green: 0.271, blue: 0.494) // #C9457E, Orion Reforged's magenta (crimson sat too close to DMZ's red)
    static let accentWarzone     = camoEmpyros        // Empyros — #26A0B5
    static let accentDMZ         = camoHelio          // Helio — #C42437

    /// Established CoD tier colors — fixed regardless of which mode's accent is active.
    static let camoGold    = Color(red: 0.831, green: 0.686, blue: 0.216) // #D4AF37
    /// The "100%+" flex-milestone color — a cool platinum/chrome, deliberately
    /// distinct from any camo's own palette since it isn't one.
    static let camoPlatinum = Color(red: 0.78, green: 0.82, blue: 0.86) // #C7D1DB
    /// From the in-game tiles; see `[Color].harmonicBreak`.
    static let camoHarmonicBreak = Color(red: 0.82, green: 0.31, blue: 0.30) // #D04F4D coral red
    static let camoDivergence    = Color(red: 0.43, green: 0.61, blue: 0.91) // #6E9BE8 holographic blue

    /// MW4's real Mastery camo tier colors — all 9 of them (3 per mode),
    /// sampled directly from the camo art itself (Destructoid's "All MW4
    /// Mastery camos" gallery), not invented. Each is the most saturated
    /// color pulled from that camo's weapon skin, so the badge actually looks
    /// like the camo it names. Progression within a mode: per-weapon tier1 →
    /// category-gated per-weapon tier2 → mode-wide tier2-on-everything.

    // Multiplayer
    static let camoMercurialDrift     = Color(red: 0.878, green: 0.082, blue: 0.498) // #E0157F — hot magenta/pink liquid-metal
    static let camoPolyatomicReforged = Color(red: 0.357, green: 0.384, blue: 0.878) // #5B62E0 — faceted blue-violet crystal
    static let camoOrionReforged      = Color(red: 0.639, green: 0.251, blue: 0.416) // #A3406A plum-magenta nebula

    // Warzone
    static let camoParallax           = Color(red: 0.761, green: 0.608, blue: 0.769) // #C29BC4 pale lilac
    static let camoDamascusReforged   = Color(red: 0.082, green: 0.255, blue: 0.776) // #1541C6 — blue-violet marbled steel
    static let camoEmpyros            = Color(red: 0.149, green: 0.627, blue: 0.710) // #26A0B5 — teal mosaic

    // DMZ
    static let camoChiral             = Color(red: 0.757, green: 0.004, blue: 0.004) // #C10101 — translucent blood red
    static let camoRippleTide         = Color(red: 0.765, green: 0.584, blue: 0.165) // #C3952A — amber lava marble
    static let camoHelio              = Color(red: 0.769, green: 0.141, blue: 0.216) // #C42437 — crimson-pink translucent

    static let appBackground = Color(red: 0.043, green: 0.059, blue: 0.051) // #0B0F0D
    static let appSurface    = Color(red: 0.082, green: 0.102, blue: 0.090) // #151A17
    static let appSurface2   = Color(red: 0.114, green: 0.141, blue: 0.125) // #1D2420
    static let appInk        = Color(red: 0.929, green: 0.937, blue: 0.918) // #EDEFEA
    static let appInkMuted   = Color(red: 0.545, green: 0.584, blue: 0.553) // #8B958D
}

extension Font {
    /// Hitmarker Text (variable weight) — titles and labels only, never body copy.
    /// Bold, per design-system v0.1: Hitmarker is the identity face and always
    /// reads at 700 there, with Regular reserved for secondary display text.
    static func hitmarker(_ size: CGFloat) -> Font {
        .custom("Hitmarker Text VF", size: size).weight(.bold)
    }
}

/// Reusable dark gradient background, mode-tinted at the top edge.
struct AppBackground: View {
    var accent: Color = .accentMultiplayer
    var body: some View {
        ZStack(alignment: .top) {
            Color.appBackground.ignoresSafeArea()
            LinearGradient(
                stops: [
                    .init(color: accent.opacity(0.12), location: 0),
                    .init(color: .clear, location: 0.35)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        }
    }
}
