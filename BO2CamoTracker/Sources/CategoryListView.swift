import SwiftUI

struct CategoryListView: View {
    @Environment(TrackerViewModel.self) private var vm

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 12) {
                    overallBanner
                        .padding(.horizontal)
                        .padding(.top, 4)

                    ForEach(Array(vm.categories.enumerated()), id: \.element.id) { index, category in
                        NavigationLink(destination: WeaponListView(categoryIndex: index)) {
                            CategoryCard(category: category)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal)
                    }
                }
                .padding(.vertical, 8)
                .padding(.bottom, 24)
            }
            .navigationTitle("BO2 Camo Tracker")
            .background(AppBackground())
        }
    }

    private var overallBanner: some View {
        HStack(spacing: 0) {
            bannerCell(value: "\(vm.goldWeapons)/\(vm.totalWeapons)", label: "Gold")
            Divider().frame(height: 40).background(.white.opacity(0.12))
            bannerCell(value: "\(vm.diamondCategories)/\(vm.totalCategories)", label: "Diamond")
            Divider().frame(height: 40).background(.white.opacity(0.12))
            bannerCell(value: String(format: "%.0f%%", vm.overallCamoProgress * 100), label: "Done")
        }
        .padding(.vertical, 14)
        .glassEffect()
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(Color.accent.opacity(0.25), lineWidth: 1)
        )
    }

    private func bannerCell(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.agency(22))
                .foregroundStyle(.white)
            Text(label)
                .font(.agencyReg(13))
                .foregroundStyle(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
    }
}

struct CategoryCard: View {
    let category: WeaponCategory

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(category.hasDiamond ? Color.cyan.opacity(0.2) : Color.accentMuted)
                        .frame(width: 44, height: 44)
                    Image(systemName: category.categoryIcon)
                        .font(.agencyReg(20))
                        .foregroundStyle(category.hasDiamond ? .cyan : .accent)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(category.WeaponCategoryName)
                        .font(.agency(17))
                        .foregroundStyle(.white)
                    Text("\(category.Weapons.count) weapons")
                        .font(.agencyReg(13))
                        .foregroundStyle(.white.opacity(0.5))
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    if category.hasDiamond {
                        Label("Diamond", systemImage: "diamond.fill")
                            .font(.agency(13))
                            .foregroundStyle(.cyan)
                    } else {
                        Text("\(category.goldCount)/\(category.Weapons.count)")
                            .font(.agency(15))
                            .foregroundStyle(category.goldCount > 0 ? Color.accent : .white.opacity(0.4))
                        Text("Gold")
                            .font(.agencyReg(11))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                }

                Image(systemName: "chevron.right")
                    .font(.agencyReg(13))
                    .foregroundStyle(.white.opacity(0.3))
            }

            ProgressView(value: category.overallProgress)
                .tint(category.hasDiamond ? .cyan : .accent)
        }
        .padding(16)
        .glassEffect()
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(
                    category.hasDiamond ? Color.cyan.opacity(0.4) :
                    category.overallProgress > 0 ? Color.accent.opacity(0.2) : Color.clear,
                    lineWidth: 1
                )
        )
    }
}
