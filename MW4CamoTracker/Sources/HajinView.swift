import SwiftUI
import UIKit

/// The Hajin tab: the DMZ Tac Map up top, then the reference guide
/// (level unlocks, crafting, stations, bosses...). Everything comes from
/// `hajin.json`, which updates over the air as more gets confirmed.
struct HajinView: View {
    @EnvironmentObject private var store: HajinStore
    @State private var query = ""
    @State private var showsMap = false
    @State private var shownSection: HajinGuide.Section?

    private var accent: Color { .accentDMZ }

    var body: some View {
        ZStack {
            AppBackground(accent: accent)
            if let guide = store.guide {
                List {
                    if query.isEmpty {
                        Button { showsMap = true } label: {
                            MapHeroCard(guide: guide, pinCount: store.pins.count)
                        }
                        .buttonStyle(.plain)
                        .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)

                        Section {
                            ForEach(guide.guide) { section in
                                NavigationLink {
                                    GuideSectionView(section: section)
                                } label: {
                                    SectionRow(section: section)
                                }
                                .listRowBackground(Color.appSurface)
                            }
                        } header: {
                            Text("mw4.ui.hajin.guide".localized())
                        } footer: {
                            footer(guide)
                        }
                    } else {
                        searchResults(guide)
                    }
                }
                .scrollContentBackground(.hidden)
                .listStyle(.insetGrouped)
                .searchable(text: $query, prompt: "mw4.ui.hajin.search_guide".localized())
            }
        }
        .navigationTitle("mw4.ui.hajin.title".localized())
        .navigationDestination(isPresented: $showsMap) { HajinMapScreen() }
        .navigationDestination(isPresented: Binding(get: { shownSection != nil }, set: { if !$0 { shownSection = nil } })) {
            if let shownSection { GuideSectionView(section: shownSection) }
        }
        .onAppear(perform: openScreenshotTarget)
        .task { await store.refresh() }
    }

    /// `SS_HAJIN=map` or `SS_HAJIN=<section id>` opens that screen for the
    /// screenshot harness. DEBUG-only.
    private func openScreenshotTarget() {
        #if DEBUG
        guard let target = ProcessInfo.processInfo.environment["SS_HAJIN"], !target.isEmpty else { return }
        if target == "map" { showsMap = true } else { shownSection = store.guide?.guide.first { $0.id == target } }
        #endif
    }

    private func footer(_ guide: HajinGuide) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("mw4.ui.hajin.early_access".localized())
            if let updated = guide.updated {
                Text(String(format: "mw4.ui.hajin.updated".localized(), updated))
            }
            if let credit = guide.map.credit { Text(credit) }
        }
        .font(.caption)
        .foregroundStyle(Color.appInkMuted)
        .padding(.top, 6)
    }

    /// Every row and marker whose text matches, grouped by where it lives.
    @ViewBuilder private func searchResults(_ guide: HajinGuide) -> some View {
        let needle = query.lowercased()
        let places = guide.markers.filter { $0.name.resolved.lowercased().contains(needle) || ($0.note?.resolved.lowercased().contains(needle) ?? false) }
        let uniquePlaces = Dictionary(grouping: places, by: { $0.name.resolved }).compactMap { $0.value.first }
            .sorted { $0.name.resolved < $1.name.resolved }
        if !uniquePlaces.isEmpty {
            Section("mw4.ui.hajin.map".localized()) {
                ForEach(uniquePlaces) { marker in
                    NavigationLink {
                        HajinMapScreen(startAt: marker)
                    } label: {
                        MarkerRow(marker: marker, category: guide.category(marker.cat))
                    }
                    .listRowBackground(Color.appSurface)
                }
            }
        }
        ForEach(guide.guide) { section in
            let rows = section.rows.filter {
                $0.title.resolved.lowercased().contains(needle)
                    || ($0.subtitle?.resolved.lowercased().contains(needle) ?? false)
                    || ($0.value?.resolved.lowercased().contains(needle) ?? false)
            }
            if !rows.isEmpty {
                Section(section.title.resolved) {
                    ForEach(rows, id: \.self) { row in
                        GuideRowView(row: row, highlight: needle)
                            .listRowBackground(Color.appSurface)
                    }
                }
            }
        }
        if uniquePlaces.isEmpty && !guide.guide.contains(where: { s in s.rows.contains { $0.title.resolved.lowercased().contains(needle) || ($0.subtitle?.resolved.lowercased().contains(needle) ?? false) } }) {
            Text("mw4.ui.hajin.no_results".localized())
                .foregroundStyle(Color.appInkMuted)
                .listRowBackground(Color.clear)
        }
    }
}

