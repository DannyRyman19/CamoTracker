import SwiftUI

extension String {
    /// Looks up static app chrome (tab names, button labels, onboarding copy)
    /// in the bundled `Localizable.strings`. Content that arrives over the air
    /// — weapon names, camo text, DMZ objectives — uses `LocalizedText`
    /// instead (see Models.swift), since a bundle key can't resolve until the
    /// next app update ships a matching entry.
    func localized() -> String {
        NSLocalizedString(self, bundle: .main, comment: "")
    }
}

/// A camo name rendered in its own shifting multi-color gradient instead of
/// flat text — the in-game Mastery camos are animated metallic/holographic
/// finishes, so a static swatch undersells them.
///
/// Painted directly as the text's `foregroundStyle` (never masked), driven by
/// `TimelineView(.animation)` recomputing the gradient from wall-clock time
/// every frame — not SwiftUI's `withAnimation` interpolation. That sidesteps
/// the bug the mask+offset version had: mask alignment doesn't track an
/// offset view's *painted* position, only its layout frame, so the sliding
/// gradient would drift out from under the mask and the text would flash
/// transparent. Painting the gradient straight onto the text glyphs means
/// there's no separate mask to lose alignment with — some blend of the
/// gradient always covers 100% of the text every frame.
struct AnimatedGradientText: View {
    let text: String
    let colors: [Color]
    var font: Font = .hitmarker(16)
    var period: Double = 3.2
    /// Glow the text in its own base color — this is the real sibling
    /// trackers' actual technique for a "special" title (BO7 Camo Tracker's
    /// unlock modal uses a solid gold `textShadowColor`/`textShadowRadius`
    /// glow, not a moving gradient), so pairing it with the shimmer here
    /// keeps this aligned with that family's look rather than a from-scratch
    /// invention.
    var glow = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private func gradient(phase: Double) -> LinearGradient {
        // Stops slide together by `phase` (‑0.5…0.5, a smooth sine ping-pong)
        // and clamp at the edges rather than wrap, so there's never a seam —
        // worst case the sweep briefly rests on a single edge color, it never
        // has a gap.
        let count = max(colors.count - 1, 1)
        let stops = colors.enumerated().map { index, color in
            Gradient.Stop(color: color, location: min(1, max(0, Double(index) / Double(count) + phase)))
        }
        return LinearGradient(gradient: Gradient(stops: stops), startPoint: .leading, endPoint: .trailing)
    }

    private func styled(_ text: Text, phase: Double) -> some View {
        text
            .font(font)
            .foregroundStyle(gradient(phase: phase))
            .shadow(color: glow ? (colors.first ?? .clear).opacity(0.75) : .clear, radius: 6)
    }

    var body: some View {
        if reduceMotion {
            styled(Text(text), phase: 0)
        } else {
            TimelineView(.animation) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                let phase = 0.5 * sin(t / period * 2 * .pi)
                styled(Text(text), phase: phase)
            }
        }
    }
}

/// A one-shot confetti burst from the top of its bounds — real, concrete
/// inspiration pulled from the sibling BO7 Camo Tracker app's own unlock
/// celebration (`react-native-confetti-cannon`), reimplemented natively here
/// with `Canvas` + `TimelineView` since there's no equivalent SwiftUI
/// package already in this project. Colored from the camo that was just
/// earned instead of a generic rainbow, so it reads as *that* camo's moment.
struct ConfettiBurst: View {
    let colors: [Color]
    var pieceCount: Int = 28
    var lifespan: Double = 1.5

    private struct Piece {
        let color: Color
        let angle: Double
        let speed: Double
        let rotationSpeed: Double
        let size: CGFloat
        let drift: Double
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pieces: [Piece] = []
    @State private var startDate = Date()

