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
        case .multiplayer: return "scope"
        case .warzone:     return "aqi.medium"
        case .dmz:         return "shippingbox"
        }
    }

    var accent: Color {
        switch self {
        case .multiplayer: return .accentMultiplayer
        case .warzone:     return .accentWarzone
        case .dmz:         return .accentDMZ
        }
    }
}

extension Color {
    /// Task Force red — primary brand accent, distinct from the BO-line apps' orange.
    static let accentMultiplayer = Color(red: 0.882, green: 0.267, blue: 0.204) // #E14434
    /// Toxic gas green — Warzone's shrinking circle.
    static let accentWarzone     = Color(red: 0.561, green: 0.749, blue: 0.247) // #8FBF3F
    static let accentDMZ         = Color(red: 0.788, green: 0.635, blue: 0.153) // #C9A227

    /// Established CoD tier colors — fixed regardless of which mode's accent is active.
    static let camoGold    = Color(red: 0.831, green: 0.686, blue: 0.216) // #D4AF37
    static let camoDiamond = Color(red: 0.749, green: 0.890, blue: 0.941) // #BFE3F0

    static let appBackground = Color(red: 0.043, green: 0.059, blue: 0.051) // #0B0F0D
    static let appSurface    = Color(red: 0.082, green: 0.102, blue: 0.090) // #151A17
    static let appSurface2   = Color(red: 0.114, green: 0.141, blue: 0.125) // #1D2420
    static let appInk        = Color(red: 0.929, green: 0.937, blue: 0.918) // #EDEFEA
    static let appInkMuted   = Color(red: 0.545, green: 0.584, blue: 0.553) // #8B958D
}

extension Font {
    /// Hitmarker Text (variable weight) — titles and labels only, never body copy.
    static func hitmarker(_ size: CGFloat) -> Font {
        .custom("Hitmarker Text", size: size)
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
