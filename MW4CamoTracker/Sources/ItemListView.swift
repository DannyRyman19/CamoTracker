import SwiftUI

/// Lists the top-level items in a mode-exclusive objective category
/// (e.g. DMZ's Hajin extraction objectives) — content with no weapon-catalog
/// equivalent, unlike the camo tracks covered by WeaponListView/WeaponDetailView.
struct ItemListView: View {
    let mode: AppMode
    let category: Category
    @EnvironmentObject private var viewModel: TrackerViewModel

    /// Shared across every objective-category screen — same persisted,
    /// global-not-per-screen choice as `WeaponListView`/`CategoryListView`.
    @AppStorage("mw4_item_sort") private var sortRaw = ProgressSort.natural.rawValue
    @AppStorage("mw4_item_filter") private var filterRaw = CompletionFilter.all.rawValue
    private static let sortOptions: [ProgressSort] = [.natural, .alphabetical, .progressDesc, .progressAsc]

    private var sort: ProgressSort { ProgressSort(rawValue: sortRaw) ?? .natural }
    private var filter: CompletionFilter { CompletionFilter(rawValue: filterRaw) ?? .all }
    private var sortBinding: Binding<ProgressSort> {
        Binding(get: { sort }, set: { sortRaw = $0.rawValue })
    }
    private var filterBinding: Binding<CompletionFilter> {
        Binding(get: { filter }, set: { filterRaw = $0.rawValue })
    }

    private func fraction(_ item: ChallengeItem) -> Double {
        viewModel.objectiveProgressFraction(of: item, mode: mode.rawValue, categoryId: category.categoryId)
    }
    private func isComplete(_ item: ChallengeItem) -> Bool {
        item.isLeaf
            ? viewModel.isObjectiveComplete(mode: mode.rawValue, categoryId: category.categoryId, item: item)
            : fraction(item) >= 1
    }

    private var displayedItems: [ChallengeItem] {
        var items = category.items
        switch filter {
        case .all:
            break
        case .incomplete:
            items = items.filter { !isComplete($0) }
        case .complete:
            items = items.filter { isComplete($0) }
        }
        switch sort {
        case .natural, .level:
            break
        case .alphabetical:
            items.sort { $0.name.resolved().localizedCaseInsensitiveCompare($1.name.resolved()) == .orderedAscending }
        case .progressDesc:
            items.sort { fraction($0) > fraction($1) }
        case .progressAsc:
            items.sort { fraction($0) < fraction($1) }
        }
        return items
    }

    var body: some View {
        ZStack {
            AppBackground(accent: mode.accent)
            List {
                HStack(spacing: 8) {
                    FilterSortMenu(title: "mw4.ui.filter".localized(), options: CompletionFilter.allCases, label: { $0.label }, accent: mode.accent, selection: filterBinding)
                    FilterSortMenu(title: "mw4.ui.sort".localized(), options: Self.sortOptions, label: { $0.label }, accent: mode.accent, selection: sortBinding)
                }
                .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                .listRowBackground(Color.clear)

                if displayedItems.isEmpty {
                    FilterEmptyRow()
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(displayedItems) { item in
                        NavigationLink {
                            ItemDetailView(mode: mode, category: category, item: item)
                        } label: {
                            ItemRow(mode: mode, category: category, item: item)
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

private struct ItemRow: View {
    let mode: AppMode
    let category: Category
    let item: ChallengeItem
    @EnvironmentObject private var viewModel: TrackerViewModel

    private var done: Bool {
        viewModel.isObjectiveComplete(mode: mode.rawValue, categoryId: category.categoryId, item: item)
    }
    private var fraction: Double {
        viewModel.objectiveProgressFraction(of: item, mode: mode.rawValue, categoryId: category.categoryId)
    }
    private var isComplete: Bool { item.isLeaf ? done : fraction >= 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(category.name.resolved())
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.2)
                .textCase(.uppercase)
                .foregroundStyle(Color.appInkMuted)

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.name.resolved())
                        .font(.hitmarker(15))
                        .foregroundStyle(Color.appInk)
                    if !item.isLeaf {
                        ProgressBar(fraction: fraction, accent: mode.accent)
                    }
                }
                Spacer()
                if item.isLeaf {
                    Image(systemName: done ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(done ? mode.accent : Color.appInkMuted)
                }
            }
        }
        .padding(12)
        .borderedCard(accent: isComplete ? mode.accent : nil)
    }
}
