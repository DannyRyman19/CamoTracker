import StoreKit
import SwiftUI

/// Premium: no ads and stash scans without one. A yearly subscription or a
/// one-off lifetime unlock, both set up in App Store Connect under these ids.
@MainActor
final class Premium: ObservableObject {
    static let shared = Premium()

    static let yearlyID = "com.DannyRyman.MW4CamoTracker.premium.yearly"
    static let lifetimeID = "com.DannyRyman.MW4CamoTracker.premium.lifetime"
    static let productIDs = [yearlyID, lifetimeID]
    /// The last answer, so a launch with no network still knows.
    static let cacheKey = "mw4_premium"
    static let subscriberCacheKey = "mw4_premium_subscriber"

    /// What `Transaction.currentEntitlements` says this Apple Account owns.
    struct Entitlement: Equatable {
        var premium = false
        /// Premium through the yearly plan (not lifetime), so Manage
        /// Subscription is offered.
        var subscription = false
        /// Which plan, with its renewal or end date, for Customise's card.
        var plan: PremiumPlan?
    }

    /// Why there are no products to show.
    enum LoadProblem: Equatable {
        /// The App Store couldn't be reached (offline, most likely).
        case unreachable
        /// It answered without them: they aren't on sale here, or aren't
        /// set up for this version yet. Not the player's connection.
        case unavailable
    }

    @Published private(set) var isPremium: Bool
    @Published private(set) var isSubscriber: Bool
    /// The plan Customise names; nil until StoreKit has said (it then just
    /// says "You're Premium") and for a free player.
    @Published private(set) var plan: PremiumPlan?
    /// Yearly first, then lifetime; empty until the App Store answers.
    @Published private(set) var products: [Product] = []
    @Published private(set) var purchasing = false
    @Published private(set) var loadProblem: LoadProblem?

    private var updates: Task<Void, Never>?
    private let currentEntitlement: () async -> Entitlement
    private let syncPurchases: () async throws -> Void
    private let defaults: UserDefaults
    /// Launch, the return to the foreground, a purchase and the transaction
    /// listener can all ask at once: only the newest answer may land, so a
    /// slow check started before a purchase can't take Premium away again.
    private var entitlementGeneration = 0

    init(currentEntitlement: @escaping () async -> Entitlement = Premium.storeKitEntitlement,
         syncPurchases: @escaping () async throws -> Void = { try await AppStore.sync() },
         defaults: UserDefaults = .standard) {
        self.currentEntitlement = currentEntitlement
        self.syncPurchases = syncPurchases
        self.defaults = defaults
        let premium = defaults.bool(forKey: Self.cacheKey)
        isPremium = premium
        isSubscriber = premium && defaults.bool(forKey: Self.subscriberCacheKey)
    }

    /// Called once at launch: listens for purchases made elsewhere (another
    /// device, Ask to Buy, a renewal) and checks what's owned now. The
    /// return to the foreground checks again (`refresh`), so a lapsed
    /// plan or a refund lands without a relaunch.
    func start() {
        guard updates == nil else { return }
        updates = Task {
            for await result in Transaction.updates {
                if case .verified(let transaction) = result { await transaction.finish() }
                await refresh()
            }
        }
        // The entitlement first and on its own: it needs no network, where
        // the products can take a while (or never come).
        Task { await refresh() }
        Task { await loadProducts() }
    }

    func loadProducts() async {
        guard products.isEmpty else { return }
        loadProblem = nil
        do {
            let found = try await Product.products(for: Self.productIDs)
            products = Self.productIDs.compactMap { id in found.first { $0.id == id } }
            loadProblem = products.isEmpty ? .unavailable : nil
        } catch {
            loadProblem = .unreachable
        }
    }

    /// Premium while a verified, unrevoked yearly or lifetime purchase is
    /// held. Works offline: the entitlements are on the device.
    func refresh() async {
        entitlementGeneration += 1
        let generation = entitlementGeneration
        var entitlement = await currentEntitlement()
        // A newer check started while this one waited: its answer wins.
        guard generation == entitlementGeneration else { return }
        #if DEBUG
        if defaults.bool(forKey: Self.fakeKey) { entitlement.premium = true }
        #endif
        set(entitlement)
    }

