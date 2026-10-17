import SwiftUI

/// First-launch walkthrough (and replayable via the "?" toolbar button).
/// Picks how to track (full, with weapon levels and counts, or quick tick),
/// shows the real interactions for that choice, then Suggested, the ways to
/// make the app your own, and reporting wrong data, each demoed with the
/// actual row components rather than described in text.
///
/// Styled to the same loadout-panel language as the rest of the app: 8pt
/// `borderedCard` panels, Hitmarker for titles and labels only, and the splash
/// nebula carried through at low opacity so launch → onboarding → app reads as
/// one continuous surface rather than three unrelated screens.
struct OnboardingView: View {
    /// True on the first run only. It adds a last page that says what the
    /// app's one notification is for, and its button is what leads to the
    /// system's permission prompt. Per Apple's guidance for a screen shown
    /// before a permission request, that page has a single action, titled
    /// "Continue", and it previews the notification, never the system alert.
    var asksForNotifications = false
    let onFinish: () -> Void
    @State private var page = OnboardingView.firstPage

    /// Screenshot harness: `SS_ONBOARDING_PAGE=<index>` opens the walkthrough
    /// on that page. DEBUG-only; a normal launch starts at the beginning.
    private static var firstPage: Int {
        #if DEBUG
        return Int(ProcessInfo.processInfo.environment["SS_ONBOARDING_PAGE"] ?? "") ?? 0
        #else
        return 0
        #endif
    }

    private var pageCount: Int { asksForNotifications ? 6 : 5 }

    /// Each page borrows the accent of whatever it's actually demoing, so the
    /// walkthrough previews the app's multi-mode palette instead of painting
    /// everything Multiplayer red.
    private var accent: Color {
        switch page {
        case 0:  return .camoGold
        case 1:  return .accentWarzone
        case 2:  return .accentMultiplayer
        case 3:  return .camoPlatinum
        case 4:  return .camoMercurialDrift
        default: return .camoGold
        }
    }

