import SwiftUI
import WidgetKit

/// The one-time "Add a widget" card at the top of the mode tabs, until it's
/// opened or closed. Widgets need iOS 17, so older systems never see it.
struct WidgetTipCard: View {
    let accent: Color
    static let dismissedKey = "mw4_widget_tip_dismissed"
    @AppStorage(WidgetTipCard.dismissedKey) private var dismissed = false
    @State private var showGuide = false

    var body: some View {
        if #available(iOS 17, *), !dismissed {
            Button {
                showGuide = true
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "square.grid.2x2.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(accent)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("mw4.widget.tip.title".localized())
                            .font(.hitmarker(16))
                            .foregroundStyle(Color.appInk)
                        Text("mw4.widget.tip.body".localized())
                            .font(.system(size: 13.5))
                            .foregroundStyle(Color.appInkMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    Button {
                        withAnimation(.snappy) { dismissed = true }
                        Haptics.light()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Color.appInkMuted)
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("mw4.ui.done".localized())
                }
                .padding(14)
                .borderedCard(accent: accent)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("widgetTip")
            .sheet(isPresented: $showGuide, onDismiss: { dismissed = true }) {
                WidgetGuideSheet(accent: accent)
            }
        }
    }
}

/// How to add the widgets, over the widgets themselves showing the player's
/// own progress.
struct WidgetGuideSheet: View {
    let accent: Color
    @EnvironmentObject private var viewModel: TrackerViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    WidgetShowcase(snapshot: viewModel.widgetSnapshot() ?? .preview, scale: 0.92)
                        .frame(maxWidth: .infinity)
                    VStack(alignment: .leading, spacing: 12) {
                        step(1, "mw4.widget.guide.step1".localized())
                        step(2, "mw4.widget.guide.step2".localized())
                        step(3, "mw4.widget.guide.step3".localized())
                    }
                    .padding(14)
                    .borderedCard()
                    Text("mw4.widget.guide.mode_hint".localized() + " " + "mw4.widget.guide.lock".localized())
                        .font(.system(size: 13))
                        .foregroundStyle(Color.appInkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(16)
            }
            .background(AppBackground(accent: accent))
            .navigationTitle("mw4.widget.guide.title".localized())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("mw4.ui.done".localized()) { dismiss() }
                        .foregroundStyle(accent)
                }
            }
        }
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.appBackground)
                .frame(width: 22, height: 22)
                .background(Circle().fill(accent))
            Text(text)
                .font(.system(size: 14.5))
                .foregroundStyle(Color.appInk)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// The widgets laid out as they sit on a Home Screen: Pinned weapon and Mode
/// progress at medium size, then a small Mode progress beside the
/// Completion ring. Used by the guide and the App Store screenshot.
struct WidgetShowcase: View {
    let snapshot: WidgetSnapshot
    /// 1 is an iPhone Pro Max's widget size (medium 364 x 170 pt).
    var scale: CGFloat = 1

    private var small: CGFloat { 170 * scale }
    private var medium: CGFloat { 364 * scale }
    private var gap: CGFloat { 24 * scale }
    private var modeID: String { snapshot.modes.first?.id ?? "multiplayer" }

    var body: some View {
        VStack(spacing: gap) {
            tile(width: medium) { PinnedWeaponView(snapshot: snapshot, family: .systemMedium) }
            tile(width: medium) { ModeProgressView(snapshot: snapshot, modeID: modeID, family: .systemMedium) }
            HStack(spacing: gap) {
                tile(width: small) {
                    ModeProgressView(snapshot: snapshot, modeID: snapshot.modes.dropFirst().first?.id ?? modeID,
                                     family: .systemSmall)
                }
                tile(width: small) { CompletionView(snapshot: snapshot, family: .systemSmall) }
            }
        }
    }

    private func tile<Content: View>(width: CGFloat, @ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(16 * scale)
            .frame(width: width, height: small)
            .background(RoundedRectangle(cornerRadius: 24 * scale, style: .continuous).fill(Color.widgetBackground))
            .overlay(RoundedRectangle(cornerRadius: 24 * scale, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
            .shadow(color: .black.opacity(0.35), radius: 14 * scale, y: 6 * scale)
            .environment(\.colorScheme, .dark)
    }
}

#if DEBUG
/// `SS_SCREEN=widgets`: the widgets on their own, for the App Store shot.
struct WidgetScreenshotView: View {
    @EnvironmentObject private var viewModel: TrackerViewModel

    var body: some View {
        ZStack {
            AppBackground(accent: .accentMultiplayer)
            if let snapshot = viewModel.widgetSnapshot() {
                WidgetShowcase(snapshot: snapshot)
            }
        }
        .ignoresSafeArea()
    }
}
#endif