    var body: some View {
        if reduceMotion {
            Color.clear
        } else {
            TimelineView(.animation) { context in
                let elapsed = context.date.timeIntervalSince(startDate)
                Canvas { ctx, size in
                    guard elapsed < lifespan else { return }
                    let origin = CGPoint(x: size.width / 2, y: 0)
                    for piece in pieces {
                        let vx = cos(piece.angle) * piece.speed
                        let vy = sin(piece.angle) * piece.speed
                        let x = origin.x + vx * elapsed + piece.drift * elapsed
                        let y = origin.y + vy * elapsed + 0.5 * 380 * elapsed * elapsed
                        let rect = CGRect(x: -piece.size / 2, y: -piece.size / 4, width: piece.size, height: piece.size / 2)
                        var transform = CGAffineTransform(translationX: x, y: y)
                        transform = transform.rotated(by: piece.rotationSpeed * elapsed)
                        var context2 = ctx
                        context2.opacity = max(0, 1 - elapsed / lifespan)
                        context2.fill(Path(roundedRect: rect, cornerRadius: 1).applying(transform), with: .color(piece.color))
                    }
                }
            }
            .allowsHitTesting(false)
            .onAppear {
                startDate = Date()
                pieces = (0..<pieceCount).map { _ in
                    Piece(
                        color: colors.randomElement() ?? .camoGold,
                        angle: Double.random(in: (.pi * 0.15)...(.pi * 0.85)),
                        speed: Double.random(in: 110...240),
                        rotationSpeed: Double.random(in: -6...6),
                        size: CGFloat.random(in: 5...9),
                        drift: Double.random(in: -40...40)
                    )
                }
            }
        }
    }
}

/// Weapon thumbnails — same `AsyncImage` + graceful-fallback pattern the BO2
/// app already uses, just themed with an app-token background instead of a
/// hardcoded color. A `nil` or unreachable URL falls straight to the
/// placeholder icon rather than showing a broken image.
struct WeaponThumbnail: View {
    let urlString: String?
    let size: CGFloat

    /// The official render art is a wide cutout that runs edge-to-edge in a
    /// square frame — an inset keeps it from touching the tile's rounded
    /// corners, matching `WeaponHeroImage`'s own padding.
    var inset: CGFloat? = nil

    private var url: URL? { urlString.flatMap(URL.init(string:)) }

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image.resizable().aspectRatio(contentMode: .fit).padding(inset ?? size * 0.14)
            default:
                Image(systemName: "scope")
                    .font(.system(size: size * 0.4))
                    .foregroundStyle(Color.appInkMuted)
            }
        }
        .frame(width: size, height: size)
        .background(Color.appSurface2)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.2))
    }
}

/// A wide hero banner for the weapon detail screen. The official render art
/// is a wide horizontal cutout (gun lying flat, ~2:1 to ~5:1 aspect ratio) —
/// `WeaponThumbnail`'s square frame either shrinks it to a sliver or crops
/// off the barrel/stock, so the detail screen gets its own container sized
/// to fit the art's actual shape instead.
struct WeaponHeroImage: View {
    let urlString: String?
    var height: CGFloat = 108

    private var url: URL? { urlString.flatMap(URL.init(string:)) }

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image.resizable().aspectRatio(contentMode: .fit).padding(12)
            default:
                Image(systemName: "scope")
                    .font(.system(size: height * 0.32))
                    .foregroundStyle(Color.appInkMuted)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .background(Color.appSurface2)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

/// Same idea as `WeaponThumbnail`, sized and clipped for a small camo swatch.
struct CamoThumbnail: View {
    let urlString: String?
    let size: CGFloat

    private var url: URL? { urlString.flatMap(URL.init(string:)) }

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image.resizable().aspectRatio(contentMode: .fill)
            default:
                Image(systemName: "paintpalette")
                    .font(.system(size: size * 0.4))
                    .foregroundStyle(Color.appInkMuted)
            }
        }
        .frame(width: size, height: size)
        .background(Color.appSurface2)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.25))
    }
}

struct ProgressBar: View {
    let fraction: Double
    let accent: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.appSurface2)
                Capsule().fill(accent).frame(width: max(0, geo.size.width * min(fraction, 1)))
                    .animation(.easeOut(duration: 0.35), value: fraction)
            }
        }
        .frame(height: 4)
    }
}

