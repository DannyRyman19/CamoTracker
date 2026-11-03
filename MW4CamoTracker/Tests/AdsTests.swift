import Foundation
import Testing
@testable import MW4CamoTracker

/// The EU/UK ad consent is asked where either the Region setting or the
/// App Store country is in the list, and no ad prompt comes in the session
/// a player finishes onboarding in.
@MainActor
struct AdsTests {

    @Test func consentAppliesByRegionOrAppStoreCountry() {
        #expect(AdConsent.applies(region: "DE", storefront: nil))
        #expect(AdConsent.applies(region: "US", storefront: "DEU"))
        #expect(AdConsent.applies(region: "US", storefront: "GBR"))
        #expect(AdConsent.applies(region: nil, storefront: "CHE"))
        #expect(!AdConsent.applies(region: "US", storefront: "USA"))
        #expect(!AdConsent.applies(region: nil, storefront: nil))
    }

    @Test func theSessionOnboardingEndsInHasNoAdPrompts() {
        let name = "AdsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        // A fresh install's launch: not onboarded yet
        Ads.sessionBoundary(defaults: defaults)
        #expect(!Ads.isPastFirstSession(defaults: defaults))
        // Onboarding done, the app still open: still the first session
        defaults.set(true, forKey: "mw4_has_onboarded")
        #expect(!Ads.isPastFirstSession(defaults: defaults))
        // Off to the background: the next session may ask
        Ads.sessionBoundary(defaults: defaults)
        #expect(Ads.isPastFirstSession(defaults: defaults))
    }
}
