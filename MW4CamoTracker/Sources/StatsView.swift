import SwiftUI

/// The Stats tab: an account-wide hero ring, then one dashboard card per
/// mode — its own completion ring, a `MasteryTrack` stepper for the three
/// Mastery camos, and a collapsible per-category breakdown. Replaces the
/// old flat list-of-sections layout, which had no visual hierarchy between
/// "how close am I" and "here's every category's percentage."
struct StatsView: View {
    @AppStorage(AppMode.playedKey) private var playedRaw = ""
    @EnvironmentObject private var viewModel: TrackerViewModel
    @EnvironmentObject private var hajin: HajinStore
    @State private var width: CGFloat = 0
    @State private var sharing = false

    /// Something on the card besides 0%: a brand-new player has nothing
    /// to share yet.
    private var hasProgress: Bool {
        viewModel.visibleModes.contains { viewModel.trueCompletionFraction(mode: $0.rawValue) >= 0.01 }
            || (viewModel.visibleModes.contains(.dmz) && hajin.statLines.contains { $0.done > 0 })
    }

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
                if width >= 800, GameRegistry.hasMastery, let first = modes.first {
                    // iPad: the weapons on the left, each mode's Mastery
                    // stacked beside them
                    cardRow {
                        ModeStatsCard(mode: first, part: .weapons)
                            .frame(maxWidth: .infinity, alignment: .top)
                        VStack(spacing: 12) {
                            ForEach(modes) { mode in
                                ModeStatsCard(mode: mode, part: .mastery)
                            }
                            if GameRegistry.current.capstone != nil {
                                GlobalMasteryStatsCard()
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .top)
                        .accessibilityElement(children: .contain)
                    }
                } else {
                    // One weapons card where camos count in every mode
                    // (MW4), else one per mode: each is its own grind
                    let weaponModes = GameRegistry.current.sharedCamos == true ? Array(modes.prefix(1)) : modes
                    ForEach(weaponModes) { mode in
                        ModeStatsCard(mode: mode, part: .weapons)
                            .listRowInsets(Self.rowInsets)
                            .listRowBackground(Color.clear)
                    }
                }
                if width >= 800 || !GameRegistry.hasMastery {
                    // Mastery is in the row above, or the game has none
                    EmptyView()
                } else if width >= 600 {
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
                if width < 800, GameRegistry.hasMastery, GameRegistry.current.capstone != nil {
                    // On iPad it's under the Mastery cards in the row above
                    GlobalMasteryStatsCard()
                        .listRowInsets(Self.rowInsets)
                        .listRowBackground(Color.clear)
                }

                if modes.contains(.dmz), hajin.guide != nil {
                    DMZStatsCard()
                        .listRowInsets(Self.rowInsets)
                        .listRowBackground(Color.clear)
                }

                SupportRow()
                    .listRowInsets(EdgeInsets(top: 14, leading: 12, bottom: 24, trailing: 12))
                    .listRowBackground(Color.clear)
            }
            .scrollContentBackground(.hidden)
            .listStyle(.plain)
        }
        .readingWidth($width)
        .safeAreaInset(edge: .bottom, spacing: 0) { AdBanner(placement: "stats") }
        .navigationTitle("mw4.ui.tab.stats".localized())
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if hasProgress {
                    Button { sharing = true } label: { Image(systemName: "square.and.arrow.up") }
                        .accessibilityLabel("mw4.ui.share.title".localized())
                }
            }
        }
        .sheet(isPresented: $sharing) {
            ProgressShareSheet()
                .environmentObject(viewModel)
                .environmentObject(hajin)
        }
    }
}

/// One big ring — the average of every mode's own true-completion fraction
/// — plus a quick per-mode glance row underneath so you can see at once
/// which mode is dragging the average down.
private struct OverallStatsHero: View {
    /// Stretch to the height of the card beside it, ring centred.
    var fillsHeight = false
    @EnvironmentObject private var viewModel: TrackerViewModel

    @AppStorage(AppMode.playedKey) private var playedRaw = ""

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
                .accessibilityLabel(Text("mw4.ui.stats.overall".localized()))

