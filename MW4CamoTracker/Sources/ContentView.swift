import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var viewModel: TrackerViewModel
    @State private var selectedTab = 0
    @State private var showOnboarding = false
    @AppStorage("mw4_has_onboarded") private var hasOnboarded = false

    var body: some View {
        ZStack(alignment: .top) {
            TabView(selection: $selectedTab) {
                ForEach(Array(AppMode.allCases.enumerated()), id: \.offset) { index, mode in
                    NavigationStack {
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
                MilestoneBannerView(banner: banner)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .animation(.spring(response: 0.4, dampingFraction: 0.8), value: viewModel.milestoneBanner)
            }
        }
        .onAppear {
            if !hasOnboarded { showOnboarding = true }
        }
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingView {
                hasOnboarded = true
                showOnboarding = false
            }
        }
    }

    private var currentAccent: Color {
        AppMode.allCases.indices.contains(selectedTab) ? AppMode.allCases[selectedTab].accent : .accentMultiplayer
    }
}
