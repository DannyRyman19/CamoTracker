import SwiftUI

struct ContentView: View {
    @Environment(TrackerViewModel.self) private var vm

    var body: some View {
        TabView {
            Tab("Camos", systemImage: "star.fill") {
                CategoryListView()
            }
            Tab("Challenges", systemImage: "list.bullet.clipboard.fill") {
                ChallengesView()
            }
            Tab("Reticles", systemImage: "scope") {
                ReticlesView()
            }
            Tab("Stats", systemImage: "chart.bar.fill") {
                StatsView()
            }
        }
    }
}
