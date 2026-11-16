import Foundation
import SwiftUI

/// What the stream overlay page shows, as the Worker (Backend/overlay)
/// accepts it: one game's mode at a glance, or one weapon's camos. Built the
/// same way for every game the app tracks, from the same figures as the
/// widgets.
struct CamoOverlayPayload: Codable, Equatable {
    struct Step: Codable, Equatable {
        var name: String
        var done: Int
        var total: Int
        var color: String
    }
    struct Overview: Codable, Equatable {
        var fraction: Double
        var weaponCount: Int
        var steps: [Step]
        var mastery: [Step]
    }
    struct Camo: Codable, Equatable {
        var name: String
        var image: String
        var done: Bool
    }
    struct Next: Codable, Equatable {
        var name: String
        var detail: String
        var done: Int
        var total: Int
    }
    struct Weapon: Codable, Equatable {
        var name: String
        var category: String
        /// Its Prestige stage and level ("Prestige 1 · Level 34"), or just the level.
        var badge: String = ""
        var image: String
        var camos: [Camo]
        var done: Int
        var total: Int
        var next: Next?
    }

    var view: String
    var game: String
    var mode: String
    var accent: String
    var overview: Overview?
    var weapon: Weapon?
    /// The streamer's channel, if they typed one: only labels their QR scan
    /// counts, never shown on the overlay.
    var channel: String = ""
}

/// Camo Track's stream overlay, like Leonida Log's: free for everyone, since
/// a stream with it on is the app's best advert.
///
/// Off until the player switches it on in Customise. While on, the app sends
/// the figures to the Worker shortly after each change (and on each return to
/// the app, which retries a send that failed), and the player adds `pageURL`
/// to OBS as a Browser source. The link holds a random id and nothing about
/// the player; `key`, which never leaves the app except as the request's
/// bearer token, is what lets this app (and only it) change or remove what
/// the link shows.
@MainActor
final class StreamOverlay: ObservableObject {
    static let shared = StreamOverlay()
    static let server = URL(string: "https://camo-track.app")!

    enum Content: String, CaseIterable, Identifiable {
        case overview, weapon
        var id: String { rawValue }
    }

    /// The shapes the page can take (`?layout=`), with the Browser source size each needs.
    enum Layout: String, CaseIterable, Identifiable {
        case card, vertical, minimal
        var id: String { rawValue }
        var sourceSize: (width: Int, height: Int) {
            switch self {
            case .card: (760, 340)
            case .vertical: (320, 700)
            case .minimal: (560, 250)
            }
        }
    }

    /// The page's look (`?style=`).
    enum Style: String, CaseIterable, Identifiable {
        case camo, glass, clean
        var id: String { rawValue }
    }

    enum Status: Equatable {
        case off
        /// On, nothing sent yet (or a send is on its way).
        case waiting
        /// On the page, as of the last send that arrived.
        case live(Date)
        /// The last send didn't arrive. The next change, or the next return to the app, tries again.
        case failed
    }

    @Published private(set) var isOn: Bool
    @Published private(set) var id: String
    @Published private(set) var status: Status
    @Published var content: Content { didSet { save(content.rawValue, Keys.content); refresh() } }
    /// The mode shown; empty follows the mode the app opens on.
    @Published var mode: String { didSet { save(mode, Keys.mode); refresh() } }
    @Published var layout: Layout { didSet { save(layout.rawValue, Keys.layout) } }
    @Published var style: Style { didSet { save(style.rawValue, Keys.style) } }
    @Published var showsQR: Bool { didSet { defaults.set(showsQR, forKey: Keys.showsQR) } }
    @Published var alignsRight: Bool { didSet { defaults.set(alignsRight, forKey: Keys.alignsRight) } }
    @Published var celebrates: Bool { didSet { defaults.set(celebrates, forKey: Keys.celebrates) } }
    @Published var channel: String { didSet { save(channel, Keys.channel); refresh() } }

    /// Builds what to send. Set by the app once the tracker exists.
    var makePayload: (() -> CamoOverlayPayload?)?
    /// The network; tests hand in canned answers.
    var send: (URLRequest) async throws -> (Data, URLResponse) = { try await URLSession.shared.data(for: $0) }
    /// How long a change waits before it's sent, so a count stepped up seven times is one request.
    var settleDelay: UInt64 = 1_500_000_000