private struct MapHeroCard: View {
    let guide: HajinGuide
    let pinCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HajinMapThumbnail(name: guide.map.image)
                .frame(height: 170)
                .clipped()
                .overlay(alignment: .bottomLeading) {
                    LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .center, endPoint: .bottom)
                }
                .overlay(alignment: .bottomLeading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("mw4.ui.hajin.tac_map".localized())
                            .font(.title3.weight(.heavy))
                        Text("mw4.ui.hajin.tac_map_subtitle".localized())
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    .foregroundStyle(.white)
                    .padding(12)
                }
            HStack(spacing: 14) {
                stat(guide.markers.filter { $0.cat == "fortress" }.count, "building.columns.fill", Color(hex: "#E5484D") ?? .red)
                stat(guide.markers.filter { $0.cat == "uav" }.count, "antenna.radiowaves.left.and.right", Color(hex: "#3DD68C") ?? .green)
                stat(guide.markers.filter { $0.cat == "cache" }.count, "shippingbox.fill", Color(hex: "#70B8FF") ?? .blue)
                if pinCount > 0 {
                    stat(pinCount, "mappin", Color(red: 1, green: 0.85, blue: 0.2))
                }
                Spacer()
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Color.appInkMuted)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .borderedCard(cornerRadius: 12, accent: .accentDMZ)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func stat(_ count: Int, _ symbol: String, _ tint: Color) -> some View {
        Label("\(count)", systemImage: symbol)
            .font(.footnote.weight(.semibold).monospacedDigit())
            .foregroundStyle(tint)
    }
}

/// A small, pre-shrunk copy of the map for the card, so the list never
/// decodes the full 2660 px image.
private struct HajinMapThumbnail: View {
    let name: String
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Color.appSurface2
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            }
        }
        .task {
            guard image == nil else { return }
            image = await Task.detached(priority: .userInitiated) { () -> UIImage? in
                guard let url = Bundle.main.url(forResource: name, withExtension: "jpg"),
                      let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
                let options: [CFString: Any] = [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceThumbnailMaxPixelSize: 1100,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                ]
                guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
                return UIImage(cgImage: cg)
            }.value
        }
    }
}

private struct SectionRow: View {
    let section: HajinGuide.Section

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: section.symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.accentDMZ)
                .frame(width: 28)
            Text(section.title.resolved)
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.appInk)
            Spacer()
            Text("\(section.rows.count)")
                .font(.footnote.monospacedDigit())
                .foregroundStyle(Color.appInkMuted)
        }
        .padding(.vertical, 4)
    }
}

struct MarkerRow: View {
    let marker: HajinGuide.Marker
    let category: HajinGuide.Category?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: category?.symbol ?? "mappin")
                .foregroundStyle(category?.tint ?? .appInk)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(marker.name.resolved).foregroundStyle(Color.appInk)
                if let category { Text(category.name.resolved).font(.caption).foregroundStyle(Color.appInkMuted) }
            }
        }
    }
}

/// One table in the guide, with its own search.
struct GuideSectionView: View {
    let section: HajinGuide.Section
    @State private var query = ""

    private var rows: [HajinGuide.Row] {
        guard !query.isEmpty else { return section.rows }
        let needle = query.lowercased()
        return section.rows.filter {
            $0.title.resolved.lowercased().contains(needle)
                || ($0.subtitle?.resolved.lowercased().contains(needle) ?? false)
                || ($0.value?.resolved.lowercased().contains(needle) ?? false)
        }
    }

