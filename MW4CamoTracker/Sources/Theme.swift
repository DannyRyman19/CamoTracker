import SwiftUI

/// Modes each carry their own accent so the shared component shell (row, chip, tab)
/// reads as a different mode without any layout changes. See design-system v0.1.
enum AppMode: String, CaseIterable, Identifiable {
    case multiplayer, warzone, dmz
    var id: String { rawValue }

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
    /// each color was sampled). This is the real BO7 Camo Tracker shape
    /// (Gold → Diamond → Tempest → Singularity — every step past Gold has
    /// its own per-weapon challenge, gated by aggregate completion of the
    /// step before it), assumed identical across Multiplayer/Warzone/DMZ:
    ///
    /// - **tier1** is per-weapon: available once that weapon's base track
    ///   (Slate…Gold) is done, earned via its own small challenge.
    /// - **tier2** is also per-weapon, but only *available* on a weapon once
    ///   every weapon in that weapon's category has earned tier1 — a
    ///   category-wide gate, not an individual one.
    /// - **tier3** is the single mode-wide capstone: unlocks once every
    ///   weapon in the whole mode (every category) has earned tier2. That's
    ///   the whole requirement — no leveling condition on top.
    ///
    /// See `TrackerViewModel`'s "Weapon Mastery" section for the actual
    /// per-weapon tracking this drives. Deliberately *not* modeled after
    /// BO2's tracker — Black Ops 2 predates this challenge-tier system
    /// entirely and gates Mastery on Prestige instead, a genuinely different
    /// mechanic that doesn't apply here.
    var masteryCamos: (tier1: MasteryCamo, tier2: MasteryCamo, tier3: MasteryCamo) {
        switch self {
        case .multiplayer:
            return (
                MasteryCamo(nameKey: "mw4.ui.mercurial_drift", color: .camoMercurialDrift, gradient: .mercurialDrift, requirement: .tier1),
                MasteryCamo(nameKey: "mw4.ui.polyatomic_reforged", color: .camoPolyatomicReforged, gradient: .polyatomicReforged, requirement: .tier2),
                MasteryCamo(nameKey: "mw4.ui.orion_reforged", color: .camoOrionReforged, gradient: .orionReforged, requirement: nil)
            )
        case .warzone:
            return (
                MasteryCamo(nameKey: "mw4.ui.parallax", color: .camoParallax, gradient: .parallax, requirement: .tier1),
                MasteryCamo(nameKey: "mw4.ui.damascus_reforged", color: .camoDamascusReforged, gradient: .damascusReforged, requirement: .tier2),
                MasteryCamo(nameKey: "mw4.ui.empyros", color: .camoEmpyros, gradient: .empyros, requirement: nil)
            )
        case .dmz:
            return (
                MasteryCamo(nameKey: "mw4.ui.chiral", color: .camoChiral, gradient: .chiral, requirement: .tier1),
                MasteryCamo(nameKey: "mw4.ui.ripple_tide", color: .camoRippleTide, gradient: .rippleTide, requirement: .tier2),
                MasteryCamo(nameKey: "mw4.ui.helio", color: .camoHelio, gradient: .helio, requirement: nil)
            )
        }
    }
}

/// One entry in a mode's Mastery camo trio — a localization key (camo names
/// are proper nouns and aren't translated, same convention as weapon names),
/// the single color-matched swatch used for badges/pips, a multi-stop
/// `gradient` for the animated title treatment (see `AnimatedGradientText`),
/// and (for tier1/tier2 only — tier3 is a pure aggregate gate, `nil` here)
/// its own per-weapon `requirement`.
struct MasteryCamo {
    let nameKey: String
    let color: Color
    let gradient: [Color]
    let requirement: MasteryRequirement?
    var name: String { nameKey.localized() }
}

