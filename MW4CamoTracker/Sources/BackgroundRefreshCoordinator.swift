import Foundation
import BackgroundTasks
import UserNotifications
import UIKit

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
            let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])) ?? false
            if granted { await PushRegistration.register() }
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

    /// A push said there's an announcement: fetch the data it's about now, so
    /// it's there when the player taps it. The push itself was the notification.
    static func refreshForPush() async {
        await checkForUpdates(notify: false)
    }

    private static func checkForUpdates(notify: Bool = true) async {
        let game = GameRegistry.current
        let dataService = DataService(game: game)
        // The same data `TrackerViewModel` starts on: the kept download or
        // the bundled seed, whichever is newer. Nothing is cached until a
        // version actually changes, so comparing against the cache alone made
        // every fresh install treat the whole feed as new and post a bogus
        // "New Content Available" (and, after an app update, announce
        // content the update had already bundled).
        let knownCatalogVersion = dataService.loadCatalog()?.version
        let knownModeVersions = Dictionary(uniqueKeysWithValues:
            game.modes.map(\.id).compactMap { mode -> (String, String)? in
                guard let version = dataService.load(mode: mode)?.version else { return nil }
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
        guard notify, shouldNotify(result.notification) else { return }
        // Announced by push already (this phone is registered for them).
        guard !PushRegistration.covers(result.notification) else { return }

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
        if let link = announcement?.link { content.userInfo = ["link": link] }

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        try? await center.add(request)
    }
}


/// Real pushes for content announcements: the phone's APNs token goes to
/// camo-track.app/api/push (the camo-track-push Worker) with its language and
/// nothing else, and `Tools/send_push.py` sends each announcement to every
/// registered phone. Only once notifications are allowed.
enum PushRegistration {
    static let endpoint = URL(string: "https://camo-track.app/api/push/register")!
    /// The token last sent to the Worker successfully.
    static let sentTokenKey = "ct_push_token_sent"

    /// Asks iOS for this phone's push token, if notifications are allowed.
    /// The answer arrives in `AppDelegate`, which hands it to `send(token:)`.
    static func register() async {
        guard await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .authorized else { return }
        await MainActor.run { UIApplication.shared.registerForRemoteNotifications() }
    }

    /// Whether pushes reach this phone, so it needn't post an announcement itself.
    static var isRegistered: Bool { UserDefaults.standard.string(forKey: sentTokenKey) != nil }

    /// A pushed announcement (one with an `id`) on a phone registered for pushes.
    static func covers(_ announcement: Manifest.Announcement?) -> Bool {
        announcement?.id != nil && isRegistered
    }

    /// The app's language for the push's words, of the six it ships.
    static var language: String {
        let code = Bundle.main.preferredLocalizations.first.map { String($0.prefix(2)) } ?? "en"
        return ["en", "fr", "es", "de", "it", "nl"].contains(code) ? code : "en"
    }

    static func hex(_ token: Data) -> String { token.map { String(format: "%02x", $0) }.joined() }

    /// Sends the token (again, each launch: tokens can change, and the
    /// Worker drops ones Apple says are dead). Development builds use APNs's
    /// sandbox; TestFlight and App Store builds the real one.
    static func send(token: Data) async {
        #if DEBUG
        let sandbox = true
        #else
        let sandbox = false
        #endif
        let body: [String: Any] = [
            "token": hex(token), "sandbox": sandbox, "lang": language,
            "version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "",
        ]
        var request = URLRequest(url: endpoint, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        guard let (_, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return }
        UserDefaults.standard.set(hex(token), forKey: sentTokenKey)
    }
}
