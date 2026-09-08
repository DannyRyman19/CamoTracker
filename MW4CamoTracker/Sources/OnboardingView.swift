import SwiftUI

/// First-launch walkthrough (and replayable via the "?" toolbar button).
/// Shows the two real interactions — tap-to-complete and tap-the-pill for an
/// exact amount — plus the shared weapon level and the Suggested feature,
/// each demoed with the actual row components rather than described in text.
///
/// Styled to the same loadout-panel language as the rest of the app: 8pt
/// `borderedCard` panels, Hitmarker for titles and labels only, and the splash
/// nebula carried through at low opacity so launch → onboarding → app reads as
/// one continuous surface rather than three unrelated screens.
struct OnboardingView: View {
    let onFinish: () -> Void
    @State private var page = 0

    private let pageCount = 4

    /// Each page borrows the accent of whatever it's actually demoing, so the
    /// walkthrough previews the app's multi-mode palette instead of painting
    /// everything Multiplayer red.
    private var accent: Color {
        switch page {
        case 0:  return .camoGold
        case 1:  return .accentMultiplayer
        case 2:  return .accentWarzone
        default: return .camoMercurialDrift
        }
    }

    var body: some View {
        VStack(spacing: 18) {
            header

            TabView(selection: $page) {
                WelcomePage(accent: accent).tag(0)
                MarkProgressPage().tag(1)
                WeaponLevelPage(accent: accent).tag(2)
                SuggestedPage().tag(3)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            controls
        }
        .padding(.top, 20)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // The nebula goes in a `background` rather than a ZStack sibling: at
        // `scaledToFill` the 1800pt asset is far wider than the screen, and as
        // a sibling it stretched the stack past the edges, which pushed the
        // padded cards and the button off both sides.
        .background {
            ZStack {
                AppBackground(accent: accent)
                Image("SplashBackground")
                    .resizable()
                    .scaledToFill()
                    .opacity(0.22)
                    .blur(radius: 2)
                LinearGradient(
                    colors: [Color.appBackground.opacity(0.5), Color.appBackground.opacity(0.92)],
                    startPoint: .top, endPoint: .bottom
                )
            }
            .clipped()
            .ignoresSafeArea()
        }
        .preferredColorScheme(.dark)
        .animation(.easeInOut(duration: 0.25), value: page)
    }

    private var header: some View {
        VStack(spacing: 12) {
            Text("\("mw4.onboarding.step".localized()) \(page + 1)/\(pageCount)")
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.4)
                .textCase(.uppercase)
                .foregroundStyle(accent)

            // Segmented bars rather than dots — squared off to match the
            // panels, and they double as a progress readout.
            HStack(spacing: 5) {
                ForEach(0..<pageCount, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(index <= page ? accent : Color.appInkMuted.opacity(0.25))
                        .frame(width: index == page ? 28 : 16, height: 3)
                }
            }
        }
    }

    private var controls: some View {
        VStack(spacing: 14) {
            Button {
                if page < pageCount - 1 {
                    withAnimation { page += 1 }
                } else {
                    onFinish()
                }
            } label: {
                Text(page < pageCount - 1 ? "mw4.onboarding.next".localized() : "mw4.onboarding.get_started".localized())
                    .font(.hitmarker(16))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(RoundedRectangle(cornerRadius: 8).fill(accent))
                    .foregroundStyle(Color.appBackground)
            }
            .buttonStyle(.plain)

            if page < pageCount - 1 {
                Button("mw4.onboarding.skip".localized(), action: onFinish)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.appInkMuted)
            }
        }
        .padding(.horizontal, 24)
    }
}

/// Shared page chrome: an uppercase kicker, the Hitmarker title, then content.
private struct OnboardingScaffold<Content: View>: View {
    let title: String
    let kicker: String?
    let accent: Color
    let body_: () -> Content

    init(_ title: String, kicker: String? = nil, accent: Color = .accentMultiplayer,
         @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.kicker = kicker
        self.accent = accent
        self.body_ = content
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(spacing: 8) {
                    if let kicker {
                        Text(kicker)
                            .font(.system(size: 10, weight: .semibold))
                            .tracking(1.4)
                            .textCase(.uppercase)
                            .foregroundStyle(Color.appInkMuted)
                    }
                    Text(title)
                        .font(.hitmarker(27))
                        .foregroundStyle(Color.appInk)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 24)

                body_()
                    .padding(.horizontal, 24)
            }
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
    }
}

private struct WelcomePage: View {
    let accent: Color

    var body: some View {
        OnboardingScaffold("mw4.onboarding.welcome.title".localized(), accent: accent) {
            VStack(spacing: 20) {
                // The real lockup rather than a stand-in SF Symbol — this is
                // the same art the splash and app icon use.
                Image("SplashForeground")
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 240)

                Text("mw4.onboarding.welcome.body".localized())
                    .font(.system(size: 15))
                    .foregroundStyle(Color.appInkMuted)
                    .multilineTextAlignment(.center)
                    .padding(14)
                    .borderedCard()
            }
        }
    }
}

