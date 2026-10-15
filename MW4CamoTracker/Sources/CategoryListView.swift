import SwiftUI

/// Top of each mode tab: a Suggested section (what to grind next), the shared
/// weapon categories (from the catalog), and that mode's own mode-exclusive
/// objectives, if it has any (DMZ only, for now).
struct CategoryListView: View {
    let mode: AppMode
    @EnvironmentObject private var viewModel: TrackerViewModel
    @State private var searchQuery = ""
    @State private var width: CGFloat = 0
    private var columns: Int { WideLayout.columns(for: width) }

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
                    CardGrid(items: searchResults, columns: columns, route: { .weapon($0.weaponId) }) { weapon in
                        WeaponRow(mode: mode, weapon: weapon)
                    }
                } else {
                    // No separate leading hero ring — with Gold/tier1/tier2/
                    // tier3 (and, once earned, 100%+) all shown as their own
                    // labeled rings below, an extra unlabeled blended ring
                    // next to them read as redundant clutter rather than a
                    // distinct number worth acting on.
                    StatSummaryCard(
                        stats: {
                            let total = viewModel.totalWeaponCount
                            let fraction: (Int, Int) -> Double = { done, of in of > 0 ? Double(done) / Double(of) : 0 }
                            let completeCount = viewModel.totalGoldWeaponCount(mode: mode.rawValue)
                            let harmonic = mode.completionist.steps[2]
                            let harmonicCount = viewModel.harmonicBreakCount(mode: mode.rawValue)
                            let final = mode.completionist.final
                            let finalCount = viewModel.finalCamoCount(mode: mode.rawValue)
                            // The Mastery tier being worked on: the first not
                            // yet earned, or the last once all three are.
                            let tier = (1...3).first { !viewModel.isMasteryAchieved(mode: mode.rawValue, tier: $0) } ?? 3
                            let tiers = mode.masteryCamos
                            let mastery = [tiers.tier1, tiers.tier2, tiers.tier3][tier - 1]
                            let masteryProgress = viewModel.masteryProgress(mode: mode.rawValue, tier: tier)
                            let masteryDone = viewModel.isMasteryAchieved(mode: mode.rawValue, tier: tier)
                            var stats: [StatSummaryCard.Stat] = [
                                .init(value: "\(completeCount)/\(total)", label: "mw4.ui.gold".localized(), ringFraction: fraction(completeCount, total), ringColor: .camoGold),
                                .init(value: "\(harmonicCount)/\(total)", label: harmonic.name, labelGradient: total > 0 && harmonicCount == total ? harmonic.gradient : nil, ringFraction: fraction(harmonicCount, total), ringColor: harmonic.color, ringGradient: harmonic.gradient),
                                .init(value: "\(masteryProgress.done)/\(masteryProgress.total)", label: mastery.name, labelGradient: masteryDone ? mastery.gradient : nil, ringFraction: fraction(masteryProgress.done, masteryProgress.total), ringColor: mastery.color, ringGradient: mastery.gradient)
                            ]
                            if mode.hasFinalCamo {
                                stats.insert(.init(value: "\(finalCount)/\(total)", label: final.name, labelGradient: total > 0 && finalCount == total ? final.gradient : nil, ringFraction: fraction(finalCount, total), ringColor: final.color, ringGradient: final.gradient), at: 2)
                            }
                            // Only worth showing once the last Mastery camo is
                            // earned; before then "100%+" is a goal past one
                            // not reached yet.
                            if viewModel.isMasteryAchieved(mode: mode.rawValue, tier: 3) {
                                let fullRoster = viewModel.fullRosterFinalProgress(mode: mode.rawValue)
                                stats.append(.init(value: "\(fullRoster.done)/\(fullRoster.total)", label: "mw4.ui.stats.100_plus".localized(), labelGradient: viewModel.is100PlusAchieved(mode: mode.rawValue) ? .platinum : nil, ringFraction: fraction(fullRoster.done, fullRoster.total), ringColor: .camoPlatinum, ringGradient: .platinum))
                            }
                            return stats
                        }()
                    )
                    .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                    .listRowBackground(Color.clear)

                    if let pinnedWeapon {
                        Section("mw4.ui.section.pinned".localized()) {
                            // Always the full row, even in a grid: it is one
                            // card, and half a row beside a gap looks lost.
                            CardGrid(items: [pinnedWeapon], columns: columns, fillsRow: true, route: { .weapon($0.weaponId) }) { weapon in
                                WeaponRow(mode: mode, weapon: weapon)
                            }
                        }
                    }

                    if !suggestions.isEmpty {
                        Section("mw4.ui.section.suggested".localized()) {
                            CardGrid(items: suggestions, columns: columns, route: { .weapon($0.weaponId) }) { suggestion in
                                SuggestionRow(mode: mode, suggestion: suggestion)
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
                                // Every weapon in one list first, then each class.
                                if let all = viewModel.allWeaponsCategory {
                                    CardGrid(items: [all], columns: columns, fillsRow: true, route: { _ in .allWeapons }) { category in
                                        WeaponCategoryRow(mode: mode, category: category)
                                    }
                                }
                                CardGrid(items: displayedCategories, columns: columns, route: { .weaponCategory($0.categoryId) }) { category in
                                    WeaponCategoryRow(mode: mode, category: category)
                                }
                            }
                        }
                    }

                    if !objectiveCategories.isEmpty {
                        Section("mw4.ui.section.objectives".localized()) {
                            CardGrid(items: objectiveCategories, columns: columns, route: { .objectiveCategory($0.categoryId) }) { category in
                                ObjectiveCategoryRow(mode: mode, category: category)
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .listStyle(.plain)
        }
        .readingWidth($width)
        .searchable(text: $searchQuery, prompt: "mw4.ui.search_weapons".localized())
        .navigationTitle(mode.displayNameKey.localized())
        .refreshable { await viewModel.refresh() }
    }

}

private struct SuggestionRow: View {
    let mode: AppMode
    let suggestion: Suggestion
    @EnvironmentObject private var viewModel: TrackerViewModel

    private var fraction: Double { viewModel.camoProgressFraction(weaponId: suggestion.weaponId, mode: mode.rawValue) }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: suggestion.highlight != nil ? "diamond.fill" : "arrow.up.forward")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.appBackground)
                .frame(width: 30, height: 30)
                .background(Circle().fill(suggestion.highlight ?? mode.accent))

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


    /// The best Completionist camo every weapon in this category has, for
    /// the card's border: the final camo, else Harmonic Break, else none.
    private var categoryAccent: Color? {
        guard !category.weapons.isEmpty else { return nil }
        let count = category.weapons.count
        if mode.hasFinalCamo, viewModel.categoryFinalCount(category, mode: mode.rawValue) == count { return mode.completionist.final.color }
        if viewModel.categoryCompletionistCount(category, mode: mode.rawValue, step: 2) == count { return mode.completionist.steps[2].color }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(category.weapons.count) \("mw4.ui.section.weapons".localized())")
                .font(.system(size: 11, weight: .bold))
                .textCase(.uppercase)
                .foregroundStyle(Color.appInkMuted)

            Text(category.name.resolved())
                .font(.hitmarker(16))
                .foregroundStyle(Color.appInk)

            // The same rings as this category's own weapon-list header.
            StatSummaryCard(
                stats: CategoryStats.stats(viewModel: viewModel, category: category, mode: mode),
                bordered: false,
                horizontalPadding: 0,
                verticalPadding: 4
            )
        }
        .padding(12)
        .borderedCard(accent: categoryAccent)
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
                .font(.system(size: 11, weight: .bold))
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


