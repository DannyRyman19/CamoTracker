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
                if !GameRegistry.hasMastery {
                    // Black Ops: the game-wide camos first, then each mode's
                    // four Mastery camos counted across its weapons
                    if GameRegistry.current.capstone != nil || viewModel.prestigeCamos.contains(where: { $0.weaponsNeeded != nil }) {
                        GameCamosCard()
                            .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                            .listRowBackground(Color.clear)
                    }
                }
                ForEach(ordered) { mode in
                    Section {
                        if GameRegistry.hasMastery {
                            ForEach(1...3, id: \.self) { tier in
                                row(mode: mode, tier: tier)
                            }
                        } else {
                            TrackCamoRows(mode: mode)
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

/// A Black Ops mode's Mastery camos (Gold to Dark Matter, Shattered Gold
/// to Singularity) as the game counts them: weapons with each, out of the
/// launch roster, then 100%+ over every weapon once that's done.
private struct TrackCamoRows: View {
    let mode: AppMode
    @EnvironmentObject private var viewModel: TrackerViewModel

    var body: some View {
        let camos = mode.completionistCamos
        ForEach(camos.indices, id: \.self) { index in
            let camo = camos[index]
            let count = index < TrackerViewModel.completionistStepCount
                ? viewModel.completionistCount(mode: mode.rawValue, step: index)
                : viewModel.finalCamoCount(mode: mode.rawValue)
            let progress = viewModel.launchProgress(count)
            row(name: camo.name, colors: camo.gradient, imageURL: camo.imageURL, done: progress.done, total: progress.total)
        }
        let full = viewModel.fullRosterFinalProgress(mode: mode.rawValue)
        if let last = camos.last, viewModel.launchProgress(viewModel.finalCamoCount(mode: mode.rawValue)).done >= viewModel.launchRoster, full.total > viewModel.launchRoster {
            row(name: "mw4.ui.stats.100_plus".localized() + " · " + last.name, colors: .platinum, imageURL: nil,
                done: full.done, total: full.total)
        }
    }

    private func row(name: String, colors: [Color], imageURL: String?, done: Int, total: Int) -> some View {
        HStack(spacing: 12) {
            CamoThumbnail(urlString: imageURL, size: 40)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    if done >= total, total > 0 {
                        AnimatedGradientText(text: name, colors: colors, font: .hitmarker(15))
                    } else {
                        Text(name)
                            .font(.hitmarker(15))
                            .foregroundStyle(colors.first ?? Color.appInk)
                    }
                    Spacer()
                    Text("\(done)/\(total)")
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundStyle(done >= total ? (colors.first ?? .camoGold) : Color.appInkMuted)
                }
                ProgressBar(fraction: total > 0 ? Double(done) / Double(total) : 0, accent: colors.first ?? .camoGold)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}
