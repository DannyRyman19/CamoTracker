import AppIntents
import SwiftUI
import WidgetKit

// The app writes `WidgetSnapshot` into the App Group whenever progress
// changes and asks for a reload, so every timeline here is a single entry
// that waits for the next reload rather than refreshing on a clock.

@main
struct MW4Widgets: WidgetBundle {
    var body: some Widget {
        PinnedWeaponWidget()
        ModeProgressWidget()
        CompletionWidget()
    }
}

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
    /// The mode picked when editing the Mode progress widget.
    var mode: String? = nil
}

private func currentSnapshot(preview: Bool) -> WidgetSnapshot? {
    WidgetSnapshot.load() ?? (preview ? .preview : nil)
}

// MARK: - Pinned weapon

struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry { SnapshotEntry(date: .now, snapshot: .preview) }
    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(SnapshotEntry(date: .now, snapshot: currentSnapshot(preview: context.isPreview)))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        completion(Timeline(entries: [SnapshotEntry(date: .now, snapshot: currentSnapshot(preview: false))], policy: .never))
    }
}

struct PinnedWeaponWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "PinnedWeapon", provider: SnapshotProvider()) { entry in
            PinnedWeaponView(snapshot: entry.snapshot)
                .containerBackground(Color.widgetBackground, for: .widget)
        }
        .configurationDisplayName(Text("widget.pinned.name"))
        .description(Text("widget.pinned.description"))
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct PinnedWeaponView: View {
    let snapshot: WidgetSnapshot?
    @Environment(\.widgetFamily) private var family

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
        let accent = Color(hex: pinned.accentHex) ?? .widgetAccent
        if family == .systemMedium {
            HStack(spacing: 14) {
                Ring(fraction: pinned.camosTotal > 0 ? Double(pinned.camosDone) / Double(pinned.camosTotal) : 0,
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
                    Bar(fraction: Double(pinned.nextDone) / Double(pinned.nextTotal), color: accent)
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

// MARK: - Mode progress (the mode is picked when editing the widget)

enum ModeChoice: String, AppEnum {
    case multiplayer, warzone, dmz

    static var typeDisplayRepresentation: TypeDisplayRepresentation { TypeDisplayRepresentation(name: "widget.mode") }
    static var caseDisplayRepresentations: [ModeChoice: DisplayRepresentation] {
        [.multiplayer: DisplayRepresentation(title: "widget.mode.multiplayer"),
         .warzone: DisplayRepresentation(title: "widget.mode.warzone"),
         .dmz: DisplayRepresentation(title: "widget.mode.dmz")]
    }
}

struct ModeIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "widget.mode" }
    @Parameter(title: "widget.mode", default: .multiplayer)
    var mode: ModeChoice
}

struct ModeProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: .now, snapshot: .preview, mode: ModeChoice.multiplayer.rawValue)
    }
    func snapshot(for configuration: ModeIntent, in context: Context) async -> SnapshotEntry {
        SnapshotEntry(date: .now, snapshot: currentSnapshot(preview: context.isPreview), mode: configuration.mode.rawValue)
    }
    func timeline(for configuration: ModeIntent, in context: Context) async -> Timeline<SnapshotEntry> {
        Timeline(entries: [SnapshotEntry(date: .now, snapshot: currentSnapshot(preview: false), mode: configuration.mode.rawValue)],
                 policy: .never)
    }
}

struct ModeProgressWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "ModeProgress", intent: ModeIntent.self, provider: ModeProvider()) { entry in
            ModeProgressView(snapshot: entry.snapshot, modeID: entry.mode ?? "multiplayer")
                .containerBackground(Color.widgetBackground, for: .widget)
        }
        .configurationDisplayName(Text("widget.mode_progress.name"))
        .description(Text("widget.mode_progress.description"))
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct ModeProgressView: View {
    let snapshot: WidgetSnapshot?
    let modeID: String
    @Environment(\.widgetFamily) private var family

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
        let accent = Color(hex: mode.accentHex) ?? .widgetAccent
        let ring = Ring(fraction: mode.fraction, color: accent, lineWidth: family == .systemSmall ? 7 : 8) {
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
                    MasteryPips(steps: mode.mastery)
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
                                Circle().fill(Color(hex: step.colorHex) ?? .white).frame(width: 6, height: 6)
                                Text("\(step.done)")
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundStyle(.white)
                            }
                        }
                    }
                }
                Spacer(minLength: 0)
                MasteryPips(steps: mode.mastery, compact: true)
            }
        }
    }
}

private struct StepRow: View {
    let step: WidgetSnapshot.Step

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(Color(hex: step.colorHex) ?? .white).frame(width: 7, height: 7)
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

/// The three Mastery camos as pips, filled once earned.
private struct MasteryPips: View {
    let steps: [WidgetSnapshot.Step]
    var compact = false

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(steps.enumerated()), id: \.offset) { _, step in
                let color = Color(hex: step.colorHex) ?? .white
                let earned = step.total > 0 && step.done >= step.total
                Capsule()
                    .fill(earned ? color : color.opacity(0.22))
                    .frame(height: compact ? 5 : 6)
                    .overlay(Capsule().strokeBorder(color.opacity(0.6), lineWidth: earned ? 0 : 1))
            }
        }
    }
}

// MARK: - Completion (lock screen and small)

struct CompletionWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Completion", provider: SnapshotProvider()) { entry in
            CompletionView(snapshot: entry.snapshot)
                .containerBackground(Color.widgetBackground, for: .widget)
        }
        .configurationDisplayName(Text("widget.completion.name"))
        .description(Text("widget.completion.description"))
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .systemSmall])
    }
}

struct CompletionView: View {
    let snapshot: WidgetSnapshot?
    @Environment(\.widgetFamily) private var family

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
                Ring(fraction: overall, color: .camoGold, lineWidth: 9) {
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

struct Ring<Label: View>: View {
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

struct Bar: View {
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
    static let camoGold = Color(red: 0.831, green: 0.686, blue: 0.216)

    init?(hex: String) {
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
                              pinPrompt: "", allDoneLabel: "")
    }()
}
