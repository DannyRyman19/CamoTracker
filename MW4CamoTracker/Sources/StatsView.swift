import SwiftUI

struct StatsView: View {
    @EnvironmentObject private var viewModel: TrackerViewModel

    private var weaponCategories: [WeaponCategory] { viewModel.catalog?.categories ?? [] }

    var body: some View {
        ZStack {
            AppBackground(accent: .accentMultiplayer)
            List {
                ForEach(AppMode.allCases) { mode in
                    Section(mode.displayNameKey.localized()) {
                        ForEach(weaponCategories) { category in
                            statRow(
                                name: category.nameKey.localized(),
                                fraction: viewModel.weaponCategoryProgressFraction(category, mode: mode.rawValue)
                            )
                        }
                        ForEach(viewModel.modes[mode.rawValue]?.objectives ?? []) { category in
                            statRow(
                                name: category.nameKey.localized(),
                                fraction: viewModel.objectiveProgressFraction(of: category, mode: mode.rawValue)
                            )
                        }
                    }
                    .listRowBackground(Color.appSurface)
                }
            }
            .scrollContentBackground(.hidden)
            .listStyle(.plain)
        }
        .navigationTitle("Stats")
    }

    private func statRow(name: String, fraction: Double) -> some View {
        HStack {
            Text(name)
                .foregroundStyle(Color.appInk)
            Spacer()
            Text("\(Int(fraction * 100))%")
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(Color.appInkMuted)
        }
    }
}
