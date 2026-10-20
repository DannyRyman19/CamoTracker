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
    @State private var shownItem: String?
    @State private var showsKeepSell = false
    @State private var width: CGFloat = 0

    private var accent: Color { .accentDMZ }

    var body: some View {
        ZStack {
            AppBackground(accent: accent)
            if let guide = store.guide {
                if width >= 700 {
                    // iPad: the map is the page, the guide beside or under it
                    HajinWideLayout()
                } else {
                    phoneList(guide)
                }
            }
        }
        .readingWidth($width)
        .navigationTitle("mw4.ui.hajin.title".localized())
        .navigationBarTitleDisplayMode(width >= 700 ? .inline : .automatic)
        .navigationDestination(isPresented: $showsMap) { HajinMapScreen() }
        .navigationDestination(isPresented: $showsKeepSell) { HajinKeepSellView() }
        .navigationDestination(isPresented: Binding(get: { shownSection != nil }, set: { if !$0 { shownSection = nil } })) {
            if let shownSection { GuideSectionView(section: shownSection) }
        }
        .navigationDestination(isPresented: Binding(get: { shownItem != nil }, set: { if !$0 { shownItem = nil } })) {
            if let shownItem { HajinItemView(id: shownItem) }
        }
        .onAppear(perform: openScreenshotTarget)
        .task { await store.refresh() }
    }

    private func phoneList(_ guide: HajinGuide) -> some View {
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
                    NavigationLink { HajinKeepSellView() } label: { HajinKeepSellRow() }
                        .listRowBackground(Color.appSurface)
                }

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
                    GuideFooter(guide: guide)
                }
            } else {
                GuideSearchResults(guide: guide, query: query, pick: nil)
            }
        }
        .scrollContentBackground(.hidden)
        .listStyle(.insetGrouped)
        .searchable(text: $query, prompt: "mw4.ui.hajin.search_guide".localized())
    }

    /// `SS_HAJIN=map` or `SS_HAJIN=<section id>` opens that screen for the
    /// screenshot harness (iPhone). DEBUG-only.
    private func openScreenshotTarget() {
        #if DEBUG
        guard let target = ProcessInfo.processInfo.environment["SS_HAJIN"], !target.isEmpty,
              UIDevice.current.userInterfaceIdiom == .phone else { return }
        if target == "map" {
            showsMap = true
        } else if target == "keep" {
            showsKeepSell = true
        } else if target.hasPrefix("item:") {
            shownItem = String(target.dropFirst(5))
        } else {
            shownSection = store.guide?.guide.first { $0.id == target }
        }
        #endif
    }
}

private struct GuideFooter: View {
    let guide: HajinGuide

    var body: some View {
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
}

/// Every row and marker whose text matches, grouped by where it lives.
/// `pick` set (iPad): a place flies the map there; otherwise it opens the
/// map screen on it.
private struct GuideSearchResults: View {
    let guide: HajinGuide
    let query: String
    let pick: ((HajinGuide.Marker) -> Void)?

    var body: some View {
        let needle = query.lowercased()
        let places = guide.markers.filter { $0.name.resolved.lowercased().contains(needle) || ($0.note?.resolved.lowercased().contains(needle) ?? false) }
        let uniquePlaces = Dictionary(grouping: places, by: { $0.name.resolved }).compactMap { $0.value.first }
            .sorted { $0.name.resolved < $1.name.resolved }
        let sections = guide.guide.map { ($0, $0.rows.filter { $0.matches(needle) }) }.filter { !$0.1.isEmpty }
        if !uniquePlaces.isEmpty {
            Section("mw4.ui.hajin.map".localized()) {
                ForEach(uniquePlaces) { marker in
                    Group {
                        if let pick {
                            Button { pick(marker) } label: { MarkerRow(marker: marker, category: guide.category(marker.cat)) }
                        } else {
                            NavigationLink {
                                HajinMapScreen(startAt: marker)
                            } label: {
                                MarkerRow(marker: marker, category: guide.category(marker.cat))
                            }
                        }
                    }
                    .listRowBackground(Color.appSurface)
                }
            }
        }
        ForEach(sections, id: \.0.id) { section, rows in
            Section(section.title.resolved) {
                ForEach(rows, id: \.self) { row in
                    GuideRowView(row: row, highlight: needle)
                        .listRowBackground(Color.appSurface)
                }
            }
        }
        if uniquePlaces.isEmpty && sections.isEmpty {
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
        return section.rows.filter { $0.matches(needle) }
    }

    @EnvironmentObject private var store: HajinStore

    var body: some View {
        ZStack {
            AppBackground(accent: .accentDMZ)
            if section.id == "traits", query.isEmpty, let trees = store.guide?.traitTrees {
                HajinTraitsView(trees: trees)
            } else {
                rowList
            }
        }
        .searchable(text: $query, prompt: "mw4.ui.hajin.search_section".localized())
        .navigationTitle(section.title.resolved)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var rowList: some View {
            List {
                if let intro = section.intro, query.isEmpty {
                    Text(intro.resolved)
                        .font(.subheadline)
                        .foregroundStyle(Color.appInkMuted)
                        .listRowBackground(Color.clear)
                }
                GroupedGuideRows(rows: rows, highlight: query.lowercased())
                if rows.isEmpty {
                    Text("mw4.ui.hajin.no_results".localized())
                        .foregroundStyle(Color.appInkMuted)
                        .listRowBackground(Color.clear)
                }
            }
            .scrollContentBackground(.hidden)
            .listStyle(.insetGrouped)
    }
}

/// A section's rows, under headings when they carry a `group`.
struct GroupedGuideRows: View {
    let rows: [HajinGuide.Row]
    var highlight = ""

    private var groups: [(title: String?, rows: [HajinGuide.Row])] {
        var out: [(title: String?, rows: [HajinGuide.Row])] = []
        for row in rows {
            let title = row.group?.resolved
            if let last = out.indices.last, out[last].title == title {
                out[last].rows.append(row)
            } else {
                out.append((title, [row]))
            }
        }
        return out
    }

    var body: some View {
        ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
            Section {
                ForEach(group.rows, id: \.self) { row in
                    GuideRowView(row: row, highlight: highlight)
                        .listRowBackground(Color.appSurface)
                }
            } header: {
                if let title = group.title { Text(title) }
            }
        }
    }
}

struct GuideRowView: View {
    let row: HajinGuide.Row
    var highlight = ""
    @EnvironmentObject private var store: HajinStore

