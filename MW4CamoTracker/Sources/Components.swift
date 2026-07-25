import SwiftUI

extension String {
    /// Looks up static app chrome (tab names, button labels, onboarding copy)
    /// in the bundled `Localizable.strings`. Content that arrives over the air
    /// — weapon names, camo text, DMZ objectives — uses `LocalizedText`
    /// instead (see Models.swift), since a bundle key can't resolve until the
    /// next app update ships a matching entry.
    func localized() -> String {
        NSLocalizedString(self, bundle: .main, comment: "")
    }
}

struct ProgressBar: View {
    let fraction: Double
    let accent: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.appSurface2)
                Capsule().fill(accent).frame(width: max(0, geo.size.width * min(fraction, 1)))
            }
        }
        .frame(height: 4)
    }
}

/// One row, two ways to log progress — shared by camo challenges and DMZ
/// objectives so both work identically:
/// - tap the circle to instantly mark it done/not done
/// - tap the "N / required" pill to type an exact amount (for challenges
///   where you're partway through a large number, e.g. 120 of 200 kills)
struct ChallengeRow: View {
    let item: ChallengeItem
    let accent: Color
    let amount: Int
    let isDone: Bool
    let onToggle: () -> Void
    let onSetAmount: (Int) -> Void

    @State private var showAmountEntry = false
    @State private var amountText = ""

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onToggle) {
                Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 21))
                    .foregroundStyle(isDone ? accent : Color.appInkMuted)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.name.resolved())
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.appInk)
                if let requirement = item.requirement {
                    Text(requirement.description.resolved())
                        .font(.system(size: 13))
                        .foregroundStyle(Color.appInkMuted)
                }
            }

            Spacer(minLength: 8)

            if let requirement = item.requirement, requirement.amount > 1 {
                Button {
                    amountText = "\(amount)"
                    showAmountEntry = true
                } label: {
                    Text("\(amount)/\(requirement.amount)")
                        .font(.system(size: 12.5, design: .monospaced))
                        .foregroundStyle(Color.appInkMuted)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color.appSurface2))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 5)
        .alert("mw4.ui.set_amount.title".localized(), isPresented: $showAmountEntry) {
            TextField("mw4.ui.set_amount.field".localized(), text: $amountText)
                .keyboardType(.numberPad)
            Button("mw4.ui.cancel".localized(), role: .cancel) {}
            Button("mw4.ui.save".localized()) {
                if let value = Int(amountText) { onSetAmount(value) }
            }
        } message: {
            if let requirement = item.requirement {
                Text(String(format: "mw4.ui.set_amount.message".localized(), requirement.amount))
            }
        }
    }
}

/// A transient top banner for a Gold/Diamond crossing (see `Suggestions.swift`).
struct MilestoneBannerView: View {
    let banner: MilestoneBanner

    var body: some View {
        VStack(spacing: 2) {
            Text(banner.title)
                .font(.hitmarker(16))
            Text(banner.subtitle)
                .font(.system(size: 12.5))
                .foregroundStyle(Color.appInkMuted)
        }
        .foregroundStyle(Color.appInk)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.appSurface2))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.camoGold.opacity(0.4)))
        .padding(.horizontal, 24)
        .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
    }
}
