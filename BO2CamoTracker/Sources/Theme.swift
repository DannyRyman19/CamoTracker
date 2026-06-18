import SwiftUI

extension Color {
    /// Primary brand accent — #FF6601
    static let accent = Color(red: 1.0, green: 102 / 255, blue: 1 / 255)
    /// Muted version for backgrounds / fills
    static let accentMuted = Color(red: 1.0, green: 102 / 255, blue: 1 / 255).opacity(0.18)
    /// App background — near-black with a warm tint
    static let appBackground = Color(red: 0.07, green: 0.05, blue: 0.04)
}

extension Font {
    /// Agency FB Bold — display titles and section headers.
    static func agency(_ size: CGFloat) -> Font {
        .custom("AgencyFB-Bold", size: size)
    }
    /// Agency FB Regular — body text, labels, captions.
    static func agencyReg(_ size: CGFloat) -> Font {
        .custom("AgencyFB-Reg", size: size)
    }
}

/// Reusable gradient used behind scroll content.
struct AppBackground: View {
    var body: some View {
        ZStack(alignment: .top) {
            Color.appBackground.ignoresSafeArea()
            LinearGradient(
                stops: [
                    .init(color: Color.accent.opacity(0.12), location: 0),
                    .init(color: .clear, location: 0.35)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        }
    }
}
