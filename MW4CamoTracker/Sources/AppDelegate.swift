import UIKit
import BackgroundTasks

/// BGTaskScheduler registration has to happen during
/// `application(_:didFinishLaunchingWithOptions:)`, before the app finishes
/// launching — there's no equivalent hook on the SwiftUI `App` protocol pre-
/// iOS 17 (`.backgroundTask(.appRefresh)` is iOS 17+), so a thin
/// UIApplicationDelegateAdaptor is the only way to do this at iOS 16.
final class AppDelegate: NSObject, UIApplicationDelegate {
    static let refreshTaskIdentifier = "com.DannyRyman.MW4CamoTracker.refresh"

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.refreshTaskIdentifier, using: nil) { task in
            guard let refreshTask = task as? BGAppRefreshTask else { return }
            BackgroundRefreshCoordinator.handle(task: refreshTask)
        }
        return true
    }
}
