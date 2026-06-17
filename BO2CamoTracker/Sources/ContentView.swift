import SwiftUI

struct ContentView: View {
    @Environment(TrackerViewModel.self) private var vm

    var body: some View {
        TabView {
            Tab("Tracker", systemImage: "list.bullet") {
                CategoryListView()
            }
            Tab("Stats", systemImage: "chart.bar.fill") {
                StatsView()
            }
        }
    }
}
