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
            .safeAreaInset(edge: .bottom, spacing: 0) { AdBanner(placement: "mastery") }
            .navigationTitle("mw4.ui.section.mastery".localized())
        }
    }

    private var list: some View {
            List {
                if embedded {
                    Text("mw4.ui.section.mastery".localized())
                        .hitmarkerFont(22)
                        .foregroundStyle(Color.appInk)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
                if !GameRegistry.hasMastery,
                   GameRegistry.current.capstone != nil || viewModel.prestigeCamos.contains(where: { $0.weaponsNeeded != nil }) {
                    // Black Ops: the camos earned across the whole game
                    Section {
                        GameCamoRows()
                    } header: {
                        // Not sparkles: across the app those mean Premium
                        Label("ct.ui.stats.game_camos".localized(), systemImage: "crown.fill")
                            .foregroundStyle(Palette.accent ?? .camoGold)
                    }
                    .listRowBackground(Color.appSurface)
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
                        ListHeading(title: Label { Text(mode.displayName) } icon: { ModeIcon(mode, size: 15) }
                            .foregroundStyle(mode.textAccent), opaque: false)
                    }
                    .listRowBackground(Color.appSurface)
                }
                if GameRegistry.hasMastery, let capstone = GameRegistry.current.capstone {
                    // MW4: the camo for every mode's Mastery, under them as in the game
                    Section {
                        GlobalMasteryRow(capstone: capstone)
                    } header: {
                        Label("ct.mastery.global".localized(), systemImage: "crown.fill")
                            .foregroundStyle(Palette.accent ?? .camoGold)
                    }
                    .listRowBackground(Color.appSurface)
                }
            }
            .scrollContentBackground(.hidden)
    }

    /// A mode-wide challenge to tick and count (any weapon counts; the
    /// weapon only names the milestone), else the read-only status.
    @ViewBuilder private func row(mode: AppMode, tier: Int) -> some View {
        if viewModel.masteryKind(mode: mode.rawValue, tier: tier) == .mode, let weapon = viewModel.weapons(mode: mode.rawValue).first {
            MasteryModeChallengeRow(mode: mode, weapon: weapon, tier: tier)
        } else {
            MasteryModeRow(mode: mode, tier: tier)
        }
    }
}

/// Flashpoint: every Mastery camo in every mode, counted as tiers earned.
private struct GlobalMasteryRow: View {
    let capstone: CapstoneCamo
    @EnvironmentObject private var viewModel: TrackerViewModel

    var body: some View {
        let progress = viewModel.globalMasteryProgress
        let colors = (capstone.colors ?? []).compactMap(Color.init(hex:))
        let names = ListFormatter.localizedString(byJoining: AppMode.allCases
            .filter { viewModel.modes[$0.rawValue] != nil }.map(\.displayName))
        StatusRow(name: capstone.name.resolved(), achieved: progress.total > 0 && progress.done >= progress.total,
                  color: colors.first ?? .camoGold, gradient: colors,
                  detail: String(format: "ct.mastery.global.detail".localized(), names, progress.done, progress.total),
                  imageURL: capstone.imageURL)
    }
}

/// Cold Snap and Nexus Horizon: camos the game gives for progress across
/// every weapon or mode, in the same rows as the Mastery camos.
private struct GameCamoRows: View {
    @EnvironmentObject private var viewModel: TrackerViewModel

    var body: some View {
        ForEach(Array(viewModel.prestigeCamos.enumerated()).filter { $0.element.weaponsNeeded != nil }, id: \.offset) { index, camo in
            let needed = camo.weaponsNeeded ?? 1
            let done = min(viewModel.prestigeCamoWeaponCount(camo), needed)
            let stage = viewModel.prestigeCamoStage(camo).map { viewModel.prestigeStages[$0 - 1].name.resolved() } ?? ""
            let colors = [Color].prestige(camo, index: index)
            StatusRow(name: camo.name.resolved(), achieved: done >= needed, color: colors.first ?? .camoGold, gradient: colors,
                      detail: String(format: "ct.ui.prestige_camo.weapons".localized(), stage, camo.level ?? 1, needed, done),
                      imageURL: camo.imageURL)
        }
        if let capstone = GameRegistry.current.capstone {
            let parts = viewModel.capstoneModes
            let colors = (capstone.colors ?? []).compactMap(Color.init(hex:))
            let names = ListFormatter.localizedString(byJoining: parts.map(\.mode.completionist.final.name))
            StatusRow(name: capstone.name.resolved(), achieved: !parts.isEmpty && parts.allSatisfy(\.done),
                      color: colors.first ?? .camoGold, gradient: colors,
                      detail: String(format: "ct.mastery.capstone".localized(), names, parts.filter(\.done).count, parts.count),
                      imageURL: capstone.imageURL)
        }
    }
}

