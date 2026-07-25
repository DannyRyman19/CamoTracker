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
                    ChallengeRow(mode: mode, category: category, item: row)
                        .listRowBackground(Color.appSurface)
                }
            }
            .scrollContentBackground(.hidden)
            .listStyle(.plain)
        }
        .navigationTitle(item.nameKey.localized())
    }
}

private struct ChallengeRow: View {
    let mode: AppMode
    let category: Category
    let item: ChallengeItem
    @EnvironmentObject private var viewModel: TrackerViewModel

    private var done: Bool {
        viewModel.isObjectiveComplete(mode: mode.rawValue, categoryId: category.categoryId, item: item)
    }

    var body: some View {
        Button {
            viewModel.toggleObjective(mode: mode.rawValue, categoryId: category.categoryId, item: item)
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.nameKey.localized())
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.appInk)
                    if let requirement = item.requirement {
                        Text(requirement.descriptionKey.localized())
                            .font(.system(size: 13))
                            .foregroundStyle(Color.appInkMuted)
                    }
                }
                Spacer()
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(done ? mode.accent : Color.appInkMuted)
            }
        }
        .buttonStyle(.plain)
        .padding(.vertical, 4)
    }
}