    private let defaults: UserDefaults
    private var key: String
    private var lastSent: CamoOverlayPayload?
    private var pending: Task<Void, Never>?

    private enum Keys {
        static let on = "ct_overlay_on", id = "ct_overlay_id", key = "ct_overlay_key"
        static let content = "ct_overlay_content", mode = "ct_overlay_mode", layout = "ct_overlay_layout"
        static let style = "ct_overlay_style", showsQR = "ct_overlay_qr", alignsRight = "ct_overlay_right"
        static let celebrates = "ct_overlay_celebrate", channel = "ct_overlay_channel"
        static func weapon(_ game: String) -> String { "ct_overlay_weapon_\(game)" }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let id = defaults.string(forKey: Keys.id) ?? ""
        let key = defaults.string(forKey: Keys.key) ?? ""
        let on = defaults.bool(forKey: Keys.on) && !id.isEmpty && !key.isEmpty
        self.id = id
        self.key = key
        isOn = on
        status = on ? .waiting : .off
        content = defaults.string(forKey: Keys.content).flatMap(Content.init) ?? .overview
        mode = defaults.string(forKey: Keys.mode) ?? ""
        layout = defaults.string(forKey: Keys.layout).flatMap(Layout.init) ?? .card
        style = defaults.string(forKey: Keys.style).flatMap(Style.init) ?? .camo
        showsQR = defaults.object(forKey: Keys.showsQR) as? Bool ?? true
        alignsRight = defaults.bool(forKey: Keys.alignsRight)
        celebrates = defaults.object(forKey: Keys.celebrates) as? Bool ?? true
        channel = defaults.string(forKey: Keys.channel) ?? ""
    }

    private func save(_ value: String, _ key: String) { defaults.set(value, forKey: key) }

    /// The weapon shown in `game` (each game keeps its own), nil for none picked.
    func weaponId(game: String) -> Int? {
        defaults.object(forKey: Keys.weapon(game)) as? Int
    }

    func setWeapon(_ id: Int?, game: String) {
        defaults.set(id, forKey: Keys.weapon(game))
        objectWillChange.send()
        refresh()
    }

    // MARK: Links

    /// The page to add to OBS, with the chosen layout and options. Defaults
    /// are left off, so the plain link is the card in Camo Track's look.
    var pageURL: URL { withOptions(Self.server.appending(path: "overlay").appending(path: id)) }

    /// What the in-app preview loads: this overlay's page when it's on, the
    /// demo (made-up figures, same look) when it isn't.
    var previewURL: URL {
        guard isOn, !id.isEmpty else {
            var url = withOptions(Self.server.appending(path: "overlay/demo"))
            if content == .weapon { url = url.appending(queryItems: [URLQueryItem(name: "view", value: "weapon")]) }
            return url
        }
        return pageURL
    }

    /// Changes each time a send lands, so the preview can reload then.
    var previewToken: String {
        if case .live(let date) = status { return String(date.timeIntervalSince1970) }
        return isOn ? "on" : "off"
    }

    func withOptions(_ page: URL) -> URL {
        var items: [URLQueryItem] = []
        if layout != .card { items.append(URLQueryItem(name: "layout", value: layout.rawValue)) }
        if style != .camo { items.append(URLQueryItem(name: "style", value: style.rawValue)) }
        if !showsQR { items.append(URLQueryItem(name: "qr", value: "0")) }
        if alignsRight { items.append(URLQueryItem(name: "align", value: "right")) }
        if !celebrates { items.append(URLQueryItem(name: "celebrate", value: "0")) }
        return items.isEmpty ? page : page.appending(queryItems: items)
    }

    private var feedURL: URL { Self.server.appending(path: "api/overlay").appending(path: id) }

    /// The channel as the Worker accepts it: no @, letters, digits, `_`, `.` and `-`, up to 40.
    static func cleanChannel(_ typed: String) -> String {
        var name = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        while name.hasPrefix("@") { name.removeFirst() }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.-")
        guard !name.isEmpty, name.count <= 40, name.unicodeScalars.allSatisfy(allowed.contains) else { return "" }
        return name
    }

