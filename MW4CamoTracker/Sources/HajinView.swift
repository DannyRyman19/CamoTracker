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
    @AppStorage(HajinPage.key) private var page = HajinPage.guide.rawValue
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
                HajinPagePicker(page: $page)
                if page == HajinPage.mine.rawValue {
                    HajinMinePage()
                } else {
                Button { showsMap = true } label: {
                    MapHeroCard(guide: guide, pinCount: store.pins.count)
                }
                .buttonStyle(.plain)
                .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                ForEach(guide.guide) { section in
                    NavigationLink {
                        GuideSectionView(section: section)
                    } label: {
                        SectionRow(section: section)
                    }
                    .hajinCard()
                }
                GuideFooter(guide: guide)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            } else {
                GuideSearchResults(guide: guide, query: query, pick: nil)
            }
        }
        .scrollContentBackground(.hidden)
        .listStyle(.plain)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "mw4.ui.hajin.search_guide".localized())
    }

    /// `SS_HAJIN=map` or `SS_HAJIN=<section id>` opens that screen for the
    /// screenshot harness. DEBUG-only.
    private func openScreenshotTarget() {
        #if DEBUG
        // SS_STASH=id=count,id=count fills the stash for screenshots
        for pair in (ProcessInfo.processInfo.environment["SS_STASH"] ?? "").split(separator: ",") {
            let parts = pair.split(separator: "=")
            if parts.count == 2, let n = Int(parts[1]) { store.setCount(n, of: String(parts[0])) }
        }
        if let spend = ProcessInfo.processInfo.environment["SS_SPEND"] { store.toggle("upgrade-\(spend)") }
        guard let target = ProcessInfo.processInfo.environment["SS_HAJIN"], !target.isEmpty else { return }
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
            HajinHeading(title: "mw4.ui.hajin.map".localized())
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
                    .hajinCard()
                }
        }
        ForEach(sections, id: \.0.id) { section, rows in
            HajinHeading(title: section.title.resolved)
            ForEach(rows, id: \.self) { row in
                GuideRowView(row: row, highlight: needle)
                    .hajinCard()
            }
        }
        if uniquePlaces.isEmpty && sections.isEmpty {
            Text("mw4.ui.hajin.no_results".localized())
                .foregroundStyle(Color.appInkMuted)
                .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
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
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(Circle().fill(Color.accentDMZ))
            Text(section.title.resolved)
                .font(.hitmarker(16))
                .foregroundStyle(Color.appInk)
            Spacer()
            Text("\(section.rows.count)")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.appInkMuted)
        }
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
    @State private var width: CGFloat = 0

    var body: some View {
        ZStack {
            AppBackground(accent: .accentDMZ)
            if section.id == "traits", query.isEmpty, let trees = store.guide?.traitTrees {
                HajinTraitsView(trees: trees)
            } else if width >= 700, !rows.isEmpty {
                HajinRowColumns(rows: hajinCollapseTiers(rows, store.guide), intro: query.isEmpty ? section.intro?.resolved : nil, highlight: query.lowercased())
            } else {
                rowList
            }
        }
        .readingWidth($width)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "mw4.ui.hajin.search_section".localized())
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
                        .listRowSeparator(.hidden)
                }
                GroupedGuideRows(rows: hajinCollapseTiers(rows, store.guide), highlight: query.lowercased())
                if rows.isEmpty {
                    Text("mw4.ui.hajin.no_results".localized())
                        .foregroundStyle(Color.appInkMuted)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            }
            .scrollContentBackground(.hidden)
            .listStyle(.plain)
    }
}

/// The Hajin tab's two halves: the reference guide, and the player's own
/// plan (level, tracking, what to build, stash, keep or sell).
enum HajinPage: String, CaseIterable {
    case guide, mine
    static let key = "mw4_hajin_page"
    var title: String { self == .guide ? "mw4.ui.hajin.page_guide".localized() : "mw4.ui.hajin.page_mine".localized() }
}

struct HajinPagePicker: View {
    @Binding var page: String

    var body: some View {
        Picker("", selection: Binding(get: { page }, set: { if $0 != page { Haptics.step() }; page = $0 })) {
            ForEach(HajinPage.allCases, id: \.rawValue) { Text($0.title).tag($0.rawValue) }
        }
        .pickerStyle(.segmented)
        .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }
}

/// The player's own cards, in the order they're used: level, what's
/// tracked, what to build next, the stash, and keep or sell.
struct HajinMinePage: View {
    /// iPad: open these inside the guide panel instead of pushing them.
    var openStash: (() -> Void)? = nil
    var openKeepSell: (() -> Void)? = nil
    var openShopping: (() -> Void)? = nil