/// A subtle stroke on top of the existing `appSurface` fill — squared off
/// (tight 8pt radius, not the softer 12pt this used to be) to read as a
/// loadout-menu panel rather than a rounded consumer-app card, matching the
/// in-game Create-a-Class reference. An optional `accent` washes the fill and
/// brightens the border in that color — used for the one card state that's
/// meant to look "equipped" (a weapon that's gone Gold), same idea as that
/// menu's khaki-highlighted selected slot, just in this app's own Gold color
/// instead of inventing a new token for it.
struct BorderedCard: ViewModifier {
    var cornerRadius: CGFloat = 8
    var accent: Color? = nil

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color.appSurface)
                    .overlay(RoundedRectangle(cornerRadius: cornerRadius).fill(accent?.opacity(0.10) ?? Color.clear))
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .strokeBorder(accent?.opacity(0.55) ?? Color.appInkMuted.opacity(0.25), lineWidth: 1)
                    )
            )
    }
}

extension View {
    func borderedCard(cornerRadius: CGFloat = 8, accent: Color? = nil) -> some View {
        modifier(BorderedCard(cornerRadius: cornerRadius, accent: accent))
    }
}

/// A row of small tier pips plus a trailing Mastery diamond per tier — the
/// loadout screen's "○○○○○+◇" ammo-capacity readout, repurposed as a
/// camo-progress glyph: one pip per camo tier for this weapon (filled once
/// that tier is done), then one diamond per Mastery tier this weapon can
/// earn (tier1, tier2 — each lights up in its own tier's color independently
/// once earned, not just the first).
struct CamoPipRow: View {
    struct MasteryTier {
        let achieved: Bool
        let color: Color
    }
    let camos: [ChallengeItem]
    let isComplete: (ChallengeItem) -> Bool
    let filledColor: Color
    let masteryTiers: [MasteryTier]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(camos) { camo in
                Circle()
                    .fill(isComplete(camo) ? filledColor : Color.clear)
                    .overlay(Circle().strokeBorder(Color.appInkMuted.opacity(0.5), lineWidth: isComplete(camo) ? 0 : 1))
                    .frame(width: 6, height: 6)
                    .scaleEffect(isComplete(camo) ? 1 : 0.85)
                    .animation(.spring(response: 0.3, dampingFraction: 0.5), value: isComplete(camo))
            }
            ForEach(masteryTiers.indices, id: \.self) { index in
                let tier = masteryTiers[index]
                Image(systemName: tier.achieved ? "diamond.fill" : "diamond")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(tier.achieved ? tier.color : Color.appInkMuted.opacity(0.5))
                    .padding(.leading, index == 0 ? 1 : 0)
                    .animation(.spring(response: 0.3, dampingFraction: 0.5), value: tier.achieved)
            }
        }
    }
}

/// The small circular +/- used by `ChallengeRow`'s inline amount nudges and
/// `WeaponDetailView`'s compact level row.
func stepButton(systemName: String, enabled: Bool, size: CGFloat, accent: Color = .accentMultiplayer, action: @escaping () -> Void) -> some View {
    Button(action: action) {
        Image(systemName: systemName)
            .font(.system(size: size * 0.42, weight: .bold))
            .foregroundStyle(Color.appBackground)
            .frame(width: size, height: size)
            .background(Circle().fill(enabled ? accent : Color.appInkMuted.opacity(0.4)))
    }
    .buttonStyle(.plain)
    .disabled(!enabled)
}

/// A circular completion meter — the one visual primitive the whole Stats
/// dashboard is built from, so a mode's ring in `StatsView` reads as the
/// same shape as the hero ring on its own tab's `StatSummaryCard`.
struct ProgressRing: View {
    let fraction: Double
    let accent: Color
    var lineWidth: CGFloat = 8
    var size: CGFloat = 64
    var showsPercentage: Bool = true
    /// The ring's stroke once `fraction` reaches (or somehow exceeds) 100% —
    /// a rotating multi-stop sweep instead of a flat stroke, the same
    /// "shimmer means earned" rule every completed camo/badge gets elsewhere
    /// in this app (see `AnimatedGradientText`). Defaults to the generic Gold
    /// trio; pass a specific camo's own `.gradient` when this ring stands for
    /// that particular tier.
    var shimmerColors: [Color] = .gold

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isComplete: Bool { fraction >= 1 }

