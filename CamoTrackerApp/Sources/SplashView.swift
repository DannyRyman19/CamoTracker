import SwiftUI

/// The launch splash: the logo's own nebula drifting behind a fixed mark.
///
/// iOS launch screens are a static image by definition, so this is a real view
/// layered over `ContentView` for the first moment of the session and then
/// faded out — the storyboard launch screen still shows first, and matching its
/// backdrop to this one's opening frame keeps the handoff from flashing.
///
/// The background art is deliberately oversized (1800pt square against a phone
/// screen) so the slow pan and zoom always have off-screen image to move into
/// and never expose an edge.
struct SplashView: View {
    /// Driven by the parent so the fade-out can be animated from outside.
    let isFinishing: Bool

    @State private var drift = false
    /// Respect Reduce Motion — the drift is decorative, and the splash still
    /// reads perfectly as a static composition without it.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let side = max(geo.size.width, geo.size.height) * 1.6

            ZStack {
                Color.appBackground

                Image("SplashBackground")
                    .resizable()
                    .scaledToFill()
                    .frame(width: side, height: side)
                    // Each game's nebula in its own colour: the gold art as
                    // greys, multiplied by the tint
                    .modifier(SplashTint(tint: Palette.tint))
                    .scaleEffect(drift ? 1.14 : 1.0)
                    .offset(x: drift ? -26 : 26, y: drift ? 20 : -20)
                    .rotationEffect(.degrees(drift ? 1.6 : -1.6))
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)
                    .blur(radius: 0.5)

                SplashMark()
                    .frame(width: min(geo.size.width * 0.82, 460))
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)
                    // A touch of scale-in so the mark lands rather than just
                    // appearing, without competing with the background drift.
                    .scaleEffect(isFinishing ? 1.04 : 1.0)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
            .ignoresSafeArea()
        }
        .ignoresSafeArea()
        .opacity(isFinishing ? 0 : 1)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 9).repeatForever(autoreverses: true)) {
                drift = true
            }
        }
    }
}

private struct SplashTint: ViewModifier {
    let tint: Color?
    func body(content: Content) -> some View {
        if let tint {
            content.saturation(0).brightness(0.08).colorMultiply(tint)
        } else {
            content
        }
    }
}

/// "CAMO / 사 / TRACKER" for MW4, the art as drawn. Another game keeps the
/// art's CAMO and TRACKER and puts its own mark between them ("BO6", "CW")
/// in its title font, white then its colour, the way the old trackers'
/// icons read. Text only: no game logos.
struct SplashMark: View {
    private var theme: GameTheme? { GameRegistry.current.theme }

    var body: some View {
        if let mark = theme?.mark {
            Image("SplashForeground")
                .resizable()
                .scaledToFit()
                // The art's middle third (rows 395 to 807 of 1200) is MW4's
                // mark: cut it out and put this game's there
                .mask {
                    GeometryReader { geo in
                        VStack(spacing: 0) {
                            Rectangle().frame(height: geo.size.height * 0.322)
                            Color.clear
                            Rectangle().frame(height: geo.size.height * 0.315)
                        }
                    }
                }
                .overlay {
                    GeometryReader { geo in
                        markText(mark)
                            .font(.custom(theme?.font ?? "Hitmarker Text VF", size: geo.size.height * 0.5 * (theme?.fontScale ?? 1)))
                            .fontWeight(theme?.fontWeight == "regular" ? .regular : .heavy)
                            .lineLimit(1)
                            .minimumScaleFactor(0.4)
                            .shadow(color: .black.opacity(0.45), radius: 6, y: 3)
                            .frame(width: geo.size.width * 0.92, height: geo.size.height * 0.36)
                            .position(x: geo.size.width / 2, y: geo.size.height * 0.50)
                    }
                }
        } else {
            Image("SplashForeground")
                .resizable()
                .scaledToFit()
        }
    }

    private func markText(_ mark: String) -> Text {
        let white = min(theme?.markWhite ?? 0, mark.count)
        let color = theme?.markColor.flatMap(Color.init(hex:)) ?? .white
        return Text(String(mark.prefix(white))).foregroundColor(Color(white: 0.93))
            + Text(String(mark.dropFirst(white))).foregroundColor(color)
    }
}
