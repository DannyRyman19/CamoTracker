import SwiftUI

/// Top of each mode tab: the shared weapon categories (from the catalog),
/// plus that mode's own mode-exclusive objectives, if it has any (DMZ only, for now).
struct CategoryListView: View {
    let mode: AppMode
    @EnvironmentObject private var viewModel: TrackerViewModel

    private var weaponCategories: [WeaponCategory] { viewModel.catalog?.categories ?? [] }
    private var objectiveCategories: [Category] { viewModel.modes[mode.rawValue]?.objectives ?? [] }

    var body: some View {
        ZStack {
            AppBackground(accent: mode.accent)
            List {
                if !weaponCategories.isEmpty {
                    Section("Weapons") {
                        ForEach(weaponCategories) { category in
                            NavigationLink {
                                WeaponListView(mode: mode, category: category)
                            } label: {
                                WeaponCategoryRow(mode: mode, category: category)
                            }
                        }
                    }
                    .listRowBackground(Color.appSurface)
                }

                if !objectiveCategories.isEmpty {
                    Section("Objectives") {
                        ForEach(objectiveCategories) { category in
                            NavigationLink {
                                ItemListView(mode: mode, category: category)
                            } label: {
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
