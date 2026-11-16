import SwiftUI
import WebKit

/// Customise > Stream overlay: switch the overlay on, choose what it shows
/// (the mode at a glance, or one weapon) and how it looks, and copy the link
/// for OBS. The preview runs the real page.
struct StreamOverlayView: View {
    let accent: Color
    @ObservedObject private var overlay = StreamOverlay.shared
    @EnvironmentObject private var viewModel: TrackerViewModel
    @State private var copied = false

    private var gameID: String { viewModel.game.id }
    private var weaponId: Int? { overlay.weaponId(game: gameID) }
    private var weaponName: String? { weaponId.flatMap(viewModel.weapon(id:))?.name.resolved() }

    var body: some View {
        List {
            Section {
                OverlayPreview(url: overlay.previewURL, size: overlay.layout.sourceSize, reloadToken: overlay.previewToken)
                    .listRowInsets(EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10))
                Toggle("ct.overlay.on".localized(), isOn: Binding(get: { overlay.isOn }, set: { $0 ? overlay.turnOn() : overlay.turnOff() }))
                    .tint(accent)
                    .accessibilityIdentifier("overlay.on")
            } footer: {
                Text("ct.overlay.footer".localized())
            }

            Section("ct.overlay.shows".localized()) {
                Picker("ct.overlay.shows".localized(), selection: $overlay.content) {
                    Text("ct.overlay.overview".localized()).tag(StreamOverlay.Content.overview)
                    Text("ct.overlay.weapon".localized()).tag(StreamOverlay.Content.weapon)
                }
                .pickerStyle(.segmented)
                if overlay.content == .weapon {
                    NavigationLink {
                        OverlayWeaponPicker(accent: accent)
                    } label: {
                        HStack {
                            Text("ct.overlay.which_weapon".localized())
                            Spacer()
                            Text(weaponName ?? "ct.overlay.pick".localized())
                                .foregroundStyle(weaponName == nil ? accent : Color.appInkMuted)
                        }
                    }
                }
                if viewModel.visibleModes.count > 1 {
                    Picker("ct.overlay.mode".localized(), selection: $overlay.mode) {
                        Text("ct.overlay.mode_start".localized()).tag("")
                        ForEach(viewModel.visibleModes) { mode in Text(mode.displayName).tag(mode.rawValue) }
                    }
                }
            }

            Section("ct.overlay.look".localized()) {
                Picker("ct.overlay.layout".localized(), selection: $overlay.layout) {
                    Text("ct.overlay.layout.card".localized()).tag(StreamOverlay.Layout.card)
                    Text("ct.overlay.layout.vertical".localized()).tag(StreamOverlay.Layout.vertical)
                    Text("ct.overlay.layout.minimal".localized()).tag(StreamOverlay.Layout.minimal)
                }
                .pickerStyle(.segmented)
                Picker("ct.overlay.style".localized(), selection: $overlay.style) {
                    Text("Camo Track").tag(StreamOverlay.Style.camo)
                    Text("ct.overlay.style.glass".localized()).tag(StreamOverlay.Style.glass)
                    Text("ct.overlay.style.clean".localized()).tag(StreamOverlay.Style.clean)
                }
                .pickerStyle(.segmented)
                Toggle("ct.overlay.qr".localized(), isOn: $overlay.showsQR).tint(accent)
                Toggle("ct.overlay.celebrate".localized(), isOn: $overlay.celebrates).tint(accent)
                Toggle("ct.overlay.right".localized(), isOn: $overlay.alignsRight).tint(accent)
            }

            if overlay.isOn {
                Section {
                    Text(overlay.pageURL.absoluteString)
                        .font(.footnote.monospaced())
                        .textSelection(.enabled)
                    Button {
                        UIPasteboard.general.string = overlay.pageURL.absoluteString
                        copied = true
                        Haptics.milestone()
                    } label: {
                        Label(copied ? "ct.overlay.copied".localized() : "ct.overlay.copy".localized(),
                              systemImage: copied ? "checkmark" : "doc.on.doc")
                    }
                    .foregroundStyle(accent)
                    ShareLink(item: overlay.pageURL) {
                        Label("ct.overlay.share".localized(), systemImage: "square.and.arrow.up")
                    }
                    .foregroundStyle(accent)
                } header: {
                    Text("ct.overlay.link".localized())
                } footer: {
                    let size = overlay.layout.sourceSize
                    Text(String(format: "ct.overlay.link_footer".localized(), size.width, size.height) + " " + statusLine)
                }

                Section {
                    TextField("ct.overlay.channel".localized(), text: $overlay.channel)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("ct.overlay.new_link".localized(), role: .destructive) { overlay.replaceLink(); copied = false }
                } footer: {
                    Text("ct.overlay.channel_footer".localized())
                }
            }
        }
        .navigationTitle("ct.overlay.title".localized())
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: overlay.layout) { _ in copied = false }
        .onChange(of: overlay.style) { _ in copied = false }
        .onAppear {
            // The weapon view starts on the pinned gun, if there is one
            if overlay.weaponId(game: gameID) == nil, let pinned = viewModel.pinnedWeaponId {
                overlay.setWeapon(pinned, game: gameID)
            }
            overlay.refresh(immediately: true)
        }
    }

    private var statusLine: String {
        switch overlay.status {
        case .off: ""
        case .waiting: "ct.overlay.status.waiting".localized()
        case .live: "ct.overlay.status.live".localized()
        case .failed: "ct.overlay.status.failed".localized()
        }
    }
}