    var body: some View {
        ZStack {
            AppBackground(accent: .accentDMZ)
            List {
                if let intro = section.intro, query.isEmpty {
                    Text(intro.resolved)
                        .font(.subheadline)
                        .foregroundStyle(Color.appInkMuted)
                        .listRowBackground(Color.clear)
                }
                ForEach(rows, id: \.self) { row in
                    GuideRowView(row: row, highlight: query.lowercased())
                        .listRowBackground(Color.appSurface)
                }
                if rows.isEmpty {
                    Text("mw4.ui.hajin.no_results".localized())
                        .foregroundStyle(Color.appInkMuted)
                        .listRowBackground(Color.clear)
                }
            }
            .scrollContentBackground(.hidden)
            .listStyle(.insetGrouped)
            .searchable(text: $query, prompt: "mw4.ui.hajin.search_section".localized())
        }
        .navigationTitle(section.title.resolved)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct GuideRowView: View {
    let row: HajinGuide.Row
    var highlight = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(row.title.resolved)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.appInk)
                Spacer(minLength: 8)
                if let value = row.value {
                    Text(value.resolved)
                        .font(.footnote.weight(.semibold).monospacedDigit())
                        .foregroundStyle(Color.accentDMZ)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.accentDMZ.opacity(0.15)))
                }
            }
            if let subtitle = row.subtitle {
                Text(subtitle.resolved)
                    .font(.subheadline)
                    .foregroundStyle(subtitle.resolved.hasPrefix("Cost not confirmed") ? Color.appInkMuted.opacity(0.7) : Color.appInkMuted)
                    .italic(subtitle.resolved.hasPrefix("Cost not confirmed"))
            }
        }
        .padding(.vertical, 3)
    }
}

// MARK: - Map screen

struct HajinMapScreen: View {
    var startAt: HajinGuide.Marker? = nil

    @EnvironmentObject private var store: HajinStore
    @State private var image: UIImage?
    @State private var selection: HajinSelection?
    @State private var focus: HajinMapView.Focus?
    @State private var showFilters = false
    @State private var showSearch = false
    @State private var newPin: HajinPin?

    var body: some View {
        ZStack(alignment: .top) {
            Color.appBackground.ignoresSafeArea()
            if let guide = store.guide, let image {
                HajinMapView(
                    guide: guide, image: image, hidden: store.hiddenCategories, pins: store.pins,
                    selection: selection, focus: focus,
                    onSelect: { selection = $0 },
                    onLongPress: { point in
                        newPin = HajinPin(x: point.x, y: point.y, title: "", note: "")
                    }
                )
                .ignoresSafeArea(edges: .bottom)

                Text("mw4.ui.hajin.long_press_hint".localized())
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(.black.opacity(0.55)))
                    .padding(.top, 8)
                    .allowsHitTesting(false)
            } else {
                ProgressView().tint(.white).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("mw4.ui.hajin.tac_map".localized())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button { showSearch = true } label: { Image(systemName: "magnifyingglass") }
                    .accessibilityLabel("mw4.ui.hajin.search_map".localized())
                Button { showFilters = true } label: { Image(systemName: "line.3.horizontal.decrease.circle") }
                    .accessibilityLabel("mw4.ui.hajin.filters".localized())
            }
        }
        .task {
            guard image == nil, let name = store.guide?.map.image else { return }
            image = await Task.detached(priority: .userInitiated) { () -> UIImage? in
                guard let url = Bundle.main.url(forResource: name, withExtension: "jpg"),
                      let raw = UIImage(contentsOfFile: url.path) else { return nil }
                // Decode now, off the main thread, so the first pan doesn't stutter
                return raw.preparingForDisplay() ?? raw
            }.value
            #if DEBUG
            if let id = ProcessInfo.processInfo.environment["SS_HAJIN_PICK"],
               let marker = store.guide?.markers.first(where: { $0.id == id }) {
                selection = .marker(marker)
                focus = .init(point: CGPoint(x: marker.x, y: marker.y), token: 1)
            }
            #endif
            if let startAt {
                if store.hiddenCategories.contains(startAt.cat) { store.hiddenCategories.remove(startAt.cat) }
                selection = .marker(startAt)
                focus = .init(point: CGPoint(x: startAt.x, y: startAt.y), token: 1)
            }
        }
        .sheet(item: $selection) { selected in
            SelectionSheet(selection: selected) { selection = nil }
                .presentationDetents([.fraction(0.32), .large])
                .presentationDragIndicator(.visible)
                .mapStaysUsable()
        }
        .sheet(item: $newPin) { pin in
            PinEditor(pin: pin, isNew: true) { saved in
                if let saved { store.pins.append(saved) }
                newPin = nil
            }
        }
        .sheet(isPresented: $showFilters) {
            FilterSheet()
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showSearch) {
            MapSearchSheet { marker in
                showSearch = false
                if store.hiddenCategories.contains(marker.cat) { store.hiddenCategories.remove(marker.cat) }
                selection = .marker(marker)
                focus = .init(point: CGPoint(x: marker.x, y: marker.y), token: (focus?.token ?? 0) + 1)
            }
        }
    }
}

