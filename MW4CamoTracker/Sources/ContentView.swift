import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var viewModel: TrackerViewModel
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            ForEach(Array(AppMode.allCases.enumerated()), id: \.offset) { index, mode in
                NavigationStack {
                    CategoryListView(mode: mode)
                }
                .tabItem { Label(mode.displayNameKey.localized(), systemImage: mode.symbol) }
                .tag(index)
            }

            NavigationStack { StatsView() }
                .tabItem { Label("Stats", systemImage: "chart.bar.fill") }
                .tag(AppMode.allCases.count)
        }
        .tint(currentAccent)
    }

    private var currentAccent: Color {
        AppMode.allCases.indices.contains(selectedTab) ? AppMode.allCases[selectedTab].accent : .accentMultiplayer
    }
}
