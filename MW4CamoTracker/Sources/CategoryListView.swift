import SwiftUI

/// Top of each mode tab: a Suggested section (what to grind next), the shared
/// weapon categories (from the catalog), and that mode's own mode-exclusive
/// objectives, if it has any (DMZ only, for now).
struct CategoryListView: View {
    let mode: AppMode
    @EnvironmentObject private var viewModel: TrackerViewModel
    @State private var searchQuery = ""

    /// Shared across every mode tab (same idea as the sibling BO7 Camo
    /// Tracker app's `FilterContext`, minus the cross-screen sync it needs
    /// for its separate Home/Weapon-Detail screens — this app's filter only
    /// ever drives the one list it sits above).
    @AppStorage("mw4_category_sort") private var sortRaw = ProgressSort.natural.rawValue
    @AppStorage("mw4_category_filter") private var filterRaw = CompletionFilter.all.rawValue
    private static let sortOptions: [ProgressSort] = [.natural, .alphabetical, .progressDesc, .progressAsc]

    private var sort: ProgressSort { ProgressSort(rawValue: sortRaw) ?? .natural }
    private var filter: CompletionFilter { CompletionFilter(rawValue: filterRaw) ?? .all }
    private var sortBinding: Binding<ProgressSort> {
        Binding(get: { sort }, set: { sortRaw = $0.rawValue })
    }
    private var filterBinding: Binding<CompletionFilter> {
        Binding(get: { filter }, set: { filterRaw = $0.rawValue })
    }

    private var weaponCategories: [WeaponCategory] { viewModel.catalog?.categories ?? [] }
    private var objectiveCategories: [Category] { viewModel.modes[mode.rawValue]?.objectives ?? [] }
    private var suggestions: [Suggestion] { viewModel.suggestions(mode: mode.rawValue) }

    /// `weaponCategories` after the Filter/Sort pills are applied — everything
    /// else (Suggested, Pinned, Objectives) is untouched, since those aren't
    /// the flat browsable list this control is for.
    private var displayedCategories: [WeaponCategory] {
        var categories = weaponCategories
        switch filter {
        case .all:
            break
        case .incomplete:
            categories = categories.filter {
                !$0.weapons.isEmpty && viewModel.goldWeaponCount(in: $0, mode: mode.rawValue) < $0.weapons.count
            }
        case .complete:
            categories = categories.filter {
                !$0.weapons.isEmpty && viewModel.goldWeaponCount(in: $0, mode: mode.rawValue) == $0.weapons.count
            }
        }
        switch sort {
        case .natural, .level:
            break
        case .alphabetical:
            categories.sort { $0.name.resolved().localizedCaseInsensitiveCompare($1.name.resolved()) == .orderedAscending }
        case .progressDesc:
            categories.sort { viewModel.weaponCategoryProgressFraction($0, mode: mode.rawValue) > viewModel.weaponCategoryProgressFraction($1, mode: mode.rawValue) }
        case .progressAsc:
            categories.sort { viewModel.weaponCategoryProgressFraction($0, mode: mode.rawValue) < viewModel.weaponCategoryProgressFraction($1, mode: mode.rawValue) }
        }
        return categories
    }

    /// Every weapon across every category, flattened — the search results are
    /// a single flat list (matching the shipped trackers' weapon search),
    /// not scoped to whichever category you happened to be browsing.
    private var searchResults: [WeaponEntry] {
        guard !searchQuery.isEmpty else { return [] }
        return weaponCategories.flatMap(\.weapons).filter {
            $0.name.resolved().localizedCaseInsensitiveContains(searchQuery)
        }
    }

    private var pinnedWeapon: WeaponEntry? {
        viewModel.pinnedWeaponId.flatMap { viewModel.weapon(id: $0) }
    }

