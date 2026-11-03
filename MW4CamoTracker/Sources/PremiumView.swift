import StoreKit
import SwiftUI

/// The Premium sheet: what it gets you, the yearly and lifetime options,
/// restore, and the links the App Store asks for beside a subscription.
/// A Premium player gets their plan, the thanks and Manage Subscription
/// instead of the pitch.
struct PremiumView: View {
    @ObservedObject private var premium = Premium.shared
    @Environment(\.dismiss) private var dismiss
    @State private var restoring = false
    @State private var width: CGFloat = 0
    /// How a purchase or restore went (see `Premium.Notice`).
    @State private var notice: Premium.Notice?
    @State private var showsManage = false

    var body: some View {
        NavigationStack {
            ScrollView {
                Group {
                    // iPad: what you get on the left, the options on the right
                    if width >= 600 {
                        HStack(alignment: .top, spacing: 32) {
                            VStack(alignment: .leading, spacing: 20) { header; perks }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            VStack(alignment: .leading, spacing: 20) { purchase }
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxWidth: 820)
                        .padding(.vertical, 12)
                    } else {
                        VStack(alignment: .leading, spacing: 20) { header; perks; purchase }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(20)
            }
            .readingWidth($width)
            .background(Color.appBackground.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("mw4.ui.done".localized()) { dismiss() }
                }
            }
            .task { await premium.loadProducts() }
            // Premium's on: OK closes the sheet behind the message
            .premiumNotice($notice) { dismiss() }
            .manageSubscriptionsSheet(isPresented: $showsManage)
        }
        .presentationDetents([.large])
        .wideSheetOnPad()
        .appSheetBackground()
    }

    @ViewBuilder private var header: some View {
        if premium.isPremium {
            // Thanked and told their plan, not sold to
            VStack(alignment: .leading, spacing: 8) {
                Text("ct.premium.you_have".localized())
                    .hitmarkerFont(26)
                    .foregroundStyle(Color.appInk)
                Label(PremiumPlan.line(for: premium.plan), systemImage: "checkmark.seal.fill")
                    .font(.headline)
                    .foregroundStyle(Color.accentDMZText)
                Text("ct.premium.thanks".localized())
                    .font(.subheadline)
                    .foregroundStyle(Color.appInkMuted)
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("mw4.ui.premium.title".localized())
                    .hitmarkerFont(26)
                    .foregroundStyle(Color.appInk)
                Text("mw4.ui.premium.subtitle".localized())
                    .font(.subheadline)
                    .foregroundStyle(Color.appInkMuted)
            }
        }
    }

    private var perks: some View {
        VStack(alignment: .leading, spacing: 12) {
            perk("nosign", "mw4.ui.premium.perk_ads")
            perk("camera.viewfinder", "mw4.ui.premium.perk_scans")
            perk("app.badge.fill", "mw4.ui.premium.perk_icons")
            perk("slider.horizontal.3", "mw4.ui.premium.perk_customise")
            perk("icloud.fill", "mw4.ui.premium.perk_sync")
            perk("pin.fill", "mw4.ui.premium.perk_pins")
            perk("heart.fill", "mw4.ui.premium.perk_support")
        }
    }

    /// The options (or Premium's on), restore and the legal links.
    @ViewBuilder private var purchase: some View {
        if premium.isPremium {
            // Lifetime never renews, so there's nothing to manage
            if premium.isSubscriber {
                Button { showsManage = true } label: {
                    Text("ct.premium.manage".localized())
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .borderedCard()
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentDMZText)
                .accessibilityIdentifier("premium.manage")
            }
            #if DEBUG
            if premium.hasFakePurchase {
                Button("Reset test purchase (debug)") { Task { await premium.resetFakePurchase() } }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.accentDMZText)
                    .frame(maxWidth: .infinity)
            }
            #endif
        } else if (premium.products.isEmpty && premium.loadProblem != nil && fakeStore) || reviewShot {
            #if DEBUG
            fakeButton(yearly: true)
            fakeButton(yearly: false)
            if !Self.reviewShot {
                Text(verbatim: "Debug build: test purchases, nothing is charged.")
                    .font(.caption2)
                    .foregroundStyle(Color.appInkMuted)
                    .frame(maxWidth: .infinity)
            }
            #endif
        } else if premium.products.isEmpty, let problem = premium.loadProblem {
            VStack(spacing: 10) {
                // Offline, or the App Store answered without them: only the
                // first is the player's connection
                Text((problem == .unreachable ? "mw4.ui.premium.load_failed" : "ct.premium.unavailable").localized())
                    .font(.subheadline)
                    .foregroundStyle(Color.appInkMuted)
                    .multilineTextAlignment(.center)
                Button("mw4.ui.premium.retry".localized()) {
                    Task { await premium.loadProducts() }
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.accentDMZText)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .borderedCard()
        } else if premium.products.isEmpty {
            ProgressView().frame(maxWidth: .infinity).padding(.vertical, 20)
        } else {
            ForEach(premium.products, id: \.id) { product in
                productButton(product)
            }
        }

        Button {
            restoring = true
            Task { notice = await premium.restore(); restoring = false }
        } label: {
            HStack(spacing: 6) {
                if restoring { ProgressView() }
                Text("mw4.ui.premium.restore".localized())
            }
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity)
        }
        .foregroundStyle(Color.accentDMZText)
        .disabled(restoring)

        if !premium.isPremium {
            legal
        }
    }

