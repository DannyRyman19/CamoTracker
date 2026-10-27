import StoreKit
import SwiftUI

/// The Premium sheet: what it gets you, the yearly and lifetime options,
/// restore, and the links the App Store asks for beside a subscription.
struct PremiumView: View {
    @ObservedObject private var premium = Premium.shared
    @Environment(\.dismiss) private var dismiss
    @State private var restoring = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("mw4.ui.premium.title".localized())
                            .font(.hitmarker(26))
                            .foregroundStyle(Color.appInk)
                        Text("mw4.ui.premium.subtitle".localized())
                            .font(.subheadline)
                            .foregroundStyle(Color.appInkMuted)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        perk("nosign", "mw4.ui.premium.perk_ads")
                        perk("camera.viewfinder", "mw4.ui.premium.perk_scans")
                        perk("app.badge.fill", "mw4.ui.premium.perk_icons")
                        perk("slider.horizontal.3", "mw4.ui.premium.perk_customise")
                        perk("heart.fill", "mw4.ui.premium.perk_support")
                    }

                    if premium.isPremium {
                        Label("mw4.ui.premium.active".localized(), systemImage: "checkmark.seal.fill")
                            .font(.headline)
                            .foregroundStyle(Color.accentDMZ)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .borderedCard()
                    } else if premium.products.isEmpty, premium.loadFailed {
                        VStack(spacing: 10) {
                            Text("mw4.ui.premium.load_failed".localized())
                                .font(.subheadline)
                                .foregroundStyle(Color.appInkMuted)
                                .multilineTextAlignment(.center)
                            Button("mw4.ui.premium.retry".localized()) {
                                Task { await premium.loadProducts() }
                            }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.accentDMZ)
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
                        Task { await premium.restore(); restoring = false }
                    } label: {
                        HStack(spacing: 6) {
                            if restoring { ProgressView() }
                            Text("mw4.ui.premium.restore".localized())
                        }
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                    }
                    .foregroundStyle(Color.accentDMZ)
                    .disabled(restoring)

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
                .padding(20)
            }
            .background(Color.appBackground.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("mw4.ui.done".localized()) { dismiss() }
                }
            }
            .task { await premium.loadProducts() }
        }
        .presentationDetents([.large])
    }

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
        }
    }

    private func productButton(_ product: Product) -> some View {
        let yearly = product.id == Premium.yearlyID
        return Button {
            Task { if await premium.buy(product) { dismiss() } }
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
                Text(product.displayPrice)
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
            }
            .foregroundStyle(yearly ? Color.black.opacity(0.85) : Color.appInk)
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