    var body: some View {
        ZStack {
            AppBackground(accent: mode.accent)
            List {
                if !searchQuery.isEmpty {
                    ForEach(searchResults) { weapon in
                        NavigationLink(value: Route.weapon(weapon.weaponId)) {
                            WeaponRow(mode: mode, weapon: weapon)
                        }
                        .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                        .listRowBackground(Color.clear)
                    }
                } else {
                    // No separate leading hero ring — with Gold/tier1/tier2/
                    // tier3 (and, once earned, 100%+) all shown as their own
                    // labeled rings below, an extra unlabeled blended ring
                    // next to them read as redundant clutter rather than a
                    // distinct number worth acting on.
                    StatSummaryCard(
                        stats: {
                            let goldCount = viewModel.totalGoldWeaponCount(mode: mode.rawValue)
                            let tier1 = viewModel.masteryTier1Progress(mode: mode.rawValue)
                            let tier2 = viewModel.masteryTier2Progress(mode: mode.rawValue)
                            // tier3 has no weapon count of its own — its gate
                            // *is* `tier2` (capped at the launch roster) — so
                            // its ring/count mirror tier2's exactly, just in
                            // the capstone camo's own color.
                            let tier3Achieved = viewModel.isMasteryTier3Achieved(mode: mode.rawValue)
                            var stats: [StatSummaryCard.Stat] = [
                                .init(value: "\(goldCount)/\(viewModel.totalWeaponCount)", label: "mw4.ui.gold".localized(), ringFraction: viewModel.totalWeaponCount > 0 ? Double(goldCount) / Double(viewModel.totalWeaponCount) : 0, ringColor: .camoGold),
                                .init(value: "\(tier1.done)/\(tier1.total)", label: mode.masteryCamos.tier1.name, labelGradient: tier1FullyEarned(mode) ? mode.masteryCamos.tier1.gradient : nil, ringFraction: tier1.total > 0 ? Double(tier1.done) / Double(tier1.total) : 0, ringColor: mode.masteryCamos.tier1.color, ringGradient: mode.masteryCamos.tier1.gradient),
                                .init(value: "\(tier2.done)/\(tier2.total)", label: mode.masteryCamos.tier2.name, labelGradient: tier2FullyEarned(mode) ? mode.masteryCamos.tier2.gradient : nil, ringFraction: tier2.total > 0 ? Double(tier2.done) / Double(tier2.total) : 0, ringColor: mode.masteryCamos.tier2.color, ringGradient: mode.masteryCamos.tier2.gradient),
                                .init(value: "\(tier2.done)/\(tier2.total)", label: mode.masteryCamos.tier3.name, labelGradient: tier3Achieved ? mode.masteryCamos.tier3.gradient : nil, ringFraction: tier2.total > 0 ? Double(tier2.done) / Double(tier2.total) : 0, ringColor: mode.masteryCamos.tier3.color, ringGradient: mode.masteryCamos.tier3.gradient)
                            ]
                            // Only worth showing once the real capstone is
                            // actually earned — before then it's just noise
                            // ("100%+ of what?") on top of a goal not even
                            // reached yet.
                            if tier3Achieved {
                                let fullRoster = viewModel.fullRosterTier2Progress(mode: mode.rawValue)
                                stats.append(.init(value: "\(fullRoster.done)/\(fullRoster.total)", label: "mw4.ui.stats.100_plus".localized(), labelGradient: viewModel.is100PlusAchieved(mode: mode.rawValue) ? .platinum : nil, ringFraction: fullRoster.total > 0 ? Double(fullRoster.done) / Double(fullRoster.total) : 0, ringColor: .camoPlatinum, ringGradient: .platinum))
                            }
                            return stats
                        }()
                    )
                    .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                    .listRowBackground(Color.clear)

                    if let pinnedWeapon {
                        Section("mw4.ui.section.pinned".localized()) {
                            NavigationLink(value: Route.weapon(pinnedWeapon.weaponId)) {
                                WeaponRow(mode: mode, weapon: pinnedWeapon)
                            }
                            .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                            .listRowBackground(Color.clear)
                        }
                    }

                    if !suggestions.isEmpty {
                        Section("mw4.ui.section.suggested".localized()) {
                            ForEach(suggestions) { suggestion in
                                NavigationLink(value: Route.weapon(suggestion.weaponId)) {
                                    SuggestionRow(mode: mode, suggestion: suggestion)
                                }
                                .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                                .listRowBackground(Color.clear)
                            }
                        }
                    }

                    if !weaponCategories.isEmpty {
                        Section("mw4.ui.section.weapons".localized()) {
                            HStack(spacing: 8) {
                                FilterSortMenu(title: "mw4.ui.filter".localized(), options: CompletionFilter.allCases, label: { $0.label }, accent: mode.accent, selection: filterBinding)
                                FilterSortMenu(title: "mw4.ui.sort".localized(), options: Self.sortOptions, label: { $0.label }, accent: mode.accent, selection: sortBinding)
                            }
                            .listRowInsets(EdgeInsets(top: 0, leading: 12, bottom: 6, trailing: 12))
                            .listRowBackground(Color.clear)

                            if displayedCategories.isEmpty {
                                FilterEmptyRow()
                                    .listRowInsets(EdgeInsets())
                                    .listRowBackground(Color.clear)
                            } else {
                                ForEach(displayedCategories) { category in
                                    NavigationLink(value: Route.weaponCategory(category.categoryId)) {
                                        WeaponCategoryRow(mode: mode, category: category)
                                    }
                                    .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                                    .listRowBackground(Color.clear)
                                }
                            }
                        }
                    }

                    if !objectiveCategories.isEmpty {
                        Section("mw4.ui.section.objectives".localized()) {
                            ForEach(objectiveCategories) { category in
                                NavigationLink(value: Route.objectiveCategory(category.categoryId)) {
                                    ObjectiveCategoryRow(mode: mode, category: category)
                                }
                                .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                                .listRowBackground(Color.clear)
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .listStyle(.plain)
        }
        .searchable(text: $searchQuery, prompt: "mw4.ui.search_weapons".localized())
        .navigationTitle(mode.displayNameKey.localized())
        .refreshable { await viewModel.refresh() }
    }

    /// The shimmer only means something once it's actually earned — while
    /// tier1 is still in progress this stays plain text, same rule as the
    /// per-weapon Mastery rows and the Stats tab.
    private func tier1FullyEarned(_ mode: AppMode) -> Bool {
        let progress = viewModel.masteryTier1Progress(mode: mode.rawValue)
        return progress.total > 0 && progress.done == progress.total
    }

    private func tier2FullyEarned(_ mode: AppMode) -> Bool {
        let progress = viewModel.masteryTier2Progress(mode: mode.rawValue)
        return progress.total > 0 && progress.done == progress.total
    }
}

private struct SuggestionRow: View {
    let mode: AppMode
    let suggestion: Suggestion
    @EnvironmentObject private var viewModel: TrackerViewModel

    private var fraction: Double { viewModel.camoProgressFraction(weaponId: suggestion.weaponId, mode: mode.rawValue) }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: suggestion.isMasteryTier1Critical ? "diamond.fill" : "arrow.up.forward")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.appBackground)
                .frame(width: 30, height: 30)
                .background(Circle().fill(suggestion.isMasteryTier1Critical ? mode.masteryCamos.tier1.color : mode.accent))

            VStack(alignment: .leading, spacing: 4) {
                Text(suggestion.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.appInk)
                Text(suggestion.subtitle)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Color.appInkMuted)
                ProgressBar(fraction: fraction, accent: mode.accent)
            }

            Spacer(minLength: 8)
            Text("\(Int(fraction * 100))%")
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(mode.accent)
        }
        .padding(12)
        .borderedCard()
    }
}