    private var unconfirmed: Bool { row.subtitle?.values["en"]?.contains("not confirmed") ?? false }

    var body: some View {
        if let id = row.item, let item = store.guide?.item(id) {
            HajinItemRow(item: item, row: row)
        } else if let weaponId = row.weapon {
            HajinWeaponRow(row: row, weaponId: weaponId)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                plainRow
                if let links = row.links, !links.isEmpty { HajinLinkChips(ids: links) }
            }
        }
    }

    private var plainRow: some View {
        HStack(alignment: .top, spacing: 12) {
            if let key = row.check {
                let done = store.checked.contains(key)
                Button {
                    Haptics.step()
                    store.toggle(key)
                } label: {
                    Image(systemName: done ? "checkmark.square.fill" : "square")
                        .font(.title2)
                        .foregroundStyle(done ? Color.accentDMZ : Color.appInkMuted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(row.title.resolved)
                .accessibilityAddTraits(done ? .isSelected : [])
            }
            if let image = row.image, let url = URL(string: image) {
                AsyncImage(url: url) { phase in
                    if let picture = phase.image {
                        picture.resizable().scaledToFit()
                    } else {
                        Color.clear
                    }
                }
                .frame(width: 44, height: 44)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.appSurface2))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
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
                        .foregroundStyle(unconfirmed ? Color.appInkMuted.opacity(0.7) : Color.appInkMuted)
                        .italic(unconfirmed)
                }
            }
        }
        .padding(.vertical, 3)
    }
}

// MARK: - Map

/// The live map with its pins, hint and pin editor. On iPhone it fills its
/// own screen and shows details in a sheet; on iPad (`inline`) it sits in
/// the Hajin tab itself with filter chips along the top and the tapped
/// marker's details in a card over the map.
struct HajinMapPane: View {
    @Binding var selection: HajinSelection?
    @Binding var focus: HajinMapView.Focus?
    var inline = false
    var startAt: HajinGuide.Marker? = nil

    @EnvironmentObject private var store: HajinStore
    @State private var image: UIImage?
    @State private var newPin: HajinPin?

    var body: some View {
        ZStack(alignment: .top) {
            Color.appBackground
            if let guide = store.guide, let image {
                HajinMapView(
                    guide: guide, image: image, hidden: store.hiddenCategories, pins: store.pins,
                    selection: selection, focus: focus,
                    onSelect: { selection = $0 },
                    onLongPress: { point in
                        newPin = HajinPin(x: point.x, y: point.y, title: "", note: "")
                    }
                )

                // iPhone: top right, clear of the tab bar; iPad: bottom right,
                // clear of the filter chips and the marker card
                ThreatLegend(guide: guide)
                    .padding(10)
                    .padding(.top, inline ? 0 : 36)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: inline ? .bottomTrailing : .topTrailing)
                    .allowsHitTesting(false)

                VStack(spacing: 8) {
                    if inline { FilterChips(guide: guide) }
                    Text("mw4.ui.hajin.long_press_hint".localized())
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(.black.opacity(0.55)))
                        .allowsHitTesting(false)
                }
                .padding(.top, 8)

                if inline, let selected = selection {
                    SelectionCard(selection: selected) { selection = nil }
                        .id(selected.id)
                        .frame(maxWidth: 400)
                        .padding(12)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            } else {
                ProgressView().tint(.white).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .animation(.snappy(duration: 0.25), value: selection)
        .clipped()
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
                store.reveal(startAt)
                selection = .marker(startAt)
                focus = .init(point: CGPoint(x: startAt.x, y: startAt.y), token: 1)
            }
        }
        .sheet(item: $newPin) { pin in
            PinEditor(pin: pin, isNew: true) { saved in
                if let saved { store.pins.append(saved) }
                newPin = nil
            }
        }
    }
}