    // MARK: Switching

    func turnOn() {
        guard !isOn else { return }
        if id.isEmpty || key.isEmpty { mintLink() }
        isOn = true
        defaults.set(true, forKey: Keys.on)
        status = .waiting
        lastSent = nil
        refresh(immediately: true)
    }

    /// Stops sending and takes the figures down, so the page goes blank rather
    /// than freezing. The link is kept: switching back on brings the same
    /// Browser source back to life.
    func turnOff() {
        guard isOn else { return }
        isOn = false
        defaults.set(false, forKey: Keys.on)
        status = .off
        pending?.cancel()
        lastSent = nil
        let request = self.request("DELETE", url: feedURL)
        Task { [send] in _ = try? await send(request) }
    }

    /// A fresh link, for when the old one got out. The old one stops working.
    func replaceLink() {
        let old = request("DELETE", url: feedURL)
        Task { [send] in _ = try? await send(old) }
        mintLink()
        lastSent = nil
        if isOn {
            status = .waiting
            refresh(immediately: true)
        }
    }

    private func mintLink() {
        id = Self.token()
        key = Self.token()
        defaults.set(id, forKey: Keys.id)
        defaults.set(key, forKey: Keys.key)
    }

    /// 144 random bits as URL-safe text (24 characters).
    static func token() -> String {
        var generator = SystemRandomNumberGenerator()
        let bytes = (0..<18).map { _ in UInt8.random(in: .min ... .max, using: &generator) }
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
    }

    // MARK: Sending

    /// Sends the current figures if they differ from what the page has.
    func refresh(immediately: Bool = false) {
        guard isOn else { return }
        pending?.cancel()
        let delay = settleDelay
        pending = Task { [weak self] in
            if !immediately { try? await Task.sleep(nanoseconds: delay) }
            guard !Task.isCancelled else { return }
            await self?.sendNow()
        }
    }

    /// The pending send, for tests to wait on.
    func settle() async { await pending?.value }

    private func sendNow() async {
        guard isOn, var payload = makePayload?() else { return }
        payload.channel = Self.cleanChannel(channel)
        guard payload != lastSent, let body = try? JSONEncoder().encode(payload) else { return }
        var request = self.request("PUT", url: feedURL)
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let sentTo = id
        var ok = false
        if let (_, response) = try? await send(request), let http = response as? HTTPURLResponse {
            ok = (200..<300).contains(http.statusCode)
        }
        // Switched off, or the link replaced, while this was in flight
        guard isOn, sentTo == id, !Task.isCancelled else { return }
        if ok {
            lastSent = payload
            status = .live(Date())
        } else {
            status = .failed
        }
    }

    private func request(_ method: String, url: URL) -> URLRequest {
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = method
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        return request
    }
}