    private func sweep(angle: Angle) -> AngularGradient {
        AngularGradient(colors: shimmerColors + [shimmerColors[0]], center: .center, angle: angle)
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.appSurface2, lineWidth: lineWidth)

            if isComplete {
                if reduceMotion {
                    Circle().stroke(sweep(angle: .zero), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                } else {
                    TimelineView(.animation) { context in
                        let t = context.date.timeIntervalSinceReferenceDate
                        let angle = Angle.degrees((t / 3.2).truncatingRemainder(dividingBy: 1) * 360)
                        Circle().stroke(sweep(angle: angle), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    }
                }
            } else {
                // `to:` never hits exactly 0 — SwiftUI can render a `trim(to: 0)`
                // stroke as a full circle on some OS versions, so a hair above
                // zero guarantees an empty-looking ring instead of a false-full one.
                Circle()
                    .trim(from: 0, to: max(0.0015, fraction))
                    .stroke(accent, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.5), value: fraction)
            }

            if showsPercentage {
                Text("\(min(Int(fraction * 100), 100))%")
                    .font(.system(size: size * 0.22, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.appInk)
                    .minimumScaleFactor(0.7)
            }
        }
        .frame(width: size, height: size)
    }
}

/// A bordered stat readout led by a hero completion ring — mirrors the
/// shipped trackers' summary header (e.g. "6/40 Gold · 1/8 Diamond"), now
/// with the overall percentage promoted to the same ring shape `StatsView`
/// uses, instead of just another number in the row.
struct StatSummaryCard: View {
    struct Stat {
        let value: String
        let label: String
        /// When set, `label` renders as a shimmering `AnimatedGradientText`
        /// instead of flat muted text — used for the Mastery-tier-1 stat, so
        /// its camo name reads the same animated way it does everywhere else
        /// that name appears.
        var labelGradient: [Color]? = nil
        /// When set, this column leads with a small percentage ring (and
        /// still shows `value`'s raw "x/y" count underneath) — how close a
        /// tier is to earned, not just the count so far.
        var ringFraction: Double? = nil
        var ringColor: Color? = nil
        /// The ring's own shimmer once it hits 100% — that tier's actual
        /// camo gradient (e.g. Mercurial Drift's pink/orange), not the
        /// generic Gold sweep `ProgressRing` defaults to. Leave `nil` for a
        /// ring that really does mean Gold.
        var ringGradient: [Color]? = nil
    }
    /// Omit both (leave `nil`) for a card with no separate leading ring —
    /// used when one of the `stats` columns (e.g. Gold) already carries its
    /// own ring and a second one would just be redundant.
    var heroFraction: Double? = nil
    var heroAccent: Color? = nil
    let stats: [Stat]
    /// Off when embedding this row inside a view that already has its own
    /// `.borderedCard()` — avoids a card nested inside a card.
    var bordered = true
    /// Padding around the row itself — override to 0 when the embedding
    /// view already provides its own outer padding, so this doesn't end up
    /// double-inset relative to that view's other content.
    var horizontalPadding: CGFloat = 12
    var verticalPadding: CGFloat = 14

