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
    /// The class the weapon list shows (-1: every weapon), and the list's
    /// filter and sort, shared with a class's own weapon list.
    @AppStorage("mw4_home_class") private var classId = -1
    @AppStorage("mw4_weapon_sort") private var weaponSortRaw = ProgressSort.natural.rawValue
    @AppStorage("mw4_weapon_filter") private var weaponFilterRaw = WeaponFilter.all.rawValue
    private var weaponSortOptions: [ProgressSort] {
        let all: [ProgressSort] = [.natural, .alphabetical, .progressDesc, .progressAsc, .level]
        return viewModel.quickTick ? all.filter { $0 != .level } : all
    }
    private var weaponSort: ProgressSort {
        let saved = ProgressSort(rawValue: weaponSortRaw) ?? .natural
        return weaponSortOptions.contains(saved) ? saved : .natural
    }
    private var weaponFilterBinding: Binding<WeaponFilter> {
        Binding(get: { WeaponFilter(rawValue: weaponFilterRaw) ?? .all }, set: { weaponFilterRaw = $0.rawValue })
    }
    private var weaponSortBinding: Binding<ProgressSort> {
        Binding(get: { weaponSort }, set: { weaponSortRaw = $0.rawValue })
    }

    private var displayedWeapons: [WeaponEntry] {
        let filter = WeaponFilter(rawValue: weaponFilterRaw) ?? .all
        var weapons = (weaponCategories.first { $0.categoryId == classId }.map { [$0] } ?? weaponCategories)
            .flatMap(\.weapons)
            .filter { viewModel.matches(filter, mode: mode.rawValue, weaponId: $0.weaponId) }
        func progress(_ w: WeaponEntry) -> Double { viewModel.camoProgressFraction(weaponId: w.weaponId, mode: mode.rawValue) }
        func level(_ w: WeaponEntry) -> Double {
            Double(viewModel.prestige(for: w.weaponId)) + Double(viewModel.level(for: w.weaponId)) / Double(max(viewModel.maxLevel(for: w), 1))
        }
        switch weaponSort {
        case .natural: break
        case .alphabetical: weapons.sort { $0.name.resolved().localizedCaseInsensitiveCompare($1.name.resolved()) == .orderedAscending }
        case .progressDesc: weapons.sort { progress($0) > progress($1) }
        case .progressAsc: weapons.sort { progress($0) < progress($1) }
        case .level: weapons.sort { level($0) > level($1) }
        }
        return weapons
    }

    /// All, then each class: tap one to narrow the list to it.
    private var classChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("mw4.ui.filter.all".localized(), id: -1)
                ForEach(weaponCategories) { category in
                    chip(category.name.resolved(), id: category.categoryId)
                }
            }
            .padding(.horizontal, 12)
        }
    }

    private func chip(_ title: String, id: Int) -> some View {
        let on = classId == id
        return Button { classId = id } label: {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(on ? Color.black : Color.appInk)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(on ? mode.accent : Color.appSurface, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.appInkMuted.opacity(on ? 0 : 0.25), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("classChip.\(id)")
    }

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


    /// The tab's sections in the order and with the visibility the player
    /// chose in Customise.
    @AppStorage(HomeLayout.orderKey) private var layoutOrder = ""
    @AppStorage(HomeLayout.hiddenKey) private var layoutHidden = ""
    @State private var isCustomising = false
    private var layout: HomeLayout { HomeLayout(order: layoutOrder, hidden: layoutHidden) }

    @ViewBuilder
    private func sectionView(_ section: HomeSection) -> some View {
        switch section {
        case .summary:
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
                    // The camos in order: Gold, Platinum, Harmonic Break,
                    // Divergence; once Divergence is on every weapon, the
                    // Mastery camo being worked on takes its place
                    let locks = CategoryStats.Locks(viewModel: viewModel, mode: mode)
                    let gold = mode.completionist.steps[0], platinum = mode.completionist.steps[1]
                    let platinumCount = viewModel.completionistCount(mode: mode.rawValue, step: 1)
                    var stats: [StatSummaryCard.Stat] = [
                        .init(value: "\(completeCount)/\(total)", label: gold.name, labelGradient: total > 0 && completeCount == total ? gold.gradient : nil, ringFraction: fraction(completeCount, total), ringColor: .camoGold),
                        .init(value: "\(platinumCount)/\(total)", label: platinum.name, labelGradient: total > 0 && platinumCount == total ? platinum.gradient : nil, ringFraction: fraction(platinumCount, total), ringColor: platinum.color, ringGradient: platinum.gradient),
                        .init(value: "\(harmonicCount)/\(total)", label: harmonic.name, labelGradient: total > 0 && harmonicCount == total ? harmonic.gradient : nil, ringFraction: fraction(harmonicCount, total), ringColor: harmonic.color, ringGradient: harmonic.gradient, lockedHint: harmonicCount == 0 ? locks.harmonic : nil)
                    ]
                    let divergenceDone = !mode.hasFinalCamo || (total > 0 && finalCount >= total)
                    if divergenceDone {
                        stats.append(.init(value: "\(masteryProgress.done)/\(masteryProgress.total)", label: mastery.name, labelGradient: masteryDone ? mastery.gradient : nil, ringFraction: fraction(masteryProgress.done, masteryProgress.total), ringColor: mastery.color, ringGradient: mastery.gradient, lockedHint: masteryProgress.done == 0 ? locks.mastery(tier: tier) : nil))
                    } else {
                        stats.append(.init(value: "\(finalCount)/\(total)", label: final.name, labelGradient: nil, ringFraction: fraction(finalCount, total), ringColor: final.color, ringGradient: final.gradient, lockedHint: finalCount == 0 ? locks.final : nil))
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

        case .pinned:
            if let pinnedWeapon {
                Section("mw4.ui.section.pinned".localized()) {
                    // Always the full row, even in a grid: it is one
                    // card, and half a row beside a gap looks lost.
                    CardGrid(items: [pinnedWeapon], columns: columns, fillsRow: true, route: { .weapon($0.weaponId) }) { weapon in
                        WeaponRow(mode: mode, weapon: weapon)
                    }
                }
            }

        case .suggested:
            if !suggestions.isEmpty {
                Section("mw4.ui.section.suggested".localized()) {
                    CardGrid(items: suggestions, columns: columns, route: { .weapon($0.weaponId) }) { suggestion in
                        SuggestionRow(mode: mode, suggestion: suggestion)
                    }
                }
            }

        case .weapons:
            if !weaponCategories.isEmpty {
                Section {
                    classChips
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 4, trailing: 0))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    // A class picked: its Gold, Platinum, Harmonic Break
                    // and Divergence, as on the class's own page
                    if let picked = weaponCategories.first(where: { $0.categoryId == classId }) {
                        StatSummaryCard(stats: CategoryStats.stats(viewModel: viewModel, category: picked, mode: mode))
                            .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 34))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                    // Lined up with the cards below (whose chevron sits
                    // outside the card), no rules either side
                    HStack(spacing: 8) {
                        FilterSortMenu(title: "mw4.ui.filter".localized(), options: WeaponFilter.allCases, label: { $0.label(mode: mode) }, accent: mode.accent, selection: weaponFilterBinding)
                        FilterSortMenu(title: "mw4.ui.sort".localized(), options: weaponSortOptions, label: { $0.label }, accent: mode.accent, selection: weaponSortBinding)
                    }
                    .padding(.trailing, 22)
                    .listRowInsets(EdgeInsets(top: 0, leading: 12, bottom: 6, trailing: 12))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)

                    if displayedWeapons.isEmpty {
                        FilterEmptyRow()
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                    } else {
                        // Weapons first: every gun, or one class, straight to its camos
                        CardGrid(items: displayedWeapons, columns: columns, route: { .weapon($0.weaponId) }) { weapon in
                            WeaponRow(mode: mode, weapon: weapon)
                        }
                    }
                } header: {
                    Text("mw4.ui.section.weapons".localized())
                }
            }

        case .objectives:
            if !objectiveCategories.isEmpty {
                Section("mw4.ui.section.objectives".localized()) {
                    CardGrid(items: objectiveCategories, columns: columns, route: { .objectiveCategory($0.categoryId) }) { category in
                        ObjectiveCategoryRow(mode: mode, category: category)
                    }
                }
            }
        }
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
                    WidgetTipCard(accent: mode.accent)
                        .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    ForEach(layout.visible) { section in
                        sectionView(section)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .listStyle(.plain)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { AdBanner() }
        .readingWidth($width)
        .searchable(text: $searchQuery, prompt: "mw4.ui.search_weapons".localized())
        .navigationTitle(mode.displayNameKey.localized())
        .refreshable { await viewModel.refresh() }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { isCustomising = true } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .accessibilityLabel("mw4.ui.customise".localized())
                .accessibilityIdentifier("customiseHome")
            }
        }
        .onAppear {
            #if DEBUG
            // `SS_CUSTOMISE=1` opens Customise for a screenshot.
            if ProcessInfo.processInfo.environment["SS_CUSTOMISE"] == "1" { isCustomising = true }
            #endif
        }
        .sheet(isPresented: $isCustomising) {
            CustomiseHomeSheet(
                order: $layoutOrder, hidden: $layoutHidden, accent: mode.accent,
                // Objectives only when some mode has any (none at launch).
                offered: HomeSection.allCases.filter { $0 != .objectives || viewModel.modes.values.contains { !$0.objectives.isEmpty } }
            )
            .environmentObject(viewModel)
        }
    }

}

