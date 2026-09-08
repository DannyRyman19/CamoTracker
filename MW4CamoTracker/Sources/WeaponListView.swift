import SwiftUI

/// Weapons within a catalog category. The weapon list itself is identical in
/// every mode (it's the shared catalog) — only each row's camo progress bar
/// changes, pulled from the active mode's `weaponCamos`.
struct WeaponListView: View {
    let mode: AppMode
    let category: WeaponCategory
    @EnvironmentObject private var viewModel: TrackerViewModel

    /// Shared across every category screen (global, not per-category) so the
    /// choice sticks as you move between categories — same persisted-filter
    /// idea as the sibling BO7 Camo Tracker app's `FilterContext`.
    @AppStorage("mw4_weapon_sort") private var sortRaw = ProgressSort.natural.rawValue
    @AppStorage("mw4_weapon_filter") private var filterRaw = CompletionFilter.all.rawValue
    private static let sortOptions: [ProgressSort] = [.natural, .alphabetical, .progressDesc, .progressAsc, .level]

    private var sort: ProgressSort { ProgressSort(rawValue: sortRaw) ?? .natural }
    private var filter: CompletionFilter { CompletionFilter(rawValue: filterRaw) ?? .all }
    private var sortBinding: Binding<ProgressSort> {
        Binding(get: { sort }, set: { sortRaw = $0.rawValue })
    }
    private var filterBinding: Binding<CompletionFilter> {
        Binding(get: { filter }, set: { filterRaw = $0.rawValue })
    }

    private var goldCount: Int { viewModel.goldWeaponCount(in: category, mode: mode.rawValue) }
    private var hasMasteryTier1: Bool { viewModel.categoryHasMasteryTier1(category, mode: mode.rawValue) }
    private var hasMasteryTier2: Bool { viewModel.categoryHasMasteryTier2(category, mode: mode.rawValue) }

    private var displayedWeapons: [WeaponEntry] {
        var weapons = category.weapons
        switch filter {
        case .all:
            break
        case .incomplete:
            weapons = weapons.filter { !viewModel.allCamosComplete(weaponId: $0.weaponId, mode: mode.rawValue) }
        case .complete:
            weapons = weapons.filter { viewModel.allCamosComplete(weaponId: $0.weaponId, mode: mode.rawValue) }
        }
        switch sort {
        case .natural:
            break
        case .alphabetical:
            weapons.sort { $0.name.resolved().localizedCaseInsensitiveCompare($1.name.resolved()) == .orderedAscending }
        case .progressDesc:
            weapons.sort { viewModel.camoProgressFraction(weaponId: $0.weaponId, mode: mode.rawValue) > viewModel.camoProgressFraction(weaponId: $1.weaponId, mode: mode.rawValue) }
        case .progressAsc:
            weapons.sort { viewModel.camoProgressFraction(weaponId: $0.weaponId, mode: mode.rawValue) < viewModel.camoProgressFraction(weaponId: $1.weaponId, mode: mode.rawValue) }
        case .level:
            weapons.sort { levelFraction($0) > levelFraction($1) }
        }
        return weapons
    }

    private func levelFraction(_ weapon: WeaponEntry) -> Double {
        Double(viewModel.level(for: weapon.weaponId)) / Double(max(weapon.maxLevel, 1))
    }

