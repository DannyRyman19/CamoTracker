import SwiftUI

@main
struct BO2CamoTrackerApp: App {
    @State private var viewModel = TrackerViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(viewModel)
        }
    }
}