    var body: some View {
        HajinLevelCard().hajinCard()
        HajinTrackingCard().hajinCard()
        HajinBuildNextCard().hajinCard()
        entry(openShopping) { HajinShoppingListView() } label: { HajinShoppingEntry() }
        entry(openStash) { HajinStashView() } label: { HajinStashEntry() }
        entry(openKeepSell) { HajinKeepSellView() } label: { HajinKeepSellEntry() }
    }

    @ViewBuilder private func entry<D: View, L: View>(_ open: (() -> Void)?, @ViewBuilder destination: () -> D, @ViewBuilder label: () -> L) -> some View {
        if let open {
            Button(action: open) {
                HStack {
                    label()
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Color.appInkMuted)
                }
            }
            .buttonStyle(.plain)
            .hajinCard()
        } else {
            NavigationLink(destination: destination, label: label).hajinCard()
        }
    }
}

/// One row per upgrade family: later tiers live in the first tier's tabs.
func hajinCollapseTiers(_ rows: [HajinGuide.Row], _ guide: HajinGuide?) -> [HajinGuide.Row] {
    var seen = Set<String>()
    return rows.filter { row in
        guard let id = row.item, let item = guide?.item(id), let family = item.family,
              (guide?.tiers(of: item).count ?? 0) > 1 else { return true }
        return seen.insert(family).inserted
    }
}

/// Consecutive rows that share a `group`, in order.
func hajinGroups(_ rows: [HajinGuide.Row]) -> [(title: String?, rows: [HajinGuide.Row])] {
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

/// Wide screens: a section's rows as cards in two columns, under the same
/// group headings, instead of one stretched list.
struct HajinRowColumns: View {
    @EnvironmentObject private var store: HajinStore
    let rows: [HajinGuide.Row]
    var intro: String? = nil
    var highlight = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let intro {
                    Text(intro).font(.subheadline).foregroundStyle(Color.appInkMuted)
                        .frame(maxWidth: 720, alignment: .leading)
                }
                ForEach(Array(hajinGroups(rows).enumerated()), id: \.offset) { _, group in
                    VStack(alignment: .leading, spacing: 8) {
                        if let title = group.title {
                            Text(title.uppercased())
                                .font(.caption.weight(.heavy))
                                .tracking(1.2)
                                .foregroundStyle(Color.appInkMuted)
                        }
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12, alignment: .top), GridItem(.flexible(), spacing: 12, alignment: .top)],
                                  alignment: .leading, spacing: 12) {
                            ForEach(group.rows, id: \.self) { row in
                                GuideRowView(row: row, highlight: highlight)
                                    .padding(12)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                                    .borderedCard(accent: store.printableAccent(row))
                            }
                        }
                    }
                }
            }
            .padding(16)
        }
    }
}

