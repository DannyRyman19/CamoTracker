import SwiftUI

@main
struct MW4CamoTrackerApp: App {
    @StateObject private var viewModel = TrackerViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
                .preferredColorScheme(.dark)
                .task { await viewModel.refresh() }
        }
    }
}
