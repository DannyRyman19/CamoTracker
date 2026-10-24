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
                    .scaleEffect(drift ? 1.14 : 1.0)
                    .offset(x: drift ? -26 : 26, y: drift ? 20 : -20)
                    .rotationEffect(.degrees(drift ? 1.6 : -1.6))
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)
                    .blur(radius: 0.5)

                Image("SplashForeground")
                    .resizable()
                    .scaledToFit()
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