/// iPhone: the map on its own screen, details in a sheet.
struct HajinMapScreen: View {
    var startAt: HajinGuide.Marker? = nil

    @EnvironmentObject private var store: HajinStore
    @State private var selection: HajinSelection?
    @State private var focus: HajinMapView.Focus?
    @State private var showFilters = false
    @State private var showSearch = false

    var body: some View {
        HajinMapPane(selection: $selection, focus: $focus, startAt: startAt)
            .ignoresSafeArea(edges: .bottom)
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
            .sheet(item: $selection) { selected in
                SelectionSheet(selection: selected) { selection = nil }
                    .presentationDetents([.fraction(0.32), .large])
                    .presentationDragIndicator(.visible)
                    .mapStaysUsable()
            }
            .sheet(isPresented: $showFilters) {
                FilterSheet()
                    .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showSearch) {
                MapSearchSheet { marker in
                    showSearch = false
                    store.reveal(marker)
                    selection = .marker(marker)
                    focus = .init(point: CGPoint(x: marker.x, y: marker.y), token: (focus?.token ?? 0) + 1)
                }
            }
    }
}

/// iPad: the map and the guide side by side in landscape, stacked in
/// portrait. Picking a place in the guide flies the map to it.
struct HajinWideLayout: View {
    @EnvironmentObject private var store: HajinStore
    @State private var selection: HajinSelection?
    @State private var focus: HajinMapView.Focus?

    var body: some View {
        GeometryReader { geo in
            let map = HajinMapPane(selection: $selection, focus: $focus, inline: true)
            let panel = HajinGuidePanel(pick: fly(to:)).environment(\.hajinShowMarker, fly(to:))
            if geo.size.width > geo.size.height {
                HStack(spacing: 0) {
                    map
                    Rectangle().fill(Color.appInkMuted.opacity(0.15)).frame(width: 1)
                    panel.frame(width: 380)
                }
            } else {
                VStack(spacing: 0) {
                    map.frame(height: geo.size.height * 0.6)
                    Rectangle().fill(Color.appInkMuted.opacity(0.15)).frame(height: 1)
                    panel
                }
            }
        }
    }

    private func fly(to marker: HajinGuide.Marker) {
        store.reveal(marker)
        selection = .marker(marker)
        focus = .init(point: CGPoint(x: marker.x, y: marker.y), token: (focus?.token ?? 0) + 1)
    }
}

/// One tap per category along the top of the iPad map.
private struct FilterChips: View {
    let guide: HajinGuide
    @EnvironmentObject private var store: HajinStore

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(guide.categories) { category in
                    let on = !store.hiddenCategories.contains(category.id)
                    Button {
                        Haptics.step()
                        var hidden = store.hiddenCategories
                        if on { hidden.insert(category.id) } else { hidden.remove(category.id) }
                        store.hiddenCategories = hidden
                    } label: {
                        Label(category.name.resolved, systemImage: category.symbol)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(on ? category.tint : Color.appInkMuted)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                Capsule().fill(Color.black.opacity(on ? 0.72 : 0.5))
                                    .overlay(Capsule().strokeBorder(on ? category.tint.opacity(0.7) : Color.white.opacity(0.12), lineWidth: 1))
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            .padding(.horizontal, 12)
        }
    }
}

/// The tapped marker or pin, in a card over the iPad map.
private struct SelectionCard: View {
    let selection: HajinSelection
    let dismiss: () -> Void

    var body: some View {
        ScrollView {
            SelectionDetails(selection: selection, dismiss: dismiss)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .padding(.trailing, 24)
        }
        .frame(maxHeight: 300)
        .fixedSize(horizontal: false, vertical: true)
        .background(
            RoundedRectangle(cornerRadius: 16).fill(Color.appSurface.opacity(0.97))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.appInkMuted.opacity(0.25), lineWidth: 1))
                .shadow(color: .black.opacity(0.5), radius: 12, y: 4)
        )
        .overlay(alignment: .topTrailing) {
            Button(action: dismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.appInkMuted)
            }
            .padding(10)
            .accessibilityLabel("mw4.ui.hajin.done".localized())
        }
    }
}

