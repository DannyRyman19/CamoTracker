import AdSupport
import AppTrackingTransparency
import IronSource
import SwiftUI

/// Unity LevelPlay: a banner under the Weapons and DMZ lists, and a
/// rewarded ad before each stash scan. Premium players see neither.
enum AdConfig {
    // LevelPlay dashboard: the app's key, and its Banner and Rewarded ad
    // units. Empty values switch the ads off and make scans free.
    static let appKey = "290d2170d"
    static let bannerUnit = "fcdqqqb7rfkcj4ar"
    static let rewardedUnit = "gd1lxhzn6xvf29nk"

    static var isConfigured: Bool { !appKey.isEmpty && !bannerUnit.isEmpty && !rewardedUnit.isEmpty }

    /// `MW4_ADS=1` (DEBUG) acts as a free player with ads on, without
    /// starting the SDK: the scan asks first, and with no ad goes straight on.
    static var simulated: Bool {
        #if DEBUG
        ProcessInfo.processInfo.environment["MW4_ADS"] == "1"
        #else
        false
        #endif
    }

    /// `MW4_AD_TEST_SUITE=1` (DEBUG) opens LevelPlay's test suite once the
    /// SDK is up, to check each network serves an ad.
    static var testSuite: Bool {
        #if DEBUG
        ProcessInfo.processInfo.environment["MW4_AD_TEST_SUITE"] == "1"
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

    private var starting = false
    private var rewarded: LPMRewardedAd?
    private var onReward: (() -> Void)?
    private var onUnavailable: (() -> Void)?
    private var earned = false
    private var closed = false
    private var retry = 0

    /// Whether this player gets ads at all.
    var showsAds: Bool { (AdConfig.isConfigured || AdConfig.simulated) && !Premium.shared.isPremium }

    /// Called once the app is active (the tracking prompt needs that): asks
    /// about tracking, then starts the SDK. Nothing happens for Premium, or
    /// before onboarding is done: the next time the app is active after it
    /// (once the notification prompt has closed), so the prompts never stack.
    func start() {
        #if DEBUG
        print("[Ads] start: showsAds \(showsAds) ready \(ready) starting \(starting) onboarded \(UserDefaults.standard.bool(forKey: "mw4_has_onboarded")) premium \(Premium.shared.isPremium)")
        #endif
        guard showsAds, AdConfig.isConfigured, !AdConfig.simulated, !ready, !starting,
              UserDefaults.standard.bool(forKey: "mw4_has_onboarded") else { return }
        starting = true
        Task { @MainActor in
            // iOS drops the tracking request, without asking, if the app isn't
            // fully active yet, and SwiftUI reports active a moment early:
            // wait a second, and for the app itself to be active
            try? await Task.sleep(for: .seconds(1))
            for _ in 0..<20 where UIApplication.shared.applicationState != .active {
                try? await Task.sleep(for: .milliseconds(300))
            }
            _ = await ATTrackingManager.requestTrackingAuthorization()
            initialise()
        }
    }

    private func initialise() {
        if AdConfig.testSuite { LevelPlay.setMetaDataWithKey("is_test_suite", value: "enable") }
        let request = LPMInitRequestBuilder(appKey: AdConfig.appKey).build()
        LevelPlay.initWith(request) { _, error in
            Task { @MainActor in
                self.starting = false
                #if DEBUG
                print("[Ads] LevelPlay init: \(error.map { "failed \($0)" } ?? "ok")")
                // For LevelPlay's test devices (all zeros unless tracking is allowed)
                print("[Ads] IDFA \(ASIdentifierManager.shared().advertisingIdentifier.uuidString) tracking \(ATTrackingManager.trackingAuthorizationStatus.rawValue)")
                #endif
                guard error == nil else { return }  // tried again next time the app is opened
                self.ready = true
                self.loadRewarded()
                if AdConfig.testSuite {
                    // Logs whether each network's SDK and adapter are wired up
                    LevelPlay.validateIntegration()
                    // After the splash, which would otherwise cover it
                    try? await Task.sleep(for: .seconds(4))
                    let root = Self.topController()
                    #if DEBUG
                    print("[Ads] test suite over \(root.map { String(describing: type(of: $0)) } ?? "nothing")")
                    #endif
                    if let root { LevelPlay.launchTestSuite(root) }
                }
            }
        }
    }

    private func loadRewarded() {
        if rewarded == nil {
            let ad = LPMRewardedAd(adUnitId: AdConfig.rewardedUnit)
            ad.setDelegate(self)
            rewarded = ad
        }
        rewarded?.loadAd()
    }

    /// Runs `action` straight away for Premium (or with ads off); otherwise
    /// after a rewarded ad is watched to the end. No ad to show (none loaded,
    /// no network): one a day runs anyway, after that `unavailable`.
    func afterRewardedAd(_ action: @escaping () -> Void, unavailable: @escaping () -> Void) {
        guard showsAds else { action(); return }
        guard ready, let rewarded, rewarded.isAdReady(), let root = Self.topController() else {
            if ready { loadRewarded() } else { start() }
            withoutAd(action, unavailable: unavailable)
            return
        }
        onReward = action
        onUnavailable = unavailable
        earned = false
        closed = false
        rewarded.showAd(viewController: root, placementName: nil)
    }

    /// No ad to show: one scan a day goes ahead anyway, so a bad connection
    /// doesn't lock anyone out, but going offline isn't a way round the ads.
    private static let freeDayKey = "mw4_ads_free_scan_day"
    private func withoutAd(_ action: () -> Void, unavailable: () -> Void) {
        let today = Calendar.current.startOfDay(for: Date()).timeIntervalSince1970
        if UserDefaults.standard.double(forKey: Self.freeDayKey) != today {
            UserDefaults.standard.set(today, forKey: Self.freeDayKey)
            action()
        } else {
            unavailable()
        }
    }

    /// The reward and the close arrive in either order; the scan starts once
    /// both have, so its sheets don't fight the ad's own screen.
    private func finishIfDone() {
        guard closed else { return }
        if earned { onReward?() }
        onReward = nil
        onUnavailable = nil
        earned = false
        closed = false
        rewarded?.loadAd()
    }

    /// What to present the ad over: the frontmost screen.
    static func topController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        var top = scene?.windows.first { $0.isKeyWindow }?.rootViewController
        while let next = top?.presentedViewController { top = next }
        return top
    }
}