/// Every weapon in the current game, by class, to put on the overlay.
private struct OverlayWeaponPicker: View {
    let accent: Color
    @ObservedObject private var overlay = StreamOverlay.shared
    @EnvironmentObject private var viewModel: TrackerViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            ForEach(viewModel.catalog?.categories ?? [], id: \.categoryId) { category in
                Section(category.name.resolved()) {
                    ForEach(category.weapons, id: \.weaponId) { weapon in
                        Button {
                            overlay.setWeapon(weapon.weaponId, game: viewModel.game.id)
                            dismiss()
                        } label: {
                            HStack {
                                Text(weapon.name.resolved()).foregroundStyle(Color.appInk)
                                Spacer()
                                if overlay.weaponId(game: viewModel.game.id) == weapon.weaponId {
                                    Image(systemName: "checkmark").foregroundStyle(accent)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("ct.overlay.which_weapon".localized())
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// The overlay page at its Browser source size, scaled to fit, over a
/// stand-in for gameplay.
struct OverlayPreview: View {
    let url: URL
    let size: (width: Int, height: Int)
    /// Changes when a send landed, so the preview reloads instead of waiting for the page's next poll.
    let reloadToken: String

    var body: some View {
        GeometryReader { geo in
            let scale = min(1, geo.size.width / CGFloat(size.width))
            OverlayWebView(url: url, reloadToken: reloadToken)
                .frame(width: CGFloat(size.width), height: CGFloat(size.height))
                .scaleEffect(scale, anchor: .topLeading)
                .frame(width: CGFloat(size.width) * scale, height: CGFloat(size.height) * scale, alignment: .topLeading)
                .frame(maxWidth: .infinity)
                .background(
                    LinearGradient(colors: [Color(red: 0.24, green: 0.28, blue: 0.20), Color(red: 0.45, green: 0.36, blue: 0.18),
                                            Color(red: 0.62, green: 0.42, blue: 0.14)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing))
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .aspectRatio(CGFloat(size.width) / CGFloat(size.height), contentMode: .fit)
        .frame(maxHeight: size.height > size.width ? 460 : 300)
        // A tall layout is narrower than the row: centred, not left
        .frame(maxWidth: .infinity)
        .accessibilityLabel(Text("ct.overlay.preview".localized()))
    }
}

private struct OverlayWebView: UIViewRepresentable {
    let url: URL
    let reloadToken: String

    final class Coordinator { var loaded: String? }
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: .zero, configuration: config)
        view.isOpaque = false
        view.backgroundColor = .clear
        view.scrollView.backgroundColor = .clear
        view.scrollView.isScrollEnabled = false
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {
        let key = url.absoluteString + "|" + reloadToken
        guard context.coordinator.loaded != key else { return }
        context.coordinator.loaded = key
        view.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData))
    }
}