    var body: some View {
        HStack(spacing: 14) {
            if let heroFraction, let heroAccent {
                ProgressRing(fraction: heroFraction, accent: heroAccent, lineWidth: 6, size: 56)

                Rectangle()
                    .fill(Color.appInkMuted.opacity(0.25))
                    .frame(width: 1, height: 34)
            }

            HStack(spacing: 0) {
                ForEach(stats.indices, id: \.self) { index in
                    VStack(spacing: 4) {
                        if let ringFraction = stats[index].ringFraction {
                            ProgressRing(
                                fraction: ringFraction,
                                accent: stats[index].ringColor ?? Color.appInk,
                                lineWidth: 4,
                                size: 40,
                                shimmerColors: stats[index].ringGradient ?? .gold
                            )
                            Text(stats[index].value)
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundStyle(Color.appInk)
                        } else {
                            Text(stats[index].value)
                                .font(.system(size: 17, weight: .bold, design: .monospaced))
                                .foregroundStyle(Color.appInk)
                        }
                        // Fixed height regardless of wrap ("Gold" vs.
                        // "Polyatomic Reforged") so every column's box stays
                        // the same size across the row instead of only the
                        // tallest label's column looking "right."
                        Group {
                            if let gradient = stats[index].labelGradient {
                                AnimatedGradientText(text: stats[index].label, colors: gradient, font: .system(size: 11))
                            } else {
                                Text(stats[index].label)
                                    .font(.system(size: 11))
                                    .foregroundStyle(Color.appInkMuted)
                            }
                        }
                        .tracking(1.0)
                        .textCase(.uppercase)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.75)
                        .frame(height: 26, alignment: .top)
                    }
                    .frame(maxWidth: .infinity)

                    if index < stats.count - 1 {
                        Rectangle()
                            .fill(Color.appInkMuted.opacity(0.25))
                            .frame(width: 1, height: 30)
                    }
                }
            }
        }
        .padding(.vertical, verticalPadding)
        .padding(.horizontal, horizontalPadding)
        .modifier(OptionalBorderedCard(bordered: bordered))
    }
}

private struct OptionalBorderedCard: ViewModifier {
    let bordered: Bool
    func body(content: Content) -> some View {
        if bordered {
            content.borderedCard()
        } else {
            content
        }
    }
}

