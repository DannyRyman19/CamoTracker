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
            VStack(spacing: 4) {
                Text("\(vm.completedChallenges)")
                    .font(.title.bold().monospacedDigit())
                    .foregroundStyle(.white)
                Text("Completed")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
            }
            .frame(maxWidth: .infinity)

            Divider().frame(height: 40).background(.white.opacity(0.15))

            VStack(spacing: 4) {
                Text("\(vm.totalChallenges)")
                    .font(.title.bold().monospacedDigit())
                    .foregroundStyle(.white)
                Text("Total")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
            }
            .frame(maxWidth: .infinity)

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

struct ChallengeCategoryView: View {
    @Environment(TrackerViewModel.self) private var vm
    let categoryIndex: Int

    private var category: ChallengeCategory { vm.challengeCategories[categoryIndex] }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(Array(category.Challenges.enumerated()), id: \.element.id) { index, challenge in
                    MPChallengeRow(challenge: challenge) {
                        vm.toggleChallenge(categoryIndex: categoryIndex, challengeIndex: index)
                    }
                    .padding(.horizontal)
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
                    HStack {
                        Text(challenge.ChallengeName)
                            .font(.subheadline.bold())
                            .foregroundStyle(challenge.IsComplete ? .yellow : .white)
                        Spacer()
                        if challenge.IsComplete {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.caption)
                                .foregroundStyle(.yellow)
                        }
                    }
                    Text(challenge.displayDescription)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.55))
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
