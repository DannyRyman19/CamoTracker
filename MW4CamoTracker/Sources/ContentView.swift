import SwiftUI
import StoreKit

struct ContentView: View {
    @EnvironmentObject private var viewModel: TrackerViewModel
    @Environment(\.requestReview) private var requestReview
    @State private var selectedTab = 0
    @State private var showOnboarding = false
    @AppStorage("mw4_has_onboarded") private var hasOnboarded = false
    @State private var splashFinishing = false
    @State private var splashDone = false

    /// Screenshot harness: `SS_SCREEN` picks a tab and suppresses the splash
    /// and onboarding so `Tools/screenshots/make.sh` can capture one screen per
    /// launch. DEBUG-only; a normal launch never reads any of this.
    private static var screenshotScreen: String? {
        #if DEBUG
        let v = ProcessInfo.processInfo.environment["SS_SCREEN"]
        return (v?.isEmpty == false) ? v : nil
        #else
        return nil
        #endif
    }

    /// `SS_CAT` / `SS_WEAPON` deep-link one level past the tab root, so the
    /// category list and weapon detail can be captured too. DEBUG-only.
    private static var screenshotRoute: Route? {
        #if DEBUG
        let env = ProcessInfo.processInfo.environment
        if let raw = env["SS_WEAPON"], let id = Int(raw) { return .weapon(id) }
        if let raw = env["SS_CAT"], let id = Int(raw) { return .weaponCategory(id) }
        return nil
        #else
        return nil
        #endif
    }

    /// One navigation path per mode tab. Only ever non-empty under the
    /// screenshot harness; normal navigation pushes onto it as usual.
    @State private var paths: [Int: NavigationPath] = [:]

    private func pathBinding(_ index: Int) -> Binding<NavigationPath> {
        Binding(get: { paths[index] ?? NavigationPath() }, set: { paths[index] = $0 })
    }

    var body: some View {
        ZStack(alignment: .top) {
            TabView(selection: $selectedTab) {
                ForEach(Array(AppMode.allCases.enumerated()), id: \.offset) { index, mode in
                    NavigationStack(path: pathBinding(index)) {
                        CategoryListView(mode: mode)
                            .navigationDestination(for: Route.self) { route in
                                RouteDestinationView(mode: mode, route: route)
                            }
                            .toolbar {
                                ToolbarItem(placement: .navigationBarTrailing) {
                                    Button {
                                        showOnboarding = true
                                    } label: {
                                        Image(systemName: "questionmark.circle")
                                    }
                                }
                            }
                    }
                    .tabItem { Label(mode.displayNameKey.localized(), systemImage: mode.symbol) }
                    .tag(index)
                }

                NavigationStack { StatsView() }
                    .tabItem { Label("mw4.ui.tab.stats".localized(), systemImage: "chart.bar.fill") }
                    .tag(AppMode.allCases.count)
            }
            .tint(currentAccent)

            if let banner = viewModel.milestoneBanner {
                ConfettiBurst(colors: banner.titleGradient)
                    .frame(height: 260)
                    .allowsHitTesting(false)
                MilestoneBannerView(banner: banner)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .animation(.spring(response: 0.4, dampingFraction: 0.8), value: viewModel.milestoneBanner)
            }
        }
        .onAppear {
            if let screen = Self.screenshotScreen {
                let index = ["multiplayer": 0, "warzone": 1, "dmz": 2, "stats": 3][screen] ?? 0
                selectedTab = index
                if let route = Self.screenshotRoute {
                    var path = NavigationPath()
                    path.append(route)
                    paths[index] = path
                }
                splashDone = true
                return
            }
            if !hasOnboarded { showOnboarding = true }
        }
        .overlay {
            if !splashDone, Self.screenshotScreen == nil {
                SplashView(isFinishing: splashFinishing)
                    .transition(.identity)
                    .task {
                        // Long enough to read the mark, short enough not to be
                        // in the way on every cold start.
                        try? await Task.sleep(nanoseconds: 1_600_000_000)
                        withAnimation(.easeOut(duration: 0.55)) { splashFinishing = true }
                        try? await Task.sleep(nanoseconds: 600_000_000)
                        splashDone = true
                    }
            }
        }
        #if DEBUG
        // Completes a weapon's remaining base camos through the real
        // toggleCamo path, so the whole rating chain (checkMilestone ->
        // shouldAsk -> token -> guard -> requestReview) can be driven from
        // the command line. Seed a save a weapon short of a milestone, then
        // launch with MW4_FORCE_COMPLETE=<weaponId>.
        .task {
            guard let raw = ProcessInfo.processInfo.environment["MW4_FORCE_COMPLETE"],
                  let weaponId = Int(raw) else { return }
            var waited = 0
            while viewModel.catalog == nil, waited < 200 {
                try? await Task.sleep(for: .milliseconds(50)); waited += 1
            }
            try? await Task.sleep(for: .seconds(1))
            let mode = AppMode.multiplayer.rawValue
            let before = viewModel.weaponsWithBaseCamosComplete
            for camo in viewModel.camos(weaponId: weaponId, mode: mode)
            where !viewModel.isCamoComplete(mode: mode, weaponId: weaponId, camo: camo) {
                viewModel.toggleCamo(mode: mode, weaponId: weaponId, camo: camo)
            }
            print("MW4REVIEW forced weapon \(weaponId): complete \(before) -> \(viewModel.weaponsWithBaseCamosComplete), token \(viewModel.reviewRequestToken)")
        }
        #endif
        .onChange(of: viewModel.reviewRequestToken) { token in
            // 0 is the initial value, not a request; the token only ever
            // counts up from a weapon actually being finished.
            guard token > 0 else { return }
            Task {
                // Let the celebration land first: the milestone banner and
                // its confetti are up for 3.5s, and a system rating sheet on
                // top of that is both ugly and a worse moment to ask.
                try? await Task.sleep(for: .seconds(4))
                guard viewModel.milestoneBanner == nil, !showOnboarding, splashDone else { return }
                // Only spend the milestone once the prompt is really handed
                // over, so a suppressed one is retried on the next weapon.
                ReviewPrompt.markPrompted(weaponsComplete: viewModel.weaponsWithBaseCamosComplete)
                requestReview()
            }
        }
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingView {
                if !hasOnboarded {
                    BackgroundRefreshCoordinator.requestNotificationPermission()
                }
                hasOnboarded = true
                showOnboarding = false
            }
        }
    }

    private var currentAccent: Color {
        AppMode.allCases.indices.contains(selectedTab) ? AppMode.allCases[selectedTab].accent : .accentMultiplayer
    }
}