/// A 3-node horizontal stepper for a mode's Mastery progression — replaces
/// `StatsView`'s old plain list of Mastery rows with an actual track: nodes
/// connected by a line that lights up as each tier is earned, the same
/// "chain of gates" mental model `TrackerViewModel`'s Mastery logic already
/// enforces (tier2 needs the whole category on tier1, tier3 needs the whole
/// mode on tier2).
struct MasteryTrack: View {
    /// Plain (name, color, gradient) instead of a `MasteryCamo` directly —
    /// the trailing "100%+" node (see `ModeStatsCard`) isn't a real camo at
    /// all, just a flex milestone past the official capstone, so it has no
    /// `MasteryCamo` to point at.
    struct Node {
        let name: String
        let color: Color
        let gradient: [Color]
        let achieved: Bool
        let detail: String
    }
    let nodes: [Node]

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 0) {
                ForEach(nodes.indices, id: \.self) { index in
                    nodeCircle(nodes[index])
                    if index < nodes.count - 1 {
                        Rectangle()
                            .fill(nodes[index].achieved ? nodes[index].color.opacity(0.6) : Color.appInkMuted.opacity(0.25))
                            .frame(height: 2)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            HStack(alignment: .top, spacing: 0) {
                ForEach(nodes.indices, id: \.self) { index in
                    nodeLabel(nodes[index])
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func nodeCircle(_ node: Node) -> some View {
        ZStack {
            Circle()
                .fill(node.achieved ? node.color : Color.appSurface2)
                .overlay(Circle().strokeBorder(node.color, lineWidth: node.achieved ? 0 : 1.5))
            if node.achieved {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color.appBackground)
            }
        }
        .frame(width: 20, height: 20)
    }

    private func nodeLabel(_ node: Node) -> some View {
        VStack(spacing: 2) {
            if node.achieved {
                AnimatedGradientText(text: node.name, colors: node.gradient, font: .system(size: 10.5, weight: .semibold))
            } else {
                Text(node.name)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(Color.appInk)
            }
            Text(node.detail)
                .font(.system(size: 9.5, design: .monospaced))
                .foregroundStyle(Color.appInkMuted)
        }
        .multilineTextAlignment(.center)
        .lineLimit(2)
        .minimumScaleFactor(0.85)
    }
}

/// One row, three ways to log progress — shared by camo challenges and DMZ
/// objectives so both work identically:
/// - tap the circle to instantly mark it done/not done
/// - tap +/- to nudge the amount by one (quick, tactile — matches the
///   shipped trackers' feel)
/// - tap the "N / required" pill itself to type an exact amount in one go
///   (still needed for challenges like "200 kills" — nudging one at a time
///   the whole way there would be painful)
struct ChallengeRow: View {
    let item: ChallengeItem
    let accent: Color
    let amount: Int
    let isDone: Bool
    /// Whether the *previous* tier in this chain is complete yet — mirrors
    /// the real family's cascading unlock (see `TrackerViewModel.isCamoAvailable`).
    /// A locked tier shows a lock glyph instead of a checkbox and can't be
    /// toggled or nudged, so you can't jump ahead out of order.
    var isAvailable: Bool = true
    /// Overrides the default "Finish the tier above first." locked message —
    /// used by weapon Mastery's tier2 row, which is gated by a whole
    /// category rather than the row directly above it.
    var lockedReason: String? = nil
    /// When set and `isDone`, the title shimmers through these colors
    /// instead of sitting in flat text — used by weapon Mastery rows, not
    /// the plain per-weapon camo tiers, same "shimmer means earned" rule as
    /// everywhere else this appears.
    var titleGradient: [Color]? = nil
    let onToggle: () -> Void
    let onSetAmount: (Int) -> Void

    @State private var showAmountEntry = false
    @State private var amountText = ""

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onToggle) {
                Image(systemName: isDone ? "checkmark.circle.fill" : (isAvailable ? "circle" : "lock.fill"))
                    .font(.system(size: isAvailable ? 21 : 17))
                    .foregroundStyle(isDone ? accent : Color.appInkMuted.opacity(isAvailable ? 1 : 0.5))
                    .frame(width: 21, height: 21)
            }
            .buttonStyle(.plain)
            .disabled(!isAvailable)

            if item.imageURL != nil {
                CamoThumbnail(urlString: item.imageURL, size: 34)
                    .opacity(isAvailable ? 1 : 0.4)
            }

            VStack(alignment: .leading, spacing: 4) {
                if isDone, let titleGradient {
                    AnimatedGradientText(text: item.name.resolved(), colors: titleGradient, font: .hitmarker(15))
                } else {
                    Text(item.name.resolved())
                        .font(.hitmarker(15))
                        .foregroundStyle(isAvailable ? Color.appInk : Color.appInkMuted)
                }
                if let requirement = item.requirement {
                    Text(isAvailable ? requirement.description.resolved() : (lockedReason ?? "mw4.ui.locked".localized()))
                        .font(.system(size: 13))
                        .foregroundStyle(Color.appInkMuted)
                }
            }

            Spacer(minLength: 8)

            if let requirement = item.requirement, requirement.amount > 1, isAvailable {
                HStack(spacing: 6) {
                    stepButton(systemName: "minus", enabled: amount > 0, size: 22, accent: accent) {
                        onSetAmount(max(0, amount - 1))
                    }
                    Button {
                        amountText = "\(amount)"
                        showAmountEntry = true
                    } label: {
                        Text("\(amount)/\(requirement.amount)")
                            .font(.system(size: 12.5, design: .monospaced))
                            .foregroundStyle(Color.appInkMuted)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(Color.appSurface2))
                    }
                    .buttonStyle(.plain)
                    stepButton(systemName: "plus", enabled: amount < requirement.amount, size: 22, accent: accent) {
                        onSetAmount(min(requirement.amount, amount + 1))
                    }
                }
            }
        }
        .padding(.vertical, 5)
        .alert("mw4.ui.set_amount.title".localized(), isPresented: $showAmountEntry) {
            TextField("mw4.ui.set_amount.field".localized(), text: $amountText)
                .keyboardType(.numberPad)
            Button("mw4.ui.cancel".localized(), role: .cancel) {}
            Button("mw4.ui.save".localized()) {
                if let value = Int(amountText) { onSetAmount(value) }
            }
        } message: {
            if let requirement = item.requirement {
                Text(String(format: "mw4.ui.set_amount.message".localized(), requirement.amount))
            }
        }
    }
}

