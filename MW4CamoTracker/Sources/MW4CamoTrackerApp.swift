import SwiftUI

@main
struct MW4CamoTrackerApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var gameStore = GameStore()
    private var viewModel: TrackerViewModel { gameStore.viewModel }
    @StateObject private var hajin = HajinStore(defaults: HajinStore.launchDefaults())
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
                .screenshotWidth()
                // The scanner sits outside the tabs, so it's given both too
                // (the Gunsmith list it opens reads the weapons)
                .hajinScanHost()
                .environmentObject(viewModel)
                .environmentObject(hajin)
                .environmentObject(gameStore)
                // Each game's screens start fresh on its own tracker and look
                .id(gameStore.game.id)
                .preferredColorScheme(.dark)
                .task {
                    // The stream overlay's figures, from whichever game is open
                    let store = gameStore
                    StreamOverlay.shared.makePayload = {
                        let overlay = StreamOverlay.shared, tracker = store.viewModel
                        return tracker.streamOverlayPayload(content: overlay.content, modeRaw: overlay.mode,
                                                            weaponId: overlay.weaponId(game: tracker.game.id))
                    }
                    StreamOverlay.shared.refresh(immediately: true)
                    Premium.shared.start()
                    #if DEBUG
                    Premium.shared.debugOverride()
                    #endif
                    if imageCacheToken < Self.currentImageCacheToken {
                        URLCache.shared.removeAllCachedResponses()
                        imageCacheToken = Self.currentImageCacheToken
                    }
                    Task { await NoticeStore.shared.refresh() }
                    await viewModel.refresh()
                    BackgroundRefreshCoordinator.scheduleNext()
                }
        }
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .background {
                BackgroundRefreshCoordinator.scheduleNext()
                // The end of a session: onboarded by now, the next one may
                // ask about ads (see `Ads.pastFirstSessionKey`)
                Ads.sessionBoundary()
            }
            // Coming back to the app checks again, so an update published
            // while it sat in the background shows without a relaunch.
            // Ads start once the app is active: the tracking prompt needs it
            if newPhase == .active { Ads.shared.start() }
            // Another device's progress may have landed while the app was
            // away, and iCloud doesn't always say so: merge it now.
            if newPhase == .active { CloudSync.syncAll() }
            // A yearly plan can lapse, or a purchase be refunded, while the
            // app sits in the background; launch isn't the only time to ask.
            if newPhase == .active { Task { await Premium.shared.refresh() } }
            // Back in the app: send the overlay's figures (retries one that failed)
            if newPhase == .active { StreamOverlay.shared.refresh(immediately: true) }
            // A notice switched on or off in the repo (Data/CT/notices.json)
            if newPhase == .active { Task { await NoticeStore.shared.refresh() } }
            if newPhase == .active, !viewModel.isRefreshing {
                Task { await viewModel.refresh() }
            }
        }
    }
}
