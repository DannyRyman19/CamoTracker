import AdSupport
import AppTrackingTransparency
import IronSource
import StoreKit
import SwiftUI

/// Unity LevelPlay: a banner under the Weapons, Mastery, Stats and DMZ
/// screens, now and then a full-screen ad on leaving a weapon (see
/// `Interstitials`), and a rewarded ad before each stash scan. Premium
/// players see none of them.
enum AdConfig {
    // LevelPlay dashboard: the app's key, and its Banner and Rewarded ad
    // units. Empty values switch the ads off and make scans free.
    static let appKey = "290d2170d"
    static let defaultBannerUnit = "fcdqqqb7rfkcj4ar"
    static let rewardedUnit = "gd1lxhzn6xvf29nk"

    /// Each game's own Banner and Interstitial units, so the dashboard
    /// shows what each game earns. A game without its own banner unit uses
    /// the default one; without an interstitial unit it shows none.
    static let units: [String: (banner: String, interstitial: String)] = [
        "mw4": (banner: "xkdnvyfkyx24ydzp", interstitial: "z1krvpx01jwlunnv"),
        "bo6": (banner: "fipjry0oebp367c4", interstitial: "bgxevec9c92rww69"),
        "bo7": (banner: "ptql35gzi327ljk0", interstitial: "cjumwhahmkvyqb0p"),
        "mw3": (banner: "fzh0m7bvvjd7u5rg", interstitial: "t5rixa2399wftbly"),
    ]

    /// The placement names set up in the dashboard ("weapons", "stats"...):
    /// a banner reports under its screen's once it's listed here. LevelPlay
    /// refuses a placement it doesn't know, so none are sent until then.
    static let placements: Set<String> = []

    static var bannerUnit: String {
        let own = units[GameRegistry.current.id]?.banner ?? ""
        return own.isEmpty ? defaultBannerUnit : own
    }

    static var interstitialUnit: String? {
        let own = units[GameRegistry.current.id]?.interstitial ?? ""
        return own.isEmpty ? nil : own
    }

    static func placement(_ name: String?) -> String? {
        name.flatMap { placements.contains($0) ? $0 : nil }
    }

    static var isConfigured: Bool { !appKey.isEmpty && !defaultBannerUnit.isEmpty && !rewardedUnit.isEmpty }

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

/// Consent for personalised ads where the law asks for it: GDPR in the EU
/// and EEA, UK GDPR and Swiss law. Apple's tracking question is separate (that
/// one is about the advertising ID; this one about using any personal data to
/// pick ads), so both are asked. Players elsewhere (by Region setting and App
/// Store country) never see it. The answer goes to LevelPlay and can be
/// changed under Customise.
enum AdConsent {
    static let key = "ct_ads_consent"
    private static let regions: Set<String> = [
        "AT", "BE", "BG", "HR", "CY", "CZ", "DK", "EE", "FI", "FR", "DE", "GR", "HU", "IE", "IT", "LV", "LT", "LU", "MT",
        "NL", "PL", "PT", "RO", "SK", "SI", "ES", "SE",       // the EU
        "IS", "LI", "NO",                                     // the rest of the EEA
        "GB", "CH",
    ]

    /// The same countries as App Store storefronts, which are ISO alpha-3.
    private static let storefronts: Set<String> = [
        "AUT", "BEL", "BGR", "HRV", "CYP", "CZE", "DNK", "EST", "FIN", "FRA", "DEU", "GRC", "HUN", "IRL", "ITA", "LVA",
        "LTU", "LUX", "MLT", "NLD", "POL", "PRT", "ROU", "SVK", "SVN", "ESP", "SWE",
        "ISL", "LIE", "NOR",
        "GBR", "CHE",
    ]
    /// The App Store country last read (`updateStorefront`).
    static let storefrontKey = "ct_ads_storefront"

    /// The phone's Region setting or its App Store country is on the list:
    /// a player in Germany with the Region set to the US still has a German
    /// App Store account, so is still asked.
    static var applies: Bool {
        applies(region: Locale.current.region?.identifier,
                storefront: UserDefaults.standard.string(forKey: storefrontKey))
    }

    static func applies(region: String?, storefront: String?) -> Bool {
        region.map(regions.contains) == true || storefront.map(storefronts.contains) == true
    }

    /// Reads the App Store country, which only comes asynchronously, and
    /// keeps it for `applies`. Kept as it was when there's no answer.
    static func updateStorefront() async {
        if let country = await Storefront.current?.countryCode {
            UserDefaults.standard.set(country, forKey: storefrontKey)
        }
    }

    /// nil until answered
    static var granted: Bool? { UserDefaults.standard.object(forKey: key) as? Bool }

    static var needsAsking: Bool { applies && granted == nil }

    /// Tells LevelPlay. Until there's an answer, ads in these regions are non-personalised.
    static func apply() {
        guard applies else { return }
        LevelPlay.setConsent(granted ?? false)
    }

    static func set(_ value: Bool) {
        UserDefaults.standard.set(value, forKey: key)
        apply()
    }