/// "Acquired by: Level 9" (or "Acquired by: Default" for a weapon with no
/// level gate) — the same label+value framing everywhere a weapon's unlock
/// condition shows up, instead of dropping the raw network sentence
/// ("Unlock at level 9.") straight into the UI unlabeled.
struct AcquiredByLabel: View {
    let weapon: WeaponEntry
    var font: Font = .system(size: 12.5)
    var color: Color = .appInkMuted

    var body: some View {
        Text(text)
            .font(font)
            .foregroundStyle(color)
    }

    private var text: String {
        if let level = weapon.unlockLevel {
            String(format: "mw4.ui.acquired_by_level".localized(), level)
        } else {
            "mw4.ui.acquired_by_default".localized()
        }
    }
}

// MARK: - Filter/Sort

/// Shared sort vocabulary for every list page (categories, weapons,
/// objectives) — not every page offers every case (only `WeaponListView`
/// offers `.level`), each page just passes the subset it supports as
/// `FilterSortMenu.options`.
enum ProgressSort: String, CaseIterable, Hashable {
    case natural, alphabetical, progressDesc, progressAsc, level

    var label: String {
        switch self {
        case .natural: return "mw4.ui.sort.default".localized()
        case .alphabetical: return "mw4.ui.sort.alphabetical".localized()
        case .progressDesc: return "mw4.ui.sort.progress_desc".localized()
        case .progressAsc: return "mw4.ui.sort.progress_asc".localized()
        case .level: return "mw4.ui.sort.level".localized()
        }
    }
}

/// Shared completion-status filter — "Gold" for weapons, "every weapon in
/// the category" for categories, "every leaf" for objectives, but the same
/// three-state idea everywhere, matching the sibling BO7 Camo Tracker app's
/// own tap-to-cycle Type filter.
enum CompletionFilter: String, CaseIterable, Hashable {
    case all, incomplete, complete

    var label: String {
        switch self {
        case .all: return "mw4.ui.filter.all".localized()
        case .incomplete: return "mw4.ui.filter.incomplete".localized()
        case .complete: return "mw4.ui.filter.complete".localized()
        }
    }
}

/// A labeled control that opens the standard iOS menu of choices on tap —
/// a `Picker` inside a `Menu` gets the system's own checkmarked dropdown
/// list for free (the same furniture Files/Photos use for their Sort menus),
/// styled to match this app's bordered-capsule pills. Picking a new option
/// is a single tap from the label, not a cycle through every other option
/// first.
struct FilterSortMenu<T: Hashable>: View {
    let title: String
    let options: [T]
    let label: (T) -> String
    var accent: Color = .appInk
    @Binding var selection: T

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.0)
                .textCase(.uppercase)
                .foregroundStyle(Color.appInkMuted)
            Menu {
                Picker(title, selection: $selection) {
                    ForEach(options, id: \.self) { option in
                        Text(label(option)).tag(option)
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(label(selection))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9, weight: .bold))
                }
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(accent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(Capsule().fill(Color.appSurface2))
                .overlay(Capsule().strokeBorder(accent.opacity(0.4), lineWidth: 1))
            }
        }
    }
}

/// Centered placeholder row for when a filter leaves nothing to show.
struct FilterEmptyRow: View {
    var body: some View {
        Text("mw4.ui.filter.empty".localized())
            .font(.system(size: 13))
            .foregroundStyle(Color.appInkMuted)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
    }
}

/// A transient top banner for a Gold/Diamond crossing (see `Suggestions.swift`).
struct MilestoneBannerView: View {
    let banner: MilestoneBanner

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: banner.icon)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(banner.titleGradient.first ?? .camoGold)
            AnimatedGradientText(text: banner.title, colors: banner.titleGradient, font: .hitmarker(16))
            Text(banner.subtitle)
                .font(.system(size: 12.5))
                .foregroundStyle(Color.appInkMuted)
        }
        .foregroundStyle(Color.appInk)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.appSurface2))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(
                    LinearGradient(colors: banner.titleGradient, startPoint: .leading, endPoint: .trailing).opacity(0.6),
                    lineWidth: 1.5
                )
        )
        .padding(.horizontal, 24)
        .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
    }
}