    /// Verified, unrevoked Premium transactions this account holds now.
    static func storeKitEntitlement() async -> Entitlement {
        var entitlement = Entitlement()
        var plans: [PremiumPlan] = []
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result, productIDs.contains(transaction.productID),
               transaction.revocationDate == nil {
                entitlement.premium = true
                if transaction.productType == .autoRenewable { entitlement.subscription = true }
                if let kind = PremiumPlan.kind(forProductID: transaction.productID) {
                    plans.append(await describe(kind, from: transaction))
                }
            }
        }
        entitlement.plan = PremiumPlan.best(plans)
        return entitlement
    }

    /// The yearly plan's period end, and whether it renews then or ends,
    /// from its renewal info; Lifetime has neither.
    private static func describe(_ kind: PremiumPlan.Kind, from transaction: StoreKit.Transaction) async -> PremiumPlan {
        guard kind != .lifetime else { return PremiumPlan(kind: .lifetime) }
        var plan = PremiumPlan(kind: kind, periodEnd: transaction.expirationDate)
        if let status = await transaction.subscriptionStatus,
           case .verified(let renewal) = status.renewalInfo {
            plan.renews = renewal.willAutoRenew
        }
        return plan
    }

    /// What the player is told after a purchase or restore. Cancelling
    /// says nothing: they chose to.
    enum Notice: Identifiable, Equatable {
        case purchased
        case restored
        /// Ask to Buy, or a payment the bank still has to approve.
        case pending
        case purchaseFailed
        case restoreFailed
        case nothingToRestore
        var id: Self { self }
    }

    /// Buys `product`; nil when the player cancelled.
    func buy(_ product: Product) async -> Notice? {
        guard !purchasing else { return nil }
        purchasing = true
        defer { purchasing = false }
        let result: Product.PurchaseResult
        do {
            result = try await product.purchase()
        } catch {
            return Self.notice(forPurchaseError: error)
        }
        switch result {
        case .success(.verified(let transaction)):
            await transaction.finish()
            await refresh()
            return .purchased
        case .success(.unverified):
            return .purchaseFailed
        case .pending:
            return .pending
        case .userCancelled:
            return nil
        @unknown default:
            return nil
        }
    }

    /// Re-syncs this Apple Account's purchases and says how it went; nil
    /// when the player cancelled the sign-in.
    func restore() async -> Notice? {
        var failure: Error?
        do {
            try await syncPurchases()
        } catch {
            failure = error
        }
        await refresh()
        if isPremium { return .restored }
        if let failure { return Self.isCancellation(failure) ? nil : .restoreFailed }
        return .nothingToRestore
    }

    static func notice(forPurchaseError error: Error) -> Notice? {
        isCancellation(error) ? nil : .purchaseFailed
    }

    private static func isCancellation(_ error: Error) -> Bool {
        if case StoreKitError.userCancelled = error { return true }
        return error is CancellationError
    }

    private func set(_ entitlement: Entitlement) {
        #if DEBUG
        if forced { return }
        #endif
        let owned = entitlement.premium
        isSubscriber = owned && entitlement.subscription
        plan = owned ? entitlement.plan : nil
        defaults.set(isSubscriber, forKey: Self.subscriberCacheKey)
        guard owned != isPremium else { return }
        isPremium = owned
        defaults.set(owned, forKey: Self.cacheKey)
        // Sync starts (or stops) with Premium: a merge pass, so a device
        // that wasn't syncing takes in iCloud's progress before it writes
        CloudSync.syncAll()
    }

    #if DEBUG
    /// Debug builds on a device (not run from Xcode, so no StoreKit test
    /// file): when the App Store has no products, the Premium sheet offers
    /// test ones that unlock straight away, and a reset back to free.
    static let fakeKey = "mw4_debug_fake_premium"
    var hasFakePurchase: Bool { defaults.bool(forKey: Self.fakeKey) }

    func fakeBuy() async {
        purchasing = true
        try? await Task.sleep(for: .milliseconds(600))
        defaults.set(true, forKey: Self.fakeKey)
        purchasing = false
        await refresh()
    }

    func resetFakePurchase() async {
        defaults.set(false, forKey: Self.fakeKey)
        await refresh()
    }

    /// `MW4_PREMIUM=1` launches as Premium, for screenshots, and holds it
    /// against the App Store's answer: `=lifetime` as Lifetime, and with
    /// `MW4_SUBSCRIBER=1` as a yearly plan renewing in 300 days (`=ending`:
    /// one ending in 12), so Manage Subscription can be shown.
    private var forced = false
    func debugOverride() {
        let env = ProcessInfo.processInfo.environment
        guard let premium = env["MW4_PREMIUM"], premium == "1" || premium == "lifetime" else { return }
        forced = true
        isPremium = true
        isSubscriber = env["MW4_SUBSCRIBER"] != nil
        if let subscriber = env["MW4_SUBSCRIBER"] {
            plan = PremiumPlan(kind: .yearly, periodEnd: Date().addingTimeInterval((subscriber == "ending" ? 12 : 300) * 86_400),
                               renews: subscriber != "ending")
        } else if premium == "lifetime" {
            plan = PremiumPlan(kind: .lifetime)
        }
    }
    #endif
}

