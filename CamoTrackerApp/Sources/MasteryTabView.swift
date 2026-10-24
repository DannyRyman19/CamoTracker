import SwiftUI

/// Mastery, the one part of the grind that's per mode: every mode you play,
/// one under the other, each with its three Mastery camos to tick and count.
struct MasteryTabView: View {
    @EnvironmentObject private var viewModel: TrackerViewModel
    /// The mode picked in the Weapons title goes first.
    @AppStorage("mw4.primaryMode") private var primaryModeRaw = AppMode.multiplayer.rawValue
    /// Beside the weapons on the iPad home: no background or title of its
    /// own, a heading instead.
    var embedded = false

    private var ordered: [AppMode] {
        let modes = viewModel.visibleModes
        guard let first = modes.first(where: { $0.rawValue == primaryModeRaw }) else { return modes }
        return [first] + modes.filter { $0 != first }
    }

    var body: some View {
        if embedded {
            // The home's own background, so the column reads as part of it
            ZStack {
                AppBackground(accent: ordered.first?.accent ?? .accentMultiplayer)
                list
            }
        } else {
            ZStack {
                AppBackground(accent: ordered.first?.accent ?? .accentMultiplayer)
                list
            }
            .navigationTitle("mw4.ui.section.mastery".localized())
        }
    }

    private var list: some View {
            List {
                if embedded {
                    Text("mw4.ui.section.mastery".localized())
                        .font(.hitmarker(22))
                        .foregroundStyle(Color.appInk)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
                ForEach(ordered) { mode in
                    Section {
                        ForEach(1...3, id: \.self) { tier in
                            row(mode: mode, tier: tier)
                        }
                    } header: {
                        Label(mode.displayName, systemImage: mode.symbol)
                            .foregroundStyle(mode.accent)
                    }
                    .listRowBackground(Color.appSurface)
                }
            }
            .scrollContentBackground(.hidden)
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
