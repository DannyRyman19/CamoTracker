import SwiftUI

struct WeaponDetailView: View {
    @Environment(TrackerViewModel.self) private var vm
    let categoryIndex: Int
    let weaponIndex: Int

    private var weapon: Weapon { vm.categories[categoryIndex].Weapons[weaponIndex] }
    private var category: WeaponCategory { vm.categories[categoryIndex] }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                weaponHero

                MasteryStatusCard(weapon: weapon, category: category)
                    .padding(.horizontal)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Camo Challenges")
                        .font(.title3.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal)

                    ForEach(Array(weapon.Camos.enumerated()), id: \.element.id) { index, camo in
                        ChallengeRow(camo: camo) {
                            vm.toggleCamo(categoryIndex: categoryIndex, weaponIndex: weaponIndex, camoIndex: index)
                        }
                        .padding(.horizontal)
                    }
                }

                Spacer(minLength: 32)
            }
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .navigationTitle(weapon.WeaponName)
        .navigationBarTitleDisplayMode(.large)
        .background(.black)
    }

    private var weaponHero: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20)
                .fill(.white.opacity(0.04))
            AsyncImage(url: URL(string: weapon.WeaponImageURL)) { phase in
                switch phase {
                case .success(let image):
                    image.resizable()
                        .aspectRatio(contentMode: .fit)
                        .padding(24)
                case .failure, .empty:
                    Image(systemName: "scope")
                        .font(.system(size: 60))
                        .foregroundStyle(.white.opacity(0.15))
                        .padding(24)
                @unknown default:
                    ProgressView().tint(.white).padding(24)
                }
            }
        }
        .frame(height: 140)
        .padding(.horizontal)
        .glassEffect()
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .padding(.horizontal)
    }
}

struct MasteryStatusCard: View {
    let weapon: Weapon
    let category: WeaponCategory

    var body: some View {
        HStack(spacing: 0) {
            MasteryPill(
                label: "Gold",
                icon: "star.fill",
                unlocked: weapon.hasGold,
                color: .yellow,
                detail: weapon.hasGold ? "Unlocked" : "\(weapon.completedChallenges)/\(weapon.totalChallenges)"
            )
            Divider()
                .frame(height: 40)
                .background(.white.opacity(0.15))
            MasteryPill(
                label: "Diamond",
                icon: "diamond.fill",
                unlocked: category.hasDiamond,
                color: .cyan,
                detail: category.hasDiamond ? "Unlocked" : "\(category.goldCount)/\(category.Weapons.count) Gold"
            )
        }
        .padding(.vertical, 8)
        .glassEffect()
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

struct MasteryPill: View {
    let label: String
    let icon: String
    let unlocked: Bool
    let color: Color
    let detail: String

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.subheadline)
                    .foregroundStyle(unlocked ? color : .white.opacity(0.3))
                Text(label)
                    .font(.subheadline.bold())
                    .foregroundStyle(unlocked ? color : .white.opacity(0.4))
            }
            Text(detail)
                .font(.caption.monospacedDigit())
                .foregroundStyle(unlocked ? color.opacity(0.8) : .white.opacity(0.35))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
}

struct ChallengeRow: View {
    let camo: Camo
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 12) {
                CamoThumbnail(url: camo.CamoImageURL, size: 44)

                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(camo.CamoName)
                            .font(.subheadline.bold())
                            .foregroundStyle(camo.IsChallengeComplete ? .yellow : .white)
                        Spacer()
                        if camo.IsChallengeComplete {
                            Text("Done")
                                .font(.caption2.bold())
                                .foregroundStyle(.black)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.yellow)
                                .clipShape(Capsule())
                        } else {
                            Text("#\(camo.CamoID + 1)")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.white.opacity(0.3))
                        }
                    }
                    Text(camo.displayRequirement)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.55))
                        .multilineTextAlignment(.leading)
                }

                ZStack {
                    Circle()
                        .fill(camo.IsChallengeComplete ? Color.yellow : Color.white.opacity(0.1))
                        .frame(width: 28, height: 28)
                    if camo.IsChallengeComplete {
                        Image(systemName: "checkmark")
                            .font(.caption.bold())
                            .foregroundStyle(.black)
                    }
                }
            }
            .padding(14)
            .glassEffect()
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }
}
