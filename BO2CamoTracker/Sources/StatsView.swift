import SwiftUI

struct StatsView: View {
    @Environment(TrackerViewModel.self) private var vm

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    overallCard
                    categoryBreakdown
                }
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .navigationTitle("Progress")
            .background(.black)
        }
    }

    private var overallCard: some View {
        VStack(spacing: 16) {
            HStack {
                StatTile(
                    value: "\(vm.goldWeapons)",
                    total: "\(vm.totalWeapons)",
                    label: "Gold Weapons",
                    icon: "star.fill",
                    color: .yellow
                )
                StatTile(
                    value: "\(vm.diamondCategories)",
                    total: "\(vm.totalCategories)",
                    label: "Diamond Classes",
                    icon: "diamond.fill",
                    color: .cyan
                )
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Overall Completion")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.7))
                    Spacer()
                    Text(String(format: "%.1f%%", vm.overallProgress * 100))
                        .font(.subheadline.bold().monospacedDigit())
                        .foregroundStyle(.white)
                }
                ProgressView(value: vm.overallProgress)
                    .tint(.yellow)
            }
        }
        .padding(18)
        .glassEffect()
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private var categoryBreakdown: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("By Category")
                .font(.title3.bold())
                .foregroundStyle(.white)

            ForEach(vm.categories) { category in
                CategoryStatRow(category: category)
            }
        }
    }
}

struct StatTile: View {
    let value: String
    let total: String
    let label: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title)
                .foregroundStyle(color)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.title.bold().monospacedDigit())
                    .foregroundStyle(.white)
                Text("/\(total)")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.4))
            }
            Text(label)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .glassEffect()
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

struct CategoryStatRow: View {
    let category: WeaponCategory

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: category.categoryIcon)
                .font(.subheadline)
                .foregroundStyle(category.hasDiamond ? .cyan : .yellow)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(category.WeaponCategoryName)
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                    Spacer()
                    if category.hasDiamond {
                        Label("Diamond", systemImage: "diamond.fill")
                            .font(.caption2.bold())
                            .foregroundStyle(.cyan)
                    } else {
                        Text("\(category.goldCount)/\(category.Weapons.count) Gold")
                            .font(.caption2.bold())
                            .foregroundStyle(.yellow)
                    }
                }
                ProgressView(value: category.overallProgress)
                    .tint(category.hasDiamond ? .cyan : .yellow)
            }
        }
        .padding(14)
        .glassEffect()
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}
