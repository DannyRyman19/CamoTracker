import SwiftUI
import StoreKit

struct ContentView: View {
    @EnvironmentObject private var viewModel: TrackerViewModel
    @Environment(\.requestReview) private var requestReview
    @State private var selectedTab = 0
    /// "I mostly play": the mode the Weapons tab opens in.
    @AppStorage("mw4.primaryMode") private var primaryModeRaw = AppMode.multiplayer.rawValue
    private var primaryMode: AppMode {
        let m = AppMode(rawValue: primaryModeRaw) ?? .multiplayer
        return viewModel.visibleModes.contains(m) ? m : viewModel.visibleModes.first ?? .multiplayer
    }
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
        if env["SS_CAT"] == "all" { return .allWeapons }
        if let raw = env["SS_CAT"], let id = Int(raw) { return .weaponCategory(id) }
        return nil
        #else
        return nil
        #endif
    }

    /// Preview-video harness: `SS_DEMO=<take>` plays that take's scripted run
    /// for `Tools/preview/make.sh`. DEBUG-only, like the screenshot harness it
    /// sits on top of.
    private static var demoTake: String? {
        #if DEBUG
        let v = ProcessInfo.processInfo.environment["SS_DEMO"]
        return (v?.isEmpty == false) ? v : nil
        #else
        return nil
        #endif
    }

    /// The weapon the `grind` take finishes on camera: Kastov 762, which
    /// `seed.py --preview` leaves one camo short in Warzone and which is the
    /// pinned weapon, so the Suggested card points at it too.
    private static let demoWeaponId = 3

    /// One navigation path per mode tab. Only ever non-empty under the
    /// screenshot harness; normal navigation pushes onto it as usual.
    @AppStorage(AppMode.playedKey) private var playedRaw = ""
    @AppStorage(AppLanguage.key) private var languageRaw = ""
    @AppStorage(AppMode.startKey) private var startRaw = ""
    @State private var paths: [Int: NavigationPath] = [:]

    private func pathBinding(_ index: Int) -> Binding<NavigationPath> {
        Binding(get: { paths[index] ?? NavigationPath() }, set: { paths[index] = $0 })
    }

    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var rootWidth: CGFloat = 0

    /// Room for Mastery beside the weapons: an iPad, or an unfolded iPhone
    /// Duo held sideways. Upright the Duo (about 670pt) keeps the tab.
    private var hasMasteryColumn: Bool { sizeClass == .regular && rootWidth >= 800 }

    /// iPad: Mastery in a column beside the weapons, shown or hidden from
    /// the toolbar. It stands in for the Mastery tab, which iPad drops.
    @AppStorage("mw4.masteryColumn") private var showsMasteryColumn = true

    @ViewBuilder private func homeRoot(mode: AppMode) -> some View {
        if hasMasteryColumn {
            HStack(spacing: 0) {
                CategoryListView(mode: mode)
                    .frame(maxWidth: .infinity)
                if showsMasteryColumn {
                    MasteryTabView(embedded: true)
                        .frame(width: 300)
                        .overlay(alignment: .leading) {
                            Rectangle().fill(Color.appInkMuted.opacity(0.12)).frame(width: 1).ignoresSafeArea()
                        }
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
        } else {
            CategoryListView(mode: mode)
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.clear.readingWidth($rootWidth)
            TabView(selection: $selectedTab) {
                // Weapons first: one list, in the mode you mostly play;
                // each weapon switches modes for its own counts
                let index = 0, mode = primaryMode
                NavigationStack(path: pathBinding(index)) {
                    homeRoot(mode: mode)
                        .navigationDestination(for: Route.self) { route in
                            RouteDestinationView(mode: mode, route: route)
                        }
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            // The title is the mode, with a ▾ to change it
                            ToolbarItem(placement: .principal) {
                                Menu {
                                    Picker("mw4.ui.mostly_play".localized(), selection: $primaryModeRaw) {
                                        ForEach(viewModel.visibleModes) { m in
                                            Label(m.displayNameKey.localized(), systemImage: m.symbol).tag(m.rawValue)
                                        }
                                    }
                                } label: {
                                    HStack(spacing: 6) {
                                        Text(mode.displayNameKey.localized())
                                            .font(.hitmarker(22))
                                            .foregroundStyle(Color.appInk)
                                        Image(systemName: "chevron.down.circle.fill")
                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundStyle(mode.accent)
                                    }
                                }
                                .accessibilityLabel("mw4.ui.mostly_play".localized())
                            }
                            ToolbarItem(placement: .navigationBarTrailing) {
                                Button {
                                    showOnboarding = true
                                } label: {
                                    Image(systemName: "questionmark.circle")
                                }
                            }
                            if hasMasteryColumn {
                                ToolbarItem(placement: .navigationBarTrailing) {
                                    Button {
                                        Haptics.step()
                                        withAnimation(.snappy) { showsMasteryColumn.toggle() }
                                    } label: {
                                        Image(systemName: showsMasteryColumn ? "sidebar.trailing" : "sidebar.right")
                                    }
                                    .accessibilityLabel("mw4.ui.section.mastery".localized())
                                }
                            }
                        }
                }
                .id(mode)
                .environment(\.pushRoute) { route in
                    var path = paths[index] ?? NavigationPath()
                    path.append(route)
                    paths[index] = path
                }
                .tabItem { Label("mw4.ui.section.weapons".localized(), systemImage: "scope") }
                .tag(index)

                // iPad has Mastery beside the weapons instead
                if !hasMasteryColumn {
                    NavigationStack { MasteryTabView() }
                        .tabItem { Label("mw4.ui.section.mastery".localized(), systemImage: "star.circle.fill") }
                        .tag(2)
                }

                NavigationStack { StatsView() }
                    .tabItem { Label("mw4.ui.tab.stats".localized(), systemImage: "chart.bar.fill") }
                    .tag(1)
            }
            .tint(currentAccent)
            // A language switch redraws every screen in the new language.
            .id(languageRaw)
            // A widget tap: mw4camo://mode/<mode>[/weapon/<id>] opens that
            // mode's tab, and the weapon on it when there is one.
            .onOpenURL { url in
                guard url.scheme == "mw4camo", url.host == "mode" else { return }
                let parts = url.pathComponents.filter { $0 != "/" }
                guard let mode = parts.first.flatMap(AppMode.init(rawValue:)),
                      viewModel.visibleModes.contains(mode) else { return }
                // The Weapons tab, in that mode
                primaryModeRaw = mode.rawValue
                selectedTab = 0
                var path = NavigationPath()
                if parts.count >= 3, parts[1] == "weapon", let id = Int(parts[2]) {
                    path.append(Route.weapon(id))
                }
                paths[0] = path
            }
            .onChange(of: languageRaw) { _ in viewModel.refreshWidgets() }
            .onChange(of: hasMasteryColumn) { column in
                if column, selectedTab == 2 { selectedTab = 0 }
            }
            .onChange(of: startRaw) { _ in viewModel.refreshWidgets() }
            // The title's mode is where the app opens next time, and what
            // the widgets follow
            .onChange(of: primaryModeRaw) { raw in
                if startRaw != raw { startRaw = raw }
            }
            // A mode no longer played falls back in `primaryMode` itself
            .onChange(of: playedRaw) { _ in viewModel.refreshWidgets() }

            #if DEBUG
            if Self.screenshotScreen == "widgets" { WidgetScreenshotView() }
            #endif

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
                if let m = AppMode(rawValue: screen) { primaryModeRaw = m.rawValue }
                let index = screen == "stats" ? 1 : 0
                selectedTab = index
                if let route = Self.screenshotRoute {
                    var path = NavigationPath()
                    path.append(route)
                    paths[index] = path
                }
                splashDone = true
                return
            }
            // Weapons opens in the mode last picked in its title
            if !startRaw.isEmpty {
                primaryModeRaw = AppMode.start(startRaw, played: playedRaw).rawValue
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
        // Preview video: wait for make.sh to start recording (it drops `ss_go`
        // in the app's tmp dir), then play the take. Every change goes through
        // the real setCamoAmount / toggleCamo path, so the progress bars, the
        // milestone banner and its confetti are the app's own behaviour and not
        // a mock-up. `suggest` and `stats` are stills: the harness only has to
        // leave them alone on a settled screen.
        .task {
            guard let take = Self.demoTake else { return }
            var waited = 0
            while viewModel.catalog == nil, waited < 200 {
                try? await Task.sleep(for: .milliseconds(50)); waited += 1
            }
            let go = (NSTemporaryDirectory() as NSString).appendingPathComponent("ss_go")
            while !FileManager.default.fileExists(atPath: go) {
                try? await Task.sleep(for: .milliseconds(50))
            }
            guard take == "grind" else { return }
            let mode = AppMode.warzone.rawValue
            let camos = viewModel.camos(weaponId: Self.demoWeaponId, mode: mode)
            guard camos.count >= 3 else { return }
            // The times here and the segment times in
            // Tools/preview/assemble.py describe the same clock: recording
            // time = this time + 1.0s. Change one, change the other.
            try? await Task.sleep(for: .seconds(2.5))
            viewModel.setCamoAmount(mode: mode, weaponId: Self.demoWeaponId, camo: camos[1],
                                    amount: camos[1].requirement?.amount ?? 1)
            try? await Task.sleep(for: .seconds(3))
            viewModel.toggleCamo(mode: mode, weaponId: Self.demoWeaponId, camo: camos[2])
        }
        #endif
        .onChange(of: viewModel.reviewRequestToken) { token in
            // 0 is the initial value, not a request; the token only ever
            // counts up from a weapon actually being finished.
            guard token > 0 else { return }
            // A system rating sheet in the middle of a take would end up in
            // the App Store preview.
            guard Self.demoTake == nil else { return }
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
            OnboardingView(asksForNotifications: !hasOnboarded) {
                if !hasOnboarded {
                    BackgroundRefreshCoordinator.requestNotificationPermission()
                }
                hasOnboarded = true
                showOnboarding = false
            }
            .environmentObject(viewModel)
        }
    }

    private var currentAccent: Color {
        primaryMode.accent
    }
}
