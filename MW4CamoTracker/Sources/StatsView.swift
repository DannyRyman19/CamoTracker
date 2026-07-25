import SwiftUI

struct StatsView: View {
    @EnvironmentObject private var viewModel: TrackerViewModel

    var body: some View {
        ZStack {
            AppBackground(accent: .accentMultiplayer)
            List {
                ForEach(AppMode.allCases) { mode in
                    if let file = viewModel.modes[mode.rawValue] {
                        Section(mode.displayNameKey.localized()) {
                            ForEach(file.categories) { category in
                                HStack {
                                    Text(category.nameKey.localized())
                                        .foregroundStyle(Color.appInk)
                                    Spacer()
                                    Text("\(Int(viewModel.progressFraction(of: category, mode: mode.rawValue) * 100))%")
                                        .font(.system(size: 13, design: .monospaced))
                                        .foregroundStyle(Color.appInkMuted)
                                }
                            }
                        }
                        .listRowBackground(Color.appSurface)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .listStyle(.plain)
        }
        .navigationTitle("Stats")
    }
}
