import SwiftUI

struct WeaponListView: View {
    @Environment(TrackerViewModel.self) private var vm
    let categoryIndex: Int

    private var category: WeaponCategory { vm.categories[categoryIndex] }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                // Diamond status banner
                if category.hasDiamond {
                    DiamondBanner(categoryName: category.WeaponCategoryName)
                        .padding(.horizontal)
                        .padding(.top, 4)
                }

                ForEach(Array(category.Weapons.enumerated()), id: \.element.id) { index, weapon in
                    NavigationLink(destination: WeaponDetailView(categoryIndex: categoryIndex, weaponIndex: index)) {
                        WeaponRow(weapon: weapon)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal)
                }
            }
            .padding(.vertical, 8)
            .padding(.bottom, 24)
        }
        .navigationTitle(category.WeaponCategoryName)
        .navigationBarTitleDisplayMode(.large)
        .background(.black)
    }
}

struct WeaponRow: View {
    let weapon: Weapon

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(weapon.hasGold ? Color.yellow.opacity(0.2) : Color.white.opacity(0.08))
                    .frame(width: 44, height: 44)
                if weapon.hasGold {
                    Image(systemName: "star.fill")
                        .font(.title3)
                        .foregroundStyle(.yellow)
                } else {
                    Text("\(weapon.completedChallenges)")
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(.white)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(weapon.WeaponName)
                        .font(.headline)
                        .foregroundStyle(.white)
                    if weapon.hasGold {
                        Text("GOLD")
                            .font(.caption2.bold())
                            .foregroundStyle(.black)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.yellow)
                            .clipShape(Capsule())
                    }
                }
                ProgressView(value: weapon.progress)
                    .tint(weapon.hasGold ? .yellow : .white.opacity(0.6))
                Text("\(weapon.completedChallenges)/\(weapon.totalChallenges) challenges")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.3))
        }
        .padding(14)
        .glassEffect()
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

struct DiamondBanner: View {
    let categoryName: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "diamond.fill")
                .font(.title2)
                .foregroundStyle(.cyan)
            VStack(alignment: .leading, spacing: 2) {
                Text("Diamond Unlocked!")
                    .font(.headline.bold())
                    .foregroundStyle(.cyan)
                Text("Gold on all \(categoryName)")
                    .font(.caption)
                    .foregroundStyle(.cyan.opacity(0.7))
            }
            Spacer()
        }
        .padding(16)
        .glassEffect()
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
