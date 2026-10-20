import SwiftUI

/// Mastery, the one part of the grind that's per mode: every mode you play,
/// one under the other, each with its three Mastery camos to tick and count.
struct MasteryTabView: View {
    @EnvironmentObject private var viewModel: TrackerViewModel
    /// The mode picked in the Weapons title goes first.
    @AppStorage("mw4.primaryMode") private var primaryModeRaw = AppMode.multiplayer.rawValue

    private var ordered: [AppMode] {
        let modes = viewModel.visibleModes
        guard let first = modes.first(where: { $0.rawValue == primaryModeRaw }) else { return modes }
        return [first] + modes.filter { $0 != first }
    }

    var body: some View {
        ZStack {
            AppBackground(accent: ordered.first?.accent ?? .accentMultiplayer)
            List {
                ForEach(ordered) { mode in
                    Section {
                        ForEach(1...3, id: \.self) { tier in
                            row(mode: mode, tier: tier)
                        }
                    } header: {
                        Label(mode.displayNameKey.localized(), systemImage: mode.symbol)
                            .foregroundStyle(mode.accent)
                    }
                    .listRowBackground(Color.appSurface)
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("mw4.ui.section.mastery".localized())
    }

    /// A mode-wide challenge to tick and count (any weapon counts; the
    /// weapon only names the milestone), else the read-only status.
    @ViewBuilder private func row(mode: AppMode, tier: Int) -> some View {
        if viewModel.masteryKind(mode: mode.rawValue, tier: tier) == .mode, let weapon = viewModel.allWeapons.first {
            MasteryModeChallengeRow(mode: mode, weapon: weapon, tier: tier)
        } else {
            MasteryModeRow(mode: mode, tier: tier)
        }
    }
}
