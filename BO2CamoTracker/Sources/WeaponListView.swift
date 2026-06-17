import SwiftUI

struct WeaponListView: View {
    @Environment(TrackerViewModel.self) private var vm
    let categoryIndex: Int

    private var category: WeaponCategory { vm.categories[categoryIndex] }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
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
            WeaponThumbnail(url: weapon.WeaponImageURL, size: 56)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
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

            Spacer(minLength: 0)

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
                    .font(.title2)
                    .foregroundStyle(.white.opacity(0.4))
            @unknown default:
                ProgressView()
                    .tint(.white)
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
                    .fill(.white.opacity(0.08))
                    .frame(width: size, height: size)
                    .overlay {
                        Image(systemName: "paintpalette")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.3))
                    }
            @unknown default:
                RoundedRectangle(cornerRadius: size * 0.25)
                    .fill(.white.opacity(0.08))
                    .frame(width: size, height: size)
            }
        }
    }
}
