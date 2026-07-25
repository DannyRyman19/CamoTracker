import SwiftUI

struct CategoryListView: View {
    let mode: AppMode
    @EnvironmentObject private var viewModel: TrackerViewModel

    private var modeFile: ModeFile? { viewModel.modes[mode.rawValue] }

    var body: some View {
        ZStack {
            AppBackground(accent: mode.accent)
            List {
                ForEach(modeFile?.categories ?? []) { category in
                    NavigationLink {
                        ItemListView(mode: mode, category: category)
                    } label: {
                        CategoryRow(mode: mode, category: category)
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

private struct CategoryRow: View {
    let mode: AppMode
    let category: Category
    @EnvironmentObject private var viewModel: TrackerViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(category.nameKey.localized())
                .font(.hitmarker(16))
                .foregroundStyle(Color.appInk)
            ProgressBar(fraction: viewModel.progressFraction(of: category, mode: mode.rawValue), accent: mode.accent)
        }
        .padding(.vertical, 4)
    }
}