private struct WeaponCategoryRow: View {
    let mode: AppMode
    let category: WeaponCategory
    @EnvironmentObject private var viewModel: TrackerViewModel

    private var goldCount: Int { viewModel.goldWeaponCount(in: category, mode: mode.rawValue) }

    /// The highest Mastery tier this category has fully earned, if any —
    /// tier2 takes precedence over tier1 when both are true, so the badge
    /// always reflects the category's best standing, not just its first rung.
    private var highestTierAchieved: MasteryCamo? {
        let tiers = mode.masteryCamos
        if viewModel.categoryHasMasteryTier2(category, mode: mode.rawValue) { return tiers.tier2 }
        if viewModel.categoryHasMasteryTier1(category, mode: mode.rawValue) { return tiers.tier1 }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(category.weapons.count) \("mw4.ui.section.weapons".localized())")
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.2)
                .textCase(.uppercase)
                .foregroundStyle(Color.appInkMuted)

            Text(category.name.resolved())
                .font(.hitmarker(16))
                .foregroundStyle(Color.appInk)

            // Same ring-and-count treatment as the mode root tab's header and
            // this category's own weapon-list header — Gold/tier1/tier2 read
            // the same way everywhere they show up now, not a one-off badge
            // here and rings elsewhere.
            StatSummaryCard(
                stats: [
                    .init(value: "\(goldCount)/\(category.weapons.count)", label: "mw4.ui.gold".localized(), ringFraction: viewModel.weaponCategoryProgressFraction(category, mode: mode.rawValue), ringColor: .camoGold),
                    .init(value: "\(viewModel.categoryMasteryTier1Count(category, mode: mode.rawValue))/\(category.weapons.count)", label: mode.masteryCamos.tier1.name, labelGradient: viewModel.categoryHasMasteryTier1(category, mode: mode.rawValue) ? mode.masteryCamos.tier1.gradient : nil, ringFraction: category.weapons.isEmpty ? 0 : Double(viewModel.categoryMasteryTier1Count(category, mode: mode.rawValue)) / Double(category.weapons.count), ringColor: mode.masteryCamos.tier1.color, ringGradient: mode.masteryCamos.tier1.gradient),
                    .init(value: "\(viewModel.categoryMasteryTier2Count(category, mode: mode.rawValue))/\(category.weapons.count)", label: mode.masteryCamos.tier2.name, labelGradient: viewModel.categoryHasMasteryTier2(category, mode: mode.rawValue) ? mode.masteryCamos.tier2.gradient : nil, ringFraction: category.weapons.isEmpty ? 0 : Double(viewModel.categoryMasteryTier2Count(category, mode: mode.rawValue)) / Double(category.weapons.count), ringColor: mode.masteryCamos.tier2.color, ringGradient: mode.masteryCamos.tier2.gradient)
                ],
                bordered: false,
                horizontalPadding: 0,
                verticalPadding: 4
            )
        }
        .padding(12)
        .borderedCard(accent: highestTierAchieved?.color)
    }
}

private struct ObjectiveCategoryRow: View {
    let mode: AppMode
    let category: Category
    @EnvironmentObject private var viewModel: TrackerViewModel

    private var fraction: Double { viewModel.objectiveProgressFraction(of: category, mode: mode.rawValue) }
    private var isComplete: Bool { fraction >= 1 && !category.items.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(category.items.count) \("mw4.ui.section.objectives".localized())")
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.2)
                .textCase(.uppercase)
                .foregroundStyle(Color.appInkMuted)
            Text(category.name.resolved())
                .font(.hitmarker(16))
                .foregroundStyle(Color.appInk)
            ProgressBar(fraction: fraction, accent: mode.accent)
        }
        .padding(12)
        .borderedCard(accent: isComplete ? mode.accent : nil)
    }
}

