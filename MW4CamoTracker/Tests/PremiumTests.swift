import Foundation
import Testing
@testable import MW4CamoTracker

/// A paying player is never shown the free app while StoreKit is asked:
/// the store starts on the last answer, the check is asked again on each
/// return to the app, and only the newest of overlapping checks lands.
@MainActor
@Suite(.serialized)
struct PremiumEntitlementTests {

    private func freshDefaults() -> UserDefaults {
        let name = "PremiumEntitlementTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private static let never: () async -> Premium.Entitlement = {
        try? await Task.sleep(for: .seconds(30))
        return .init()
    }

    @Test func startsOnTheLastKnownAnswer() {
        let defaults = freshDefaults()
        defaults.set(true, forKey: Premium.cacheKey)
        #expect(Premium(currentEntitlement: Self.never, defaults: defaults).isPremium)
        #expect(!Premium(currentEntitlement: Self.never, defaults: freshDefaults()).isPremium)
    }

    @Test func aCheckCorrectsALapseAndRemembersIt() async {
        let defaults = freshDefaults()
        defaults.set(true, forKey: Premium.cacheKey)
        let store = Premium(currentEntitlement: { .init() }, defaults: defaults)
        await store.refresh()
        #expect(!store.isPremium)
        #expect(!defaults.bool(forKey: Premium.cacheKey))
    }

    @Test func aSlowOlderCheckCannotOverwriteANewerOne() async {
        // The first ask is slow and says free (from before a purchase);
        // the second is quick and says Premium.
        var calls = 0
        let store = Premium(currentEntitlement: {
            calls += 1
            if calls == 1 {
                try? await Task.sleep(for: .milliseconds(300))
                return .init()
            }
            return .init(premium: true)
        }, defaults: freshDefaults())
        let first = Task { await store.refresh() }
        while calls == 0 { await Task.yield() }
        await store.refresh()
        await first.value
        #expect(store.isPremium)
    }
}
