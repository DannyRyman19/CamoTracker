import SwiftUI

/// Lists the top-level items in a category — weapons in Multiplayer/Campaign,
/// objectives in DMZ. Same view for every mode; only the data differs.
struct ItemListView: View {
    let mode: AppMode
    let category: Category
    @EnvironmentObject private var viewModel: TrackerViewModel

    var body: some View {
        ZStack {
            AppBackground(accent: mode.accent)
            List {
                ForEach(category.items) { item in
                    NavigationLink {
                        ItemDetailView(mode: mode, category: category, item: item)
                    } label: {
                        ItemRow(mode: mode, category: category, item: item)
                    }
                    .listRowBackground(Color.appSurface)
                }
            }
            .scrollContentBackground(.hidden)
            .listStyle(.plain)
        }
        .navigationTitle(category.nameKey.localized())
    }
}

private struct ItemRow: View {
    let mode: AppMode
    let category: Category
    let item: ChallengeItem
    @EnvironmentObject private var viewModel: TrackerViewModel

    private var done: Bool {
        viewModel.isComplete(mode: mode.rawValue, categoryId: category.categoryId, item: item)
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(item.nameKey.localized())
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.appInk)
                if !item.isLeaf {
                    ProgressBar(
                        fraction: viewModel.progressFraction(of: item, mode: mode.rawValue, categoryId: category.categoryId),
                        accent: mode.accent
                    )
                }
            }
            Spacer()
            if item.isLeaf {
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(done ? mode.accent : Color.appInkMuted)
            }
        }
        .padding(.vertical, 4)
    }
}
