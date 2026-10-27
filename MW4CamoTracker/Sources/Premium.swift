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
    private static let cacheKey = "mw4_premium"

    @Published private(set) var isPremium = UserDefaults.standard.bool(forKey: cacheKey)
    /// Yearly first, then lifetime; empty until the App Store answers.
    @Published private(set) var products: [Product] = []
    @Published private(set) var purchasing = false
    /// The App Store didn't answer (offline, or the products aren't set up)
    @Published private(set) var loadFailed = false

    private var updates: Task<Void, Never>?

    /// Called once at launch: listens for purchases made elsewhere (another
    /// device, Ask to Buy, a renewal) and checks what's owned now.
    func start() {
        guard updates == nil else { return }
        updates = Task {
            for await result in Transaction.updates {
                if case .verified(let transaction) = result { await transaction.finish() }
                await refresh()
            }
        }
        Task {
            await refresh()
            await loadProducts()
        }
    }

    func loadProducts() async {
        guard products.isEmpty else { return }
        loadFailed = false
        let found = (try? await Product.products(for: Self.productIDs)) ?? []
        products = Self.productIDs.compactMap { id in found.first { $0.id == id } }
        loadFailed = products.isEmpty
    }

    /// Premium while a verified, unrevoked yearly or lifetime purchase is held.
    func refresh() async {
        var owned = false
        #if DEBUG
        if UserDefaults.standard.bool(forKey: Self.fakeKey) { owned = true }
        #endif
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result, Self.productIDs.contains(transaction.productID),
               transaction.revocationDate == nil {
                owned = true
            }
        }
        set(owned)
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
        UserDefaults.standard.set(owned, forKey: Self.cacheKey)
    }

    #if DEBUG
    /// Debug builds on a device (not run from Xcode, so no StoreKit test
    /// file): when the App Store has no products, the Premium sheet offers
    /// test ones that unlock straight away, and a reset back to free.
    static let fakeKey = "mw4_debug_fake_premium"
    var hasFakePurchase: Bool { UserDefaults.standard.bool(forKey: Self.fakeKey) }

    func fakeBuy() async {
        purchasing = true
        try? await Task.sleep(for: .milliseconds(600))
        UserDefaults.standard.set(true, forKey: Self.fakeKey)
        purchasing = false
        await refresh()
    }

    func resetFakePurchase() async {
        UserDefaults.standard.set(false, forKey: Self.fakeKey)
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
