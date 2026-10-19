import SwiftUI

/// The Stats tab: an account-wide hero ring, then one dashboard card per
/// mode — its own completion ring, a `MasteryTrack` stepper for the three
/// Mastery camos, and a collapsible per-category breakdown. Replaces the
/// old flat list-of-sections layout, which had no visual hierarchy between
/// "how close am I" and "here's every category's percentage."
struct StatsView: View {
    @EnvironmentObject private var viewModel: TrackerViewModel
    @State private var width: CGFloat = 0

    private static let rowInsets = EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12)

    private func cardRow<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 12, content: content)
            .listRowInsets(Self.rowInsets)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }

    var body: some View {
        ZStack {
            AppBackground(accent: .accentMultiplayer)
            List {
                let modes = viewModel.visibleModes
                // Camos are one track per weapon, so the weapons are shown
                // once; only Mastery is per mode
                OverallStatsHero()
                    .listRowInsets(Self.rowInsets)
                    .listRowBackground(Color.clear)
                if let first = modes.first {
                    ModeStatsCard(mode: first, part: .weapons)
                        .listRowInsets(Self.rowInsets)
                        .listRowBackground(Color.clear)
                }
                if width >= 600 {
                    cardRow {
                        ForEach(modes) { mode in
                            ModeStatsCard(mode: mode, part: .mastery).frame(maxWidth: .infinity, alignment: .top)
                        }
                    }
                } else {
                    ForEach(modes) { mode in
                        ModeStatsCard(mode: mode, part: .mastery)
                            .listRowInsets(Self.rowInsets)
                            .listRowBackground(Color.clear)
                    }
                }

                SupportRow()
                    .listRowInsets(EdgeInsets(top: 14, leading: 12, bottom: 24, trailing: 12))
                    .listRowBackground(Color.clear)
            }
            .scrollContentBackground(.hidden)
            .listStyle(.plain)
        }
        .readingWidth($width)
        .navigationTitle("mw4.ui.tab.stats".localized())
    }
}

/// One big ring — the average of every mode's own true-completion fraction
/// — plus a quick per-mode glance row underneath so you can see at once
/// which mode is dragging the average down.
private struct OverallStatsHero: View {
    /// Stretch to the height of the card beside it, ring centred.
    var fillsHeight = false
    @EnvironmentObject private var viewModel: TrackerViewModel

    private var perMode: [(mode: AppMode, fraction: Double)] {
        viewModel.visibleModes.map { ($0, viewModel.trueCompletionFraction(mode: $0.rawValue)) }
    }
    private var overallFraction: Double {
        let values = perMode.map(\.fraction)
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }

