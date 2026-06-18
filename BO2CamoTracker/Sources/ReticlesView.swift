import SwiftUI

struct ReticlesView: View {
    @Environment(TrackerViewModel.self) private var vm

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 12) {
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
            .background(AppBackground())
        }
    }

    private var reticleSummary: some View {
        HStack(spacing: 0) {
            VStack(spacing: 4) {
                Text("\(vm.unlockedReticles)")
                    .font(.agency(22))
                    .foregroundStyle(.white)
                Text("Unlocked")
                    .font(.agencyReg(13))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .frame(maxWidth: .infinity)

            Divider().frame(height: 40).background(.white.opacity(0.12))

            VStack(spacing: 4) {
                Text("\(vm.totalReticles)")
                    .font(.agency(22))
                    .foregroundStyle(.white)
                Text("Total")
                    .font(.agencyReg(13))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .frame(maxWidth: .infinity)

            Divider().frame(height: 40).background(.white.opacity(0.12))

            VStack(spacing: 4) {
                Text(String(format: "%.0f%%", vm.overallReticleProgress * 100))
                    .font(.agency(22))
                    .foregroundStyle(.white)
                Text("Complete")
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
}

struct ReticleOpticCard: View {
    let optic: ReticleOptic

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(optic.isComplete ? Color.accentMuted : Color.white.opacity(0.07))
                        .frame(width: 44, height: 44)
                    Image(systemName: optic.isComplete ? "checkmark.circle.fill" : "scope")
                        .font(.agencyReg(20))
                        .foregroundStyle(optic.isComplete ? Color.accent : .white.opacity(0.55))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(optic.OpticName)
                        .font(.agency(17))
                        .foregroundStyle(.white)
                    Text(optic.UnlockDescription)
                        .font(.agencyReg(13))
                        .foregroundStyle(.white.opacity(0.45))
                        .lineLimit(1)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(optic.unlockedCount)/\(optic.totalCount)")
                        .font(.agency(15))
                        .foregroundStyle(optic.isComplete ? Color.accent : .white.opacity(0.6))
                    Text("reticles")
                        .font(.agencyReg(11))
                        .foregroundStyle(.white.opacity(0.35))
                }

                Image(systemName: "chevron.right")
                    .font(.agencyReg(13))
                    .foregroundStyle(.white.opacity(0.3))
            }

            ProgressView(value: optic.progress)
                .tint(optic.isComplete ? .accent : Color.accent.opacity(0.6))
        }
        .padding(16)
        .glassEffect()
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(
                    optic.isComplete ? Color.accent.opacity(0.45) :
                    optic.progress > 0 ? Color.accent.opacity(0.15) : Color.clear,
                    lineWidth: 1
                )
        )
    }
}

// MARK: - Optic detail

struct ReticleOpticDetailView: View {
    @Environment(TrackerViewModel.self) private var vm
    let opticIndex: Int

    private var optic: ReticleOptic { vm.reticleOptics[opticIndex] }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                killCountCard
                    .padding(.horizontal)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Reticles")
                        .font(.agency(22))
                        .foregroundStyle(.white)
                        .padding(.horizontal)

                    ForEach(optic.Reticles) { reticle in
                        ReticleRow(reticle: reticle, currentKills: optic.CurrentAmount)
                            .padding(.horizontal)
                    }
                }

                Spacer(minLength: 24)
            }
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .navigationTitle(optic.OpticName)
        .navigationBarTitleDisplayMode(.large)
        .background(AppBackground())
    }

    private var killCountCard: some View {
        VStack(spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Kills with \(optic.OpticName)")
                        .font(.agencyReg(15))
                        .foregroundStyle(.white.opacity(0.6))
                    Text("\(optic.CurrentAmount)")
                        .font(.agency(28))
                        .foregroundStyle(.white)
                }
                Spacer()
                KillStepper(value: optic.CurrentAmount,
                            max: optic.Reticles.last?.AmountRequired ?? 9999) { newValue in
                    vm.setReticleAmount(opticIndex: opticIndex, amount: newValue)
                }
            }

            ProgressView(value: optic.progress)
                .tint(.accent)

            HStack {
                Text("\(optic.unlockedCount)/\(optic.totalCount) reticles unlocked")
                    .font(.agencyReg(13))
                    .foregroundStyle(.white.opacity(0.45))
                Spacer()
                if let next = optic.Reticles.first(where: { !$0.IsUnlocked }) {
                    Text("\(next.AmountRequired - optic.CurrentAmount) kills to \(next.ReticleName)")
                        .font(.agencyReg(13))
                        .foregroundStyle(Color.accent.opacity(0.85))
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
                    .fill(reticle.IsUnlocked ? Color.accentMuted : Color.white.opacity(0.05))
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
                    .font(.agency(15))
                    .foregroundStyle(reticle.IsUnlocked ? Color.accent : .white.opacity(0.6))
                Text("Requires \(reticle.AmountRequired) kills")
                    .font(.agencyReg(13))
                    .foregroundStyle(.white.opacity(0.35))
            }

            Spacer()

            if reticle.IsUnlocked {
                Text("Unlocked")
                    .font(.agency(11))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.accent)
                    .clipShape(Capsule())
            } else {
                let remaining = reticle.AmountRequired - currentKills
                Text("\(remaining) left")
                    .font(.agencyReg(11))
                    .foregroundStyle(.white.opacity(0.3))
            }
        }
        .padding(12)
        .glassEffect()
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(reticle.IsUnlocked ? Color.accent.opacity(0.35) : Color.clear, lineWidth: 1)
        )
    }

    private var reticleIcon: some View {
        Image(systemName: "scope")
            .font(.agencyReg(20))
            .foregroundStyle(reticle.IsUnlocked ? Color.accent : .white.opacity(0.18))
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
                    .font(.agencyReg(22))
                    .foregroundStyle(Color.accent.opacity(0.8))
            }
            .buttonStyle(.plain)

            TextField("0", text: $text)
                .keyboardType(.numberPad)
                .focused($focused)
                .multilineTextAlignment(.center)
                .font(.agencyReg(17))
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
                    .font(.agencyReg(22))
                    .foregroundStyle(Color.accent.opacity(0.8))
            }
            .buttonStyle(.plain)
        }
    }
}