/// The guide beside (landscape) or under (portrait) the iPad map: search,
/// then the sections, each opening in place.
struct HajinGuidePanel: View {
    let pick: (HajinGuide.Marker) -> Void
    @EnvironmentObject private var store: HajinStore
    @State private var query = ""
    @State private var stack: [Page] = []

    private enum Page: Hashable {
        case section(HajinGuide.Section)
        case item(String)
    }

    private var open: HajinGuide.Section? {
        if case .section(let section) = stack.last { return section }
        return nil
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                if let page = stack.last {
                    Button { withAnimation(.snappy) { _ = stack.popLast(); query = "" } } label: {
                        Image(systemName: "chevron.left").font(.body.weight(.semibold))
                    }
                    .accessibilityLabel("mw4.ui.hajin.guide".localized())
                    Text(title(page)).font(.headline).foregroundStyle(Color.appInk).lineLimit(1)
                } else {
                    Text("mw4.ui.hajin.guide".localized()).font(.headline).foregroundStyle(Color.appInk)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)

            if case .item(let id) = stack.last {
                HajinItemView(id: id)
                    .id(id)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(Color.appInkMuted)
                TextField(open == nil ? "mw4.ui.hajin.search_guide".localized() : "mw4.ui.hajin.search_section".localized(), text: $query)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Color.appInkMuted) }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.appSurface2))
            .padding(.horizontal, 12)
            .padding(.bottom, 6)

            if let guide = store.guide, let section = open, section.id == "traits", query.isEmpty, let trees = guide.traitTrees {
                HajinTraitsView(trees: trees)
            } else if let guide = store.guide {
                List {
                    if let section = open {
                        sectionRows(section)
                    } else if !query.isEmpty {
                        GuideSearchResults(guide: guide, query: query, pick: pick)
                    } else {
                        NavigationLink { HajinKeepSellView() } label: { HajinKeepSellRow() }
                            .listRowBackground(Color.appSurface)
                        ForEach(guide.guide) { section in
                            Button { withAnimation(.snappy) { stack = [.section(section)] } } label: {
                                HStack {
                                    SectionRow(section: section)
                                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Color.appInkMuted)
                                }
                            }
                            .listRowBackground(Color.appSurface)
                        }
                        GuideFooter(guide: guide)
                            .listRowBackground(Color.clear)
                    }
                }
                .scrollContentBackground(.hidden)
                .listStyle(.insetGrouped)
            }
            }
        }
        .background(Color.appBackground)
        .environment(\.hajinOpenItem) { id in withAnimation(.snappy) { stack.append(.item(id)) } }
    }

    private func title(_ page: Page) -> String {
        switch page {
        case .section(let section): return section.title.resolved
        case .item(let id): return store.guide?.item(id)?.name.resolved ?? ""
        }
    }

    @ViewBuilder private func sectionRows(_ section: HajinGuide.Section) -> some View {
        let needle = query.lowercased()
        let rows = needle.isEmpty ? section.rows : section.rows.filter { $0.matches(needle) }
        if let intro = section.intro, needle.isEmpty {
            Text(intro.resolved).font(.subheadline).foregroundStyle(Color.appInkMuted).listRowBackground(Color.clear)
        }
        GroupedGuideRows(rows: rows)
        if rows.isEmpty {
            Text("mw4.ui.hajin.no_results".localized()).foregroundStyle(Color.appInkMuted).listRowBackground(Color.clear)
        }
    }
}

/// What's shown when a marker or pin is tapped (iPhone).
private struct SelectionSheet: View {
    let selection: HajinSelection
    let dismiss: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                SelectionDetails(selection: selection, dismiss: dismiss)
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
    }
}

/// A marker's name, threat and write-up, or a pin's note with edit and
/// delete. Shared by the iPhone sheet and the iPad card.
private struct SelectionDetails: View {
    let selection: HajinSelection
    let dismiss: () -> Void
    @EnvironmentObject private var store: HajinStore
    @State private var editing: HajinPin?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch selection {
            case .marker(let marker): markerBody(marker)
            case .pin(let id):
                if let pin = store.pins.first(where: { $0.id == id }) { pinBody(pin) }
            }
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

/// The threat colours the map's area names use, Low to Extreme.
private struct ThreatLegend: View {
    let guide: HajinGuide

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("mw4.ui.hajin.threat_legend".localized().uppercased())
                .font(.system(size: 9, weight: .heavy))
                .tracking(0.8)
                .foregroundStyle(.white.opacity(0.7))
            ForEach(Array(guide.threatLevels.enumerated()), id: \.offset) { index, level in
                HStack(spacing: 5) {
                    Circle().fill(HajinThreat.color(index + 1)).frame(width: 7, height: 7)
                    Text(level.resolved).font(.system(size: 10, weight: .semibold)).foregroundStyle(.white.opacity(0.9))
                }
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(.black.opacity(0.6)))
    }
}