/// A section's rows, under headings when they carry a `group`.
struct GroupedGuideRows: View {
    let rows: [HajinGuide.Row]
    var highlight = ""
    @EnvironmentObject private var store: HajinStore

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
            if let title = group.title { HajinHeading(title: title) }
            ForEach(group.rows, id: \.self) { row in
                GuideRowView(row: row, highlight: highlight)
                    .hajinCard(accent: store.printableAccent(row))
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
        if let id = row.item, let item = store.guide?.item(id), let tiers = store.guide?.tiers(of: item), tiers.count > 1 {
            HajinUpgradeFamilyCard(tiers: tiers)
        } else if let id = row.item, let item = store.guide?.item(id) {
            HajinItemRow(item: item, row: row)
        } else if row.objectives != nil || row.cash != nil || row.rewards != nil || row.place != nil {
            HajinMissionRow(row: row)
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
                HajinTick(done: store.checked.contains(key), label: row.title.resolved) { store.toggle(key) }
            } else if let level = row.level, store.dmzLevel > 0 {
                // Level unlocks tick themselves up to the player's level
                Image(systemName: level <= store.dmzLevel ? "checkmark.circle.fill" : "lock.fill")
                    .font(.system(size: level <= store.dmzLevel ? 21 : 16))
                    .foregroundStyle(level <= store.dmzLevel ? Color.accentDMZ : Color.appInkMuted.opacity(0.6))
                    .frame(width: 24, height: 24)
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
                        .font(.hitmarker(15))
                        .foregroundStyle(Color.appInk)
                    Spacer(minLength: 8)
                    if let value = row.value { HajinValueBadge(text: value.resolved, locked: store.isLocked(row.requiredLevel)) }
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
                    .padding(.top, inline ? 0 : 46)
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
    @State private var panelWidth: CGFloat = 0
    @AppStorage(HajinPage.key) private var page = HajinPage.guide.rawValue

    private enum Page: Hashable {
        case section(HajinGuide.Section)
        case item(String)
        case stash
        case keepSell
        case shopping
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
                TextField(stack.isEmpty ? "mw4.ui.hajin.search_guide".localized() : "mw4.ui.hajin.search_section".localized(), text: $query)
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

            if stack.last == .stash {
                HajinStashView(embeddedQuery: query)
            } else if stack.last == .keepSell {
                HajinKeepSellView(embeddedQuery: query)
            } else if stack.last == .shopping {
                HajinShoppingListView(embeddedQuery: query)
            } else if let guide = store.guide, let section = open, section.id == "traits", query.isEmpty, let trees = guide.traitTrees {
                HajinTraitsView(trees: trees)
            } else if let section = open, panelWidth >= 700 {
                let needle = query.lowercased()
                HajinRowColumns(rows: hajinCollapseTiers(needle.isEmpty ? section.rows : section.rows.filter { $0.matches(needle) }, store.guide),
                                intro: needle.isEmpty ? section.intro?.resolved : nil, highlight: needle)
            } else if let guide = store.guide {
                List {
                    if let section = open {
                        sectionRows(section)
                    } else if !query.isEmpty {
                        GuideSearchResults(guide: guide, query: query, pick: pick)
                    } else {
                        HajinPagePicker(page: $page)
                        if page == HajinPage.mine.rawValue {
                            HajinMinePage(openStash: { withAnimation(.snappy) { stack = [.stash]; query = "" } },
                                          openKeepSell: { withAnimation(.snappy) { stack = [.keepSell]; query = "" } },
                                          openShopping: { withAnimation(.snappy) { stack = [.shopping]; query = "" } })
                        } else {
                        ForEach(guide.guide) { section in
                            Button { withAnimation(.snappy) { stack = [.section(section)] } } label: {
                                HStack {
                                    SectionRow(section: section)
                                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Color.appInkMuted)
                                }
                            }
                            .hajinCard()
                        }
                        GuideFooter(guide: guide)
                            .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        }
                    }
                }
                .scrollContentBackground(.hidden)
                .listStyle(.plain)
            }
            }
        }
        .background(Color.appBackground)
        .readingWidth($panelWidth)
        .environment(\.hajinOpenItem) { id in withAnimation(.snappy) { stack.append(.item(id)) } }
        #if DEBUG
        // SS_PANEL=stash, keep or shop opens that page in the panel for screenshots
        .onAppear {
            switch ProcessInfo.processInfo.environment["SS_PANEL"] {
            case "stash": stack = [.stash]
            case "keep": stack = [.keepSell]
            case "shop": stack = [.shopping]
            default: break
            }
        }
        #endif
    }

    private func title(_ page: Page) -> String {
        switch page {
        case .section(let section): return section.title.resolved
        case .item(let id): return store.guide?.item(id)?.name.resolved ?? ""
        case .stash: return "mw4.ui.hajin.stash".localized()
        case .keepSell: return "mw4.ui.keep.title".localized()
        case .shopping: return "mw4.ui.hajin.shop".localized()
        }
    }

    @ViewBuilder private func sectionRows(_ section: HajinGuide.Section) -> some View {
        let needle = query.lowercased()
        let rows = hajinCollapseTiers(needle.isEmpty ? section.rows : section.rows.filter { $0.matches(needle) }, store.guide)
        if let intro = section.intro, needle.isEmpty {
            Text(intro.resolved).font(.subheadline).foregroundStyle(Color.appInkMuted).listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
        }
        GroupedGuideRows(rows: rows)
        if rows.isEmpty {
            Text("mw4.ui.hajin.no_results".localized()).foregroundStyle(Color.appInkMuted).listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
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
        if let parts = marker.parts, !parts.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("mw4.ui.hajin.inside".localized().uppercased())
                    .font(.caption.weight(.heavy))
                    .tracking(1.2)
                    .foregroundStyle(Color.appInkMuted)
                HajinWrap(spacing: 6) {
                    ForEach(parts, id: \.self) { part in
                        let tint = part.threat.map(HajinThreat.color) ?? Color.appInkMuted
                        HStack(spacing: 5) {
                            Circle().fill(tint).frame(width: 7, height: 7)
                            Text(part.name.resolved).font(.caption.weight(.semibold)).foregroundStyle(Color.appInk)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.appSurface2).overlay(Capsule().strokeBorder(tint.opacity(0.5), lineWidth: 1)))
                    }
                }
            }
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

/// A group heading that scrolls with the cards, in the app's bold style.
struct HajinHeading: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.title3.weight(.bold))
            .foregroundStyle(Color.appInk)
            .listRowInsets(EdgeInsets(top: 18, leading: 16, bottom: 4, trailing: 16))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }
}

