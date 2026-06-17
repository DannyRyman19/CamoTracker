import SwiftUI

struct ReticlesView: View {
    @Environment(TrackerViewModel.self) private var vm

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 14) {
                    reticleSummary
                        .padding(.horizontal)
                        .padding(.top, 4)

                    ForEach(Array(vm.reticleOptics.enumerated()), id: \.element.id) { index, optic in
                        NavigationLink(destination: ReticleOpticDetailView(opticIndex: index)) {
                            ReticleOpticCard(optic: optic)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal)
                    }
                }
                .padding(.vertical, 8)
                .padding(.bottom, 24)
            }
            .navigationTitle("Reticles")
            .background(.black)
        }
    }

    private var reticleSummary: some View {
        HStack(spacing: 0) {
            VStack(spacing: 4) {
                Text("\(vm.unlockedReticles)")
                    .font(.title.bold().monospacedDigit())
                    .foregroundStyle(.white)
                Text("Unlocked")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
            }
            .frame(maxWidth: .infinity)

            Divider().frame(height: 40).background(.white.opacity(0.15))

            VStack(spacing: 4) {
                Text("\(vm.totalReticles)")
                    .font(.title.bold().monospacedDigit())
                    .foregroundStyle(.white)
                Text("Total")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
            }
            .frame(maxWidth: .infinity)

            Divider().frame(height: 40).background(.white.opacity(0.15))

            VStack(spacing: 4) {
                Text(String(format: "%.0f%%", vm.overallReticleProgress * 100))
                    .font(.title.bold().monospacedDigit())
                    .foregroundStyle(.white)
                Text("Complete")
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

struct ReticleOpticCard: View {
    let optic: ReticleOptic

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(optic.isComplete ? Color.green.opacity(0.2) : Color.white.opacity(0.08))
                        .frame(width: 44, height: 44)
                    Image(systemName: optic.isComplete ? "checkmark.circle.fill" : "scope")
                        .font(.title3)
                        .foregroundStyle(optic.isComplete ? .green : .white.opacity(0.6))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(optic.OpticName)
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text(optic.UnlockDescription)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(1)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(optic.unlockedCount)/\(optic.totalCount)")
                        .font(.subheadline.bold().monospacedDigit())
                        .foregroundStyle(optic.isComplete ? .green : .white.opacity(0.7))
                    Text("reticles")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.4))
                }

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.3))
            }

            ProgressView(value: optic.progress)
                .tint(optic.isComplete ? .green : .cyan)
        }
        .padding(16)
        .glassEffect()
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }
}

// MARK: - Optic detail

struct ReticleOpticDetailView: View {
    @Environment(TrackerViewModel.self) private var vm
    let opticIndex: Int

    private var optic: ReticleOptic { vm.reticleOptics[opticIndex] }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                killCountCard
                    .padding(.horizontal)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Reticles")
                        .font(.title3.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal)

                    ForEach(optic.Reticles) { reticle in
                        ReticleRow(reticle: reticle, currentKills: optic.CurrentAmount)
                            .padding(.horizontal)
                    }
                }

                Spacer(minLength: 32)
            }
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .navigationTitle(optic.OpticName)
        .navigationBarTitleDisplayMode(.large)
        .background(.black)
    }

    private var killCountCard: some View {
        VStack(spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Kills with \(optic.OpticName)")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.7))
                    Text("\(optic.CurrentAmount)")
                        .font(.title.bold().monospacedDigit())
                        .foregroundStyle(.white)
                }
                Spacer()
                KillStepper(value: optic.CurrentAmount,
                            max: optic.Reticles.last?.AmountRequired ?? 9999) { newValue in
                    vm.setReticleAmount(opticIndex: opticIndex, amount: newValue)
                }
            }

            ProgressView(value: optic.progress)
                .tint(.cyan)

            HStack {
                Text("\(optic.unlockedCount)/\(optic.totalCount) reticles unlocked")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
                Spacer()
                if let next = optic.Reticles.first(where: { !$0.IsUnlocked }) {
                    Text("\(next.AmountRequired - optic.CurrentAmount) kills to \(next.ReticleName)")
                        .font(.caption)
                        .foregroundStyle(.cyan.opacity(0.8))
                }
            }
        }
        .padding(16)
        .glassEffect()
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

struct ReticleRow: View {
    let reticle: ReticleChallenge
    let currentKills: Int

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(reticle.IsUnlocked ? Color.cyan.opacity(0.15) : Color.white.opacity(0.06))
                    .frame(width: 44, height: 44)
                if let url = reticle.ImageURL {
                    AsyncImage(url: URL(string: url)) { phase in
                        if case .success(let img) = phase {
                            img.resizable().aspectRatio(contentMode: .fit).padding(6)
                        } else {
                            reticleIcon
                        }
                    }
                } else {
                    reticleIcon
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(reticle.ReticleName)
                    .font(.subheadline.bold())
                    .foregroundStyle(reticle.IsUnlocked ? .cyan : .white.opacity(0.6))
                Text("Requires \(reticle.AmountRequired) kills")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.4))
            }

            Spacer()

            if reticle.IsUnlocked {
                Text("Unlocked")
                    .font(.caption2.bold())
                    .foregroundStyle(.black)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.cyan)
                    .clipShape(Capsule())
            } else {
                let remaining = reticle.AmountRequired - currentKills
                Text("\(remaining) left")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.3))
            }
        }
        .padding(12)
        .glassEffect()
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var reticleIcon: some View {
        Image(systemName: reticle.IsUnlocked ? "scope" : "scope")
            .font(.title3)
            .foregroundStyle(reticle.IsUnlocked ? .cyan : .white.opacity(0.2))
    }
}

// MARK: - Kill count stepper

struct KillStepper: View {
    let value: Int
    let max: Int
    let onChange: (Int) -> Void

    @State private var text: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Button {
                let v = Swift.max(0, value - 25)
                onChange(v)
            } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.white.opacity(0.6))
            }
            .buttonStyle(.plain)

            TextField("0", text: $text)
                .keyboardType(.numberPad)
                .focused($focused)
                .multilineTextAlignment(.center)
                .font(.headline.monospacedDigit())
                .foregroundStyle(.white)
                .frame(width: 64)
                .padding(.vertical, 6)
                .glassEffect()
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .onAppear { text = "\(value)" }
                .onChange(of: value) { _, v in if !focused { text = "\(v)" } }
                .onSubmit {
                    if let v = Int(text) { onChange(Swift.min(v, max)) }
                }

            Button {
                let v = Swift.min(max, value + 25)
                onChange(v)
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.white.opacity(0.6))
            }
            .buttonStyle(.plain)
        }
    }
}
