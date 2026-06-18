import SwiftUI

struct ChallengesView: View {
    @Environment(TrackerViewModel.self) private var vm

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 12) {
                    challengesSummary
                        .padding(.horizontal)
                        .padding(.top, 4)

                    ForEach(Array(vm.challengeCategories.enumerated()), id: \.element.id) { index, cat in
                        NavigationLink(destination: ChallengeCategoryView(categoryIndex: index)) {
                            ChallengeCategoryCard(category: cat)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal)
                    }
                }
                .padding(.vertical, 8)
                .padding(.bottom, 24)
            }
            .navigationTitle("Challenges")
            .background(AppBackground())
        }
    }

    private var challengesSummary: some View {
        HStack(spacing: 0) {
            summaryCell(value: vm.completedChallenges, label: "Done")
            Divider().frame(height: 40).background(.white.opacity(0.12))
            summaryCell(value: vm.totalChallenges, label: "Total")
            Divider().frame(height: 40).background(.white.opacity(0.12))
            VStack(spacing: 4) {
                Text(String(format: "%.0f%%", vm.overallChallengeProgress * 100))
                    .font(.agency(22))
                    .foregroundStyle(.white)
                Text("Progress")
                    .font(.agencyReg(13))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 14)
        .glassEffect()
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(Color.accent.opacity(0.25), lineWidth: 1)
        )
    }

    private func summaryCell(value: Int, label: String) -> some View {
        VStack(spacing: 4) {
            Text("\(value)")
                .font(.agency(22))
                .foregroundStyle(.white)
            Text(label)
                .font(.agencyReg(13))
                .foregroundStyle(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
    }
}

struct ChallengeCategoryCard: View {
    let category: ChallengeCategory

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(category.isComplete ? Color.accentMuted : Color.white.opacity(0.07))
                        .frame(width: 44, height: 44)
                    Image(systemName: category.CategoryIcon)
                        .font(.agencyReg(20))
                        .foregroundStyle(category.isComplete ? Color.accent : .white.opacity(0.6))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(category.CategoryName)
                        .font(.agency(17))
                        .foregroundStyle(.white)
                    Text("\(category.totalCount) challenges")
                        .font(.agencyReg(13))
                        .foregroundStyle(.white.opacity(0.5))
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(category.completedCount)/\(category.totalCount)")
                        .font(.agency(15))
                        .foregroundStyle(category.isComplete ? Color.accent : .white.opacity(0.5))
                    if category.isComplete {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.agencyReg(13))
                            .foregroundStyle(Color.accent)
                    }
                }

                Image(systemName: "chevron.right")
                    .font(.agencyReg(13))
                    .foregroundStyle(.white.opacity(0.3))
            }

            ProgressView(value: category.progress)
                .tint(category.isComplete ? .accent : Color.accent.opacity(0.6))
        }
        .padding(16)
        .glassEffect()
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(
                    category.isComplete ? Color.accent.opacity(0.45) :
                    category.progress > 0 ? Color.accent.opacity(0.15) : Color.clear,
                    lineWidth: 1
                )
        )
    }
}

// MARK: - Category detail (tier-aware)

struct ChallengeCategoryView: View {
    @Environment(TrackerViewModel.self) private var vm
    let categoryIndex: Int

    private var category: ChallengeCategory { vm.challengeCategories[categoryIndex] }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(Array(category.groupedChallenges.enumerated()), id: \.offset) { _, group in
                    if group.count > 1 {
                        TieredChallengeGroup(group: group, categoryIndex: categoryIndex,
                                             categoryID: category.CategoryID,
                                             challenges: category.Challenges)
                            .padding(.horizontal)
                    } else if let challenge = group.first,
                              let ji = category.Challenges.firstIndex(where: { $0.id == challenge.id }) {
                        MPChallengeRow(challenge: challenge) {
                            vm.toggleChallenge(categoryIndex: categoryIndex, challengeIndex: ji)
                        }
                        .padding(.horizontal)
                    }
                }
            }
            .padding(.vertical, 8)
            .padding(.bottom, 24)
        }
        .navigationTitle(category.CategoryName)
        .navigationBarTitleDisplayMode(.large)
        .background(AppBackground())
    }
}

