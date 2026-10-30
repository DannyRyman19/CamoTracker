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

/// The snapshot of the game a widget is set to: the one open in the app
/// (the default), or one game's own.
private func widgetSnapshot(game: GameChoice, preview: Bool) -> WidgetSnapshot? {
    WidgetSnapshot.load(game: game == .current ? nil : game.rawValue) ?? (preview ? .preview : nil)
}

// MARK: - Game (every widget can follow one game)

enum GameChoice: String, AppEnum {
    case current, mw4, bo7, bo6

    static var typeDisplayRepresentation: TypeDisplayRepresentation { TypeDisplayRepresentation(name: "widget.game") }
    static var caseDisplayRepresentations: [GameChoice: DisplayRepresentation] {
        [.current: DisplayRepresentation(title: "widget.game.current"),
         .mw4: DisplayRepresentation(title: "widget.game.mw4"),
         .bo7: DisplayRepresentation(title: "widget.game.bo7"),
         .bo6: DisplayRepresentation(title: "widget.game.bo6")]
    }
}

struct GameIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "widget.game" }
    @Parameter(title: "widget.game", default: .current)
    var game: GameChoice
}

struct GameProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry { SnapshotEntry(date: .now, snapshot: .preview) }
    func snapshot(for configuration: GameIntent, in context: Context) async -> SnapshotEntry {
        SnapshotEntry(date: .now, snapshot: widgetSnapshot(game: configuration.game, preview: context.isPreview))
    }
    func timeline(for configuration: GameIntent, in context: Context) async -> Timeline<SnapshotEntry> {
        Timeline(entries: [SnapshotEntry(date: .now, snapshot: widgetSnapshot(game: configuration.game, preview: false))],
                 policy: .never)
    }
}

// MARK: - Pinned weapon

struct PinnedWeaponWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "PinnedWeapon", intent: GameIntent.self, provider: GameProvider()) { entry in
            PinnedWeaponFace(snapshot: entry.snapshot)
                .containerBackground(Color.widgetBackground, for: .widget)
        }
        .configurationDisplayName(Text("widget.pinned.name"))
        .description(Text("widget.pinned.description"))
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Mode progress (the mode is picked when editing the widget)

enum ModeChoice: String, AppEnum {
    case multiplayer, warzone, dmz, zombies, campaign

    static var typeDisplayRepresentation: TypeDisplayRepresentation { TypeDisplayRepresentation(name: "widget.mode") }
    static var caseDisplayRepresentations: [ModeChoice: DisplayRepresentation] {
        [.multiplayer: DisplayRepresentation(title: "widget.mode.multiplayer"),
         .warzone: DisplayRepresentation(title: "widget.mode.warzone"),
         .dmz: DisplayRepresentation(title: "widget.mode.dmz"),
         .zombies: DisplayRepresentation(title: "widget.mode.zombies"),
         .campaign: DisplayRepresentation(title: "widget.mode.campaign")]
    }
}

struct ModeIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "widget.mode" }
    @Parameter(title: "widget.mode", default: .multiplayer)
    var mode: ModeChoice
    @Parameter(title: "widget.game", default: .current)
    var game: GameChoice
}

struct ModeProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: .now, snapshot: .preview, mode: ModeChoice.multiplayer.rawValue)
    }
    func snapshot(for configuration: ModeIntent, in context: Context) async -> SnapshotEntry {
        SnapshotEntry(date: .now, snapshot: widgetSnapshot(game: configuration.game, preview: context.isPreview), mode: configuration.mode.rawValue)
    }
    func timeline(for configuration: ModeIntent, in context: Context) async -> Timeline<SnapshotEntry> {
        Timeline(entries: [SnapshotEntry(date: .now, snapshot: widgetSnapshot(game: configuration.game, preview: false), mode: configuration.mode.rawValue)],
                 policy: .never)
    }
}

struct ModeProgressWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "ModeProgress", intent: ModeIntent.self, provider: ModeProvider()) { entry in
            ModeProgressFace(snapshot: entry.snapshot, modeID: entry.mode ?? "multiplayer")
                .containerBackground(Color.widgetBackground, for: .widget)
        }
        .configurationDisplayName(Text("widget.mode_progress.name"))
        .description(Text("widget.mode_progress.description"))
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Completion (lock screen and small)

struct CompletionWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "Completion", intent: GameIntent.self, provider: GameProvider()) { entry in
            CompletionFace(snapshot: entry.snapshot)
                .containerBackground(Color.widgetBackground, for: .widget)
        }
        .configurationDisplayName(Text("widget.completion.name"))
        .description(Text("widget.completion.description"))
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .systemSmall])
    }
}

// MARK: - Faces, reading the size from the widget environment

struct PinnedWeaponFace: View {
    let snapshot: WidgetSnapshot?
    @Environment(\.widgetFamily) private var family
    var body: some View { PinnedWeaponView(snapshot: snapshot, family: family) }
}

struct ModeProgressFace: View {
    let snapshot: WidgetSnapshot?
    let modeID: String
    @Environment(\.widgetFamily) private var family
    var body: some View { ModeProgressView(snapshot: snapshot, modeID: modeID, family: family) }
}

struct CompletionFace: View {
    let snapshot: WidgetSnapshot?
    @Environment(\.widgetFamily) private var family
    var body: some View { CompletionView(snapshot: snapshot, family: family) }
}