/// A weapon category's three rings, on its card here and atop its own weapon
/// list: camo lists complete, Harmonic Break, and the final camo.
enum CategoryStats {
    @MainActor
    static func stats(viewModel: TrackerViewModel, category: WeaponCategory, mode: AppMode) -> [StatSummaryCard.Stat] {
        let count = category.weapons.count
        let fraction: (Int) -> Double = { count > 0 ? Double($0) / Double(count) : 0 }
        let harmonic = mode.completionist.steps[2]
        let harmonicCount = viewModel.categoryCompletionistCount(category, mode: mode.rawValue, step: 2)
        let final = mode.completionist.final
        let finalCount = viewModel.categoryFinalCount(category, mode: mode.rawValue)
        var stats: [StatSummaryCard.Stat] = [
            .init(value: "\(viewModel.goldWeaponCount(in: category, mode: mode.rawValue))/\(count)", label: "mw4.ui.gold".localized(), ringFraction: viewModel.weaponCategoryProgressFraction(category, mode: mode.rawValue), ringColor: .camoGold),
            .init(value: "\(harmonicCount)/\(count)", label: harmonic.name, labelGradient: count > 0 && harmonicCount == count ? harmonic.gradient : nil, ringFraction: fraction(harmonicCount), ringColor: harmonic.color, ringGradient: harmonic.gradient)
        ]
        // The final camo's ring, when the track has one.
        if mode.hasFinalCamo {
            stats.append(.init(value: "\(finalCount)/\(count)", label: final.name, labelGradient: count > 0 && finalCount == count ? final.gradient : nil, ringFraction: fraction(finalCount), ringColor: final.color, ringGradient: final.gradient))
        }
        return stats
    }
}
