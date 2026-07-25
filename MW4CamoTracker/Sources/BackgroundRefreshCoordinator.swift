import Foundation
import BackgroundTasks
import UserNotifications

/// Periodically checks `manifest.json` in the background and posts a local
/// notification if a new season/weapon/challenge has landed.
///
/// This is a best-effort mechanism, not a timer: iOS decides when (or
/// whether) to actually run the task based on the user's usage patterns,
/// battery state, and its own scheduling heuristics — it can lag hours to
/// days behind a real content update, and never runs at all for someone who
/// rarely opens the app. There's no server involved, so it stays free, but
/// "the instant we publish" delivery would need real push notifications
/// (APNs) with a backend to trigger them instead.
enum BackgroundRefreshCoordinator {
    /// Requests permission to show the update notification. Call once,
    /// after onboarding — asking right after the user has seen what the app
    /// does reads better than a cold-launch permission prompt.
    static func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { _, _ in }
    }

    /// Asks iOS to wake the app sometime in the next several hours to check
    /// for new content. Call on launch and whenever the app backgrounds —
    /// each request is consumed the moment it fires (or expires), so it has
    /// to be resubmitted every time.
    static func scheduleNext() {
        let request = BGAppRefreshTaskRequest(identifier: AppDelegate.refreshTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 4 * 60 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    static func handle(task: BGAppRefreshTask) {
        scheduleNext() // keep the chain going regardless of how this run turns out

        let work = Task {
            await checkForUpdates()
            task.setTaskCompleted(success: true)
        }
        task.expirationHandler = {
            work.cancel()
        }
    }

    private static func checkForUpdates() async {
        let dataService = DataService()
        let knownCatalogVersion = dataService.loadCachedCatalog()?.version
        let knownModeVersions = Dictionary(uniqueKeysWithValues:
            ["multiplayer", "warzone", "dmz"].compactMap { mode -> (String, String)? in
                guard let version = dataService.loadCached(mode: mode)?.version else { return nil }
                return (mode, version)
            }
        )

        guard let result = try? await dataService.refreshIfNeeded(
            knownCatalogVersion: knownCatalogVersion,
            knownModeVersions: knownModeVersions
        ) else { return }

        let changedModes = result.modes.keys.sorted()
        guard result.catalog != nil || !changedModes.isEmpty else { return }

        await postNotification(catalogChanged: result.catalog != nil, changedModes: changedModes)
    }

    private static func postNotification(catalogChanged: Bool, changedModes: [String]) async {
        let center = UNUserNotificationCenter.current()
        guard await center.notificationSettings().authorizationStatus == .authorized else { return }

        var changedAreas: [String] = []
        if catalogChanged { changedAreas.append("mw4.ui.section.weapons".localized()) }
        changedAreas += changedModes.map { "mw4.mode.\($0)".localized() }

        let content = UNMutableNotificationContent()
        content.title = "mw4.notif.title".localized()
        content.body = changedAreas.isEmpty
            ? "mw4.notif.generic_body".localized()
            : String(format: "mw4.notif.body_format".localized(), changedAreas.joined(separator: ", "))
        content.sound = .default

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        try? await center.add(request)
    }
}
