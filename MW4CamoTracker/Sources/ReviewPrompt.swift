import Foundation

/// Asks for an App Store rating at a genuine high point: once a real number
/// of weapons have had their base camo track finished, and never more often
/// than Apple already allows (3 per year, system-enforced regardless).
///
/// Purely a function of the current count of finished weapons, with no
/// separate event counter to drift out of sync. Reading the real total is
/// what makes an imported backup, a correction, or a progress reset all
/// behave sensibly, since each of those changes progress without passing
/// through here.
///
/// The caller owns the actual `requestReview` call, since that needs a
/// SwiftUI environment value, and confirms it with `markPrompted` so a
/// prompt suppressed at the last moment (behind the milestone banner, say)
/// is retried on the next weapon rather than silently burned.
enum ReviewPrompt {
    private static let milestoneKey = "reviewMilestoneReached"

    /// Weapon counts that earn a prompt, spread out so the first only lands
    /// once the app has clearly pulled its weight. Sorted.
    private static let milestones = [5, 20, 50]

    /// The highest milestone this count has reached, if any. A threshold
    /// rather than an exact match, so a count that arrives in a jump still
    /// earns its prompt instead of sailing past it.
    private static func reached(_ weapons: Int) -> Int? {
        milestones.last { $0 <= weapons }
    }

    /// True when this build came from TestFlight, which ships a sandbox
    /// receipt. `requestReview` does nothing at all in that case.
    static var isTestFlight: Bool {
        Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
    }

    /// Returns `true` when the caller should request a review for this many
    /// finished weapons, which it then confirms with `markPrompted`.
    @MainActor
    static func shouldAsk(weaponsComplete: Int, defaults: UserDefaults = .standard) -> Bool {
        guard let milestone = reached(weaponsComplete) else { return false }
        return milestone > defaults.integer(forKey: milestoneKey)
    }

    /// Called once the prompt has actually been handed to StoreKit.
    ///
    /// On TestFlight this deliberately records nothing. `requestReview` is a
    /// no-op there, so stamping the milestone would spend it on a build that
    /// cannot show a prompt - and because the stamp is what suppresses future
    /// asks, the tester would then never see that milestone again, not even
    /// once the App Store build arrived.
    @MainActor
    static func markPrompted(weaponsComplete: Int,
                             defaults: UserDefaults = .standard,
                             onTestFlight: Bool = isTestFlight) {
        guard !onTestFlight else { return }
        guard let milestone = reached(weaponsComplete) else { return }
        defaults.set(milestone, forKey: milestoneKey)
    }

    #if DEBUG
    @MainActor
    static func debugReset() {
        UserDefaults.standard.removeObject(forKey: milestoneKey)
    }
    #endif
}
