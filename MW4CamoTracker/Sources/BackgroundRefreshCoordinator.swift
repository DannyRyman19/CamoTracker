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
// BGAppRefreshTask isn't marked Sendable, but Apple's docs guarantee
// setTaskCompleted/expirationHandler are safe to use across this boundary.
extension BGAppRefreshTask: @unchecked @retroactive Sendable {}

enum BackgroundRefreshCoordinator {
    /// Requests permission to show the update notification. Call once,
    /// after onboarding — asking right after the user has seen what the app
    /// does reads better than a cold-launch permission prompt.
    static func requestNotificationPermission() {
        // The async form, not a completion closure: an empty closure created
        // on the main actor still gets Swift 6's main-queue check, and the
        // system calls it back on a background queue.
        Task {
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
        }
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
        // Fall back to the bundled seed exactly as `TrackerViewModel` does.
        // Nothing is cached until a version actually changes, so comparing
        // against the cache alone made every fresh install treat the whole
        // feed as new and post a bogus "New Content Available".
        let knownCatalogVersion = (dataService.loadCachedCatalog() ?? dataService.loadSeedCatalog())?.version
        let knownModeVersions = Dictionary(uniqueKeysWithValues:
            ["multiplayer", "warzone", "dmz"].compactMap { mode -> (String, String)? in
                guard let version = (dataService.loadCached(mode: mode) ?? dataService.loadSeed(mode: mode))?.version else { return nil }
                return (mode, version)
            }
        )

        guard let result = try? await dataService.refreshIfNeeded(
            knownCatalogVersion: knownCatalogVersion,
            knownModeVersions: knownModeVersions
        ) else { return }

        let changedModes = result.modes.keys.sorted()
        guard result.catalog != nil || !changedModes.isEmpty else { return }
        // The data is already downloaded and cached by now; a silent update
        // only skips telling anyone.
        guard shouldNotify(result.notification) else { return }

        await postNotification(catalogChanged: result.catalog != nil, changedModes: changedModes, announcement: result.notification)
    }

    /// An update notifies unless the manifest marks it silent.
    static func shouldNotify(_ announcement: Manifest.Announcement?) -> Bool {
        announcement?.silent != true
    }

    /// The notification's words: the manifest's own where it supplies them,
    /// otherwise the built-in title and a body naming what changed. An empty
    /// string in the manifest counts as not supplied.
    static func notificationText(catalogChanged: Bool, changedModes: [String], announcement: Manifest.Announcement?) -> (title: String, body: String) {
        var changedAreas: [String] = []
        if catalogChanged { changedAreas.append("mw4.ui.section.weapons".localized()) }
        changedAreas += changedModes.map { "mw4.mode.\($0)".localized() }
        let builtInBody = changedAreas.isEmpty
            ? "mw4.notif.generic_body".localized()
            : String(format: "mw4.notif.body_format".localized(), changedAreas.joined(separator: ", "))

        func supplied(_ text: LocalizedText?) -> String? {
            guard let value = text?.resolved().trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
            return value
        }
        return (supplied(announcement?.title) ?? "mw4.notif.title".localized(), supplied(announcement?.body) ?? builtInBody)
    }

    private static func postNotification(catalogChanged: Bool, changedModes: [String], announcement: Manifest.Announcement?) async {
        let center = UNUserNotificationCenter.current()
        guard await center.notificationSettings().authorizationStatus == .authorized else { return }

        let text = notificationText(catalogChanged: catalogChanged, changedModes: changedModes, announcement: announcement)
        let content = UNMutableNotificationContent()
        content.title = text.title
        content.body = text.body
        content.sound = .default

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        try? await center.add(request)
    }
}
