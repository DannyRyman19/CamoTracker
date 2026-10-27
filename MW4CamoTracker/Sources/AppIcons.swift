import SwiftUI

/// The unlockable home-screen icons: the usual icon recoloured in a camo's
/// own colours (drawn by `tools-mw4-icon.py variants`). Earn the camo and its
/// icon unlocks; Gold's is free, the rest come with Premium too.
enum AppIconChoice: String, CaseIterable, Identifiable {
    case standard
    case gold, platinum, harmonicBreak, divergence
    case mercurialDrift, polyatomicReforged, orionReforged
    case parallax, damascusReforged, empyros
    case chiral, rippleTide, helio

    var id: String { rawValue }

    /// The alternate icon's asset name; nil for the usual icon.
    var iconName: String? {
        switch self {
        case .standard: return nil
        default: return "AppIcon-" + rawValue.prefix(1).uppercased() + rawValue.dropFirst()
        }
    }

    var previewName: String { (iconName ?? "AppIcon") + "-Preview" }

    /// Gold is the free one.
    var needsPremium: Bool { self != .standard && self != .gold }

    /// Which Completionist step (0 Gold … 3 the final camo) this is, if any.
    private var step: Int? {
        switch self {
        case .gold: return 0
        case .platinum: return 1
        case .harmonicBreak: return 2
        case .divergence: return 3
        default: return nil
        }
    }

    /// Which mode's Mastery tier this is, if any.
    private var mastery: (mode: AppMode, tier: Int)? {
        switch self {
        case .mercurialDrift: return (.multiplayer, 1)
        case .polyatomicReforged: return (.multiplayer, 2)
        case .orionReforged: return (.multiplayer, 3)
        case .parallax: return (.warzone, 1)
        case .damascusReforged: return (.warzone, 2)
        case .empyros: return (.warzone, 3)
        case .chiral: return (.dmz, 1)
        case .rippleTide: return (.dmz, 2)
        case .helio: return (.dmz, 3)
        default: return nil
        }
    }

    /// The camo's name, as the rest of the app shows it.
    var title: String {
        if let step {
            let camos = AppMode.multiplayer.completionist
            return step < camos.steps.count ? camos.steps[step].name : camos.final.name
        }
        if let (mode, tier) = mastery {
            let camos = mode.masteryCamos
            return [camos.tier1, camos.tier2, camos.tier3][tier - 1].name
        }
        return "mw4.ui.app_icon.standard".localized()
    }

    /// What earns it, for a locked one.
    var requirement: String {
        if step != nil { return String(format: "mw4.ui.app_icon.need_weapon".localized(), title) }
        if let (mode, _) = mastery {
            return String(format: "mw4.ui.app_icon.need_mode".localized(), title, mode.displayNameKey.localized())
        }
        return ""
    }

    /// Earned: the camo on any weapon in any mode, or that mode's Mastery tier.
    @MainActor
    func isEarned(_ viewModel: TrackerViewModel) -> Bool {
        if let step {
            return AppMode.allCases.contains { mode in
                step < mode.completionist.steps.count
                    ? viewModel.completionistCount(mode: mode.rawValue, step: step) > 0
                    : mode.hasFinalCamo && viewModel.finalCamoCount(mode: mode.rawValue) > 0
            }
        }
        if let (mode, tier) = mastery { return viewModel.isMasteryAchieved(mode: mode.rawValue, tier: tier) }
        return true
    }

    static var current: AppIconChoice {
        let name = UIApplication.shared.alternateIconName
        return allCases.first { $0.iconName == name } ?? .standard
    }
}

/// Customise > App icon: every icon, the earned ones to pick from, the rest
/// showing what unlocks them.
struct AppIconPicker: View {
    @EnvironmentObject private var viewModel: TrackerViewModel
    @ObservedObject private var premium = Premium.shared
    @State private var current = AppIconChoice.current
    @State private var showsPremium = false
    let accent: Color

    private let columns = [GridItem(.adaptive(minimum: 92), spacing: 14)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("mw4.ui.app_icon.footer".localized())
                    .font(.footnote)
                    .foregroundStyle(Color.appInkMuted)
                LazyVGrid(columns: columns, spacing: 18) {
                    ForEach(AppIconChoice.allCases) { choice in
                        cell(choice)
                    }
                }
            }
            .padding(16)
        }
        .background(Color.appBackground.ignoresSafeArea())
        .navigationTitle("mw4.ui.app_icon.title".localized())
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showsPremium) { PremiumView() }
    }

    private func cell(_ choice: AppIconChoice) -> some View {
        let earned = choice.isEarned(viewModel)
        let needsPremium = earned && choice.needsPremium && !premium.isPremium
        let selected = choice == current
        return Button {
            if !earned { return }
            if needsPremium { showsPremium = true; return }
            pick(choice)
        } label: {
            VStack(spacing: 6) {
                Image(choice.previewName)
                    .resizable()
                    .aspectRatio(1, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    // Locked ones keep their colours, dimmed: the goal is the point
                    .opacity(earned ? 1 : 0.5)
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(selected ? accent : Color.white.opacity(0.08), lineWidth: selected ? 3 : 1)
                    }
                    .overlay(alignment: .topTrailing) {
                        if !earned || needsPremium {
                            Image(systemName: earned ? "sparkles" : "lock.fill")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(6)
                                .background(Circle().fill(earned ? accent : Color.black.opacity(0.6)))
                                .padding(5)
                        }
                    }
                Text(choice.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(earned ? Color.appInk : Color.appInkMuted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(earned ? (needsPremium ? "mw4.ui.app_icon.premium".localized() : " ") : choice.requirement)
                    .font(.caption2)
                    .foregroundStyle(Color.appInkMuted)
                    .multilineTextAlignment(.center)
                    .lineLimit(2, reservesSpace: true)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(choice.title)
        .accessibilityValue(selected ? "mw4.ui.app_icon.in_use".localized() : (earned ? "" : choice.requirement))
    }

    private func pick(_ choice: AppIconChoice) {
        guard choice != current, UIApplication.shared.supportsAlternateIcons else { return }
        Haptics.step()
        UIApplication.shared.setAlternateIconName(choice.iconName) { error in
            if error == nil { Task { @MainActor in current = choice } }
        }
    }
}
