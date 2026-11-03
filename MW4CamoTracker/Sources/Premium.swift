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

    /// What `Transaction.currentEntitlements` says this Apple Account owns.
    struct Entitlement: Equatable {
        var premium = false
    }

    @Published private(set) var isPremium: Bool
    /// Yearly first, then lifetime; empty until the App Store answers.
    @Published private(set) var products: [Product] = []
    @Published private(set) var purchasing = false
    /// The App Store didn't answer (offline, or the products aren't set up)
    @Published private(set) var loadFailed = false

    private var updates: Task<Void, Never>?
    private let currentEntitlement: () async -> Entitlement
    private let defaults: UserDefaults
    /// Launch, the return to the foreground, a purchase and the transaction
    /// listener can all ask at once: only the newest answer may land, so a
    /// slow check started before a purchase can't take Premium away again.
    private var entitlementGeneration = 0

    init(currentEntitlement: @escaping () async -> Entitlement = Premium.storeKitEntitlement,
         defaults: UserDefaults = .standard) {
        self.currentEntitlement = currentEntitlement
        self.defaults = defaults
        isPremium = defaults.bool(forKey: Self.cacheKey)
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
        loadFailed = false
        let found = (try? await Product.products(for: Self.productIDs)) ?? []
        products = Self.productIDs.compactMap { id in found.first { $0.id == id } }
        loadFailed = products.isEmpty
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
        set(entitlement.premium)
    }

    /// Verified, unrevoked Premium transactions this account holds now.
    static func storeKitEntitlement() async -> Entitlement {
        var entitlement = Entitlement()
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result, productIDs.contains(transaction.productID),
               transaction.revocationDate == nil {
                entitlement.premium = true
            }
        }
        return entitlement
    }

    /// True once the purchase went through.
    func buy(_ product: Product) async -> Bool {
        purchasing = true
        defer { purchasing = false }
        guard let result = try? await product.purchase() else { return false }
        if case .success(.verified(let transaction)) = result {
            await transaction.finish()
            await refresh()
        }
        return isPremium
    }

    func restore() async {
        try? await AppStore.sync()
        await refresh()
    }

    private func set(_ owned: Bool) {
        #if DEBUG
        if forced { return }
        #endif
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
    /// against the App Store's answer.
    private var forced = false
    func debugOverride() {
        if ProcessInfo.processInfo.environment["MW4_PREMIUM"] == "1" { forced = true; isPremium = true }
    }
    #endif
}