extension Ads: @preconcurrency LPMRewardedAdDelegate {
    func didLoadAd(with adInfo: LPMAdInfo) { retry = 0 }

    func didFailToLoadAd(withAdUnitId adUnitId: String, error: Error) {
        // Back off, up to a minute, then try again
        retry += 1
        let delay = min(64, 1 << min(retry, 6))
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            self.rewarded?.loadAd()
        }
    }

    func didDisplayAd(with adInfo: LPMAdInfo) {}

    func didRewardAd(with adInfo: LPMAdInfo, reward: LPMReward) {
        earned = true
        finishIfDone()
    }

    func didCloseAd(with adInfo: LPMAdInfo) {
        closed = true
        // The reward can land just after the close: give it a moment
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            self.finishIfDone()
        }
    }

    func didFailToDisplayAd(with adInfo: LPMAdInfo, error: Error) {
        // Couldn't show it: the same as no ad at all
        if let action = onReward, let unavailable = onUnavailable { withoutAd(action, unavailable: unavailable) }
        onReward = nil
        onUnavailable = nil
        rewarded?.loadAd()
    }
}

/// A banner at the foot of a list screen: a solid strip with a hairline
/// above it, the ad pinned inside so it never hangs over the list. Empty
/// for Premium and until the SDK is ready.
struct AdBanner: View {
    @ObservedObject private var ads = Ads.shared
    @ObservedObject private var premium = Premium.shared

    var body: some View {
        if ads.ready, !premium.isPremium {
            let size = BannerController.size
            AdBannerView()
                .frame(width: CGFloat(size.width), height: CGFloat(size.height))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(Color.appBackground)
                .overlay(alignment: .top) { Rectangle().fill(Color.appInkMuted.opacity(0.25)).frame(height: 0.5) }
        }
    }
}

/// LevelPlay loads a banner against a view controller, so the banner lives
/// in one of its own.
private struct AdBannerView: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> BannerController { BannerController() }
    func updateUIViewController(_ controller: BannerController, context: Context) {}
    static func dismantleUIViewController(_ controller: BannerController, coordinator: ()) { controller.banner?.destroy() }
}

private final class BannerController: UIViewController, @preconcurrency LPMBannerAdViewDelegate {
    /// Banner on iPhone, leaderboard on iPad; worked out once so the strip
    /// and the ad agree on it.
    static let size: LPMAdSize = LPMAdSize.createAdaptive() ?? LPMAdSize.banner()

    var banner: LPMBannerAdView?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        view.clipsToBounds = true
        let size = Self.size
        let config = LPMBannerAdViewConfigBuilder().set(adSize: size).build()
        let banner = LPMBannerAdView(adUnitId: AdConfig.bannerUnit, config: config)
        banner.setDelegate(self)
        banner.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(banner)
        NSLayoutConstraint.activate([
            banner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            banner.topAnchor.constraint(equalTo: view.topAnchor),
            banner.widthAnchor.constraint(equalToConstant: CGFloat(size.width)),
            banner.heightAnchor.constraint(equalToConstant: CGFloat(size.height)),
        ])
        banner.loadAd(with: self)
        self.banner = banner
    }

    func didLoadAd(with adInfo: LPMAdInfo) {}
    func didFailToLoadAd(withAdUnitId adUnitId: String, error: Error) {}
}