    /// One plain question; both answers are one tap and either keeps the app the same.
    @MainActor static func ask() async {
        guard let root = Ads.topController() else { return }
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            let alert = UIAlertController(title: "ct.ads.consent.title".localized(), message: "ct.ads.consent.message".localized(),
                                          preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "ct.ads.consent.yes".localized(), style: .default) { _ in set(true); done.resume() })
            alert.addAction(UIAlertAction(title: "ct.ads.consent.no".localized(), style: .default) { _ in set(false); done.resume() })
            root.present(alert, animated: true)
        }
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

    /// The session a player finishes onboarding in has no ad prompts and
    /// no ads: a new player was asked about notifications, ads and tracking
    /// in their first ten seconds. A session ends when the app goes to the
    /// background, so the next launch or return to the app is the second.
    static let pastFirstSessionKey = "ct_ads_past_first_session"

    /// At launch and on going to the background: a session that starts,
    /// or ends, onboarded makes the next one a later session.
    static func sessionBoundary(defaults: UserDefaults = .standard) {
        if defaults.bool(forKey: "mw4_has_onboarded") { defaults.set(true, forKey: pastFirstSessionKey) }
    }

    static func isPastFirstSession(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: pastFirstSessionKey)
    }

    /// Called once the app is active (the tracking prompt needs that): asks
    /// about ads where the law says to, then about tracking, then starts
    /// the SDK, so nothing is requested before both answers. Nothing happens
    /// for Premium, or before the player's second session (see
    /// `pastFirstSessionKey`), by when onboarding and the notification
    /// prompt are long closed.
    func start() {
        #if DEBUG
        print("[Ads] start: showsAds \(showsAds) ready \(ready) starting \(starting) onboarded \(UserDefaults.standard.bool(forKey: "mw4_has_onboarded")) premium \(Premium.shared.isPremium)")
        // Screenshot launches (SS_SCREEN) never ask: the prompt would be in the shot
        if ProcessInfo.processInfo.environment["SS_SCREEN"] != nil { return }
        #endif
        guard showsAds, AdConfig.isConfigured, !AdConfig.simulated, !ready, !starting,
              UserDefaults.standard.bool(forKey: "mw4_has_onboarded"), Self.isPastFirstSession() else { return }
        starting = true
        Task { @MainActor in
            // iOS drops the tracking request, without asking, if the app isn't
            // fully active yet, and SwiftUI reports active a moment early:
            // wait a second, and for the app itself to be active
            try? await Task.sleep(for: .seconds(1))
            for _ in 0..<20 where UIApplication.shared.applicationState != .active {
                try? await Task.sleep(for: .milliseconds(300))
            }
            // The law's question (EU, EEA, UK, Switzerland) before Apple's
            await AdConsent.updateStorefront()
            if AdConsent.needsAsking { await AdConsent.ask() }
            _ = await ATTrackingManager.requestTrackingAuthorization()
            initialise()
        }
    }

    private func initialise() {
        if AdConfig.testSuite { LevelPlay.setMetaDataWithKey("is_test_suite", value: "enable") }
        AdConsent.apply()
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
                Interstitials.shared.prepare()
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
/// above it, the ad pinned inside so it never hangs over the list, and a
/// "Remove ads" link to Premium above the ad. The ad's size comes from the
/// strip's own width (an iPad column can be narrower than the screen), so
/// it never pushes the layout wider. Empty for Premium, until the SDK is
/// ready, and until there's an ad to show: the banner loads out of sight and
/// the strip only opens once one has arrived, so no ad means no blank space.
struct AdBanner: View {
    /// The screen it's on, reported as its placement once that's set up
    var placement: String? = nil
    @ObservedObject private var ads = Ads.shared
    @ObservedObject private var premium = Premium.shared
    @State private var showsPremium = false
    @State private var width: CGFloat = 0
    @State private var loaded = false

    var body: some View {
        if ads.ready || AdConfig.simulated, !premium.isPremium {
            let size = BannerController.size(fitting: width)
            let shown = loaded || AdConfig.simulated
            VStack(spacing: 4) {
                if shown {
                    Button { showsPremium = true } label: {
                        // No ✕: beside an ad that reads as the ad's own close button
                        Label("mw4.ui.premium.remove_ads".localized(), systemImage: "sparkles")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Color.appInkMuted)
                    }
                    .buttonStyle(.plain)
                    .frame(width: CGFloat(size.width), alignment: .trailing)
                }
                Group {
                    if AdConfig.simulated {
                        // MW4_ADS=1: a stand-in the size of a real banner, for layout
                        Rectangle().fill(Color.gray.opacity(0.35)).overlay(Text(verbatim: "Test banner").font(.caption))
                    } else {
                        AdBannerView(size: size, placement: placement) { loaded = true }
                            .id(size.width)  // a new banner when the strip changes size class
                    }
                }
                .frame(width: CGFloat(size.width), height: shown ? CGFloat(size.height) : 0)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, shown ? 4 : 0)
            .padding(.bottom, shown ? 6 : 0)
            .background(shown ? Color.appBackground : Color.clear)
            .background(GeometryReader { geo in
                Color.clear
                    .onAppear { width = geo.size.width }
                    .onChange(of: geo.size.width) { width = $0 }
            })
            .overlay(alignment: .top) { Rectangle().fill(Color.appInkMuted.opacity(shown ? 0.25 : 0)).frame(height: 0.5) }
            .sheet(isPresented: $showsPremium) { PremiumView() }
        }
    }
}