/// A Black Ops mode's Mastery camos (Gold to Dark Matter, Shattered Gold
/// to Singularity): weapons with each out of the launch roster, and what
/// still holds it shut, in the rows MW4's Mastery uses. The class camo
/// lists each class's count under its row; 100%+ follows once the last
/// camo is on the launch roster.
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
            let progress = viewModel.launchProgress(count, mode: mode.rawValue)
            let gate = gate(index: index, before: index > 0 ? camos[index - 1].name : nil)
            VStack(alignment: .leading, spacing: 6) {
                StatusRow(name: camo.name, achieved: progress.done >= progress.total, color: camo.color, gradient: camo.gradient,
                          detail: [String(format: "ct.mastery.weapons".localized(), progress.done, progress.total), gate.text]
                            .compactMap { $0 }.joined(separator: " "),
                          imageURL: camo.imageURL)
                if gate.classes {
                    classCounts(step: index)
                        .padding(.leading, 79)
                }
            }
        }
        let full = viewModel.fullRosterFinalProgress(mode: mode.rawValue)
        let roster = viewModel.launchRoster(mode: mode.rawValue)
        if let last = camos.last, viewModel.launchProgress(viewModel.finalCamoCount(mode: mode.rawValue), mode: mode.rawValue).done >= roster,
           full.total > roster {
            StatusRow(name: "mw4.ui.stats.100_plus".localized(), achieved: full.done >= full.total, color: .camoPlatinum, gradient: .platinum,
                      detail: String(format: "mw4.ui.milestone.100_plus_subtitle".localized(), last.name))
        }
    }

    /// What still opens this camo, if anything; `classes` when it opens
    /// class by class
    private func gate(index: Int, before: String?) -> (text: String?, classes: Bool) {
        let raw = mode.rawValue
        if index >= TrackerViewModel.completionistStepCount {
            let needed = viewModel.harmonicBreaksNeeded(mode: raw)
            let have = min(viewModel.harmonicBreakCount(mode: raw), needed)
            return (have >= needed ? nil : String(format: "ct.mastery.gate_weapons".localized(), before ?? "", needed, have), false)
        }
        switch viewModel.completionistGate(mode: raw, step: index) {
        case .weapon:
            let ready = viewModel.launchProgress(viewModel.totalGoldWeaponCount(mode: raw), mode: raw).done
            return (String(format: "ct.mastery.gate_camos".localized(), ready), false)
        case .mode:
            let gate = viewModel.completionistModeGateProgress(mode: raw, step: index)
            return (gate.done >= gate.total ? nil
                    : String(format: "ct.mastery.gate_weapons".localized(), before ?? "", gate.total, min(gate.done, gate.total)), false)
        case .category:
            let classes = viewModel.categories(mode: raw)
            let open = classes.filter { category in
                let p = viewModel.completionistCategoryGateProgress(category, mode: raw, step: index)
                return p.done >= p.total
            }.count
            return (open >= classes.count ? nil
                    : String(format: "ct.mastery.gate_class".localized(), before ?? "", open, classes.count), open < classes.count)
        }
    }

    /// The classes still shut, with their count of the camo before, as
    /// Stats lists its classes: two columns where every name fits whole,
    /// else one. Open classes drop off, since no class has to be done for
    /// another to open.
    private func classCounts(step: Int) -> some View {
        let rows = viewModel.categories(mode: mode.rawValue).map { category in
            (category, viewModel.completionistCategoryGateProgress(category, mode: mode.rawValue, step: step))
        }.filter { $0.1.done < $0.1.total }
        let half = (rows.count + 1) / 2
        return ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 16) {
                classColumn(Array(rows.prefix(half)))
                classColumn(Array(rows.dropFirst(half)))
            }
            classColumn(rows)
        }
        .padding(.bottom, 4)
    }

    private func classColumn(_ rows: [(WeaponCategory, (done: Int, total: Int))]) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(rows, id: \.0.id) { category, p in
                HStack(spacing: 8) {
                    Text(category.name.resolved())
                        .fixedSize()
                    Spacer(minLength: 8)
                    Text("\(min(p.done, p.total))/\(p.total)")
                        .scaledFont(11, design: .monospaced)
                        .fixedSize()
                }
                .scaledFont(12)
                .foregroundStyle(p.done >= p.total ? mode.accent : Color.appInkMuted)
            }
        }
    }
}
