import SwiftUI

struct StatsView: View {
    @Environment(TrackerViewModel.self) private var vm

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
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
            .background(AppBackground())
        }
    }

    private var camoOverviewCard: some View {
        VStack(spacing: 14) {
            HStack {
                Image(systemName: "star.fill")
                    .foregroundStyle(Color.accent)
                Text("Camo Progress")
                    .font(.agency(17))
                    .foregroundStyle(.white)
                Spacer()
                Text(String(format: "%.1f%%", vm.overallCamoProgress * 100))
                    .font(.agency(15))
                    .foregroundStyle(Color.accent)
            }

            HStack(spacing: 12) {
                StatTile(value: "\(vm.goldWeapons)", total: "\(vm.totalWeapons)",
                         label: "Gold", icon: "star.fill", color: .accent)
                StatTile(value: "\(vm.diamondCategories)", total: "\(vm.totalCategories)",
                         label: "Diamond", icon: "diamond.fill", color: .cyan)
            }

            ProgressView(value: vm.overallCamoProgress)
                .tint(.accent)
        }
        .padding(18)
        .glassEffect()
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(Color.accent.opacity(0.2), lineWidth: 1)
        )
    }

    private var challengeOverviewCard: some View {
        VStack(spacing: 14) {
            HStack {
                Image(systemName: "list.bullet.clipboard.fill")
                    .foregroundStyle(Color.accent)
                Text("Challenge Progress")
                    .font(.agency(17))
                    .foregroundStyle(.white)
                Spacer()
                Text(String(format: "%.1f%%", vm.overallChallengeProgress * 100))
                    .font(.agency(15))
                    .foregroundStyle(Color.accent)
            }

            HStack(spacing: 12) {
                StatTile(value: "\(vm.completedChallenges)", total: "\(vm.totalChallenges)",
                         label: "Done", icon: "checkmark.seal.fill", color: .accent)
                StatTile(value: "\(vm.totalChallenges - vm.completedChallenges)", total: "\(vm.totalChallenges)",
                         label: "Remaining", icon: "clock.fill", color: .white.opacity(0.5))
            }

            ProgressView(value: vm.overallChallengeProgress)
                .tint(.accent)
        }
        .padding(18)
        .glassEffect()
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(Color.accent.opacity(0.2), lineWidth: 1)
        )
    }

    private var reticleOverviewCard: some View {
        VStack(spacing: 14) {
            HStack {
                Image(systemName: "scope")
                    .foregroundStyle(Color.accent)
                Text("Reticle Progress")
                    .font(.agency(17))
                    .foregroundStyle(.white)
                Spacer()
                Text(String(format: "%.1f%%", vm.overallReticleProgress * 100))
                    .font(.agency(15))
                    .foregroundStyle(Color.accent)
            }

            HStack(spacing: 12) {
                StatTile(value: "\(vm.unlockedReticles)", total: "\(vm.totalReticles)",
                         label: "Unlocked", icon: "scope", color: .accent)
                StatTile(value: "\(vm.reticleOptics.filter(\.isComplete).count)",
                         total: "\(vm.reticleOptics.count)",
                         label: "Optics Done", icon: "checkmark.circle.fill", color: .cyan)
            }

            ProgressView(value: vm.overallReticleProgress)
                .tint(.accent)
        }
        .padding(18)
        .glassEffect()
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(Color.accent.opacity(0.2), lineWidth: 1)
        )
    }

    private var categoryBreakdown: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Camos by Class")
                .font(.agency(22))
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
                .font(.agencyReg(22))
                .foregroundStyle(color)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.agency(22))
                    .foregroundStyle(.white)
                Text("/\(total)")
                    .font(.agencyReg(15))
                    .foregroundStyle(.white.opacity(0.35))
            }
            Text(label)
                .font(.agencyReg(13))
                .foregroundStyle(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .glassEffect()
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

struct CategoryStatRow: View {
    let category: WeaponCategory

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(category.hasDiamond ? Color.cyan.opacity(0.18) : Color.accentMuted)
                    .frame(width: 36, height: 36)
                Image(systemName: category.categoryIcon)
                    .font(.agencyReg(15))
                    .foregroundStyle(category.hasDiamond ? .cyan : .accent)
            }

            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(category.WeaponCategoryName)
                        .font(.agency(15))
                        .foregroundStyle(.white)
                    Spacer()
                    if category.hasDiamond {
                        Label("Diamond", systemImage: "diamond.fill")
                            .font(.agency(11))
                            .foregroundStyle(.cyan)
                    } else {
                        Text("\(category.goldCount)/\(category.Weapons.count) Gold")
                            .font(.agency(11))
                            .foregroundStyle(category.goldCount > 0 ? Color.accent : .white.opacity(0.4))
                    }
                }
                ProgressView(value: category.overallProgress)
                    .tint(category.hasDiamond ? .cyan : .accent)
            }
        }
        .padding(14)
        .glassEffect()
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}
