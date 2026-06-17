import SwiftUI

struct StatsView: View {
    @Environment(TrackerViewModel.self) private var vm

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    camoOverviewCard
                    challengeOverviewCard
                    reticleOverviewCard
                    categoryBreakdown
                }
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .navigationTitle("Stats")
            .background(.black)
        }
    }

    private var reticleOverviewCard: some View {
        VStack(spacing: 14) {
            HStack {
                Text("Reticle Progress")
                    .font(.headline)
                    .foregroundStyle(.white)
                Spacer()
            }
            HStack(spacing: 12) {
                StatTile(value: "\(vm.unlockedReticles)", total: "\(vm.totalReticles)",
                         label: "Unlocked", icon: "scope", color: .cyan)
                StatTile(value: "\(vm.reticleOptics.filter(\.isComplete).count)",
                         total: "\(vm.reticleOptics.count)",
                         label: "Optics Done", icon: "checkmark.circle.fill", color: .green)
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Overall Reticle Completion")
                        .font(.caption).foregroundStyle(.white.opacity(0.6))
                    Spacer()
                    Text(String(format: "%.1f%%", vm.overallReticleProgress * 100))
                        .font(.caption.bold().monospacedDigit()).foregroundStyle(.white)
                }
                ProgressView(value: vm.overallReticleProgress).tint(.cyan)
            }
        }
        .padding(18)
        .glassEffect()
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private var camoOverviewCard: some View {
        VStack(spacing: 14) {
            HStack {
                Text("Camo Progress")
                    .font(.headline)
                    .foregroundStyle(.white)
                Spacer()
            }

            HStack(spacing: 12) {
                StatTile(
                    value: "\(vm.goldWeapons)",
                    total: "\(vm.totalWeapons)",
                    label: "Gold",
                    icon: "star.fill",
                    color: .yellow
                )
                StatTile(
                    value: "\(vm.diamondCategories)",
                    total: "\(vm.totalCategories)",
                    label: "Diamond",
                    icon: "diamond.fill",
                    color: .cyan
                )
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Overall Camo Completion")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                    Spacer()
                    Text(String(format: "%.1f%%", vm.overallCamoProgress * 100))
                        .font(.caption.bold().monospacedDigit())
                        .foregroundStyle(.white)
                }
                ProgressView(value: vm.overallCamoProgress)
                    .tint(.yellow)
            }
        }
        .padding(18)
        .glassEffect()
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private var challengeOverviewCard: some View {
        VStack(spacing: 14) {
            HStack {
                Text("Challenge Progress")
                    .font(.headline)
                    .foregroundStyle(.white)
                Spacer()
            }

            HStack(spacing: 12) {
                StatTile(
                    value: "\(vm.completedChallenges)",
                    total: "\(vm.totalChallenges)",
                    label: "Done",
                    icon: "checkmark.seal.fill",
                    color: .green
                )
                StatTile(
                    value: "\(vm.totalChallenges - vm.completedChallenges)",
                    total: "\(vm.totalChallenges)",
                    label: "Remaining",
                    icon: "clock.fill",
                    color: .orange
                )
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Overall Challenge Completion")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                    Spacer()
                    Text(String(format: "%.1f%%", vm.overallChallengeProgress * 100))
                        .font(.caption.bold().monospacedDigit())
                        .foregroundStyle(.white)
                }
                ProgressView(value: vm.overallChallengeProgress)
                    .tint(.green)
            }
        }
        .padding(18)
        .glassEffect()
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private var categoryBreakdown: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Camos by Class")
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
                .font(.title2)
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
