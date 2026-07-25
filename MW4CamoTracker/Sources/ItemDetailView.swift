import SwiftUI

/// Shows a mode-exclusive objective's sub-tiers (e.g. a DMZ extraction goal's
/// stages) — whichever `children` the selected item happens to carry.
struct ItemDetailView: View {
    let mode: AppMode
    let category: Category
    let item: ChallengeItem
    @EnvironmentObject private var viewModel: TrackerViewModel

    private var rows: [ChallengeItem] { item.children.isEmpty ? [item] : item.children }

    var body: some View {
        ZStack {
            AppBackground(accent: mode.accent)
            List {
                ForEach(rows) { row in
                    ChallengeRow(
                        item: row,
                        accent: mode.accent,
                        amount: viewModel.objectiveAmount(mode: mode.rawValue, categoryId: category.categoryId, item: row),
                        isDone: viewModel.isObjectiveComplete(mode: mode.rawValue, categoryId: category.categoryId, item: row),
                        onToggle: { viewModel.toggleObjective(mode: mode.rawValue, categoryId: category.categoryId, item: row) },
                        onSetAmount: { viewModel.setObjectiveAmount(mode: mode.rawValue, categoryId: category.categoryId, item: row, amount: $0) }
                    )
                    .listRowBackground(Color.appSurface)
                }
            }
            .scrollContentBackground(.hidden)
            .listStyle(.plain)
        }
        .navigationTitle(item.nameKey.localized())
    }
}
