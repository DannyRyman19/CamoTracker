import SwiftUI
import WidgetKit

// The widgets' faces, shared by the widget extension and the app: the app
// draws them for the "Add a widget" guide and the App Store screenshot. The
// size class is passed in rather than read from the environment, which only
// a widget has.

struct PinnedWeaponView: View {
    let snapshot: WidgetSnapshot?
    let family: WidgetFamily

    var body: some View {
        if let pinned = snapshot?.pinned {
            content(pinned)
                .widgetURL(WidgetSnapshot.link(mode: pinned.mode, weaponId: pinned.weaponId))
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: "pin.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Color.widgetAccent)
                Text(snapshot?.pinPrompt ?? String(localized: "widget.pin_prompt"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func content(_ pinned: WidgetSnapshot.Pinned) -> some View {
        let accent = Color(widgetHex: pinned.accentHex) ?? .widgetAccent
        if family == .systemMedium {
            HStack(spacing: 14) {
                WidgetRing(fraction: pinned.camosTotal > 0 ? Double(pinned.camosDone) / Double(pinned.camosTotal) : 0,
                     color: accent, lineWidth: 8) {
                    VStack(spacing: 0) {
                        Text("\(pinned.camosDone)")
                            .font(.system(size: 22, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                        Text("/\(pinned.camosTotal)")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
                .frame(width: 84, height: 84)
                details(pinned, accent: accent)
            }
        } else {
            details(pinned, accent: accent)
        }
    }

    private func details(_ pinned: WidgetSnapshot.Pinned, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(pinned.modeName.uppercased())
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(accent)
            Text(pinned.name)
                .font(.system(size: family == .systemMedium ? 19 : 17, weight: .heavy))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 2)
            if let next = pinned.nextName {
                Text(next)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)
                if let detail = pinned.nextDetail, family == .systemMedium {
                    Text(detail)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(2)
                }
                if pinned.nextTotal > 1 {
                    WidgetBar(fraction: Double(pinned.nextDone) / Double(pinned.nextTotal), color: accent)
                    Text("\(pinned.nextDone)/\(pinned.nextTotal)")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.6))
                }
            } else {
                Text(snapshot?.allDoneLabel ?? "")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(accent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ModeProgressView: View {
    let snapshot: WidgetSnapshot?
    let modeID: String
    let family: WidgetFamily

    var body: some View {
        // A mode the player has switched off in the app isn't in the
        // snapshot; show the first one they do play instead.
        if let mode = snapshot?.modes.first(where: { $0.id == modeID }) ?? snapshot?.modes.first {
            content(mode).widgetURL(WidgetSnapshot.link(mode: mode.id))
        } else {
            Text("widget.open_app")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.8))
        }
    }

    @ViewBuilder
    private func content(_ mode: WidgetSnapshot.Mode) -> some View {
        let accent = Color(widgetHex: mode.accentHex) ?? .widgetAccent
        let ring = WidgetRing(fraction: mode.fraction, color: accent, lineWidth: family == .systemSmall ? 7 : 8) {
            Text(mode.fraction, format: .percent.precision(.fractionLength(0)))
                .font(.system(size: family == .systemSmall ? 16 : 18, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
        }
        if family == .systemMedium {
            HStack(spacing: 16) {
                VStack(spacing: 6) {
                    ring.frame(width: 80, height: 80)
                    Text(mode.name.uppercased())
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(accent)
                        .lineLimit(1)
                }
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(Array(mode.steps.enumerated()), id: \.offset) { _, step in
                        StepRow(step: step)
                    }
                    MasteryPips(steps: mode.mastery, label: snapshot?.masteryLabel)
                        .padding(.top, 2)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(mode.name.uppercased())
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(accent)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                HStack(spacing: 10) {
                    ring.frame(width: 58, height: 58)
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(Array(mode.steps.prefix(3).enumerated()), id: \.offset) { _, step in
                            HStack(spacing: 4) {
                                Circle().fill(Color(widgetHex: step.colorHex) ?? .white).frame(width: 6, height: 6)
                                Text("\(step.done)/\(step.total)")
                                    .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                            }
                        }
                    }
                }
                Spacer(minLength: 0)
                MasteryPips(steps: mode.mastery, label: snapshot?.masteryLabel, compact: true)
            }
        }
    }
}

private struct StepRow: View {
    let step: WidgetSnapshot.Step

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(Color(widgetHex: step.colorHex) ?? .white).frame(width: 7, height: 7)
            Text(step.name)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
            Spacer(minLength: 4)
            Text("\(step.done)/\(step.total)")
                .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
        }
    }
}

/// The mode's three Mastery camos under a "Mastery" label: a bar each in
/// the camo's colour, filling as its challenge counts up (250 kills, say)
/// and solid once earned.
private struct MasteryPips: View {
    let steps: [WidgetSnapshot.Step]
    var label: String?
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let label {
                Text(label.uppercased())
                    .font(.system(size: compact ? 8.5 : 9, weight: .heavy))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
            }
            HStack(spacing: 4) {
                ForEach(Array(steps.enumerated()), id: \.offset) { _, step in
                    let color = Color(widgetHex: step.colorHex) ?? .white
                    let fraction = step.total > 0 ? min(Double(step.done) / Double(step.total), 1) : 0
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(color.opacity(0.22))
                            Capsule().fill(color).frame(width: proxy.size.width * fraction)
                        }
                    }
                    .frame(height: compact ? 5 : 6)
                    .overlay(Capsule().strokeBorder(color.opacity(0.6), lineWidth: fraction >= 1 ? 0 : 1))
                    .accessibilityLabel("\(step.name) \(step.done)/\(step.total)")
                }
            }
        }
    }
}

struct CompletionView: View {
    let snapshot: WidgetSnapshot?
    let family: WidgetFamily

