import Foundation
import StoreKit
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

/// Restore and purchase always say how they went (Premium on, nothing to
/// restore, a failure), and nothing when the player cancelled.
@MainActor
@Suite(.serialized)
struct PremiumNoticeTests {

    private struct Offline: Error {}

    private func store(premiumAfterSync: Bool, sync: @escaping () async throws -> Void) -> Premium {
        let name = "PremiumNoticeTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return Premium(currentEntitlement: { .init(premium: premiumAfterSync) }, syncPurchases: sync, defaults: defaults)
    }

    @Test func aRestoreThatFindsPremiumSaysSo() async {
        let store = store(premiumAfterSync: true, sync: {})
        #expect(await store.restore() == .restored)
        #expect(store.isPremium)
    }

    @Test func aRestoreWithNothingToRestoreSaysSo() async {
        #expect(await store(premiumAfterSync: false, sync: {}).restore() == .nothingToRestore)
    }

    @Test func aFailedRestoreSaysSo() async {
        #expect(await store(premiumAfterSync: false, sync: { throw Offline() }).restore() == .restoreFailed)
    }

    @Test func aCancelledRestoreSaysNothing() async {
        #expect(await store(premiumAfterSync: false, sync: { throw StoreKitError.userCancelled }).restore() == nil)
    }

    @Test func aFailedSyncThatStillFindsPremiumSaysItsRestored() async {
        #expect(await store(premiumAfterSync: true, sync: { throw Offline() }).restore() == .restored)
    }

    @Test func aPurchaseErrorFailsUnlessCancelled() {
        #expect(Premium.notice(forPurchaseError: Offline()) == .purchaseFailed)
        #expect(Premium.notice(forPurchaseError: StoreKitError.networkError(URLError(.notConnectedToInternet))) == .purchaseFailed)
        #expect(Premium.notice(forPurchaseError: StoreKitError.userCancelled) == nil)
    }

    @Test func everyNoticeHasATitleAndMessage() {
        for notice in [Premium.Notice.purchased, .restored, .pending, .purchaseFailed, .restoreFailed, .nothingToRestore] {
            #expect(!notice.title.isEmpty && !notice.title.hasPrefix("ct."))
            #expect(!notice.message.isEmpty && !notice.message.hasPrefix("ct."))
        }
    }
}

/// Customise names the plan StoreKit reports, with its renewal or end
/// date, and offers Manage Subscription only for the yearly plan.
@MainActor
struct PremiumPlanTests {
    private let date = Date(timeIntervalSince1970: 1_825_000_000)

    @Test func eachPlanReadsAsItself() {
        #expect(PremiumPlan.line(for: PremiumPlan(kind: .lifetime)) == "ct.premium.plan.lifetime".localized())
        let renews = PremiumPlan.line(for: PremiumPlan(kind: .yearly, periodEnd: date))
        let ends = PremiumPlan.line(for: PremiumPlan(kind: .yearly, periodEnd: date, renews: false))
        #expect(renews != ends)
        #expect(PremiumPlan.line(for: PremiumPlan(kind: .yearly)) == "mw4.ui.premium.yearly".localized())
        #expect(PremiumPlan.line(for: nil) == "ct.premium.plan.unknown".localized())
    }

    @Test func productIDsMapToPlans() {
        #expect(PremiumPlan.kind(forProductID: Premium.lifetimeID) == .lifetime)
        #expect(PremiumPlan.kind(forProductID: Premium.yearlyID) == .yearly)
        #expect(PremiumPlan.kind(forProductID: "something.else") == nil)
    }

    /// Lifetime outranks the yearly plan: it's what keeps Premium if that lapses.
    @Test func lifetimeIsTheBestPlan() {
        let yearly = PremiumPlan(kind: .yearly, periodEnd: date)
        #expect(PremiumPlan.best([yearly, PremiumPlan(kind: .lifetime)])?.kind == .lifetime)
        #expect(PremiumPlan.best([yearly]) == yearly)
        #expect(PremiumPlan.best([]) == nil)
    }

    /// The store keeps the plan and subscriber state the check found, and
    /// drops both once Premium has gone.
    @Test func theStoreKeepsWhatTheCheckFound() async {
        let plan = PremiumPlan(kind: .yearly, periodEnd: date, renews: false)
        var entitlement = Premium.Entitlement(premium: true, subscription: true, plan: plan)
        let store = Premium(currentEntitlement: { entitlement }, defaults: UserDefaults(suiteName: UUID().uuidString)!)
        await store.refresh()
        #expect(store.plan == plan)
        #expect(store.isSubscriber)
        entitlement = Premium.Entitlement()
        await store.refresh()
        #expect(store.plan == nil)
        #expect(!store.isSubscriber)
    }
}
