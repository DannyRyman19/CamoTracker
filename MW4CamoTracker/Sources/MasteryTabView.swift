import SwiftUI

/// Mastery, the one part of the grind that's per mode: each mode's three
/// Mastery camos, side by side with a mode switch.
struct MasteryTabView: View {
    let startMode: AppMode
    @State private var mode: AppMode?
    @EnvironmentObject private var viewModel: TrackerViewModel

    private var shown: AppMode { mode ?? startMode }

    var body: some View {
        ZStack {
            AppBackground(accent: shown.accent)
            List {
                if viewModel.visibleModes.count > 1 {
                    Picker("mw4.ui.counts_for".localized(), selection: Binding(get: { shown }, set: { mode = $0 })) {
                        ForEach(viewModel.visibleModes) { m in
                            Text(m.displayNameKey.localized()).tag(m)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                }
                Section {
                    ForEach(1...3, id: \.self) { tier in
                        MasteryModeRow(mode: shown, tier: tier)
                    }
                }
                .listRowBackground(Color.appSurface)
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("mw4.ui.section.mastery".localized())
    }
}