/// The player's DMZ level, stepped like Weapon Level on a weapon. Set it
/// and the guide shows what's unlocked and what's still locked.
struct HajinLevelCard: View {
    @EnvironmentObject private var store: HajinStore
    @State private var entering = false
    @State private var text = ""

    var body: some View {
        let level = store.dmzLevel
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text("mw4.ui.hajin.dmz_level".localized())
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.appInkMuted)
                Spacer(minLength: 4)
                stepButton(systemName: "minus", enabled: level > 0, size: 26, accent: .accentDMZ) { store.setLevel(level - 1) }
                Button {
                    text = level > 0 ? "\(level)" : ""
                    entering = true
                } label: {
                    Text(level > 0 ? "\(level)/\(HajinStore.maxLevel)" : "–/\(HajinStore.maxLevel)")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.accentDMZ)
                        .contentTransition(.numericText())
                        .frame(minWidth: 56)
                }
                .buttonStyle(.borderless)
                stepButton(systemName: "plus", enabled: level < HajinStore.maxLevel, size: 26, accent: .accentDMZ) { store.setLevel(level + 1) }
            }
            ProgressBar(fraction: Double(level) / Double(HajinStore.maxLevel), accent: .accentDMZ)
            Text(level > 0 ? "mw4.ui.hajin.dmz_level_set".localized() : "mw4.ui.hajin.dmz_level_hint".localized())
                .font(.caption)
                .foregroundStyle(Color.appInkMuted)
        }
        .alert("mw4.ui.hajin.dmz_level".localized(), isPresented: $entering) {
            TextField("1–\(HajinStore.maxLevel)", text: $text).keyboardType(.numberPad)
            Button("mw4.ui.hajin.save".localized()) { if let n = Int(text) { store.setLevel(n) } }
            Button("mw4.ui.hajin.cancel".localized(), role: .cancel) {}
        }
    }
}

/// A mission, order or op: tick, where it is, its steps (each tickable),
/// and its rewards as cash, linked items and unlocks.
struct HajinMissionRow: View {
    let row: HajinGuide.Row
    @EnvironmentObject private var store: HajinStore

    private var key: String { row.check ?? "op-\(row.title.resolved)" }

    var body: some View {
        let done = store.checked.contains(key)
        let objectives = row.objectives ?? []
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                HajinTick(done: done, label: row.title.resolved) { store.toggle(key) }
                VStack(alignment: .leading, spacing: 3) {
                    Text(row.title.resolved)
                        .font(.hitmarker(15))
                        .foregroundStyle(Color.appInk)
                    if let place = row.place {
                        Label(place.resolved, systemImage: "mappin.and.ellipse")
                            .font(.caption)
                            .foregroundStyle(Color.appInkMuted)
                    } else if let subtitle = row.subtitle {
                        Text(subtitle.resolved).font(.caption).italic().foregroundStyle(Color.appInkMuted.opacity(0.8))
                    }
                }
                Spacer(minLength: 0)
                if !objectives.isEmpty {
                    let stepsDone = objectives.indices.filter { done || store.checked.contains("\(key)#\($0)") }.count
                    Text("\(stepsDone)/\(objectives.count)")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(stepsDone == objectives.count ? Color.accentDMZ : Color.appInkMuted)
                }
            }
            if !objectives.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(objectives.enumerated()), id: \.offset) { index, objective in
                        let stepKey = "\(key)#\(index)"
                        let stepDone = done || store.checked.contains(stepKey)
                        Button {
                            Haptics.step()
                            store.toggle(stepKey)
                        } label: {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Image(systemName: stepDone ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 14))
                                    .foregroundStyle(stepDone ? Color.accentDMZ : Color.appInkMuted)
                                Text(objective.resolved)
                                    .font(.subheadline)
                                    .foregroundStyle(stepDone ? Color.appInkMuted : Color.appInk)
                                    .strikethrough(stepDone, color: Color.appInkMuted)
                                    .multilineTextAlignment(.leading)
                                Spacer(minLength: 0)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.borderless)
                        .disabled(done)
                    }
                }
                .padding(.leading, 36)
            }
            let items = row.links ?? []
            let other = row.rewards ?? []
            if row.cash != nil || !items.isEmpty || !other.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("mw4.ui.hajin.rewards".localized().uppercased())
                        .font(.system(size: 11, weight: .bold))
                        .tracking(0.8)
                        .foregroundStyle(Color.appInkMuted)
                    HajinWrap(spacing: 6) {
                        if let cash = row.cash {
                            HajinValueBadge(text: "$\(cash.formatted())")
                        }
                        ForEach(other.indices, id: \.self) { i in
                            HajinValueBadge(text: other[i].resolved)
                        }
                    }
                    if !items.isEmpty { HajinLinkChips(ids: items) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 36)
            }
        }
        .opacity(done ? 0.75 : 1)
    }
}
