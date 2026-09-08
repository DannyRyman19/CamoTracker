import SwiftUI

@main
struct MW4CamoTrackerApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var viewModel = TrackerViewModel()
    @Environment(\.scenePhase) private var scenePhase

    /// GitHub Pages serves `cache-control: max-age=14400` on 404s as well as
    /// hits, so a weapon image requested before its file was pushed leaves a
    /// four-hour-old "missing" answer in `URLCache.shared` — which is what
    /// `AsyncImage` reads, so the art stays a placeholder long after the file
    /// is live. Bump this token whenever image URLs change to drop those
    /// stale negatives once, rather than re-fetching every launch.
    @AppStorage("mw4_image_cache_token") private var imageCacheToken = 0
    private static let currentImageCacheToken = 1

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
                .preferredColorScheme(.dark)
                .task {
                    if imageCacheToken < Self.currentImageCacheToken {
                        URLCache.shared.removeAllCachedResponses()
                        imageCacheToken = Self.currentImageCacheToken
                    }
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
