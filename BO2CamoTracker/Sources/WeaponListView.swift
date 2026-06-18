import SwiftUI

struct WeaponListView: View {
    @Environment(TrackerViewModel.self) private var vm
    let categoryIndex: Int

    private var category: WeaponCategory { vm.categories[categoryIndex] }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
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
        .background(AppBackground())
    }
}

struct WeaponRow: View {
    let weapon: Weapon

    var body: some View {
        HStack(spacing: 14) {
            WeaponThumbnail(url: weapon.WeaponImageURL, size: 56)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(weapon.WeaponName)
                        .font(.agency(17))
                        .foregroundStyle(.white)
                    if weapon.hasGold {
                        Text("GOLD")
                            .font(.agency(11))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.accent)
                            .clipShape(Capsule())
                    }
                }

                ProgressView(value: weapon.progress)
                    .tint(weapon.hasGold ? .accent : .white.opacity(0.5))

                Text("\(weapon.completedChallenges)/\(weapon.totalChallenges) challenges")
                    .font(.agencyReg(13))
                    .foregroundStyle(.white.opacity(0.45))
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.agencyReg(13))
                .foregroundStyle(.white.opacity(0.3))
        }
        .padding(14)
        .glassEffect()
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(weapon.hasGold ? Color.accent.opacity(0.45) : Color.clear, lineWidth: 1)
        )
    }
}

struct DiamondBanner: View {
    let categoryName: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "diamond.fill")
                .font(.agencyReg(22))
                .foregroundStyle(.cyan)
            VStack(alignment: .leading, spacing: 2) {
                Text("Diamond Unlocked!")
                    .font(.agency(17))
                    .foregroundStyle(.cyan)
                Text("All \(categoryName) at Gold")
                    .font(.agencyReg(13))
                    .foregroundStyle(.cyan.opacity(0.7))
            }
            Spacer()
            Image(systemName: "sparkles")
                .font(.agencyReg(20))
                .foregroundStyle(.cyan.opacity(0.6))
        }
        .padding(16)
        .glassEffect()
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.cyan.opacity(0.5), lineWidth: 1)
        )
    }
}

// MARK: - Shared image components

struct WeaponThumbnail: View {
    let url: String
    let size: CGFloat

    var body: some View {
        AsyncImage(url: URL(string: url)) { phase in
            switch phase {
            case .success(let image):
                image.resizable()
                    .aspectRatio(contentMode: .fit)
            case .failure, .empty:
                Image(systemName: "scope")
                    .font(.agencyReg(22))
                    .foregroundStyle(.white.opacity(0.3))
            @unknown default:
                ProgressView().tint(.white)
            }
        }
        .frame(width: size, height: size * 0.6)
    }
}

struct CamoThumbnail: View {
    let url: String
    let size: CGFloat

    var body: some View {
        AsyncImage(url: URL(string: url)) { phase in
            switch phase {
            case .success(let image):
                image.resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.25))
            case .failure, .empty:
                RoundedRectangle(cornerRadius: size * 0.25)
                    .fill(.white.opacity(0.07))
                    .frame(width: size, height: size)
                    .overlay {
                        Image(systemName: "paintpalette")
                            .font(.agencyReg(13))
                            .foregroundStyle(.white.opacity(0.25))
                    }
            @unknown default:
                RoundedRectangle(cornerRadius: size * 0.25)
                    .fill(.white.opacity(0.07))
                    .frame(width: size, height: size)
            }
        }
    }
}