    private var overall: Double { snapshot?.overall ?? 0 }

    var body: some View {
        switch family {
        case .accessoryCircular:
            Gauge(value: overall) {
                Image(systemName: "scope")
            } currentValueLabel: {
                Text(overall, format: .percent.precision(.fractionLength(0)))
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .widgetAccentable()
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text(snapshot?.overallLabel ?? String(localized: "widget.completion.name"))
                    .font(.system(size: 12, weight: .bold))
                    .widgetAccentable()
                    .lineLimit(1)
                ForEach(snapshot?.modes ?? []) { mode in
                    HStack(spacing: 4) {
                        Text(mode.name)
                            .lineLimit(1)
                        Spacer(minLength: 2)
                        Text(mode.fraction, format: .percent.precision(.fractionLength(0)))
                            .monospacedDigit()
                    }
                    .font(.system(size: 12))
                }
            }
        default:
            VStack(spacing: 8) {
                WidgetRing(fraction: overall, color: .widgetGold, lineWidth: 9) {
                    Text(overall, format: .percent.precision(.fractionLength(0)))
                        .font(.system(size: 22, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                }
                .frame(width: 92, height: 92)
                Text((snapshot?.overallLabel ?? "").uppercased())
                    .font(.system(size: 9.5, weight: .heavy))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
    }
}

// MARK: - Pieces

struct WidgetRing<Label: View>: View {
    let fraction: Double
    let color: Color
    var lineWidth: CGFloat = 8
    @ViewBuilder let label: () -> Label

    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.12), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0, min(fraction, 1)))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            label()
        }
        .padding(lineWidth / 2)
    }
}

struct WidgetBar: View {
    let fraction: Double
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.14))
                Capsule().fill(color).frame(width: proxy.size.width * max(0, min(fraction, 1)))
            }
        }
        .frame(height: 5)
    }
}

extension Color {
    static let widgetBackground = Color(red: 0.07, green: 0.07, blue: 0.08)
    static let widgetAccent = Color(red: 0.76, green: 0.11, blue: 0.03)
    static let widgetGold = Color(red: 0.831, green: 0.686, blue: 0.216)

    init?(widgetHex hex: String) {
        let digits = hex.replacingOccurrences(of: "#", with: "")
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        self.init(red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255,
                  blue: Double(value & 0xFF) / 255)
    }
}

extension WidgetSnapshot {
    /// The widget gallery's sample, before the app has written anything.
    static let preview: WidgetSnapshot = {
        let gold = "#D4AF37", platinum = "#C7D1DB", harmonic = "#5CC7DB", divergence = "#B04FE8"
        let mode = Mode(id: "multiplayer", name: "Multiplayer", accentHex: "#C11D07", fraction: 0.42, weaponCount: 33,
                        steps: [Step(name: "Gold", done: 18, total: 33, colorHex: gold),
                                Step(name: "Platinum", done: 9, total: 33, colorHex: platinum),
                                Step(name: "Harmonic Break", done: 3, total: 33, colorHex: harmonic),
                                Step(name: "Divergence", done: 0, total: 33, colorHex: divergence)],
                        mastery: [Step(name: "Mercurial Drift", done: 0, total: 1, colorHex: "#E0457B"),
                                  Step(name: "Polyatomic Reforged", done: 0, total: 250, colorHex: "#5A5AE6"),
                                  Step(name: "Orion Reforged", done: 0, total: 250, colorHex: "#C11D07")])
        let pinned = Pinned(weaponId: 0, name: "HAN 86", category: "Assault Rifles", mode: "multiplayer",
                            modeName: "Multiplayer", accentHex: "#C11D07", camosDone: 9, camosTotal: 11,
                            nextName: "Stormwave", nextDetail: "Get 40 headshot kills against players.",
                            nextDone: 26, nextTotal: 40)
        return WidgetSnapshot(modes: [mode], pinned: pinned, overall: 0.42, overallLabel: "Overall Completion",
                              pinPrompt: "", allDoneLabel: "", masteryLabel: "Mastery")
    }()
}
