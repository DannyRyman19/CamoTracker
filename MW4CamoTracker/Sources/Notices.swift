import SwiftUI

/// A card at the top of the mode tabs that is written, switched on and
/// switched off from the repo, with no app update: `Data/CT/notices.json`
/// (see CONTENT.md, "Notices"; `Tools/notices.py` checks and switches them).
///
///     { "notices": [ {
///         "id": "android-testers",
///         "enabled": true,
///         "title":  { "en": "Know someone on Android?" },
///         "body":   { "en": "Camo Track needs testers on Google Play." },
///         "button": { "en": "Send the invite" },
///         "url": "https://camo-track.app/android",
///         "action": "share",
///         "shareText": { "en": "Help test Camo Track on Android:" },
///         "icon": "person.2.fill",
///         "from": "2026-11-26", "until": "2026-12-31"
///     } ] }
///
/// Only `id` and `title` are needed. The first notice that is on, in its
/// dates and not yet closed by the player is the one shown. Closing is
/// remembered by `id`, so a new `id` asks everyone again.
struct AppNotice: Decodable, Identifiable {
    let id: String
    /// false switches it off; left out counts as on
    let enabled: Bool?
    let title: LocalizedText
    let body: LocalizedText?
    /// The button's words; without them a share says "Share" and a link has no button
    let button: LocalizedText?
    /// Where the button goes (https only). Without it the card is words alone.
    let url: String?
    /// "share" hands `url` (and `shareText`) to the share sheet; anything else opens it
    let action: String?
    let shareText: LocalizedText?
    /// An SF Symbol name
    let icon: String?
    /// First and last day shown (yyyy-MM-dd, UTC, both inclusive)
    let from: String?
    let until: String?

    var link: URL? {
        guard let url, let parsed = URL(string: url), parsed.scheme == "https", parsed.host != nil else { return nil }
        return parsed
    }

    var shares: Bool { action == "share" }

    /// On, with words to show, and today within `from`...`until`. A date that
    /// isn't yyyy-MM-dd hides the notice: better unseen than shown past its day.
    func isLive(on date: Date = Date()) -> Bool {
        guard enabled != false, !id.isEmpty, !title.resolved().isEmpty else { return false }
        let today = ChallengeItem.dayFormatter.string(from: date)
        for day in [from, until].compactMap({ $0 }) where ChallengeItem.dayFormatter.date(from: day) == nil || day.count != 10 {
            return false
        }
        if let from, today < from { return false }
        if let until, today > until { return false }
        return true
    }

    static func current(in notices: [AppNotice], dismissed: Set<String>, on date: Date = Date()) -> AppNotice? {
        notices.first { $0.isLive(on: date) && !dismissed.contains($0.id) }
    }
}

/// The file itself. A notice that doesn't decode is left out, not the rest.
struct NoticeFile: Decodable {
    let notices: [AppNotice]

    private enum CodingKeys: String, CodingKey { case notices }
    private struct Anything: Decodable {
        init(from decoder: Decoder) throws {}
    }

    init(from decoder: Decoder) throws {
        var list = try decoder.container(keyedBy: CodingKeys.self).nestedUnkeyedContainer(forKey: .notices)
        var found: [AppNotice] = []
        while !list.isAtEnd {
            let index = list.currentIndex
            if let notice = try? list.decode(AppNotice.self) {
                found.append(notice)
            } else {
                _ = try? list.decode(Anything.self)
            }
            // Neither moved on: stop, not loop
            if list.currentIndex == index { break }
        }
        notices = found
    }
}

/// Fetches the notices when the app opens or comes back, keeps the last copy
/// for a launch with no signal, and remembers which ones the player closed.
@MainActor
final class NoticeStore: ObservableObject {
    static let shared = NoticeStore()
    static let dismissedKey = "ct_notices_dismissed"
    private static let path = "Data/CT/notices.json"
    /// jsDelivr first, GitHub when it fails, as `DataService` does
    private static let sources = [
        URL(string: "https://cdn.jsdelivr.net/gh/DannyRyman19/CamoTracker@master/")!,
        URL(string: "https://raw.githubusercontent.com/DannyRyman19/CamoTracker/master/")!
    ].map { $0.appendingPathComponent(path) }

    @Published private(set) var notices: [AppNotice] = []
    @Published private(set) var dismissed: Set<String>
    private let defaults: UserDefaults
    private let cacheURL: URL
    private let session: URLSession

