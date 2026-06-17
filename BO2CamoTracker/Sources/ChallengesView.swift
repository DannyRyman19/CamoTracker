import SwiftUI

struct ChallengesView: View {
    @Environment(TrackerViewModel.self) private var vm

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 14) {
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
            .background(.black)
        }
    }

    private var challengesSummary: some View {
        HStack(spacing: 0) {
            summaryCell(value: vm.completedChallenges, label: "Done")
            Divider().frame(height: 40).background(.white.opacity(0.15))
            summaryCell(value: vm.totalChallenges, label: "Total")
            Divider().frame(height: 40).background(.white.opacity(0.15))
            VStack(spacing: 4) {
                Text(String(format: "%.0f%%", vm.overallChallengeProgress * 100))
                    .font(.title.bold().monospacedDigit())
                    .foregroundStyle(.white)
                Text("Progress")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 12)
        .glassEffect()
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func summaryCell(value: Int, label: String) -> some View {
        VStack(spacing: 4) {
            Text("\(value)")
                .font(.title.bold().monospacedDigit())
                .foregroundStyle(.white)
            Text(label)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
    }
}

struct ChallengeCategoryCard: View {
    let category: ChallengeCategory

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: category.CategoryIcon)
                    .font(.title2)
                    .foregroundStyle(category.isComplete ? .yellow : .white.opacity(0.7))
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(category.CategoryName)
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text("\(category.totalCount) challenges")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.5))
                }

                Spacer()

                Text("\(category.completedCount)/\(category.totalCount)")
                    .font(.subheadline.bold().monospacedDigit())
                    .foregroundStyle(category.isComplete ? .yellow : .white.opacity(0.6))

                if category.isComplete {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.yellow)
                }

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.3))
            }

            ProgressView(value: category.progress)
                .tint(category.isComplete ? .yellow : .white.opacity(0.5))
        }
        .padding(16)
        .glassEffect()
        .clipShape(RoundedRectangle(cornerRadius: 18))
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
        .background(.black)
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
    private var highestUnlocked: MPChallenge? { group.filter(\.IsComplete).max(by: { ($0.Tier ?? 0) < ($1.Tier ?? 0) }) }

    var body: some View {
        VStack(spacing: 0) {
            Button { withAnimation(.spring(duration: 0.3)) { expanded.toggle() } } label: {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(completedCount == group.count ? Color.yellow.opacity(0.2) : Color.white.opacity(0.08))
                            .frame(width: 36, height: 36)
                        Image(systemName: completedCount == group.count ? "checkmark" : "list.number")
                            .font(.caption.bold())
                            .foregroundStyle(completedCount == group.count ? .yellow : .white.opacity(0.5))
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(seriesName)
                            .font(.subheadline.bold())
                            .foregroundStyle(.white)
                        if let top = highestUnlocked {
                            Text("Reached Tier \(top.tierLabel ?? "")")
                                .font(.caption)
                                .foregroundStyle(.yellow.opacity(0.7))
                        } else {
                            Text("\(group.count) tiers")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.4))
                        }
                    }

                    Spacer()

                    Text("\(completedCount)/\(group.count)")
                        .font(.caption.bold().monospacedDigit())
                        .foregroundStyle(completedCount == group.count ? .yellow : .white.opacity(0.5))

                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.3))
                }
                .padding(14)
            }
            .buttonStyle(.plain)

            if expanded {
                Divider().background(.white.opacity(0.1)).padding(.horizontal, 14)

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
        .clipShape(RoundedRectangle(cornerRadius: 14))
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
                        .fill(challenge.IsComplete ? Color.yellow : Color.white.opacity(0.08))
                        .frame(width: 36, height: 36)
                    if challenge.IsComplete {
                        Image(systemName: "checkmark")
                            .font(.subheadline.bold())
                            .foregroundStyle(.black)
                    } else {
                        Image(systemName: "circle")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.3))
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(challenge.ChallengeName)
                            .font(.subheadline.bold())
                            .foregroundStyle(challenge.IsComplete ? .yellow : .white)

                        if let label = challenge.tierLabel {
                            Text(label)
                                .font(.caption2.bold())
                                .foregroundStyle(challenge.IsComplete ? .black : .white.opacity(0.6))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(challenge.IsComplete ? Color.yellow : Color.white.opacity(0.15))
                                .clipShape(Capsule())
                        }

                        Spacer()

                        if challenge.IsComplete {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.caption)
                                .foregroundStyle(.yellow)
                        }
                    }
                    Text(challenge.displayDescription)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.5))
                        .multilineTextAlignment(.leading)
                }
            }
            .padding(14)
            .glassEffect()
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }
}
