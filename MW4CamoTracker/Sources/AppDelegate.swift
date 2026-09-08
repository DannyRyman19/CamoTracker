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
        Self.configureNavigationBarAppearance()
        return true
    }

    /// `.navigationTitle` can't be restyled per-view, so design-system v0.1's
    /// "Hitmarker for titles" rule has to land once, globally, here — every
    /// screen's nav title picks it up for free.
    ///
    /// Deliberately does NOT set `scrollEdgeAppearance`: assigning it via this
    /// global proxy this early breaks large-title rendering entirely (blank
    /// title, confirmed by direct testing) in this SwiftUI `NavigationStack` +
    /// `List` combination — a real platform quirk, not a font issue. Per
    /// Apple's docs, `standardAppearance` is used as the fallback everywhere
    /// `scrollEdgeAppearance` isn't set, including the at-rest/large-title
    /// state, so nothing is lost by leaving it alone.
    private static func configureNavigationBarAppearance() {
        let titleFont = hitmarkerBold(size: 34) // large-title size; UIKit scales down for inline
        let inlineFont = hitmarkerBold(size: 17)
        let ink = UIColor(red: 0.929, green: 0.937, blue: 0.918, alpha: 1) // Color.appInk

        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(red: 0.043, green: 0.059, blue: 0.051, alpha: 1) // Color.appBackground
        appearance.largeTitleTextAttributes = [.font: titleFont, .foregroundColor: ink]
        appearance.titleTextAttributes = [.font: inlineFont, .foregroundColor: ink]

        let bar = UINavigationBar.appearance()
        bar.standardAppearance = appearance
        bar.compactAppearance = appearance
    }

    /// Hitmarker Text ships as a single variable-weight file (its registered
    /// family name is "Hitmarker Text VF", not "Hitmarker Text"), so getting
    /// Bold out of it means dialing the `wght` axis directly rather than
    /// relying on `UIFont(name:size:)`, which just returns the default
    /// instance. Starts from that known-good regular instance and layers the
    /// axis on top, rather than building a descriptor from scratch — falls
    /// back to the system bold face if the named font isn't registered at all.
    private static func hitmarkerBold(size: CGFloat) -> UIFont {
        guard let base = UIFont(name: "Hitmarker Text VF", size: size) else {
            return .boldSystemFont(ofSize: size)
        }
        let wghtAxis: UInt32 = 0x77676874 // 'wght'
        let boldDescriptor = base.fontDescriptor.addingAttributes([
            kCTFontVariationAttribute as UIFontDescriptor.AttributeName: [wghtAxis: 700]
        ])
        return UIFont(descriptor: boldDescriptor, size: size)
    }
}