/// LevelPlay loads a banner against a view controller, so the banner lives
/// in one of its own.
private struct AdBannerView: UIViewControllerRepresentable {
    let size: LPMAdSize
    let placement: String?
    let onLoaded: () -> Void
    func makeUIViewController(context: Context) -> BannerController { BannerController(size: size, placement: placement, onLoaded: onLoaded) }
    func updateUIViewController(_ controller: BannerController, context: Context) {}
    static func dismantleUIViewController(_ controller: BannerController, coordinator: ()) { controller.banner?.destroy() }
}

private final class BannerController: UIViewController, @preconcurrency LPMBannerAdViewDelegate {
    /// The leaderboard (728x90) where the strip has room for it, else the
    /// standard banner (320x50).
    static func size(fitting width: CGFloat) -> LPMAdSize {
        width >= 744 ? LPMAdSize.leaderBoard() : LPMAdSize.banner()
    }

    let size: LPMAdSize
    let placement: String?
    let onLoaded: () -> Void
    var banner: LPMBannerAdView?

    init(size: LPMAdSize, placement: String?, onLoaded: @escaping () -> Void) {
        self.size = size
        self.placement = placement
        self.onLoaded = onLoaded
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        view.clipsToBounds = true
        var builder = LPMBannerAdViewConfigBuilder().set(adSize: size)
        if let placement = AdConfig.placement(placement) { builder = builder.set(placementName: placement) }
        let config = builder.build()
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

    func didLoadAd(with adInfo: LPMAdInfo) { onLoaded() }
    func didFailToLoadAd(withAdUnitId adUnitId: String, error: Error) {}
}

/// A full-screen ad now and then, on the way back from a weapon to the
/// list: never while ticking, at most one every ten minutes, and none in a
/// player's first two days. Only for games with an interstitial unit.
@MainActor
final class Interstitials: NSObject, @preconcurrency LPMInterstitialAdDelegate {
    static let shared = Interstitials()

    private static let lastShownKey = "ct_ads_interstitial_last"
    private static let firstSeenKey = "ct_ads_first_seen"
    private static let gap: TimeInterval = 10 * 60
    private static let grace: TimeInterval = 2 * 24 * 60 * 60

    private var ad: LPMInterstitialAd?
    private var unit: String?
    private var retry = 0
    /// A weapon was open: the next list screen to appear is the way back
    var leftWeapon = false

    /// Loads the current game's ad, a new one when the game changed.
    func prepare() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: Self.firstSeenKey) == nil { defaults.set(Date(), forKey: Self.firstSeenKey) }
        guard Ads.shared.ready, let wanted = AdConfig.interstitialUnit else { ad = nil; unit = nil; return }
        if unit != wanted || ad == nil {
            let ad = LPMInterstitialAd(adUnitId: wanted)
            ad.setDelegate(self)
            self.ad = ad
            unit = wanted
            retry = 0
        }
        if ad?.isAdReady() != true { ad?.loadAd() }
    }

    /// Back on a list from a weapon: shows one if it's due.
    func weaponClosed() {
        guard leftWeapon else { return }
        leftWeapon = false
        let defaults = UserDefaults.standard
        guard Ads.shared.showsAds, !AdConfig.simulated else { return }
        prepare()
        let now = Date()
        if let first = defaults.object(forKey: Self.firstSeenKey) as? Date, now.timeIntervalSince(first) < Self.grace { return }
        if let last = defaults.object(forKey: Self.lastShownKey) as? Date, now.timeIntervalSince(last) < Self.gap { return }
        guard let ad, ad.isAdReady() else { return }
        Task { @MainActor in
            // After the list has finished sliding back in
            try? await Task.sleep(for: .milliseconds(450))
            guard let root = Ads.topController() else { return }
            defaults.set(Date(), forKey: Self.lastShownKey)
            ad.showAd(viewController: root, placementName: AdConfig.placement("weapon_exit"))
        }
    }

    func didLoadAd(with adInfo: LPMAdInfo) { retry = 0 }

    func didFailToLoadAd(withAdUnitId adUnitId: String, error: Error) {
        retry += 1
        let delay = min(64, 1 << min(retry, 6))
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            self.ad?.loadAd()
        }
    }

    func didDisplayAd(with adInfo: LPMAdInfo) {}
    func didCloseAd(with adInfo: LPMAdInfo) { ad?.loadAd() }
    func didFailToDisplayAd(with adInfo: LPMAdInfo, error: Error) { ad?.loadAd() }
}
