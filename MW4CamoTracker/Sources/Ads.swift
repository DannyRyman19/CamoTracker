import AppLovinSDK
import AppTrackingTransparency
import SwiftUI

/// AppLovin MAX: a banner under the Weapons and DMZ lists, and a rewarded
/// ad before each stash scan. Premium players see neither.
enum AdConfig {
    // AppLovin dashboard: Account > Keys, and MAX > Ad Units. Until these
    // are filled in, the app shows no ads and scans are free.
    static let sdkKey = ""
    static let bannerUnit = ""
    static let rewardedUnit = ""

    static var isConfigured: Bool { !sdkKey.isEmpty && !bannerUnit.isEmpty && !rewardedUnit.isEmpty }

    /// `MW4_ADS=1` (DEBUG) acts as a free player with ads on, without keys:
    /// the scan asks first, and with no ad to show it goes straight on.
    static var simulated: Bool {
        #if DEBUG
        ProcessInfo.processInfo.environment["MW4_ADS"] == "1"
        #else
        false
        #endif
    }
}

@MainActor
final class Ads: NSObject, ObservableObject {
    static let shared = Ads()

    /// The SDK is up and banners can load.
    @Published private(set) var ready = false

    private var rewarded: MARewardedAd?
    private var onReward: (() -> Void)?
    private var earned = false
    private var retry = 0

    /// Whether this player gets ads at all.
    var showsAds: Bool { (AdConfig.isConfigured || AdConfig.simulated) && !Premium.shared.isPremium }

    /// Called once the app is active (the tracking prompt needs that): asks
    /// about tracking, then starts the SDK. Nothing happens for Premium.
    func start() {
        guard showsAds, AdConfig.isConfigured, !ready, !ALSdk.shared().isInitialized else { return }
        ATTrackingManager.requestTrackingAuthorization { _ in
            Task { @MainActor in self.initialise() }
        }
    }

    private func initialise() {
        let config = ALSdkInitializationConfiguration(sdkKey: AdConfig.sdkKey) { builder in
            builder.mediationProvider = ALMediationProviderMAX
        }
        ALSdk.shared().initialize(with: config) { _ in
            Task { @MainActor in
                self.ready = true
                self.loadRewarded()
            }
        }
    }

    private func loadRewarded() {
        if rewarded == nil {
            rewarded = MARewardedAd.shared(withAdUnitIdentifier: AdConfig.rewardedUnit)
            rewarded?.delegate = self
        }
        rewarded?.load()
    }

    /// Runs `action` straight away for Premium (or with ads off); otherwise
    /// after a rewarded ad is watched to the end. No ad to show (none loaded,
    /// no network) never blocks the player: the action runs anyway.
    func afterRewardedAd(_ action: @escaping () -> Void) {
        guard showsAds, ready, let rewarded, rewarded.isReady else {
            if showsAds, AdConfig.isConfigured { start(); if ready { loadRewarded() } }
            action()
            return
        }
        onReward = action
        earned = false
        rewarded.show()
    }
}

extension Ads: @preconcurrency MARewardedAdDelegate {
    func didLoad(_ ad: MAAd) { retry = 0 }

    func didFailToLoadAd(forAdUnitIdentifier adUnitIdentifier: String, withError error: MAError) {
        // AppLovin's advice: back off, up to a minute
        retry += 1
        let delay = min(64, 1 << min(retry, 6))
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            self.rewarded?.load()
        }
    }

    func didDisplay(_ ad: MAAd) {}
    func didClick(_ ad: MAAd) {}

    func didRewardUser(for ad: MAAd, with reward: MAReward) { earned = true }

    /// The scan starts once the ad has closed, so its sheets don't fight the
    /// ad's own screen.
    func didHide(_ ad: MAAd) {
        if earned { onReward?() }
        onReward = nil
        earned = false
        rewarded?.load()
    }

    func didFail(toDisplay ad: MAAd, withError error: MAError) {
        // Couldn't show it: let them scan rather than lose the tap
        onReward?()
        onReward = nil
        rewarded?.load()
    }
}

/// A standard banner, 50pt tall (90 on iPad), at the foot of a list screen.
/// Empty for Premium and until the SDK is ready.
struct AdBanner: View {
    @ObservedObject private var ads = Ads.shared
    @ObservedObject private var premium = Premium.shared
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        if ads.ready, AdConfig.isConfigured, !premium.isPremium {
            AdBannerView()
                .frame(height: sizeClass == .regular ? 90 : 50)
                .frame(maxWidth: .infinity)
                .background(Color.appBackground)
        }
    }
}

private struct AdBannerView: UIViewRepresentable {
    func makeUIView(context: Context) -> MAAdView {
        let view = MAAdView(adUnitIdentifier: AdConfig.bannerUnit)
        view.backgroundColor = .clear
        view.loadAd()
        return view
    }

    func updateUIView(_ view: MAAdView, context: Context) {}

    static func dismantleUIView(_ view: MAAdView, coordinator: ()) {
        view.stopAutoRefresh()
    }
}