    /// The renewal terms and links the App Store asks for beside a
    /// subscription on sale.
    private var legal: some View {
        VStack(spacing: 6) {
            Text("mw4.ui.premium.legal".localized())
                .font(.caption2)
                .foregroundStyle(Color.appInkMuted)
                .multilineTextAlignment(.center)
            HStack(spacing: 16) {
                Link("mw4.ui.premium.terms".localized(), destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
                Link("mw4.ui.premium.privacy".localized(), destination: URL(string: "https://camotracker.djr.li/privacy-policy")!)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.appInkMuted)
        }
        .frame(maxWidth: .infinity)
    }

    /// SS_REVIEW_SHOT=1 (DEBUG): both purchases at the UK prices, whatever
    /// the App Store returned, for App Review's purchase screenshot.
    private var reviewShot: Bool {
        #if DEBUG
        Self.reviewShot
        #else
        false
        #endif
    }

    private var fakeStore: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }

    #if DEBUG
    /// `SS_REVIEW_SHOT=1`: the test prices without "(test)", for App Review's
    /// purchase screenshot.
    static let reviewShot = ProcessInfo.processInfo.environment["SS_REVIEW_SHOT"] == "1"

    /// A stand-in for a product the App Store didn't return, in the same look.
    private func fakeButton(yearly: Bool) -> some View {
        Button {
            Task { await premium.fakeBuy(); dismiss() }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text((yearly ? "mw4.ui.premium.yearly" : "mw4.ui.premium.lifetime").localized()).font(.headline)
                    Text((yearly ? "mw4.ui.premium.yearly_hint" : "mw4.ui.premium.lifetime_hint").localized()).font(.caption).opacity(0.8)
                }
                Spacer()
                Text((yearly ? "£1.99" + "mw4.ui.premium.per_year".localized() : "£7.99") + (Self.reviewShot ? "" : " (test)"))
                    .scaledFont(16, weight: .bold, design: .monospaced)
            }
            .foregroundStyle(yearly ? Color.white : Color.appInk)
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 12).fill(yearly ? Color.accentDMZ : Color.appSurface))
        }
        .buttonStyle(.plain)
        .disabled(premium.purchasing)
    }
    #endif

    private func perk(_ symbol: String, _ key: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(Circle().fill(Color.accentDMZ))
            Text(key.localized())
                .font(.subheadline)
                .foregroundStyle(Color.appInk)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func productButton(_ product: Product) -> some View {
        let yearly = product.id == Premium.yearlyID
        return Button {
            Task { notice = await premium.buy(product) }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text((yearly ? "mw4.ui.premium.yearly" : "mw4.ui.premium.lifetime").localized())
                        .font(.headline)
                    Text((yearly ? "mw4.ui.premium.yearly_hint" : "mw4.ui.premium.lifetime_hint").localized())
                        .font(.caption)
                        .opacity(0.8)
                }
                Spacer()
                // A subscription's price always says what it's per
                Text(yearly ? product.displayPrice + "mw4.ui.premium.per_year".localized() : product.displayPrice)
                    .scaledFont(16, weight: .bold, design: .monospaced)
            }
            .foregroundStyle(yearly ? Color.white : Color.appInk)
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(yearly ? Color.accentDMZ : Color.appSurface)
            )
        }
        .buttonStyle(.plain)
        .disabled(premium.purchasing)
    }
}

extension View {
    /// iPad: a page-sized sheet, with room for two columns, where the OS
    /// can (18 and up); a form sheet before that.
    @ViewBuilder func wideSheetOnPad() -> some View {
        if #available(iOS 18, *) {
            presentationSizing(.page)
        } else {
            self
        }
    }

    /// The whole sheet in the app's background rather than iOS's glass,
    /// where the OS can (16.4 and up).
    @ViewBuilder func appSheetBackground() -> some View {
        if #available(iOS 16.4, *) {
            presentationBackground(Color.appBackground)
        } else {
            self
        }
    }
}
