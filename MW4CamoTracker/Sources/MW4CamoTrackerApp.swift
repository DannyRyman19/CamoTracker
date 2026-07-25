import SwiftUI

@main
struct MW4CamoTrackerApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var viewModel = TrackerViewModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
                .preferredColorScheme(.dark)
                .task {
                    await viewModel.refresh()
                    BackgroundRefreshCoordinator.scheduleNext()
                }
        }
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .background {
                BackgroundRefreshCoordinator.scheduleNext()
            }
        }
    }
}
