import SwiftUI

/// The level control at the top is global — change it here while looking at
/// Multiplayer and it reads the same when you check this weapon from DMZ.
/// The camo list below it is specific to whichever mode tab got you here.
struct WeaponDetailView: View {
    let mode: AppMode
    let weapon: WeaponEntry
    @EnvironmentObject private var viewModel: TrackerViewModel

    private var camos: [ChallengeItem] { viewModel.camos(weaponId: weapon.weaponId, mode: mode.rawValue) }

    var body: some View {
        ZStack {
            AppBackground(accent: mode.accent)
            List {
                Section {
                    LevelControl(weapon: weapon)
                }
                .listRowBackground(Color.appSurface)

                if camos.isEmpty {
                    Text("No \(mode.displayNameKey.localized()) camo data for this weapon yet.")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.appInkMuted)
                        .listRowBackground(Color.appSurface)
                } else {
                    Section("Camos") {
                        ForEach(camos) { camo in
                            ChallengeRow(
                                item: camo,
                                accent: mode.accent,
                                amount: viewModel.camoAmount(mode: mode.rawValue, weaponId: weapon.weaponId, camo: camo),
                                isDone: viewModel.isCamoComplete(mode: mode.rawValue, weaponId: weapon.weaponId, camo: camo),
                                onToggle: { viewModel.toggleCamo(mode: mode.rawValue, weaponId: weapon.weaponId, camo: camo) },
                                onSetAmount: { viewModel.setCamoAmount(mode: mode.rawValue, weaponId: weapon.weaponId, camo: camo, amount: $0) }
                            )
                        }
                    }
                    .listRowBackground(Color.appSurface)
                }
            }
            .scrollContentBackground(.hidden)
            .listStyle(.plain)
        }
        .navigationTitle(weapon.nameKey.localized())
    }
}

private struct LevelControl: View {
    let weapon: WeaponEntry
    @EnvironmentObject private var viewModel: TrackerViewModel

    var body: some View {
        Stepper(
            value: Binding(
                get: { viewModel.level(for: weapon.weaponId) },
                set: { viewModel.setLevel($0, for: weapon) }
            ),
            in: 0...weapon.maxLevel
        ) {
            HStack {
                Text("Weapon Level")
                    .foregroundStyle(Color.appInk)
                Spacer()
                Text("\(viewModel.level(for: weapon.weaponId)) / \(weapon.maxLevel)")
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundStyle(Color.appInkMuted)
            }
        }
        .tint(.accentMultiplayer)
    }
}