            Text("mw4.ui.stats.overall".localized())
                .scaledFont(12, weight: .bold)
                .textCase(.uppercase)
                .foregroundStyle(Color.appInkMuted)
                .accessibilityHidden(true)

            HStack(spacing: 0) {
                ForEach(perMode, id: \.mode.rawValue) { entry in
                    VStack(spacing: 4) {
                        Image(systemName: entry.mode.symbol)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(entry.mode.accent)
                        Text(entry.fraction.percentText)
                            .scaledFont(14, weight: .bold, design: .monospaced)
                            .foregroundStyle(Color.appInk)
                        Text(entry.mode.displayName)
                            .scaledFont(10)
                            .foregroundStyle(Color.appInkMuted)
                    }
                    .frame(maxWidth: .infinity)
                    // "Multiplayer, 45%", not the three percentages then the names
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(entry.mode.displayName))
                    .accessibilityValue(Text(entry.fraction.percentText))
                }
            }
        }
        .padding(.vertical, 20)
        .frame(maxHeight: fillsHeight ? .infinity : nil)
        .borderedCard()
        .accessibilityElement(children: .contain)
    }
}

/// The DMZ grind beyond camos: DMZ level, FOB upgrades printed, blueprints
/// and Manuals found, bosses taken down and missions done, from what's
/// ticked on the DMZ tab. The ring is the average of the five.
private struct DMZStatsCard: View {
    @EnvironmentObject private var store: HajinStore

    private var lines: [DMZStatLine] { store.statLines }

    var body: some View {
        let lines = lines
        let overall = lines.isEmpty ? 0 : lines.map(\.fraction).reduce(0, +) / Double(lines.count)
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                ProgressRing(fraction: overall, accent: .accentDMZ, lineWidth: 6, size: 56)
                    .accessibilityLabel(Text("mw4.ui.stats.dmz".localized()))
                VStack(alignment: .leading, spacing: 2) {
                    Label("mw4.ui.stats.dmz".localized(), systemImage: AppMode.dmz.symbol)
                        .font(.headline)
                        .foregroundStyle(Color.accentDMZText)
                    if store.cash > 0 {
                        Text("mw4.ui.hajin.cash_title".localized() + " $\(store.cash.formatted())")
                            .scaledFont(12, weight: .semibold, design: .monospaced)
                            .foregroundStyle(Color.appInkMuted)
                    }
                }
                Spacer(minLength: 0)
            }
            ForEach(lines) { line in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Image(systemName: line.symbol)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Color.accentDMZText)
                            .frame(width: 18)
                        Text(line.title)
                            .font(.subheadline)
                            .foregroundStyle(Color.appInk)
                        Spacer(minLength: 6)
                        Text("\(line.done)/\(line.total)")
                            .scaledFont(13, weight: .bold, design: .monospaced)
                            .foregroundStyle(line.done >= line.total ? Color.accentDMZText : Color.appInkMuted)
                    }
                    ProgressBar(fraction: line.fraction, accent: .accentDMZ)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(16)
        .borderedCard()
        .accessibilityElement(children: .contain)
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
                        .scaledFont(12, weight: .semibold)
                    Text(Self.address)
                        .scaledFont(12, design: .monospaced)
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

/// MW4's Flashpoint: each mode's three Mastery camos, then the camo for
/// having all of them.
private struct GlobalMasteryStatsCard: View {
    @EnvironmentObject private var viewModel: TrackerViewModel

