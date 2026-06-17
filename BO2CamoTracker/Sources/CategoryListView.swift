import SwiftUI

struct CategoryListView: View {
    @Environment(TrackerViewModel.self) private var vm

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 14) {
                    ForEach(Array(vm.categories.enumerated()), id: \.element.id) { index, category in
                        NavigationLink(destination: WeaponListView(categoryIndex: index)) {
                            CategoryCard(category: category)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .navigationTitle("BO2 Camo Tracker")
            .background(.black)
        }
    }
}

struct CategoryCard: View {
    let category: WeaponCategory

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: category.categoryIcon)
                    .font(.title2)
                    .foregroundStyle(category.hasDiamond ? .cyan : .yellow)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(category.WeaponCategoryName)
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text("\(category.Weapons.count) weapons")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    if category.hasDiamond {
                        Label("Diamond", systemImage: "diamond.fill")
                            .font(.caption.bold())
                            .foregroundStyle(.cyan)
                    } else {
                        Text("\(category.goldCount)/\(category.Weapons.count) Gold")
                            .font(.caption.bold())
                            .foregroundStyle(.yellow)
                    }
                }

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.3))
            }

            ProgressView(value: category.overallProgress)
                .tint(category.hasDiamond ? .cyan : .yellow)
                .background(.white.opacity(0.1))
                .clipShape(Capsule())
        }
        .padding(16)
        .glassEffect()
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }
}
