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
                            CamoRow(mode: mode, weaponId: weapon.weaponId, camo: camo)
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

private struct CamoRow: View {
    let mode: AppMode
    let weaponId: Int
    let camo: ChallengeItem
    @EnvironmentObject private var viewModel: TrackerViewModel

    private var done: Bool {
        viewModel.isCamoComplete(mode: mode.rawValue, weaponId: weaponId, camo: camo)
    }

    var body: some View {
        Button {
            viewModel.toggleCamo(mode: mode.rawValue, weaponId: weaponId, camo: camo)
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(camo.nameKey.localized())
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.appInk)
                    if let requirement = camo.requirement {
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