struct TieredChallengeGroup: View {
    let group: [MPChallenge]
    let categoryIndex: Int
    let categoryID: Int
    let challenges: [MPChallenge]
    @Environment(TrackerViewModel.self) private var vm
    @State private var expanded = false

    private var seriesName: String { group.first?.SeriesName ?? "" }
    private var completedCount: Int { group.filter(\.IsComplete).count }
    private var highestUnlocked: MPChallenge? {
        group.filter(\.IsComplete).max(by: { ($0.Tier ?? 0) < ($1.Tier ?? 0) })
    }
    private var allDone: Bool { completedCount == group.count }

    var body: some View {
        VStack(spacing: 0) {
            Button { withAnimation(.spring(duration: 0.3)) { expanded.toggle() } } label: {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(allDone ? Color.accentMuted : Color.white.opacity(0.07))
                            .frame(width: 40, height: 40)
                        Image(systemName: allDone ? "checkmark" : "list.number")
                            .font(.agency(13))
                            .foregroundStyle(allDone ? Color.accent : .white.opacity(0.5))
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(seriesName)
                            .font(.agency(15))
                            .foregroundStyle(.white)
                        if let top = highestUnlocked {
                            Text("Reached Tier \(top.tierLabel ?? "")")
                                .font(.agencyReg(13))
                                .foregroundStyle(Color.accent.opacity(0.8))
                        } else {
                            Text("\(group.count) tiers")
                                .font(.agencyReg(13))
                                .foregroundStyle(.white.opacity(0.4))
                        }
                    }

                    Spacer()

                    Text("\(completedCount)/\(group.count)")
                        .font(.agency(13))
                        .foregroundStyle(allDone ? Color.accent : .white.opacity(0.45))

                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.agencyReg(13))
                        .foregroundStyle(.white.opacity(0.3))
                }
                .padding(14)
            }
            .buttonStyle(.plain)

            if expanded {
                Divider().background(.white.opacity(0.08)).padding(.horizontal, 14)

                VStack(spacing: 6) {
                    ForEach(group) { challenge in
                        if let ji = challenges.firstIndex(where: { $0.id == challenge.id }) {
                            MPChallengeRow(challenge: challenge) {
                                vm.toggleChallenge(categoryIndex: categoryIndex, challengeIndex: ji)
                            }
                        }
                    }
                }
                .padding(10)
            }
        }
        .glassEffect()
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(allDone ? Color.accent.opacity(0.4) : Color.clear, lineWidth: 1)
        )
    }
}

struct MPChallengeRow: View {
    let challenge: MPChallenge
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(challenge.IsComplete ? Color.accent : Color.white.opacity(0.07))
                        .frame(width: 36, height: 36)
                    if challenge.IsComplete {
                        Image(systemName: "checkmark")
                            .font(.agency(15))
                            .foregroundStyle(.black)
                    } else {
                        Image(systemName: "circle")
                            .font(.agencyReg(15))
                            .foregroundStyle(.white.opacity(0.25))
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(challenge.ChallengeName)
                            .font(.agency(15))
                            .foregroundStyle(challenge.IsComplete ? Color.accent : .white)

                        if let label = challenge.tierLabel {
                            Text(label)
                                .font(.agency(11))
                                .foregroundStyle(challenge.IsComplete ? .black : .white.opacity(0.5))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(challenge.IsComplete ? Color.accent : Color.white.opacity(0.12))
                                .clipShape(Capsule())
                        }

                        Spacer()
                    }
                    Text(challenge.displayDescription)
                        .font(.agencyReg(13))
                        .foregroundStyle(.white.opacity(0.45))
                        .multilineTextAlignment(.leading)
                }
            }
            .padding(14)
            .glassEffect()
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(challenge.IsComplete ? Color.accent.opacity(0.35) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