    var body: some View {
        ZStack {
            AppBackground(accent: mode.accent)
            List {
                Section {
                    // No separate leading hero ring here — Gold's own column
                    // carries the ring instead, since in this per-category
                    // view "overall progress" and "Gold progress" are the
                    // same number, unlike the root tab's blended completion
                    // metric (which really is distinct from any one column).
                    StatSummaryCard(
                        stats: [
                            .init(value: "\(goldCount)/\(category.weapons.count)", label: "mw4.ui.gold".localized(), ringFraction: viewModel.weaponCategoryProgressFraction(category, mode: mode.rawValue), ringColor: .camoGold),
                            .init(value: "\(viewModel.categoryMasteryTier1Count(category, mode: mode.rawValue))/\(category.weapons.count)", label: mode.masteryCamos.tier1.name, labelGradient: hasMasteryTier1 ? mode.masteryCamos.tier1.gradient : nil, ringFraction: category.weapons.isEmpty ? 0 : Double(viewModel.categoryMasteryTier1Count(category, mode: mode.rawValue)) / Double(category.weapons.count), ringColor: mode.masteryCamos.tier1.color, ringGradient: mode.masteryCamos.tier1.gradient),
                            .init(value: "\(viewModel.categoryMasteryTier2Count(category, mode: mode.rawValue))/\(category.weapons.count)", label: mode.masteryCamos.tier2.name, labelGradient: hasMasteryTier2 ? mode.masteryCamos.tier2.gradient : nil, ringFraction: category.weapons.isEmpty ? 0 : Double(viewModel.categoryMasteryTier2Count(category, mode: mode.rawValue)) / Double(category.weapons.count), ringColor: mode.masteryCamos.tier2.color, ringGradient: mode.masteryCamos.tier2.gradient)
                        ]
                    )
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)

                HStack(spacing: 8) {
                    FilterSortMenu(title: "mw4.ui.filter".localized(), options: CompletionFilter.allCases, label: { $0.label }, accent: mode.accent, selection: filterBinding)
                    FilterSortMenu(title: "mw4.ui.sort".localized(), options: Self.sortOptions, label: { $0.label }, accent: mode.accent, selection: sortBinding)
                }
                .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                .listRowBackground(Color.clear)

                if displayedWeapons.isEmpty {
                    FilterEmptyRow()
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(displayedWeapons) { weapon in
                        NavigationLink(value: Route.weapon(weapon.weaponId)) {
                            WeaponRow(mode: mode, weapon: weapon, showsCamoCount: false)
                        }
                        .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                        .listRowBackground(Color.clear)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .listStyle(.plain)
        }
        .navigationTitle(category.name.resolved())
    }
}

/// Styled after the in-game loadout slot card: a small tracked category
/// eyebrow paired with a tier-pip readout on one line, the weapon itself on
/// the next. A weapon that's gone Gold gets the same "equipped" gold wash
/// `borderedCard` gives any accented card, echoing that menu's highlighted
/// selected slot.
struct WeaponRow: View {
    let mode: AppMode
    let weapon: WeaponEntry
    /// Off inside `WeaponListView`, where every row is already scoped to one
    /// category by the screen's own nav title and the header card already
    /// covers camo counts for the whole category. Stays on for
    /// `CategoryListView`'s cross-category contexts (search results, the
    /// pinned weapon), where this weapon's own "x/y camos done" is more
    /// useful at a glance than naming which category it's in.
    var showsCamoCount = true
    @EnvironmentObject private var viewModel: TrackerViewModel

    private var camos: [ChallengeItem] { viewModel.camos(weaponId: weapon.weaponId, mode: mode.rawValue) }
    private var isGold: Bool { viewModel.allCamosComplete(weaponId: weapon.weaponId, mode: mode.rawValue) }
    /// This weapon's own tier1/tier2 Mastery — each diamond glyph reflects
    /// the individual weapon's status now (BO7's Mastery camos are earned
    /// per weapon), not the whole category's.
    private var hasMasteryTier1: Bool {
        viewModel.isWeaponMasteryComplete(mode: mode.rawValue, weaponId: weapon.weaponId, tier: 1)
    }
    private var hasMasteryTier2: Bool {
        viewModel.isWeaponMasteryComplete(mode: mode.rawValue, weaponId: weapon.weaponId, tier: 2)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // No longer its own row: with `showsCamoCount` off (every
            // `WeaponListView` row), a whole top row here was just empty
            // space to the left of the pips. Sitting right after the name
            // uses that space instead of wasting it.
            if showsCamoCount {
                let counts = viewModel.camoCounts(weaponId: weapon.weaponId, mode: mode.rawValue)
                Text("\(counts.done)/\(counts.total) \("mw4.ui.section.camos".localized())")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.2)
                    .textCase(.uppercase)
                    .foregroundStyle(Color.appInkMuted)
            }

            HStack(spacing: 12) {
                WeaponThumbnail(urlString: weapon.imageURL, size: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Text(weapon.name.resolved())
                        .font(.hitmarker(15))
                        .foregroundStyle(Color.appInk)
                        .lineLimit(1)
                    AcquiredByLabel(weapon: weapon, font: .system(size: 10.5), color: .appInkMuted)
                }
                Spacer(minLength: 8)
                // Pips stay right-aligned above the level, out of the name's
                // way — sharing a line with the name pushed long weapon
                // names off the edge instead of just truncating gracefully.
                VStack(alignment: .trailing, spacing: 4) {
                    if !camos.isEmpty {
                        CamoPipRow(
                            camos: camos,
                            isComplete: { viewModel.isCamoComplete(mode: mode.rawValue, weaponId: weapon.weaponId, camo: $0) },
                            filledColor: mode.accent,
                            masteryTiers: [
                                .init(achieved: hasMasteryTier1, color: mode.masteryCamos.tier1.color),
                                .init(achieved: hasMasteryTier2, color: mode.masteryCamos.tier2.color)
                            ]
                        )
                    }
                    // Weapon level is global — the same number shows up under every mode tab.
                    Text("LVL \(viewModel.level(for: weapon.weaponId))/\(weapon.maxLevel)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Color.appInkMuted)
                }
            }
        }
        .padding(12)
        .borderedCard(accent: isGold ? .camoGold : nil)
    }
}