/// A per-weapon Mastery tier's own challenge, on top of its availability gate
/// (see `TrackerViewModel`'s Weapon Mastery section). Amounts are
/// placeholders — MW4 hasn't published real numbers for these — but a small
/// escalating headshot-kill count *per weapon* is the real family's own
/// pattern (BO7 Camo Tracker's own per-tier `AmountRequired`, e.g. Diamond
/// asking for a handful of headshots on each gun), not invented from nothing.
struct MasteryRequirement {
    let amount: Int
    /// Names the camo it earns — "Get 3 headshot kills with this weapon to
    /// earn Mercurial Drift," not a generic amount with no context.
    func description(camoName: String) -> String {
        String(format: "mw4.ui.mastery_requirement".localized(), amount, camoName)
    }

    static let tier1 = MasteryRequirement(amount: 3)
    static let tier2 = MasteryRequirement(amount: 5)
}

extension [Color] {
    /// Each trio is the base sampled swatch (see `Color` extension below)
    /// plus the companion tones actually visible in that camo's art —
    /// Mercurial Drift's orange flame streaks, Orion's brass-gold nebula
    /// glow, Parallax's mint-to-gold color-shift, and so on.
    static let mercurialDrift: [Color]     = [.camoMercurialDrift, Color(red: 1.00, green: 0.70, blue: 0.28), Color(red: 1.00, green: 0.31, blue: 0.64)]
    static let polyatomicReforged: [Color] = [.camoPolyatomicReforged, Color(red: 0.31, green: 0.85, blue: 0.91), Color(red: 0.64, green: 0.36, blue: 0.88)]
    static let orionReforged: [Color]      = [.camoOrionReforged, Color(red: 1.00, green: 0.72, blue: 0.30), Color(red: 0.75, green: 0.16, blue: 0.42)]
    static let parallax: [Color]           = [.camoParallax, Color(red: 0.96, green: 0.83, blue: 0.37), Color(red: 0.44, green: 0.91, blue: 0.77)]
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
}

extension Color {
    /// Each mode's accent is that mode's own ultimate Mastery camo color
    /// (tier3 — Orion Reforged / Empyros / Helio) rather than an arbitrary
    /// brand pick, so the whole mode is visually "about" the camo it's
    /// building toward, not just a generic red/green/gold wash.
    static let accentMultiplayer = camoOrionReforged // Orion Reforged — #C11D07
    static let accentWarzone     = camoEmpyros        // Empyros — #26A0B5
    static let accentDMZ         = camoHelio          // Helio — #C42437

    /// Established CoD tier colors — fixed regardless of which mode's accent is active.
    static let camoGold    = Color(red: 0.831, green: 0.686, blue: 0.216) // #D4AF37
    /// The "100%+" flex-milestone color — a cool platinum/chrome, deliberately
    /// distinct from any camo's own palette since it isn't one.
    static let camoPlatinum = Color(red: 0.78, green: 0.82, blue: 0.86) // #C7D1DB

    /// MW4's real Mastery camo tier colors — all 9 of them (3 per mode),
    /// sampled directly from the camo art itself (Destructoid's "All MW4
    /// Mastery camos" gallery), not invented. Each is the most saturated
    /// color pulled from that camo's weapon skin, so the badge actually looks
    /// like the camo it names. Progression within a mode: per-weapon tier1 →
    /// category-gated per-weapon tier2 → mode-wide tier2-on-everything.

    // Multiplayer
    static let camoMercurialDrift     = Color(red: 0.878, green: 0.082, blue: 0.498) // #E0157F — hot magenta/pink liquid-metal
    static let camoPolyatomicReforged = Color(red: 0.357, green: 0.384, blue: 0.878) // #5B62E0 — faceted blue-violet crystal
    static let camoOrionReforged      = Color(red: 0.757, green: 0.114, blue: 0.027) // #C11D07 — crimson nebula with ember glow

    // Warzone
    static let camoParallax           = Color(red: 0.553, green: 0.816, blue: 0.443) // #8DD071 — mint-to-gold shifting chrome
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