/// A real, tappable demo — not a frozen mockup. The two demo camos use the
/// actual `ChallengeRow` with local, ephemeral `@State` (nothing here touches
/// `TrackerViewModel` or persists), so a first-time player can genuinely tap
/// the circle, type a pill amount, and — once both camos are done — see the
/// exact "Camos complete" celebration the real app fires.
private struct MarkProgressPage: View {
    private let demoNames = ["Foliage", "Frostbite"]
    private let demoRequired = [10, 10]

    @State private var amounts = [10, 6]
    @State private var showCelebration = false

    private var isGold: Bool { zip(amounts, demoRequired).allSatisfy { $0 >= $1 } }

    var body: some View {
        OnboardingScaffold("mw4.onboarding.mark.title".localized(), accent: .accentMultiplayer) {
            VStack(alignment: .leading, spacing: 16) {
                if showCelebration {
                    MilestoneBannerView(banner: MilestoneBanner(
                        id: UUID(),
                        title: "Camos complete",
                        subtitle: "You'll see this for real when it lands.",
                        titleGradient: .gold,
                        icon: "medal.fill"
                    ))
                    .padding(.horizontal, -24) // MilestoneBannerView adds its own horizontal padding; cancel the scaffold's so it doesn't get squeezed
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                demoBlock(index: 0, hint: "mw4.onboarding.mark.tap_circle".localized())
                demoBlock(index: 1, hint: "mw4.onboarding.mark.tap_pill".localized())
            }
        }
    }

    private func demoBlock(index: Int, hint: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            demoRow(index: index)
            Label(hint, systemImage: "hand.tap.fill")
                .font(.system(size: 12.5))
                .foregroundStyle(Color.accentMultiplayer)
        }
        .padding(12)
        .borderedCard()
    }

    private func demoRow(index: Int) -> some View {
        ChallengeRow(
            item: ChallengeItem(
                itemId: index,
                name: LocalizedText(demoNames[index]),
                imageURL: nil,
                tier: nil,
                requirement: Requirement(amount: demoRequired[index], unit: "kills", description: LocalizedText("Get \(demoRequired[index]) kills with this weapon.")),
                children: []
            ),
            accent: .accentMultiplayer,
            amount: amounts[index],
            isDone: amounts[index] >= demoRequired[index],
            onToggle: {
                withAnimation {
                    amounts[index] = amounts[index] >= demoRequired[index] ? 0 : demoRequired[index]
                    checkCelebration()
                }
            },
            onSetAmount: { newAmount in
                withAnimation {
                    amounts[index] = newAmount
                    checkCelebration()
                }
            }
        )
    }

    private func checkCelebration() {
        guard isGold else { return }
        showCelebration = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) {
            withAnimation { showCelebration = false }
        }
    }
}

private struct WeaponLevelPage: View {
    let accent: Color
    @State private var level = 34
    private let maxLevel = 55

    var body: some View {
        OnboardingScaffold("mw4.onboarding.level.title".localized(), accent: accent) {
            VStack(alignment: .leading, spacing: 16) {
                VStack(spacing: 12) {
                    Stepper(value: $level, in: 0...maxLevel) {
                        HStack {
                            Text("mw4.ui.weapon_level".localized())
                                .font(.system(size: 14))
                                .foregroundStyle(Color.appInk)
                            Spacer()
                            Text("\(level)/\(maxLevel)")
                                .font(.system(size: 14, weight: .bold, design: .monospaced))
                                .foregroundStyle(accent)
                        }
                    }
                    .tint(accent)

                    ProgressBar(fraction: Double(level) / Double(maxLevel), accent: accent)
                }
                .padding(12)
                .borderedCard(accent: level >= maxLevel ? accent : nil)

                Text("mw4.onboarding.level.body".localized())
                    .font(.system(size: 15))
                    .foregroundStyle(Color.appInkMuted)
                    .padding(14)
                    .borderedCard()
            }
        }
    }
}

private struct SuggestedPage: View {
    var body: some View {
        OnboardingScaffold("mw4.onboarding.suggested.title".localized(), accent: .camoMercurialDrift) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    Image(systemName: "diamond.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.appBackground)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(Color.camoMercurialDrift))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Kastov 762")
                            .font(.hitmarker(15))
                            .foregroundStyle(Color.appInk)
                        Text("1 camo from Mercurial Drift in Assault Rifles")
                            .font(.system(size: 12.5))
                            .foregroundStyle(Color.appInkMuted)
                    }
                }
                .padding(12)
                .borderedCard(accent: .camoMercurialDrift)

                Text("mw4.onboarding.suggested.body1".localized())
                    .font(.system(size: 15))
                    .foregroundStyle(Color.appInkMuted)

                MilestoneBannerView(banner: MilestoneBanner(id: UUID(), title: "Mercurial Drift unlocked", subtitle: "Every Assault Rifle is now Gold.", titleGradient: .mercurialDrift, icon: "diamond.fill"))

                Text("mw4.onboarding.suggested.body2".localized())
                    .font(.system(size: 15))
                    .foregroundStyle(Color.appInkMuted)
            }
        }
    }
}
