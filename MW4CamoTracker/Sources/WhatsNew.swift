import SwiftUI
import UserNotifications

/// What's new in this version, shown once after an update (never on a fresh
/// install: onboarding covers that) and kept in Customise. Each release lists
/// a few things, each with a button that takes the player straight to it.
///
/// To announce a release: add its items under its version in `releases`, with
/// their strings in every Localizable.strings. A version with nothing listed
/// shows nothing.
enum WhatsNew {
    struct Item: Identifiable {
        enum Action { case streamOverlay, notifications }
        let id: String
        let symbol: String
        var action: Action? = nil
        var title: String { "ct.whatsnew.\(id).title".localized() }
        var body: String { "ct.whatsnew.\(id).body".localized() }
    }

    static let releases: [String: [Item]] = [
        "1.0.5": [
            Item(id: "overlay", symbol: "dot.radiowaves.left.and.right", action: .streamOverlay),
            Item(id: "push", symbol: "bell.badge.fill", action: .notifications),
            Item(id: "modes", symbol: "square.stack.3d.up.fill"),
        ],
    ]

    static let seenKey = "ct_whats_new_seen"

    static var version: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "" }

    /// This version's items, or none.
    static var items: [Item] { releases[version] ?? [] }

    /// After an update, for someone who'd already been through onboarding.
    static func shouldShow(hasOnboarded: Bool, defaults: UserDefaults = .standard, version: String = WhatsNew.version) -> Bool {
        hasOnboarded && !(releases[version] ?? []).isEmpty && defaults.string(forKey: seenKey) != version
    }

    /// Seen (or nothing to see: a fresh install, which starts on this version).
    static func markSeen(defaults: UserDefaults = .standard, version: String = WhatsNew.version) {
        defaults.set(version, forKey: seenKey)
    }
}

struct WhatsNewSheet: View {
    let accent: Color
    @EnvironmentObject private var viewModel: TrackerViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var notifications: UNAuthorizationStatus = .notDetermined

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(String(format: "ct.whatsnew.heading".localized(), WhatsNew.version))
                        .hitmarkerFont(28)
                        .foregroundStyle(Color.appInk)
                        .padding(.bottom, 4)
                    ForEach(WhatsNew.items) { item in
                        card(item)
                    }
                }
                .padding(20)
            }
            .background(Color.appBackground.ignoresSafeArea())
            .safeAreaInset(edge: .bottom) {
                Button {
                    dismiss()
                } label: {
                    Text("ct.whatsnew.continue".localized())
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .foregroundStyle(Color.black)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
                .accessibilityIdentifier("whatsnew.continue")
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .task { notifications = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus }
        .onAppear { WhatsNew.markSeen() }
    }

    private func card(_ item: WhatsNew.Item) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: item.symbol)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(accent)
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(.headline)
                        .foregroundStyle(Color.appInk)
                    Text(item.body)
                        .font(.subheadline)
                        .foregroundStyle(Color.appInkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let action = item.action {
                actionButton(action)
                    .padding(.leading, 42)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.appSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder
    private func actionButton(_ action: WhatsNew.Item.Action) -> some View {
        switch action {
        case .streamOverlay:
            NavigationLink {
                StreamOverlayView(accent: accent).environmentObject(viewModel)
            } label: {
                Label("ct.whatsnew.overlay.action".localized(), systemImage: "arrow.right")
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(accent)
        case .notifications:
            switch notifications {
            case .authorized, .provisional, .ephemeral:
                Label("ct.whatsnew.push.on".localized(), systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.appInkMuted)
            case .denied:
                // iOS won't ask twice: Settings is the only way back
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                } label: {
                    Label("ct.whatsnew.push.settings".localized(), systemImage: "gear")
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(accent)
            default:
                Button {
                    Task {
                        let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])) ?? false
                        if granted { await PushRegistration.register() }
                        notifications = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
                    }
                } label: {
                    Label("ct.whatsnew.push.action".localized(), systemImage: "bell")
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(accent)
            }
        }
    }
}
