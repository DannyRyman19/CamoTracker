import SwiftUI

/// Top of each mode tab: a Suggested section (what to grind next), the shared
/// weapon categories (from the catalog), and that mode's own mode-exclusive
/// objectives, if it has any (DMZ only, for now).
struct CategoryListView: View {
    let mode: AppMode
    @EnvironmentObject private var viewModel: TrackerViewModel

    private var weaponCategories: [WeaponCategory] { viewModel.catalog?.categories ?? [] }
    private var objectiveCategories: [Category] { viewModel.modes[mode.rawValue]?.objectives ?? [] }
    private var suggestions: [Suggestion] { viewModel.suggestions(mode: mode.rawValue) }

    var body: some View {
        ZStack {
            AppBackground(accent: mode.accent)
            List {
                if !suggestions.isEmpty {
                    Section("Suggested") {
                        ForEach(suggestions) { suggestion in
                            NavigationLink(value: Route.weapon(suggestion.weaponId)) {
                                SuggestionRow(mode: mode, suggestion: suggestion)
                            }
                        }
                    }
                    .listRowBackground(Color.appSurface)
                }

                if !weaponCategories.isEmpty {
                    Section("Weapons") {
                        ForEach(weaponCategories) { category in
                            NavigationLink(value: Route.weaponCategory(category.categoryId)) {
                                WeaponCategoryRow(mode: mode, category: category)
                            }
                        }
                    }
                    .listRowBackground(Color.appSurface)
                }

                if !objectiveCategories.isEmpty {
                    Section("Objectives") {
                        ForEach(objectiveCategories) { category in
                            NavigationLink(value: Route.objectiveCategory(category.categoryId)) {
                                ObjectiveCategoryRow(mode: mode, category: category)
                            }
                        }
                    }
                    .listRowBackground(Color.appSurface)
                }
            }
            .scrollContentBackground(.hidden)
            .listStyle(.plain)
        }
        .navigationTitle(mode.displayNameKey.localized())
        .refreshable { await viewModel.refresh() }
    }
}

private struct SuggestionRow: View {
    let mode: AppMode
    let suggestion: Suggestion

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: suggestion.isDiamondCritical ? "diamond.fill" : "arrow.up.forward.circle.fill")
                .foregroundStyle(suggestion.isDiamondCritical ? Color.camoDiamond : mode.accent)
            VStack(alignment: .leading, spacing: 3) {
                Text(suggestion.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.appInk)
                Text(suggestion.subtitle)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Color.appInkMuted)
            }
        }
        .padding(.vertical, 3)
    }
}

private struct WeaponCategoryRow: View {
    let mode: AppMode
    let category: WeaponCategory
    @EnvironmentObject private var viewModel: TrackerViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(category.nameKey.localized())
                .font(.hitmarker(16))
                .foregroundStyle(Color.appInk)
            ProgressBar(fraction: viewModel.weaponCategoryProgressFraction(category, mode: mode.rawValue), accent: mode.accent)
        }
        .padding(.vertical, 4)
    }
}

private struct ObjectiveCategoryRow: View {
    let mode: AppMode
    let category: Category
    @EnvironmentObject private var viewModel: TrackerViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(category.nameKey.localized())
                .font(.hitmarker(16))
                .foregroundStyle(Color.appInk)
            ProgressBar(fraction: viewModel.objectiveProgressFraction(of: category, mode: mode.rawValue), accent: mode.accent)
        }
        .padding(.vertical, 4)
    }
}