/// What's shown when a marker or pin is tapped.
private struct SelectionSheet: View {
    let selection: HajinSelection
    let dismiss: () -> Void
    @EnvironmentObject private var store: HajinStore
    @State private var editing: HajinPin?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    switch selection {
                    case .marker(let marker): markerBody(marker)
                    case .pin(let id):
                        if let pin = store.pins.first(where: { $0.id == id }) { pinBody(pin) }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
            }
            .background(Color.appBackground.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("mw4.ui.hajin.done".localized(), action: dismiss)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .sheet(item: $editing) { pin in
            PinEditor(pin: pin, isNew: false) { saved in
                if let saved, let index = store.pins.firstIndex(where: { $0.id == saved.id }) { store.pins[index] = saved }
                editing = nil
            }
        }
    }

    @ViewBuilder private func markerBody(_ marker: HajinGuide.Marker) -> some View {
        let category = store.guide?.category(marker.cat)
        HStack(spacing: 10) {
            Image(systemName: category?.symbol ?? "mappin")
                .font(.title3.weight(.semibold))
                .foregroundStyle(category?.tint ?? .appInk)
            VStack(alignment: .leading, spacing: 2) {
                Text(marker.name.resolved).font(.title3.weight(.heavy)).foregroundStyle(Color.appInk)
                if let category { Text(category.name.resolved).font(.subheadline).foregroundStyle(Color.appInkMuted) }
            }
        }
        if let threat = marker.threat, let name = store.guide?.threatName(threat) {
            Label(String(format: "mw4.ui.hajin.threat".localized(), name), systemImage: "exclamationmark.triangle.fill")
                .font(.footnote.weight(.bold))
                .foregroundStyle(HajinThreat.color(threat))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(HajinThreat.color(threat).opacity(0.15)))
        }
        if let note = marker.note {
            Text(note.resolved).font(.body).foregroundStyle(Color.appInk)
        }
        if let blurb = category?.blurb {
            Text(blurb.resolved).font(.subheadline).foregroundStyle(Color.appInkMuted)
        }
    }

    @ViewBuilder private func pinBody(_ pin: HajinPin) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "mappin").font(.title3.weight(.semibold)).foregroundStyle(Color(red: 1, green: 0.85, blue: 0.2))
            VStack(alignment: .leading, spacing: 2) {
                Text(pin.title.isEmpty ? "mw4.ui.hajin.my_pin".localized() : pin.title)
                    .font(.title3.weight(.heavy)).foregroundStyle(Color.appInk)
                Text("mw4.ui.hajin.my_pin".localized()).font(.subheadline).foregroundStyle(Color.appInkMuted)
            }
        }
        if !pin.note.isEmpty { Text(pin.note).foregroundStyle(Color.appInk) }
        HStack {
            Button { editing = pin } label: { Label("mw4.ui.hajin.edit_pin".localized(), systemImage: "pencil") }
                .buttonStyle(.bordered)
            Button(role: .destructive) {
                store.pins.removeAll { $0.id == pin.id }
                dismiss()
            } label: { Label("mw4.ui.hajin.delete_pin".localized(), systemImage: "trash") }
                .buttonStyle(.bordered)
        }
        .padding(.top, 4)
    }
}