extension TrackerViewModel {
    /// The overlay's figures for `content` in `modeRaw` (empty: the mode the
    /// app opens on, else the first played), with `weaponId` for the weapon
    /// view. Nil before the catalog has loaded, or for a weapon that isn't in
    /// this game. Works the same for every game: the steps, mastery and camos
    /// come from the game's own data, as on the Stats tab and the widgets.
    func streamOverlayPayload(content: StreamOverlay.Content, modeRaw: String, weaponId: Int?) -> CamoOverlayPayload? {
        guard catalog != nil else { return nil }
        let played = visibleModes
        let defaults = UserDefaults.standard
        let fallback = AppMode.start(defaults.string(forKey: AppMode.startKey) ?? "", played: defaults.string(forKey: AppMode.playedKey) ?? "")
        let mode = AppMode(rawValue: modeRaw).flatMap { played.contains($0) ? $0 : nil } ?? fallback
        let raw = mode.rawValue
        var payload = CamoOverlayPayload(view: content.rawValue, game: game.shortName, mode: mode.displayName,
                                         accent: mode.accent.hexString)

        if content == .weapon {
            guard let weaponId, let weapon = weapon(id: weaponId) else { return nil }
            let leaves = camos(weaponId: weaponId, mode: raw).flatMap(leafItems)
            var camoRow = leaves.map {
                CamoOverlayPayload.Camo(name: $0.name.resolved(), image: $0.imageURL ?? "",
                                        done: isCamoComplete(mode: raw, weaponId: weaponId, camo: $0))
            }
            // Then the Completionist camos (Gold, Platinum...), earned per weapon
            camoRow += mode.completionistCamos.enumerated().map { step, camo in
                CamoOverlayPayload.Camo(name: camo.name, image: camo.imageURL ?? "",
                                        done: isCompletionistComplete(mode: raw, weaponId: weaponId, step: step))
            }
            // Then its Prestige camos, in this weapon's own names and pictures
            // (BO7's per-weapon ones, MW4's Pyroclasts), where the game has them
            camoRow += prestigeCamos.enumerated().map { index, camo in
                CamoOverlayPayload.Camo(name: prestigeCamoName(camo, weaponId: weaponId).resolved(),
                                        image: prestigeCamoImageURL(camo, weaponId: weaponId) ?? "",
                                        done: isPrestigeCamoComplete(weaponId: weaponId, index: index))
            }
            let levelText = String(format: "ct.overlay.level".localized(), level(for: weaponId), maxLevel(for: weapon))
            let badge = prestigeName(for: weaponId).map { "\($0) · \(levelText)" } ?? levelText
            let pinned = overlayNext(weapon, mode: mode)
            payload.weapon = CamoOverlayPayload.Weapon(
                name: weapon.name.resolved(),
                category: category(containingWeaponId: weaponId)?.name.resolved() ?? "",
                badge: badge,
                image: weapon.imageURL ?? "", camos: camoRow,
                done: camoRow.filter(\.done).count, total: camoRow.count, next: pinned)
            payload.overview = nil
            return payload
        }

        guard let snapshot = widgetSnapshot(), let figures = snapshot.modes.first(where: { $0.id == raw }) else { return nil }
        payload.overview = CamoOverlayPayload.Overview(
            fraction: figures.fraction, weaponCount: figures.weaponCount,
            steps: figures.steps.map { .init(name: $0.name, done: $0.done, total: $0.total, color: $0.colorHex) },
            mastery: figures.mastery.map { .init(name: $0.name, done: $0.done, total: $0.total, color: $0.colorHex) })
        return payload
    }

    /// What the weapon is on now: the next camo with its challenge and count,
    /// else the next Completionist camo. Nil once it has everything.
    private func overlayNext(_ weapon: WeaponEntry, mode: AppMode) -> CamoOverlayPayload.Next? {
        let raw = mode.rawValue
        let leaves = camos(weaponId: weapon.weaponId, mode: raw).flatMap(leafItems)
        if let camo = leaves.first(where: { !isCamoComplete(mode: raw, weaponId: weapon.weaponId, camo: $0) }) {
            if let requirement = camo.requirement {
                let current = requirement.byMode?.first { $0.mode == raw }?.description.resolved()
                return .init(name: camo.name.resolved(), detail: current ?? requirement.description.resolved(),
                             done: camoAmount(mode: raw, weaponId: weapon.weaponId, camo: camo),
                             total: max(requirement.amount, 1))
            }
            if let level = militaryLevel(mode: raw, weaponId: weapon.weaponId, camo: camo) {
                return .init(name: camo.name.resolved(), detail: levelGateText(level, weaponId: weapon.weaponId, kind: "reach"),
                             done: min(self.level(for: weapon.weaponId), level), total: max(level, 1))
            }
            return .init(name: camo.name.resolved(), detail: "", done: 0, total: 1)
        }
        if let step = (0..<mode.completionistCamos.count).first(where: {
            !isCompletionistComplete(mode: raw, weaponId: weapon.weaponId, step: $0)
        }) {
            // Its own challenge where the mode gives one (BO7's Doomsteel: per weapon)
            if let requirement = completionistRequirement(mode: raw, weaponId: weapon.weaponId, step: step) {
                return .init(name: mode.completionistCamos[step].name, detail: requirement.description.resolved(),
                             done: min(completionistAmount(mode: raw, weaponId: weapon.weaponId, step: step), requirement.amount),
                             total: max(requirement.amount, 1))
            }
            return .init(name: mode.completionistCamos[step].name, detail: "", done: 0, total: 1)
        }
        return nil
    }
}