    init(defaults: UserDefaults = .standard, cacheDir: URL? = nil, session: URLSession = .shared) {
        self.defaults = defaults
        self.session = session
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = cacheDir ?? support.appendingPathComponent("CamoTracker", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        cacheURL = dir.appendingPathComponent("notices.json")
        dismissed = Set(defaults.stringArray(forKey: Self.dismissedKey) ?? [])
        if let data = Self.debugFile ?? (try? Data(contentsOf: cacheURL)) {
            notices = (try? JSONDecoder().decode(NoticeFile.self, from: data))?.notices ?? []
        }
    }

    var current: AppNotice? { AppNotice.current(in: notices, dismissed: dismissed) }

    func dismiss(_ notice: AppNotice) {
        dismissed.insert(notice.id)
        defaults.set(dismissed.sorted(), forKey: Self.dismissedKey)
    }

    /// A file that can't be fetched or read changes nothing: the last good
    /// copy stays, so a typo in the repo doesn't blank a running notice.
    func refresh() async {
        #if DEBUG
        let environment = ProcessInfo.processInfo.environment
        if Self.debugFile != nil || environment["MW4_OFFLINE"] != nil || environment["SS_SCREEN"] != nil { return }
        #endif
        for source in Self.sources {
            var request = URLRequest(url: source)
            // jsDelivr's week-long max-age would otherwise hide a switch-off
            request.cachePolicy = .reloadIgnoringLocalCacheData
            guard let (data, response) = try? await session.data(for: request),
                  (response as? HTTPURLResponse).map({ (200...299).contains($0.statusCode) }) ?? true,
                  let file = try? JSONDecoder().decode(NoticeFile.self, from: data) else { continue }
            notices = file.notices
            try? data.write(to: cacheURL, options: .atomic)
            return
        }
    }

    /// DEBUG: `CT_NOTICES='{"notices":[…]}'` shows that file instead of the
    /// published one (for the simulator and screenshots).
    private static var debugFile: Data? {
        #if DEBUG
        ProcessInfo.processInfo.environment["CT_NOTICES"]?.data(using: .utf8)
        #else
        nil
        #endif
    }
}

/// The notice card: words, an optional button (share or open a link) and a
/// close button. Nothing at all when no notice is running.
struct NoticeCard: View {
    let accent: Color
    @ObservedObject private var store = NoticeStore.shared
    @Environment(\.openURL) private var openURL

    var body: some View {
        if let notice = store.current {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: symbol(notice.icon))
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(accent)
                        .frame(width: 28)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(notice.title.resolved())
                            .hitmarkerFont(16)
                            .foregroundStyle(Color.appInk)
                            .fixedSize(horizontal: false, vertical: true)
                        if let body = notice.body?.resolved(), !body.isEmpty {
                            Text(body)
                                .scaledFont(13.5)
                                .foregroundStyle(Color.appInkMuted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 0)
                    Button {
                        withAnimation(.snappy) { store.dismiss(notice) }
                        Haptics.light()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Color.appInkMuted)
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("ct.notice.hide".localized())
                    .accessibilityIdentifier("noticeHide")
                }
                if let link = notice.link {
                    let words = notice.button?.resolved() ?? ""
                    if notice.shares {
                        ShareLink(item: link, message: Text(notice.shareText?.resolved() ?? "")) {
                            buttonLabel(words.isEmpty ? "mw4.ui.share.button".localized() : words, symbol: "square.and.arrow.up")
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("noticeButton")
                    } else if !words.isEmpty {
                        Button { openURL(link) } label: { buttonLabel(words, symbol: "arrow.up.forward") }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("noticeButton")
                    }
                }
            }
            .padding(14)
            .borderedCard(accent: accent)
            .accessibilityIdentifier("notice")
        }
    }

    private func buttonLabel(_ words: String, symbol: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .bold))
            Text(words)
                .scaledFont(14.5, weight: .semibold)
        }
        .foregroundStyle(Color.appBackground)
        .frame(maxWidth: .infinity, minHeight: 44)
        .background(accent, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .contentShape(Rectangle())
    }

    /// The notice's own symbol when the system has it
    private func symbol(_ name: String?) -> String {
        if let name, UIImage(systemName: name) != nil { return name }
        return "megaphone.fill"
    }
}