/// The plan a Premium player is on, as StoreKit reports it, for Customise
/// and the Premium sheet. nil wherever StoreKit couldn't say (offline
/// before the first check): they then just say "You're Premium".
struct PremiumPlan: Equatable {
    enum Kind: Equatable { case lifetime, yearly }

    var kind: Kind
    /// The yearly plan's current period end: its next renewal, or the day
    /// it ends when auto-renew is off. nil for Lifetime or when unknown.
    var periodEnd: Date?
    /// False when the subscriber has turned auto-renew off.
    var renews = true

    static func kind(forProductID id: String) -> Kind? {
        switch id {
        case Premium.lifetimeID: .lifetime
        case Premium.yearlyID: .yearly
        default: nil
        }
    }

    /// "Lifetime: yours for good", "Yearly · renews 3 Nov 2027", "Yearly ·
    /// ends 14 Nov 2026", or just "Yearly" without a date; "You're
    /// Premium" when the plan isn't known.
    static func line(for plan: PremiumPlan?) -> String {
        guard let plan else { return "ct.premium.plan.unknown".localized() }
        switch plan.kind {
        case .lifetime:
            return "ct.premium.plan.lifetime".localized()
        case .yearly:
            guard let end = plan.periodEnd else { return "mw4.ui.premium.yearly".localized() }
            let date = end.formatted(.dateTime.day().month(.abbreviated).year().locale(AppLanguage.locale))
            return String(format: (plan.renews ? "ct.premium.plan.renews" : "ct.premium.plan.ends").localized(), date)
        }
    }

    /// Of everything an account holds, the plan to describe: Lifetime
    /// outranks the yearly plan (it's what keeps Premium if that lapses).
    static func best(_ plans: [PremiumPlan]) -> PremiumPlan? {
        if let lifetime = plans.first(where: { $0.kind == .lifetime }) { return lifetime }
        return plans.max { ($0.periodEnd ?? .distantPast) < ($1.periodEnd ?? .distantPast) }
    }
}

extension View {
    /// The short message after a purchase or restore, shown by whichever
    /// screen started it, so it never tries to present from under a sheet.
    /// `onPremium` runs on OK when the purchase or restore unlocked Premium.
    func premiumNotice(_ notice: Binding<Premium.Notice?>, onPremium: @escaping () -> Void = {}) -> some View {
        alert(notice.wrappedValue?.title ?? "",
              isPresented: Binding(get: { notice.wrappedValue != nil },
                                   set: { if !$0 { notice.wrappedValue = nil } }),
              presenting: notice.wrappedValue) { shown in
            Button("mw4.ui.done".localized()) {
                if shown == .purchased || shown == .restored { onPremium() }
            }
        } message: { shown in
            Text(shown.message)
        }
    }
}

extension Premium.Notice {
    var title: String {
        switch self {
        case .purchased: "ct.premium.notice.purchased".localized()
        case .restored: "ct.premium.notice.restored".localized()
        case .pending: "ct.premium.notice.pending".localized()
        case .purchaseFailed: "ct.premium.notice.purchase_failed".localized()
        case .restoreFailed: "ct.premium.notice.restore_failed".localized()
        case .nothingToRestore: "ct.premium.notice.nothing".localized()
        }
    }

    var message: String {
        switch self {
        case .purchased: "ct.premium.notice.purchased_message".localized()
        case .restored: "ct.premium.notice.restored_message".localized()
        case .pending: "ct.premium.notice.pending_message".localized()
        case .purchaseFailed: "ct.premium.notice.purchase_failed_message".localized()
        case .restoreFailed: "ct.premium.notice.restore_failed_message".localized()
        case .nothingToRestore: "ct.premium.notice.nothing_message".localized()
        }
    }
}