    var body: some View {
        if let capstone = GameRegistry.current.capstone {
            let progress = viewModel.globalMasteryProgress
            let fraction = progress.total > 0 ? Double(progress.done) / Double(progress.total) : 0
            let colors = (capstone.colors ?? []).compactMap(Color.init(hex:))
            let accent = colors.first ?? .camoGold
            let modes = AppMode.allCases.filter { viewModel.modes[$0.rawValue] != nil }
            let nodes: [MasteryTrack.Node] = modes.map { mode in
                let done = (1...3).filter { viewModel.isMasteryAchieved(mode: mode.rawValue, tier: $0) }.count
                return .init(name: mode.displayName, color: mode.accent, gradient: mode.masteryCamos.tier3.gradient,
                             achieved: done == 3, detail: "\(done)/3")
            } + [.init(name: capstone.name.resolved(), color: accent, gradient: colors.isEmpty ? .gold : colors,
                       achieved: viewModel.isGlobalMasteryAchieved, detail: "\(progress.done)/\(progress.total)")]
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(accent)
                    Text("ct.mastery.global".localized())
                        .hitmarkerFont(17)
                        .foregroundStyle(Color.appInk)
                    Spacer()
                    ProgressRing(fraction: fraction, accent: accent, lineWidth: 5, size: 42, showsPercentage: false,
                                 shimmerColors: colors.isEmpty ? .gold : colors)
                        .overlay(
                            Text(fraction.percentText)
                                .scaledFont(11, weight: .bold, design: .monospaced)
                                .foregroundStyle(Color.appInk)
                                .accessibilityHidden(true)
                        )
                }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
                MasteryTrack(nodes: nodes)
            }
            .padding(14)
            .borderedCard(accent: accent)
            .accessibilityElement(children: .contain)
        }
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var breakdownExpanded = true

    /// Black Ops has a card per mode, each with every class: two columns
    /// keep the stack of them short. One column at accessibility sizes,
    /// where half the card is too narrow for a class name.
    private var twoColumns: Bool { !GameRegistry.hasMastery && !dynamicTypeSize.isAccessibilitySize }

    private var weaponCategories: [WeaponCategory] { viewModel.catalog?.categories ?? [] }
    private var objectiveCategories: [Category] { viewModel.modes[mode.rawValue]?.objectives ?? [] }
    private var completion: Double { viewModel.trueCompletionFraction(mode: mode.rawValue) }

    /// Gold, Platinum, Harmonic Break and the final camo: how many of the
    /// mode's weapons have each.
    private var completionistNodes: [MasteryTrack.Node] {
        // Out of the launch roster; 100%+ below counts every weapon
        let total = viewModel.launchRoster
        var nodes: [MasteryTrack.Node] = mode.completionistCamos.enumerated().map { index, camo in
            let done = viewModel.launchProgress(viewModel.completionistCount(mode: mode.rawValue, step: index)).done
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
                // A mode's own weapons card (Black Ops) is named for the mode
                let ownGrind = part == .weapons && GameRegistry.current.sharedCamos != true
                Image(systemName: part == .weapons && !ownGrind ? "scope" : mode.symbol)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(mode.accent)
                Text(ownGrind ? mode.displayName
                     : part == .weapons ? "mw4.ui.section.weapons".localized()
                     : "\(mode.displayName) \("mw4.ui.section.mastery".localized())")
                    .hitmarkerFont(17)
                    .foregroundStyle(Color.appInk)
                Spacer()
                // `mode.accent` already *is* this mode's tier3 color (see
                // `Color.accentMultiplayer` etc. in Theme.swift), so the
                // shimmer at 100% uses that same camo's own gradient instead
                // of `ProgressRing`'s generic Gold default.
                ProgressRing(fraction: completion, accent: mode.accent, lineWidth: 5, size: 42, showsPercentage: false, shimmerColors: mode.masteryCamos.tier3.gradient)
                    .overlay(
                        Text(completion.percentText)
                            .scaledFont(11, weight: .bold, design: .monospaced)
                            .foregroundStyle(mode.textAccent)
                            .accessibilityHidden(true)
                    )
            }
            // The card's title and its percentage, one heading
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            if part == .weapons {
                // Black Ops' ladder lives on its Mastery tab; Stats keeps
                // the percentages and the class breakdown
                if GameRegistry.hasMastery {
                    VStack(spacing: 8) {
                        trackTitle("mw4.ui.section.completionist".localized())
                        MasteryTrack(nodes: completionistNodes)
                    }
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
                            .scaledFont(12, weight: .semibold)
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
                    let rows = Group {
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
                    Group {
                        if twoColumns {
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16, alignment: .top), count: 2),
                                      alignment: .leading, spacing: 14) { rows }
                        } else {
                            VStack(spacing: 10) { rows }
                        }
                    }
                    .padding(.top, 10)
                }
            }
        }
        .padding(14)
        .borderedCard(accent: mode.accent)
        // Read card by card: on iPad, with Mastery in a column beside the
        // weapons, VoiceOver otherwise went across both a line at a time
        .accessibilityElement(children: .contain)
    }

    private func trackTitle(_ title: String) -> some View {
        Text(title)
            .scaledFont(12, weight: .semibold)
            .foregroundStyle(Color.appInkMuted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }

    private func statRow(name: String, fraction: Double, count: String? = nil) -> some View {
        Group {
            if twoColumns {
                compactStatRow(name: name, fraction: fraction, count: count)
            } else {
                wideStatRow(name: name, fraction: fraction, count: count)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(name))
        .accessibilityValue(Text([fraction.percentText, count.map(Spoken.counts)].compactMap { $0 }.joined(separator: ", ")))
    }

    /// Half a card wide: the name and percentage over the bar, the count
    /// under it.
    private func compactStatRow(name: String, fraction: Double, count: String?) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(name)
                    .scaledFont(13)
                    .foregroundStyle(Color.appInk)
                    .lineLimit(2)
                Spacer(minLength: 4)
                Text(fraction.percentText)
                    .scaledFont(12, design: .monospaced)
                    .foregroundStyle(Color.appInkMuted)
            }
            ProgressBar(fraction: fraction, accent: mode.accent)
            if let count {
                Text(count)
                    .scaledFont(11, design: .monospaced)
                    .foregroundStyle(Color.appInkMuted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
    }

    private func wideStatRow(name: String, fraction: Double, count: String?) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(name)
                        .scaledFont(13)
                        .foregroundStyle(Color.appInk)
                    if let count {
                        Text(count)
                            .scaledFont(11, design: .monospaced)
                            .foregroundStyle(Color.appInkMuted)
                    }
                }
                ProgressBar(fraction: fraction, accent: mode.accent)
            }
            Text(fraction.percentText)
                .scaledFont(12, design: .monospaced)
                .foregroundStyle(Color.appInkMuted)
        }
    }
}

