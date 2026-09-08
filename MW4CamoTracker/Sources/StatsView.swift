import SwiftUI

/// The Stats tab: an account-wide hero ring, then one dashboard card per
/// mode — its own completion ring, a `MasteryTrack` stepper for the three
/// Mastery camos, and a collapsible per-category breakdown. Replaces the
/// old flat list-of-sections layout, which had no visual hierarchy between
/// "how close am I" and "here's every category's percentage."
struct StatsView: View {
    @EnvironmentObject private var viewModel: TrackerViewModel

    var body: some View {
        ZStack {
            AppBackground(accent: .accentMultiplayer)
            List {
                OverallStatsHero()
                    .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                    .listRowBackground(Color.clear)

                ForEach(AppMode.allCases) { mode in
                    ModeStatsCard(mode: mode)
                        .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                        .listRowBackground(Color.clear)
                }

                SupportRow()
                    .listRowInsets(EdgeInsets(top: 14, leading: 12, bottom: 24, trailing: 12))
                    .listRowBackground(Color.clear)
            }
            .scrollContentBackground(.hidden)
            .listStyle(.plain)
        }
        .navigationTitle("mw4.ui.tab.stats".localized())
    }
}

/// One big ring — the average of every mode's own true-completion fraction
/// — plus a quick per-mode glance row underneath so you can see at once
/// which mode is dragging the average down.
private struct OverallStatsHero: View {
    @EnvironmentObject private var viewModel: TrackerViewModel

    private var perMode: [(mode: AppMode, fraction: Double)] {
        AppMode.allCases.map { ($0, viewModel.trueCompletionFraction(mode: $0.rawValue)) }
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
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.2)
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
    let mode: AppMode
    @EnvironmentObject private var viewModel: TrackerViewModel
    @State private var breakdownExpanded = true

    private var weaponCategories: [WeaponCategory] { viewModel.catalog?.categories ?? [] }
    private var objectiveCategories: [Category] { viewModel.modes[mode.rawValue]?.objectives ?? [] }
    private var completion: Double { viewModel.trueCompletionFraction(mode: mode.rawValue) }

    private var masteryNodes: [MasteryTrack.Node] {
        let tiers = mode.masteryCamos
        let tier1 = viewModel.masteryTier1Progress(mode: mode.rawValue)
        let tier2 = viewModel.masteryTier2Progress(mode: mode.rawValue)
        let tier3Achieved = viewModel.isMasteryTier3Achieved(mode: mode.rawValue)
        // tier3 itself has no separate weapon count of its own — its gate
        // *is* `tier2` (capped at the launch roster) — so its node shows
        // that same "x/y weapons" rather than just a bare "Done."
        var nodes: [MasteryTrack.Node] = [
            .init(name: tiers.tier1.name, color: tiers.tier1.color, gradient: tiers.tier1.gradient, achieved: tier1.total > 0 && tier1.done == tier1.total, detail: "\(tier1.done)/\(tier1.total)"),
            .init(name: tiers.tier2.name, color: tiers.tier2.color, gradient: tiers.tier2.gradient, achieved: tier2.total > 0 && tier2.done == tier2.total, detail: "\(tier2.done)/\(tier2.total)"),
            .init(name: tiers.tier3.name, color: tiers.tier3.color, gradient: tiers.tier3.gradient, achieved: tier3Achieved, detail: "\(tier2.done)/\(tier2.total)")
        ]
        // Only once the real capstone is earned — before then "100%+" is a
        // goal past one you haven't reached yet, not useful information.
        if tier3Achieved {
            let fullRoster = viewModel.fullRosterTier2Progress(mode: mode.rawValue)
            nodes.append(.init(name: "mw4.ui.stats.100_plus".localized(), color: .camoPlatinum, gradient: .platinum, achieved: viewModel.is100PlusAchieved(mode: mode.rawValue), detail: "\(fullRoster.done)/\(fullRoster.total)"))
        }
        return nodes
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: mode.symbol)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(mode.accent)
                Text(mode.displayNameKey.localized())
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

            MasteryTrack(nodes: masteryNodes)

            if !weaponCategories.isEmpty || !objectiveCategories.isEmpty {
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
                        ForEach(weaponCategories) { category in
                            statRow(
                                name: category.name.resolved(),
                                fraction: viewModel.weaponCategoryProgressFraction(category, mode: mode.rawValue),
                                count: "\(viewModel.goldWeaponCount(in: category, mode: mode.rawValue))/\(category.weapons.count)"
                            )
                        }
                        ForEach(objectiveCategories) { category in
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