private struct PinEditor: View {
    @State var pin: HajinPin
    let isNew: Bool
    let finish: (HajinPin?) -> Void

    var body: some View {
        NavigationStack {
            Form {
                TextField("mw4.ui.hajin.pin_name".localized(), text: $pin.title)
                TextField("mw4.ui.hajin.pin_note".localized(), text: $pin.note, axis: .vertical)
                    .lineLimit(3...8)
            }
            .navigationTitle(isNew ? "mw4.ui.hajin.new_pin".localized() : "mw4.ui.hajin.edit_pin".localized())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("mw4.ui.hajin.cancel".localized()) { finish(nil) }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("mw4.ui.hajin.save".localized()) { finish(pin) }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

private struct FilterSheet: View {
    @EnvironmentObject private var store: HajinStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if let guide = store.guide {
                    ForEach(guide.categories) { category in
                        let count = guide.markers.filter { $0.cat == category.id }.count
                        Toggle(isOn: Binding(
                            get: { !store.hiddenCategories.contains(category.id) },
                            set: { on in
                                var hidden = store.hiddenCategories
                                if on { hidden.remove(category.id) } else { hidden.insert(category.id) }
                                store.hiddenCategories = hidden
                            }
                        )) {
                            Label {
                                HStack {
                                    Text(category.name.resolved)
                                    Spacer()
                                    Text("\(count)").monospacedDigit().foregroundStyle(Color.appInkMuted)
                                }
                            } icon: {
                                Image(systemName: category.symbol).foregroundStyle(category.tint)
                            }
                        }
                        .tint(.accentDMZ)
                    }
                }
            }
            .navigationTitle("mw4.ui.hajin.filters".localized())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Menu("mw4.ui.hajin.show".localized()) {
                        Button("mw4.ui.hajin.show_all".localized()) { store.hiddenCategories = [] }
                        Button("mw4.ui.hajin.hide_all".localized()) {
                            store.hiddenCategories = Set(store.guide?.categories.filter { !$0.isLabel }.map(\.id) ?? [])
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("mw4.ui.hajin.done".localized()) { dismiss() }
                }
            }
        }
    }
}

private struct MapSearchSheet: View {
    let pick: (HajinGuide.Marker) -> Void
    @EnvironmentObject private var store: HajinStore
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var results: [HajinGuide.Marker] {
        guard let guide = store.guide else { return [] }
        // Named places only: "UAV Tower" x14 says nothing on its own
        let named = guide.markers.filter { ["area", "place", "fortress", "compound", "key"].contains($0.cat) }
        let needle = query.lowercased()
        return named
            .filter { needle.isEmpty || $0.name.resolved.lowercased().contains(needle) }
            .sorted { $0.name.resolved < $1.name.resolved }
    }

    var body: some View {
        NavigationStack {
            List(results) { marker in
                Button { pick(marker) } label: {
                    MarkerRow(marker: marker, category: store.guide?.category(marker.cat))
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "mw4.ui.hajin.search_map".localized())
            .navigationTitle("mw4.ui.hajin.search_map".localized())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("mw4.ui.hajin.cancel".localized()) { dismiss() }
                }
            }
        }
    }
}

private extension View {
    /// Leaves the map pannable and undimmed behind the small sheet (iOS 16.4+).
    @ViewBuilder func mapStaysUsable() -> some View {
        if #available(iOS 16.4, *) {
            presentationBackgroundInteraction(.enabled(upThrough: .fraction(0.32)))
        } else {
            self
        }
    }
}
