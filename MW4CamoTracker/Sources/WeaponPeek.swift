import SwiftUI

/// Press and hold a weapon card: a quick look at the gun (its picture, camo
/// row and the challenge it's on now, with the count) and a few actions,
/// without opening it. A tap still opens the weapon as before.
struct WeaponPeekMenu: ViewModifier {
    let mode: AppMode
    let weapon: WeaponEntry
    @EnvironmentObject private var viewModel: TrackerViewModel
    @ObservedObject private var overlay = StreamOverlay.shared
    @State private var sharing = false
    /// The quick look's own height, so the pop-up hugs it up to a cap
    @State private var contentHeight: CGFloat = 440

    /// The next camo still to earn, which "Mark done" ticks.
    private var nextCamo: ChallengeItem? {
        viewModel.camos(weaponId: weapon.weaponId, mode: mode.rawValue)
            .flatMap(viewModel.leafItems)
            .first { !viewModel.isCamoComplete(mode: mode.rawValue, weaponId: weapon.weaponId, camo: $0) }
    }

    /// With every camo done: the next Completionist camo (Gold, Platinum...)
    /// that can be ticked now. The final one comes by itself, so never that.
    private var nextCompletionist: Int? {
        let raw = mode.rawValue
        let steps = min(mode.completionist.steps.count, TrackerViewModel.completionistStepCount)
        guard nextCamo == nil,
              let step = (0..<steps).first(where: { !viewModel.isCompletionistComplete(mode: raw, weaponId: weapon.weaponId, step: $0) }),
              viewModel.isCompletionistAvailable(mode: raw, weaponId: weapon.weaponId, step: step) else { return nil }
        return step
    }

    private var onOverlay: Bool {
        overlay.content == .weapon && overlay.mode == mode.rawValue
            && overlay.weaponId(game: viewModel.game.id) == weapon.weaponId
    }

    func body(content: Content) -> some View {
        content
            .pressPeek { dismiss in
                // Scrolls when it's taller than the room above or below the card
                ScrollView {
                    VStack(spacing: 0) {
                        WeaponPeek(mode: mode, weapon: weapon).environmentObject(viewModel)
                        actions(dismiss)
                    }
                    .background(GeometryReader { geo in
                        Color.clear.preference(key: PeekHeight.self, value: geo.size.height)
                    })
                }
                .onPreferenceChange(PeekHeight.self) { contentHeight = $0 }
                .frame(width: 340, height: min(max(contentHeight, 200), 440))
                .background(Color.appSurface)
            }
            .sheet(isPresented: $sharing) {
                WeaponShareSheet(weapon: weapon, mode: mode).environmentObject(viewModel)
            }
    }

    /// Under the quick look: tick the next camo, put the gun on stream, share.
    @ViewBuilder private func actions(_ dismiss: @escaping () -> Void) -> some View {
        VStack(spacing: 0) {
            if let camo = nextCamo {
                action(String(format: "ct.peek.mark_done".localized(), camo.name.resolved()), "checkmark.circle") {
                    viewModel.toggleCamo(mode: mode.rawValue, weaponId: weapon.weaponId, camo: camo)
                }
            } else if let step = nextCompletionist {
                action(String(format: "ct.peek.mark_done".localized(), mode.completionist.steps[step].name), "checkmark.circle") {
                    viewModel.toggleCompletionist(mode: mode.rawValue, weaponId: weapon.weaponId, step: step)
                }
            }
            // Only while the overlay is on: it puts this gun on stream
            if overlay.isOn, !onOverlay {
                action("ct.peek.overlay".localized(), "dot.radiowaves.left.and.right") {
                    overlay.mode = mode.rawValue
                    overlay.content = .weapon
                    overlay.setWeapon(weapon.weaponId, game: viewModel.game.id)
                    dismiss()
                }
            }
            action("mw4.ui.share.button".localized(), "square.and.arrow.up") {
                dismiss()
                // After the pop-up has gone, or the sheet has nothing to show from
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { sharing = true }
            }
        }
    }

    private func action(_ title: String, _ symbol: String, _ run: @escaping () -> Void) -> some View {
        VStack(spacing: 0) {
            Divider()
            Button(action: run) {
                HStack {
                    Text(title)
                    Spacer()
                    Image(systemName: symbol)
                }
                .font(.body)
                .foregroundStyle(Color.appInk)
                .padding(.horizontal, 16)
                .padding(.vertical, 13)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}

private struct PeekHeight: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

extension View {
    func weaponPeek(mode: AppMode, weapon: WeaponEntry) -> some View {
        modifier(WeaponPeekMenu(mode: mode, weapon: weapon))
    }
}

/// The quick look: the same figures the stream overlay shows for a weapon.
struct WeaponPeek: View {
    let mode: AppMode
    let weapon: WeaponEntry
    @EnvironmentObject private var viewModel: TrackerViewModel

    var body: some View {
        let data = viewModel.streamOverlayPayload(content: .weapon, modeRaw: mode.rawValue, weaponId: weapon.weaponId)?.weapon
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                WeaponThumbnail(urlString: weapon.imageURL, size: 64,
                                category: viewModel.category(containingWeaponId: weapon.weaponId))
                VStack(alignment: .leading, spacing: 2) {
                    Text(weapon.name.resolved())
                        .hitmarkerFont(20)
                        .foregroundStyle(Color.appInk)
                        .lineLimit(1)
                    if let data {
                        Text("\(mode.displayName) · \(data.badge)")
                            .font(.footnote)
                            .foregroundStyle(Color.appInkMuted)
                            .lineLimit(2)
                    }
                }
            }
            if let data, !data.camos.isEmpty {
                // Every camo, earned ones lit, wrapping to as many rows as it needs
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(26), spacing: 6), count: 10), alignment: .leading, spacing: 6) {
                    ForEach(Array(data.camos.enumerated()), id: \.offset) { _, camo in
                        CamoThumbnail(urlString: camo.image, size: 26)
                            .opacity(camo.done ? 1 : 0.3)
                    }
                }
                Text(String(format: "ct.peek.camos".localized(), data.done, data.total))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.appInkMuted)
            }
            if let next = data?.next {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(next.name)
                            .font(.headline)
                            .foregroundStyle(mode.accent)
                        Spacer()
                        if next.total > 1 {
                            Text("\(next.done)/\(next.total)")
                                .font(.subheadline.monospacedDigit().weight(.semibold))
                                .foregroundStyle(Color.appInk)
                        }
                    }
                    if !next.detail.isEmpty {
                        Text(next.detail)
                            .font(.subheadline)
                            .foregroundStyle(Color.appInkMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if next.total > 1 {
                        ProgressBar(fraction: Double(next.done) / Double(next.total), accent: mode.accent)
                    }
                }
                .padding(12)
                .background(Color.appSurface2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else if data != nil {
                Label("ct.peek.all_done".localized(), systemImage: "checkmark.seal.fill")
                    .font(.headline)
                    .foregroundStyle(mode.accent)
            }
        }
        .padding(16)
        .frame(width: 340)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("weapon.peek.\(weapon.name.resolved())")
    }
}