private struct SuggestionRow: View {
    let mode: AppMode
    let suggestion: Suggestion
    @EnvironmentObject private var viewModel: TrackerViewModel

    private var fraction: Double { viewModel.camoProgressFraction(weaponId: suggestion.weaponId, mode: mode.rawValue) }

    /// The camo's own gradient when it has one, else its color.
    private var badgeFill: AnyShapeStyle {
        if let colors = suggestion.gradient, colors.count > 1 {
            return AnyShapeStyle(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
        }
        return AnyShapeStyle(suggestion.highlight ?? mode.accent)
    }

    private var subtitleStyle: AnyShapeStyle {
        if let colors = suggestion.gradient, colors.count > 1 {
            return AnyShapeStyle(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
        }
        return AnyShapeStyle(Color.appInkMuted)
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: suggestion.highlight != nil ? "diamond.fill" : "arrow.up.forward")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.appBackground)
                .frame(width: 30, height: 30)
                .background(Circle().fill(badgeFill))

            VStack(alignment: .leading, spacing: 4) {
                Text(suggestion.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.appInk)
                Text(suggestion.subtitle)
                    .font(.system(size: 12.5, weight: suggestion.gradient != nil ? .semibold : .regular))
                    .foregroundStyle(subtitleStyle)
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
    /// What a mode-wide step still waits for, nil once it's open: Harmonic
    /// Break on every Platinum, the final camo on enough Harmonic Breaks,
    /// Mastery on the final camo (or the tier before).
    @MainActor
    struct Locks {
        let viewModel: TrackerViewModel
        let mode: AppMode

        var harmonic: String? {
            let gate = viewModel.completionistModeGateProgress(mode: mode.rawValue, step: 2)
            guard gate.done < gate.total else { return nil }
            return "\(gate.done)/\(gate.total) \(mode.completionist.steps[1].name)"
        }

        var final: String? {
            let needed = viewModel.harmonicBreaksNeeded(mode: mode.rawValue)
            let have = viewModel.harmonicBreakCount(mode: mode.rawValue)
            guard needed > 0, have < needed else { return nil }
            return "\(have)/\(needed) \(mode.completionist.steps[2].name)"
        }

        func mastery(tier: Int) -> String? {
            guard viewModel.masteryKind(mode: mode.rawValue, tier: tier) == .mode,
                  !viewModel.isModeMasteryAvailable(mode: mode.rawValue, tier: tier) else { return nil }
            if tier == 1 {
                let total = viewModel.totalWeaponCount
                return "\(min(viewModel.lastCompletionistCount(mode: mode.rawValue), total))/\(total) \(mode.lastCompletionist.name)"
            }
            let tiers = mode.masteryCamos
            return [tiers.tier1, tiers.tier2, tiers.tier3][tier - 2].name
        }
    }

    @MainActor
    static func stats(viewModel: TrackerViewModel, category: WeaponCategory, mode: AppMode) -> [StatSummaryCard.Stat] {
        let count = category.weapons.count
        let fraction: (Int) -> Double = { count > 0 ? Double($0) / Double(count) : 0 }
        let gold = viewModel.goldWeaponCount(in: category, mode: mode.rawValue)
        let locks = Locks(viewModel: viewModel, mode: mode)
        let platinum = mode.completionist.steps[1]
        let platinumCount = viewModel.categoryCompletionistCount(category, mode: mode.rawValue, step: 1)
        let harmonic = mode.completionist.steps[2]
        let harmonicCount = viewModel.categoryCompletionistCount(category, mode: mode.rawValue, step: 2)
        let final = mode.completionist.final
        let finalCount = viewModel.categoryFinalCount(category, mode: mode.rawValue)
        var stats: [StatSummaryCard.Stat] = [
            .init(value: "\(gold)/\(count)", label: mode.completionist.steps[0].name, labelGradient: count > 0 && gold == count ? mode.completionist.steps[0].gradient : nil, ringFraction: viewModel.weaponCategoryProgressFraction(category, mode: mode.rawValue), ringColor: .camoGold),
            // Platinum opens when every weapon in the class has Gold
            .init(value: "\(platinumCount)/\(count)", label: platinum.name, labelGradient: count > 0 && platinumCount == count ? platinum.gradient : nil, ringFraction: fraction(platinumCount), ringColor: platinum.color, ringGradient: platinum.gradient,
                  lockedHint: platinumCount == 0 && gold < count ? "\(gold)/\(count) \("mw4.ui.gold".localized())" : nil),
            .init(value: "\(harmonicCount)/\(count)", label: harmonic.name, labelGradient: count > 0 && harmonicCount == count ? harmonic.gradient : nil, ringFraction: fraction(harmonicCount), ringColor: harmonic.color, ringGradient: harmonic.gradient, lockedHint: harmonicCount == 0 ? locks.harmonic : nil)
        ]
        // The final camo's ring, when the track has one.
        if mode.hasFinalCamo {
            stats.append(.init(value: "\(finalCount)/\(count)", label: final.name, labelGradient: count > 0 && finalCount == count ? final.gradient : nil, ringFraction: fraction(finalCount), ringColor: final.color, ringGradient: final.gradient, lockedHint: finalCount == 0 ? locks.final : nil))
        }
        return stats
    }
}

// MARK: - Customise

/// A section of a mode tab, in the order Customise lists them by default.
enum HomeSection: String, CaseIterable, Identifiable {
    case summary, pinned, suggested, weapons, objectives

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .summary: return "mw4.ui.section.summary"
        case .pinned: return "mw4.ui.section.pinned"
        case .suggested: return "mw4.ui.section.suggested"
        case .weapons: return "mw4.ui.section.weapons"
        case .objectives: return "mw4.ui.section.objectives"
        }
    }

