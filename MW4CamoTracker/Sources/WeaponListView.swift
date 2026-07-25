import SwiftUI

/// Weapons within a catalog category. The weapon list itself is identical in
/// every mode (it's the shared catalog) — only each row's camo progress bar
/// changes, pulled from the active mode's `weaponCamos`.
struct WeaponListView: View {
    let mode: AppMode
    let category: WeaponCategory
    @EnvironmentObject private var viewModel: TrackerViewModel

    var body: some View {
        ZStack {
            AppBackground(accent: mode.accent)
            List {
                ForEach(category.weapons) { weapon in
                    NavigationLink {
                        WeaponDetailView(mode: mode, weapon: weapon)
                    } label: {
                        WeaponRow(mode: mode, weapon: weapon)
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

private struct WeaponRow: View {
    let mode: AppMode
    let weapon: WeaponEntry
    @EnvironmentObject private var viewModel: TrackerViewModel

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(weapon.nameKey.localized())
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.appInk)
                ProgressBar(
                    fraction: viewModel.camoProgressFraction(weaponId: weapon.weaponId, mode: mode.rawValue),
                    accent: mode.accent
                )
            }
            Spacer()
            // Weapon level is global — the same number shows up under every mode tab.
            Text("Lv \(viewModel.level(for: weapon.weaponId))/\(weapon.maxLevel)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Color.appInkMuted)
        }
        .padding(.vertical, 4)
    }
}