    var body: some View {
        VStack(spacing: 14) {
            ProgressRing(fraction: overallFraction, accent: .camoGold, lineWidth: 10, size: 110)

            Text("mw4.ui.stats.overall".localized())
                .font(.system(size: 12, weight: .bold))
                .textCase(.uppercase)
                .foregroundStyle(Color.appInkMuted)

            HStack(spacing: 0) {
                ForEach(perMode, id: \.mode.rawValue) { entry in
                    VStack(spacing: 4) {
                        Image(systemName: entry.mode.symbol)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(entry.mode.accent)
                        Text("\(Int(entry.fraction * 100))%")
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.appInk)
                        Text(entry.mode.displayNameKey.localized())
                            .font(.system(size: 10))
                            .foregroundStyle(Color.appInkMuted)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.vertical, 20)
        .frame(maxHeight: fillsHeight ? .infinity : nil)
        .borderedCard()
    }
}

/// Support contact, parked at the foot of Stats. It lives here rather than on
/// a mode tab because those are for tracking and this is housekeeping, and the
/// list already ends in a natural gap.
private struct SupportRow: View {
    private static let address = "support@camotracker.djr.li"

    var body: some View {
        Link(destination: URL(string: "mailto:\(Self.address)")!) {
            HStack(spacing: 8) {
                Image(systemName: "envelope")
                    .font(.system(size: 12, weight: .semibold))
                VStack(alignment: .leading, spacing: 2) {
                    Text("mw4.ui.support".localized())
                        .font(.system(size: 12, weight: .semibold))
                    Text(Self.address)
                        .font(.system(size: 12, design: .monospaced))
                }
                Spacer()
            }
            .foregroundStyle(Color.appInkMuted)
            .padding(12)
            .contentShape(Rectangle())
            .borderedCard()
        }
        .buttonStyle(.plain)
    }
}

/// One mode's whole dashboard card: header + hero ring, the Mastery track,
/// and a collapsible breakdown of every category/objective in that mode.
private struct ModeStatsCard: View {
    /// The weapons (shared by every mode: Completionist, 100%+ and each
    /// class), or one mode's own part (Mastery and its objectives).
    enum Part { case weapons, mastery }
    let mode: AppMode
    let part: Part
    @EnvironmentObject private var viewModel: TrackerViewModel
    @State private var breakdownExpanded = true

    private var weaponCategories: [WeaponCategory] { viewModel.catalog?.categories ?? [] }
    private var objectiveCategories: [Category] { viewModel.modes[mode.rawValue]?.objectives ?? [] }
    private var completion: Double { viewModel.trueCompletionFraction(mode: mode.rawValue) }

    /// Gold, Platinum, Harmonic Break and the final camo: how many of the
    /// mode's weapons have each.
    private var completionistNodes: [MasteryTrack.Node] {
        let total = viewModel.totalWeaponCount
        var nodes: [MasteryTrack.Node] = mode.completionistCamos.enumerated().map { index, camo in
            let done = viewModel.completionistCount(mode: mode.rawValue, step: index)
            return .init(name: camo.name, color: camo.color, gradient: camo.gradient,
                         achieved: total > 0 && done >= total, detail: "\(done)/\(total)")
        }
        // 100%+: the last Completionist camo on every weapon, new ones too,
        // shown once it's on the launch roster
        if nodes.last?.achieved == true {
            let fullRoster = viewModel.fullRosterFinalProgress(mode: mode.rawValue)
            nodes.append(.init(name: "mw4.ui.stats.100_plus".localized(), color: .camoPlatinum, gradient: .platinum,
                               achieved: fullRoster.total > 0 && fullRoster.done >= fullRoster.total,
                               detail: "\(fullRoster.done)/\(fullRoster.total)"))
        }
        return nodes
    }

    /// The mode's three Mastery camos, each with how many weapons have the
    /// final Completionist camo out of the count it needs.
    private var masteryNodes: [MasteryTrack.Node] {
        let tiers = mode.masteryCamos
        let nodes: [MasteryTrack.Node] = [tiers.tier1, tiers.tier2, tiers.tier3].enumerated().map { index, camo in
            let progress = viewModel.masteryProgress(mode: mode.rawValue, tier: index + 1)
            return .init(name: camo.name, color: camo.color, gradient: camo.gradient,
                         achieved: viewModel.isMasteryAchieved(mode: mode.rawValue, tier: index + 1),
                         detail: "\(progress.done)/\(progress.total)")
        }
        return nodes
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: part == .weapons ? "scope" : mode.symbol)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(mode.accent)
                Text(part == .weapons ? "mw4.ui.section.weapons".localized()
                     : "\(mode.displayNameKey.localized()) \("mw4.ui.section.mastery".localized())")
                    .font(.hitmarker(17))
                    .foregroundStyle(Color.appInk)
                Spacer()
                // `mode.accent` already *is* this mode's tier3 color (see
                // `Color.accentMultiplayer` etc. in Theme.swift), so the
                // shimmer at 100% uses that same camo's own gradient instead
                // of `ProgressRing`'s generic Gold default.
                ProgressRing(fraction: completion, accent: mode.accent, lineWidth: 5, size: 42, showsPercentage: false, shimmerColors: mode.masteryCamos.tier3.gradient)
                    .overlay(
                        Text("\(Int(completion * 100))%")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(mode.accent)
                    )
            }

            if part == .weapons {
                VStack(spacing: 8) {
                    trackTitle("mw4.ui.section.completionist".localized())
                    MasteryTrack(nodes: completionistNodes)
                }
            } else {
                VStack(spacing: 8) {
                    trackTitle("mw4.ui.section.mastery".localized())
                    MasteryTrack(nodes: masteryNodes)
                }
            }

            if (part == .weapons && !weaponCategories.isEmpty) || (part == .mastery && !objectiveCategories.isEmpty) {
                // A manual toggle instead of `DisclosureGroup` — inside a
                // custom `List` row, `DisclosureGroup`'s own expand/collapse
                // animation fought with the row's height change and made the
                // card visibly grow both up *and* down instead of just
                // extending downward under the label.
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        breakdownExpanded.toggle()
                    }
                } label: {
                    HStack {
                        Text("mw4.ui.stats.breakdown".localized())
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.appInkMuted)
                        Spacer()
                        Image(systemName: "chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.appInkMuted)
                            .rotationEffect(.degrees(breakdownExpanded ? 180 : 0))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if breakdownExpanded {
                    VStack(spacing: 10) {
                        ForEach(part == .weapons ? weaponCategories : []) { category in
                            statRow(
                                name: category.name.resolved(),
                                // The whole track: camos and Completionist,
                                // so a class at Divergence reads as further
                                // on than one that has only done its camos.
                                fraction: viewModel.categoryTrueCompletionFraction(category, mode: mode.rawValue),
                                count: "\(viewModel.categoryLastCompletionistCount(category, mode: mode.rawValue))/\(category.weapons.count) \(mode.lastCompletionist.name)"
                            )
                        }
                        ForEach(part == .mastery ? objectiveCategories : []) { category in
                            statRow(
                                name: category.name.resolved(),
                                fraction: viewModel.objectiveProgressFraction(of: category, mode: mode.rawValue)
                            )
                        }
                    }
                    .padding(.top, 10)
                }
            }
        }
        .padding(14)
        .borderedCard(accent: mode.accent)
    }

    private func trackTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Color.appInkMuted)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func statRow(name: String, fraction: Double, count: String? = nil) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(name)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.appInk)
                    if let count {
                        Text(count)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Color.appInkMuted)
                    }
                }
                ProgressBar(fraction: fraction, accent: mode.accent)
            }
            Text("\(Int(fraction * 100))%")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Color.appInkMuted)
        }
    }
}