    var symbol: String {
        switch self {
        case .summary: return "chart.pie"
        case .pinned: return "pin"
        case .suggested: return "arrow.up.right.circle"
        case .weapons: return "square.grid.2x2"
        case .objectives: return "checklist"
        }
    }

    /// Weapons is what the tab is for, so it can move but not go.
    var canHide: Bool { self != .weapons }
}

/// The order and visibility of a mode tab's sections, stored as two
/// comma-separated strings so `@AppStorage` can hold them. The same layout
/// applies on every mode tab; a section a tab has nothing for (Objectives
/// outside DMZ, Pinned with nothing pinned) simply doesn't draw.
struct HomeLayout {
    static let orderKey = "mw4_home_order"
    static let hiddenKey = "mw4_home_hidden"

    let order: [HomeSection]
    let hidden: Set<HomeSection>

    init(order: String, hidden: String) {
        let saved = order.split(separator: ",").compactMap { HomeSection(rawValue: String($0)) }
        var seen = Set<HomeSection>()
        let unique = saved.filter { seen.insert($0).inserted }
        // Anything new since the order was saved goes in its default place.
        var full = unique
        for section in HomeSection.allCases where !full.contains(section) {
            let before = HomeSection.allCases.prefix { $0 != section }.last { full.contains($0) }
            let at = before.flatMap { full.firstIndex(of: $0) }.map { $0 + 1 } ?? 0
            full.insert(section, at: at)
        }
        self.order = full
        self.hidden = Set(hidden.split(separator: ",").compactMap { HomeSection(rawValue: String($0)) }.filter(\.canHide))
    }

