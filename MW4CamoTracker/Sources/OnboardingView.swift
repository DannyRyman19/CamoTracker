import SwiftUI

/// First-launch walkthrough (and replayable via the "?" toolbar button).
/// Shows the two real interactions — tap-to-complete and tap-the-pill for an
/// exact amount — plus the shared weapon level and the Suggested feature,
/// each demoed with the actual row components rather than described in text.
struct OnboardingView: View {
    let onFinish: () -> Void
    @State private var page = 0

    private let pageCount = 4

    var body: some View {
        ZStack {
            AppBackground(accent: .accentMultiplayer)
            VStack(spacing: 20) {
                TabView(selection: $page) {
                    WelcomePage().tag(0)
                    MarkProgressPage().tag(1)
                    WeaponLevelPage().tag(2)
                    SuggestedPage().tag(3)
                }
                .tabViewStyle(.page(indexDisplayMode: .always))

                Button {
                    if page < pageCount - 1 {
                        withAnimation { page += 1 }
                    } else {
                        onFinish()
                    }
                } label: {
                    Text(page < pageCount - 1 ? "Next" : "Get Started")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Color.accentMultiplayer))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 24)

                if page < pageCount - 1 {
                    Button("Skip", action: onFinish)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.appInkMuted)
                }
            }
            .padding(.top, 40)
            .padding(.bottom, 24)
        }
        .preferredColorScheme(.dark)
    }
}

private struct OnboardingScaffold<Content: View>: View {
    let title: String
    let body_: () -> Content

    init(_ title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.body_ = content
    }

    var body: some View {
        VStack(spacing: 24) {
            Text(title)
                .font(.hitmarker(28))
                .foregroundStyle(Color.appInk)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            body_()
                .padding(.horizontal, 24)
            Spacer()
        }
        .padding(.top, 16)
    }
}

private struct WelcomePage: View {
    var body: some View {
        OnboardingScaffold("MW4 Camo Tracker") {
            VStack(spacing: 14) {
                Image(systemName: "scope")
                    .font(.system(size: 44))
                    .foregroundStyle(Color.accentMultiplayer)
                Text("Track every weapon, camo challenge, and DMZ objective — Multiplayer, Campaign, and DMZ each get their own tab.")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.appInkMuted)
                    .multilineTextAlignment(.center)
            }
        }
    }
}

private struct MarkProgressPage: View {
    var body: some View {
        OnboardingScaffold("Two ways to log progress") {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    demoRow(done: true, amount: 10, required: 10, name: "Foliage")
                    Label("Tap the circle to mark a camo done or not done.", systemImage: "hand.tap.fill")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Color.appInkMuted)
                }
                VStack(alignment: .leading, spacing: 6) {
                    demoRow(done: false, amount: 6, required: 10, name: "Gold")
                    Label("Tap the number to type an exact amount — handy for challenges like \"200 kills.\"", systemImage: "hand.tap.fill")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Color.appInkMuted)
                }
            }
        }
    }

    private func demoRow(done: Bool, amount: Int, required: Int, name: String) -> some View {
        ChallengeRow(
            item: ChallengeItem(
                itemId: 0,
                nameKey: name,
                imageRef: nil,
                tier: nil,
                requirement: Requirement(amount: required, unit: "kills", descriptionKey: "Get \(required) kills with this weapon."),
                children: []
            ),
            accent: .accentMultiplayer,
            amount: amount,
            isDone: done,
            onToggle: {},
            onSetAmount: { _ in }
        )
        .allowsHitTesting(false)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.appSurface))
    }
}

private struct WeaponLevelPage: View {
    var body: some View {
        OnboardingScaffold("One level, every mode") {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Weapon Level").foregroundStyle(Color.appInk)
                    Spacer()
                    Text("34 / 55").font(.system(size: 14, design: .monospaced)).foregroundStyle(Color.appInkMuted)
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.appSurface))

                Text("A weapon's level is the same everywhere — set it once from any mode's tab and it shows up on the others too, since it's the same gun.")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.appInkMuted)
            }
        }
    }
}

private struct SuggestedPage: View {
    var body: some View {
        OnboardingScaffold("We'll tell you what's next") {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    Image(systemName: "diamond.fill").foregroundStyle(Color.camoDiamond)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Kastov 762").font(.system(size: 15, weight: .semibold)).foregroundStyle(Color.appInk)
                        Text("1 camo from Diamond in Assault Rifles").font(.system(size: 12.5)).foregroundStyle(Color.appInkMuted)
                    }
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.appSurface))

                Text("Every tab has a Suggested section that points at the weapon closest to Gold — or, like here, the last one standing between a category and Diamond.")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.appInkMuted)

                MilestoneBannerView(banner: MilestoneBanner(id: UUID(), title: "💎 Diamond unlocked", subtitle: "Assault Rifles — every weapon just went Gold."))

                Text("Finish that last weapon and we'll celebrate right there.")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.appInkMuted)
            }
        }
    }
}
