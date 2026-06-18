import SwiftUI

struct WeaponDetailView: View {
    @Environment(TrackerViewModel.self) private var vm
    let categoryIndex: Int
    let weaponIndex: Int

    private var weapon: Weapon { vm.categories[categoryIndex].Weapons[weaponIndex] }
    private var category: WeaponCategory { vm.categories[categoryIndex] }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                weaponHero
                    .padding(.horizontal)

                MasteryStatusCard(weapon: weapon, category: category)
                    .padding(.horizontal)

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Camo Challenges")
                            .font(.agency(22))
                            .foregroundStyle(.white)
                        Spacer()
                        Text("\(weapon.completedChallenges)/\(weapon.totalChallenges)")
                            .font(.agency(15))
                            .foregroundStyle(Color.accent)
                    }
                    .padding(.horizontal)

                    ForEach(Array(weapon.Camos.enumerated()), id: \.element.id) { index, camo in
                        ChallengeRow(camo: camo) {
                            vm.toggleCamo(categoryIndex: categoryIndex, weaponIndex: weaponIndex, camoIndex: index)
                        }
                        .padding(.horizontal)
                    }
                }

                Spacer(minLength: 24)
            }
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .navigationTitle(weapon.WeaponName)
        .navigationBarTitleDisplayMode(.large)
        .background(AppBackground())
    }

    private var weaponHero: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20)
                .fill(weapon.hasGold ? Color.accentMuted : Color.white.opacity(0.04))
            AsyncImage(url: URL(string: weapon.WeaponImageURL)) { phase in
                switch phase {
                case .success(let image):
                    image.resizable()
                        .aspectRatio(contentMode: .fit)
                        .padding(24)
                case .failure, .empty:
                    Image(systemName: "scope")
                        .font(.system(size: 60))
                        .foregroundStyle(.white.opacity(0.12))
                        .padding(24)
                @unknown default:
                    ProgressView().tint(.white).padding(24)
                }
            }
        }
        .frame(height: 140)
        .glassEffect()
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(weapon.hasGold ? Color.accent.opacity(0.5) : Color.clear, lineWidth: 1.5)
        )
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
                color: .accent,
                detail: weapon.hasGold ? "Unlocked" : "\(weapon.completedChallenges)/\(weapon.totalChallenges)"
            )
            Divider()
                .frame(height: 40)
                .background(.white.opacity(0.12))
            MasteryPill(
                label: "Diamond",
                icon: "diamond.fill",
                unlocked: category.hasDiamond,
                color: .cyan,
                detail: category.hasDiamond ? "Unlocked" : "\(category.goldCount)/\(category.Weapons.count) Gold"
            )
        }
        .padding(.vertical, 10)
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
                    .font(.agencyReg(15))
                    .foregroundStyle(unlocked ? color : .white.opacity(0.25))
                Text(label)
                    .font(.agency(15))
                    .foregroundStyle(unlocked ? color : .white.opacity(0.35))
            }
            Text(detail)
                .font(.agencyReg(13))
                .foregroundStyle(unlocked ? color.opacity(0.8) : .white.opacity(0.3))
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

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(camo.CamoName)
                            .font(.agency(15))
                            .foregroundStyle(camo.IsChallengeComplete ? Color.accent : .white)
                        Spacer()
                        if camo.IsChallengeComplete {
                            Text("Done")
                                .font(.agency(11))
                                .foregroundStyle(.black)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Color.accent)
                                .clipShape(Capsule())
                        } else {
                            Text("#\(camo.CamoID + 1)")
                                .font(.agencyReg(11))
                                .foregroundStyle(.white.opacity(0.25))
                        }
                    }
                    Text(camo.displayRequirement)
                        .font(.agencyReg(13))
                        .foregroundStyle(.white.opacity(0.5))
                        .multilineTextAlignment(.leading)
                }

                ZStack {
                    Circle()
                        .fill(camo.IsChallengeComplete ? Color.accent : Color.white.opacity(0.08))
                        .frame(width: 28, height: 28)
                    if camo.IsChallengeComplete {
                        Image(systemName: "checkmark")
                            .font(.agency(13))
                            .foregroundStyle(.black)
                    }
                }
            }
            .padding(14)
            .glassEffect()
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(camo.IsChallengeComplete ? Color.accent.opacity(0.35) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