    var visible: [HomeSection] { order.filter { !hidden.contains($0) } }

    static func encode(_ sections: [HomeSection]) -> String { sections.map(\.rawValue).joined(separator: ",") }
    static func encode(_ sections: Set<HomeSection>) -> String { encode(HomeSection.allCases.filter(sections.contains)) }
}

/// Show, hide and reorder a mode tab's sections.
struct CustomiseHomeSheet: View {
    @Binding var order: String
    @Binding var hidden: String
    let accent: Color
    /// The sections worth listing; the rest keep their saved place unseen.
    var offered: [HomeSection] = HomeSection.allCases
    @AppStorage(ChallengeRow.showLockedKey) private var showLockedChallenges = false
    @AppStorage(CardOutline.key) private var cardOutline = CardOutline.prestige.rawValue
    @AppStorage(CloudSync.enabledKey) private var iCloudSync = true
    @AppStorage(AppLanguage.key) private var languageRaw = ""
    @EnvironmentObject private var viewModel: TrackerViewModel
    @ObservedObject private var premium = Premium.shared
    @State private var showsPremium = false
    @State private var showsIcons = false
    @Environment(\.dismiss) private var dismiss

    private var layout: HomeLayout { HomeLayout(order: order, hidden: hidden) }
    private var rows: [HomeSection] { layout.order.filter(offered.contains) }