    var body: some View {
        VStack(spacing: 18) {
            header

            TabView(selection: $page) {
                WelcomePage(accent: accent).tag(0)
                TrackingStylePage(accent: accent).tag(1)
                MarkProgressPage().tag(2)
                SuggestedPage().tag(3)
                MakeItYoursPage(accent: accent).tag(4)
                if asksForNotifications {
                    NotificationsPage().tag(5)
                }
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
                .font(.system(size: 11, weight: .bold))
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
                Text(page < pageCount - 1 ? "mw4.onboarding.next".localized()
                     : (asksForNotifications ? "mw4.onboarding.continue" : "mw4.onboarding.get_started").localized())
                    .font(.hitmarker(16))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(RoundedRectangle(cornerRadius: 8).fill(accent))
                    .foregroundStyle(Color.appBackground)
            }
            .buttonStyle(.plain)

            if page < pageCount - 1 {
                // Skipping the walkthrough still lands on the notifications
                // page when there is one, so the system prompt never arrives
                // with no explanation in front of it.
                Button("mw4.onboarding.skip".localized()) {
                    if asksForNotifications {
                        withAnimation { page = pageCount - 1 }
                    } else {
                        onFinish()
                    }
                }
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
                            .font(.system(size: 11, weight: .bold))
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

                VStack(alignment: .leading, spacing: 8) {
                    Text("mw4.ui.modes".localized())
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.appInk)
                    Text("mw4.onboarding.modes.hint".localized())
                        .font(.system(size: 12.5))
                        .foregroundStyle(Color.appInkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                    PlayedModesPicker()
                }
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
    private let demoNames = ["Smoke", "Stormwave"]
    private let demoRequired = [10, 10]
    /// The style picked on the page before. In quick tick the demo is the
    /// HAN 86's last two Military camos from the real data, where ticking
    /// the second ticks the first too, as it does in the app.
    @AppStorage(TrackerViewModel.quickTickKey) private var quickTick = false
    @EnvironmentObject private var viewModel: TrackerViewModel

    private var quickDemo: [ChallengeItem] {
        let military = viewModel.camos(weaponId: 0, mode: AppMode.multiplayer.rawValue).filter { $0.group == "military" }
        return military.count >= 2 ? Array(military.suffix(2)) : []
    }
    private var showsQuickDemo: Bool { quickTick && quickDemo.count == 2 }

    @State private var amounts = [10, 6]
    @State private var showCelebration = false

    private var isGold: Bool { zip(amounts, demoRequired).allSatisfy { $0 >= $1 } }

    var body: some View {
        OnboardingScaffold((quickTick ? "mw4.onboarding.mark.quick_title" : "mw4.onboarding.mark.title").localized(), accent: .accentMultiplayer) {
            VStack(alignment: .leading, spacing: 16) {
                if showCelebration {
                    MilestoneBannerView(banner: MilestoneBanner(
                        id: UUID(),
                        title: "mw4.ui.milestone.camos_complete_title".localized(),
                        subtitle: "mw4.onboarding.mark.celebration_subtitle".localized(),
                        titleGradient: .gold,
                        icon: "medal.fill"
                    ))
                    .padding(.horizontal, -24) // MilestoneBannerView adds its own horizontal padding; cancel the scaffold's so it doesn't get squeezed
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                demoBlock(index: 0, hint: "mw4.onboarding.mark.tap_circle".localized())
                demoBlock(index: 1, hint: (quickTick ? "mw4.onboarding.mark.quick_hint" : "mw4.onboarding.mark.tap_pill").localized())
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

    @ViewBuilder private func demoRow(index: Int) -> some View {
        if showsQuickDemo {
            quickRow(index: index)
        } else {
            countedRow(index: index)
        }
    }

    /// Quick tick: plain ticks, the second taking the first with it.
    private func quickRow(index: Int) -> some View {
        let camo = quickDemo[index]
        let done = amounts[index] >= demoRequired[index]
        return ChallengeRow(
            item: camo,
            accent: .accentMultiplayer,
            amount: amounts[index],
            isDone: done,
            detail: camo.unlockLevel.map { String(format: "mw4.ui.camo_level_reach".localized(), $0) },
            onToggle: {
                withAnimation {
                    // Ticking ticks the ones before; unticking clears the ones after.
                    let range = done ? Array(index..<amounts.count) : Array(0...index)
                    for each in range { amounts[each] = done ? 0 : demoRequired[each] }
                    checkCelebration()
                }
                Haptics.change(wasDone: done, isDone: !done)
            },
            onSetAmount: { _ in }
        )
    }

    private func countedRow(index: Int) -> some View {
        ChallengeRow(
            item: ChallengeItem(
                itemId: index,
                name: LocalizedText(demoNames[index]),
                imageURL: nil,
                tier: nil,
                unlockLevel: nil,
                requirement: Requirement(amount: demoRequired[index], unit: "kills",
                                         description: LocalizedText(String(format: "mw4.onboarding.mark.demo_challenge".localized(), demoRequired[index]))),
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

/// Full tracking or quick tick, picked here and changeable in Customise.
private struct TrackingStylePage: View {
    let accent: Color
    @EnvironmentObject private var viewModel: TrackerViewModel

    var body: some View {
        OnboardingScaffold("mw4.onboarding.tracking.title".localized(), accent: accent) {
            VStack(alignment: .leading, spacing: 14) {
                option(quick: false, symbol: "chart.bar.fill",
                       title: "mw4.onboarding.tracking.full.title".localized(),
                       body: "mw4.onboarding.tracking.full.body".localized())
                option(quick: true, symbol: "checkmark.circle.fill",
                       title: "mw4.ui.quick_tick.title".localized(),
                       body: "mw4.onboarding.tracking.quick.body".localized())
                Text("mw4.onboarding.tracking.footer".localized())
                    .font(.system(size: 13))
                    .foregroundStyle(Color.appInkMuted)
            }
        }
    }

    private func option(quick: Bool, symbol: String, title: String, body: String) -> some View {
        let picked = viewModel.quickTick == quick
        return Button {
            viewModel.setQuickTick(quick)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(picked ? accent : Color.appInkMuted)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.hitmarker(16))
                        .foregroundStyle(Color.appInk)
                    Text(body)
                        .font(.system(size: 13.5))
                        .foregroundStyle(Color.appInkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: picked ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 21))
                    .foregroundStyle(picked ? accent : Color.appInkMuted)
            }
            .padding(14)
            .contentShape(Rectangle())
            .borderedCard(accent: picked ? accent : nil)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(picked ? .isSelected : [])
    }
}

/// The ways to make the app your own, and how wrong data gets fixed.
private struct MakeItYoursPage: View {
    let accent: Color

    var body: some View {
        OnboardingScaffold("mw4.onboarding.yours.title".localized(), accent: accent) {
            VStack(alignment: .leading, spacing: 12) {
                row("pin.fill", "mw4.onboarding.yours.pin".localized())
                row("slider.horizontal.3", "mw4.onboarding.yours.customise".localized())
                row("exclamationmark.bubble.fill", "mw4.onboarding.yours.report".localized())
            }
        }
    }

    private func row(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: 26)
            Text(text)
                .font(.system(size: 14.5))
                .foregroundStyle(Color.appInk)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(14)
        .borderedCard()
    }
}

private struct SuggestedPage: View {
    var body: some View {
        let platinum = AppMode.multiplayer.completionist.steps[1]
        OnboardingScaffold("mw4.onboarding.suggested.title".localized(), accent: .camoPlatinum) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    Image(systemName: "medal.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.appBackground)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(Color.camoGold))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Kastov 762")
                            .font(.hitmarker(15))
                            .foregroundStyle(Color.appInk)
                        Text("mw4.onboarding.suggested.demo".localized())
                            .font(.system(size: 12.5))
                            .foregroundStyle(Color.appInkMuted)
                    }
                    Spacer(minLength: 0)
                }
                .padding(12)
                .borderedCard(accent: .camoGold)

                Text("mw4.onboarding.suggested.body1".localized())
                    .font(.system(size: 15))
                    .foregroundStyle(Color.appInkMuted)

                MilestoneBannerView(banner: MilestoneBanner(
                    id: UUID(),
                    title: String(format: "mw4.ui.milestone.unlocked_title".localized(), platinum.name),
                    subtitle: "mw4.onboarding.suggested.banner_subtitle".localized(),
                    titleGradient: platinum.gradient, icon: "diamond.fill"))

                Text("mw4.onboarding.suggested.body2".localized())
                    .font(.system(size: 15))
                    .foregroundStyle(Color.appInkMuted)
            }
        }
    }
}

/// The last first-run page: what the notification is for, with a preview of
/// the notification itself built from the app's real wording.
private struct NotificationsPage: View {
    var body: some View {
        OnboardingScaffold("mw4.onboarding.notif.title".localized(), accent: .camoGold) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 11) {
                    Image("SplashBackground")
                        .resizable()
                        .scaledToFill()
                        .frame(width: 40, height: 40)
                        .overlay {
                            Image("SplashForeground").resizable().scaledToFit().padding(4)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 9))

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .firstTextBaseline) {
                            Text("mw4.notif.title".localized())
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color.appInk)
                            Spacer(minLength: 8)
                            Text("mw4.onboarding.notif.now".localized())
                                .font(.system(size: 12))
                                .foregroundStyle(Color.appInkMuted)
                        }
                        Text("mw4.notif.generic_body".localized())
                            .font(.system(size: 13.5))
                            .foregroundStyle(Color.appInkMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(13)
                .background(RoundedRectangle(cornerRadius: 20).fill(Color.appSurface2))
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.appInkMuted.opacity(0.25), lineWidth: 1))

                Text("mw4.onboarding.notif.body".localized())
                    .font(.system(size: 15))
                    .foregroundStyle(Color.appInkMuted)

                Text("mw4.onboarding.notif.next_step".localized())
                    .font(.system(size: 13))
                    .foregroundStyle(Color.appInkMuted.opacity(0.8))
            }
        }
    }
}