/// One line of the DMZ grind, as Stats and the share card show it.
struct DMZStatLine: Identifiable {
    let symbol: String
    let title: String
    let done: Int
    let total: Int
    var id: String { title }
    var fraction: Double { total > 0 ? Double(done) / Double(total) : 0 }
}

extension HajinStore {
    /// DMZ level, FOB upgrades printed, blueprints and Manuals found, bosses
    /// taken down and missions done, from what's ticked on the DMZ tab.
    var statLines: [DMZStatLine] {
        let upgrades = (guide?.items ?? []).filter { $0.kind == "FOB Upgrade" }
        func checks(_ section: String) -> [String] {
            (guide?.guide.first { $0.id == section }?.rows ?? []).compactMap(\.check)
        }
        let bosses = checks("bosses"), ops = checks("ops")
        let finds = findProgress
        return [
            DMZStatLine(symbol: "chart.bar.fill", title: "mw4.ui.hajin.dmz_level".localized(), done: dmzLevel, total: Self.maxLevel),
            DMZStatLine(symbol: "arrow.up.circle.fill", title: "mw4.ui.stats.dmz_upgrades".localized(),
                        done: upgrades.filter { checked.contains("upgrade-\($0.id)") }.count, total: upgrades.count),
            DMZStatLine(symbol: "doc.text.magnifyingglass", title: "mw4.ui.stats.dmz_finds".localized(), done: finds.found, total: finds.total),
            DMZStatLine(symbol: "exclamationmark.shield.fill", title: "mw4.ui.stats.dmz_bosses".localized(),
                        done: bosses.filter(checked.contains).count, total: bosses.count),
            DMZStatLine(symbol: "checklist", title: "mw4.ui.stats.dmz_ops".localized(),
                        done: ops.filter(checked.contains).count, total: ops.count),
        ].filter { $0.total > 0 }
    }
}