    var body: some View {
        NavigationStack {
            List {
                if locked {
                    Section {
                        Button { showsPremium = true } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 30, height: 30)
                                    .background(Circle().fill(accent))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("mw4.ui.premium.customise_title".localized()).font(.headline).foregroundStyle(Color.appInk)
                                    Text("mw4.ui.premium.customise_body".localized()).font(.caption).foregroundStyle(Color.appInkMuted)
                                }
                            }
                        }
                        .accessibilityIdentifier("customise.premiumCard")
                    }
                }
                Section {
                    // Inset from the row's edges: flush, the List clipped the
                    // chips' rounded borders at the corners.
                    PlayedModesPicker()
                        .padding(.vertical, 4)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                } header: {
                    Text("mw4.ui.modes".localized())
                } footer: {
                    Text("mw4.ui.modes.footer".localized())
                }

                Section {
                    Picker("mw4.ui.language".localized(), selection: $languageRaw) {
                        Text("mw4.ui.language.system".localized()).tag("")
                        ForEach(AppLanguage.supported, id: \.code) { language in
                            Text(verbatim: language.name).tag(language.code)
                        }
                    }
                    .tint(accent)
                    .accessibilityIdentifier("customise.language")
                }

                Section {
                    ForEach(rows) { section in
                        HStack(spacing: 12) {
                            Image(systemName: section.symbol)
                                .foregroundStyle(accent)
                                .frame(width: 24)
                            Toggle(section.titleKey.localized(), isOn: binding(for: section))
                                .tint(accent)
                                .disabled(!section.canHide || locked)
                        }
                        .moveDisabled(locked)
                        .accessibilityIdentifier("customise.\(section.rawValue)")
                    }
                    .onMove { from, to in
                        var sections = rows
                        sections.move(fromOffsets: from, toOffset: to)
                        // Unlisted sections go back where they were.
                        for (index, section) in layout.order.enumerated() where !offered.contains(section) {
                            sections.insert(section, at: min(index, sections.count))
                        }
                        order = HomeLayout.encode(sections)
                    }
                } header: {
                    premiumHeader(nil)
                } footer: {
                    Text("mw4.ui.customise.footer".localized())
                }

                Section {
                    Toggle("mw4.ui.quick_tick.title".localized(), isOn: Binding(
                        get: { viewModel.quickTick },
                        set: { viewModel.setQuickTick($0) }))
                        .tint(accent)
                        .disabled(locked)
                        .accessibilityIdentifier("customise.quickTick")
                } header: {
                    premiumHeader("mw4.ui.tracking".localized())
                } footer: {
                    Text("mw4.ui.quick_tick.footer".localized())
                }

                Section {
                    Toggle("mw4.ui.customise.locked_title".localized(), isOn: $showLockedChallenges)
                        .tint(accent)
                        .disabled(locked)
                        .accessibilityIdentifier("customise.showLocked")
                } header: {
                    premiumHeader(nil)
                } footer: {
                    Text("mw4.ui.customise.locked_footer".localized())
                }

                Section {
                    Picker("mw4.ui.card_outline.title".localized(), selection: $cardOutline) {
                        ForEach(CardOutline.allCases, id: \.rawValue) { option in
                            Text(option.titleKey.localized()).tag(option.rawValue)
                        }
                    }
                    .tint(accent)
                    .disabled(locked)
                    .accessibilityIdentifier("customise.cardOutline")
                } header: {
                    premiumHeader(nil)
                } footer: {
                    Text("mw4.ui.card_outline.footer".localized())
                }

                Section {
                    Toggle("mw4.ui.icloud.title".localized(), isOn: $iCloudSync)
                        .tint(accent)
                        .accessibilityIdentifier("customise.iCloudSync")
                } footer: {
                    Text("mw4.ui.icloud.footer".localized())
                }

                Section {
                    // A button, not a NavigationLink: the list is in edit mode
                    Button { showsIcons = true } label: {
                        HStack {
                            Label("mw4.ui.app_icon.title".localized(), systemImage: "app.badge.fill")
                            Spacer()
                            Image(AppIconChoice.current.previewName)
                                .resizable()
                                .frame(width: 28, height: 28)
                                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                        }
                    }
                    .foregroundStyle(accent)
                    .accessibilityIdentifier("customise.appIcon")
                }

                Section {
                    Button { showsPremium = true } label: {
                        Label(premium.isPremium ? "mw4.ui.premium.active".localized() : "mw4.ui.premium.title".localized(),
                              systemImage: premium.isPremium ? "checkmark.seal.fill" : "sparkles")
                    }
                    .foregroundStyle(accent)
                    .accessibilityIdentifier("customise.premium")
                    if !premium.isPremium {
                        Button("mw4.ui.premium.restore".localized()) {
                            Task { await premium.restore() }
                        }
                        .foregroundStyle(accent)
                    }
                } footer: {
                    Text("mw4.ui.premium.subtitle".localized())
                }

                if !locked {
                    Section {
                        Button("mw4.ui.customise.reset".localized()) {
                            order = ""
                            hidden = ""
                        }
                        .foregroundStyle(accent)
                    }
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationDestination(isPresented: $showsIcons) { AppIconPicker(accent: accent) }
            #if DEBUG
            // `SS_APP_ICONS=1` (with SS_CUSTOMISE=1) opens App icon too.
            .onAppear { if ProcessInfo.processInfo.environment["SS_APP_ICONS"] == "1" { showsIcons = true } }
            #endif
            .navigationTitle("mw4.ui.customise".localized())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("mw4.ui.done".localized()) { dismiss() }
                        .foregroundStyle(accent)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .sheet(isPresented: $showsPremium) { PremiumView() }
    }

    /// Free players: the layout and look settings show, locked, and open
    /// Premium; modes, language and iCloud stay free.
    private var locked: Bool { !premium.isPremium }

    /// A section header with a Premium lock for free players; tapping it
    /// opens Premium.
    @ViewBuilder private func premiumHeader(_ title: String?) -> some View {
        if locked {
            Button { showsPremium = true } label: {
                HStack(spacing: 6) {
                    if let title { Text(title) }
                    Spacer(minLength: 0)
                    Label("mw4.ui.app_icon.premium".localized(), systemImage: "lock.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(accent)
                }
            }
            .buttonStyle(.plain)
        } else if let title {
            Text(title)
        }
    }

    private func binding(for section: HomeSection) -> Binding<Bool> {
        Binding(
            get: { !layout.hidden.contains(section) },
            set: { shown in
                var set = layout.hidden
                if shown { set.remove(section) } else { set.insert(section) }
                hidden = HomeLayout.encode(set)
            }
        )
    }
}
