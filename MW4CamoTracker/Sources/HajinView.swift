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
    @State private var showsStash = false
    @State private var showsBlueprints = false
    @AppStorage(HajinPage.key) private var page = HajinPage.mine.rawValue
    @State private var width: CGFloat = 0

    private var accent: Color { .accentDMZ }

    var body: some View {
        ZStack {
            AppBackground(accent: accent)
            if let guide = store.guide {
                if width >= 700 {
                    // iPad: the map is the page, the guide beside or under it,
                    // and the banner along the foot of both
                    HajinWideLayout()
                        .safeAreaInset(edge: .bottom, spacing: 0) { AdBanner() }
                } else {
                    phoneList(guide)
                        .safeAreaInset(edge: .bottom, spacing: 0) { AdBanner() }
                }
            }
        }
        .readingWidth($width)
        .toolbar {
            // iPad: in the guide panel's header instead
            if width < 700 { ToolbarItem(placement: .topBarTrailing) { HajinNumbersChip() } }
        }
        .navigationTitle("mw4.ui.hajin.title".localized())
        .navigationBarTitleDisplayMode(width >= 700 ? .inline : .automatic)
        .navigationDestination(isPresented: $showsMap) { HajinMapScreen() }
        .navigationDestination(isPresented: $showsKeepSell) { HajinKeepSellView() }
        .navigationDestination(isPresented: $showsStash) { HajinStashView() }
        .navigationDestination(isPresented: $showsBlueprints) { HajinBlueprintsView() }
        .navigationDestination(isPresented: Binding(get: { shownSection != nil }, set: { if !$0 { shownSection = nil } })) {
            if let shownSection { GuideSectionView(section: shownSection) }
        }
        .navigationDestination(isPresented: Binding(get: { shownItem != nil }, set: { if !$0 { shownItem = nil } })) {
            if let shownItem { HajinItemView(id: shownItem) }
        }
        .onAppear(perform: openScreenshotTarget)
        #if DEBUG
        .onReceive(NotificationCenter.default.publisher(for: .hajinDemoOpenStash)) { _ in showsStash = true }
        #endif
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
                HajinGuideTiles(sections: guide.guide.filter { !HajinGuide.trackedSections.contains($0.id) })
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
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "mw4.ui.hajin.search_guide".localized())
    }

    /// `SS_HAJIN=map`, `keep`, `stash` or `<section id>` opens that screen for the
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
        } else if target == "stash" {
            showsStash = true
        } else if target == "blueprints" {
            showsBlueprints = true
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
                    if let pick {
                        Button { pick(marker) } label: { MarkerRow(marker: marker, category: guide.category(marker.cat)) }
                            .hajinCardButton()
                    } else {
                        NavigationLink {
                            HajinMapScreen(startAt: marker)
                        } label: {
                            MarkerRow(marker: marker, category: guide.category(marker.cat))
                        }
                        .hajinCard()
                    }
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
    /// How many of its rows are ticked, for the sections My DMZ tracks.
    var done: Int? = nil
    var total: Int? = nil

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
            let total = total ?? section.rows.count
            Text(done.map { "\($0)/\(total)" } ?? "\(total)")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(done == total ? Color.accentDMZ : Color.appInkMuted)
        }
    }
}

struct MarkerRow: View {
    let marker: HajinGuide.Marker
    let category: HajinGuide.Category?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: marker.symbol ?? category?.symbol ?? "mappin")
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
            if section.id == "prestige" {
                List {
                    HajinPrestigeTracker()
                    GroupedGuideRows(rows: rows, highlight: query.lowercased())
                }
                .scrollContentBackground(.hidden)
                .listStyle(.plain)
            } else if section.id == "ops" {
                List {
                    if let intro = section.intro, query.isEmpty {
                        Text(intro.resolved).font(.subheadline).foregroundStyle(Color.appInkMuted)
                            .listRowBackground(Color.clear).listRowSeparator(.hidden)
                    }
                    HajinOrdersList(rows: rows)
                }
                .scrollContentBackground(.hidden)
                .listStyle(.plain)
            } else if width >= 700, !rows.isEmpty {
                HajinRowColumns(rows: hajinCollapseTiers(rows, store.guide), intro: query.isEmpty ? section.intro?.resolved : nil, highlight: query.lowercased())
            } else {
                rowList
            }
        }
        .readingWidth($width)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "mw4.ui.hajin.search_section".localized())
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HajinReportMenu(lines: ["Section: \(section.title.values["en"] ?? section.title.resolved)", "Section ID: \(section.id)"])
            }
        }
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
    // My DMZ first: the player's own progress; the guide is the wiki
    case mine, guide
    static let key = "mw4_hajin_page"
    var title: String { self == .guide ? "mw4.ui.hajin.page_guide".localized() : "mw4.ui.hajin.page_mine".localized() }
}

struct HajinPagePicker: View {
    @Binding var page: String

    var body: some View {
        SegmentTabs(selection: $page, items: HajinPage.allCases.map { ($0.rawValue, $0.title) }, accent: .accentDMZ)
        .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }
}

/// The My DMZ page's cards, in the player's order; any can be hidden.
enum HajinMineCard: String, CaseIterable, Identifiable {
    // Default order: the scan, then the player's numbers and plan, then the
    // stash and the tools that work on it
    // (DMZ Level and Cash sit in the title bar, on every page)
    // (weapon manuals are on Recipes & Manuals)
    case scan, postMatch, tracking, buildNext, orders, upgrades, blueprints, bosses, prestige, stash, keepSell, shopping
    var id: String { rawValue }
    var title: String {
        switch self {
        case .scan: return "mw4.ui.hajin.grid_scan".localized()
        case .postMatch: return "mw4.ui.postmatch.card".localized()
        case .tracking: return "mw4.ui.hajin.tracking".localized()
        case .buildNext: return "mw4.ui.hajin.build_next".localized()
        case .shopping: return "mw4.ui.hajin.shop".localized()
        case .blueprints: return "mw4.ui.hajin.blueprints".localized()
        case .stash: return "mw4.ui.hajin.stash".localized()
        case .keepSell: return "mw4.ui.keep.title".localized()
        case .orders: return "mw4.ui.hajin.mine_orders".localized()
        case .upgrades: return "mw4.ui.hajin.mine_upgrades".localized()
        case .bosses: return "mw4.ui.hajin.mine_bosses".localized()
        case .prestige: return "mw4.ui.hajin.mine_prestige".localized()
        }
    }

    /// The guide section a tracking card opens.
    var section: String? {
        switch self {
        case .orders: return "ops"
        case .upgrades: return "upgrades"
        case .bosses: return "bosses"
        case .prestige: return "prestige"
        default: return nil
        }
    }
    var symbol: String {
        switch self {
        case .scan: return "camera.viewfinder"
        case .postMatch: return "bag.fill"
        case .tracking: return "scope"
        case .buildNext: return "hammer.fill"
        case .shopping: return "list.bullet.clipboard.fill"
        case .blueprints: return "doc.text.magnifyingglass"
        case .stash: return "shippingbox.fill"
        case .keepSell: return "arrow.left.arrow.right"
        case .orders: return "checklist"
        case .upgrades: return "building.2.fill"
        case .bosses: return "person.fill.viewfinder"
        case .prestige: return "star.fill"
        }
    }

    static let orderKey = "mw4_hajin_mine_order"
    static let hiddenKey = "mw4_hajin_mine_hidden"
    /// Saved order, with any card added since slotted in after the card
    /// it follows by default.
    static func order(_ raw: String) -> [HajinMineCard] {
        var out = raw.split(separator: ",").compactMap { HajinMineCard(rawValue: String($0)) }
        for (i, card) in allCases.enumerated() where !out.contains(card) {
            let after = i > 0 ? out.firstIndex(of: allCases[i - 1]) : nil
            out.insert(card, at: after.map { $0 + 1 } ?? (i == 0 ? 0 : out.count))
        }
        // "After a match" is read by the one photo reader now, which tells a
        // backpack from the stash by itself (the case stays for saved orders)
        return out.filter { $0 != .postMatch }
    }
}

/// The player's own cards (level, cash, what's tracked, what to build
/// next, the tools), in the order they chose, with a Customise button.
struct HajinMinePage: View {
    @EnvironmentObject private var store: HajinStore
    /// iPad: open these inside the guide panel instead of pushing them.
    var openStash: (() -> Void)? = nil
    var openKeepSell: (() -> Void)? = nil
    var openShopping: (() -> Void)? = nil
    var openBlueprints: (() -> Void)? = nil
    var openSection: ((HajinGuide.Section) -> Void)? = nil
    @AppStorage(HajinMineCard.orderKey) private var orderRaw = ""
    @AppStorage(HajinMineCard.hiddenKey) private var hiddenRaw = ""
    @State private var customising = false
    @ObservedObject private var premium = Premium.shared
    @State private var showsPremium = false
    @Environment(\.hajinPush) private var push

    var body: some View {
        let hidden = Set(hiddenRaw.split(separator: ",").map(String.init))
        let shown = HajinMineCard.order(orderRaw).filter { !hidden.contains($0.rawValue) }
        // The cards in groups, each kept in the player's order: the readers,
        // their numbers, the plan, progress, then the stash tools
        if #available(iOS 17.0, *), shown.contains(.scan) {
            if store.stash.isEmpty {
                // The big card until there's a stash
                HajinStashGridButton(hero: true)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
            } else {
                HajinReaderTile()
            }
        }
        ForEach(shown.filter { [.tracking, .buildNext].contains($0) }) { card in
            if card == .tracking { HajinTrackingCard().hajinCard() } else { HajinBuildNextCard().hajinCard() }
        }
        let progress = shown.filter { $0.section != nil || $0 == .blueprints }
        if !progress.isEmpty {
            HajinHeading(title: "mw4.ui.hajin.mine_progress".localized())
            // Two a row; an odd one out takes the full width
            let paired = progress.count.isMultiple(of: 2) ? progress : Array(progress.dropLast())
            VStack(spacing: 10) {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(paired) { progressTile($0) }
                }
                if paired.count < progress.count, let last = progress.last { progressTile(last, wide: true) }
            }
            .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
        let tools = shown.filter { [.stash, .keepSell, .shopping].contains($0) }
        if !tools.isEmpty {
            VStack(spacing: 0) {
                ForEach(Array(tools.enumerated()), id: \.element) { i, card in
                    if i > 0 { Divider().overlay(Color.appSurface2).padding(.leading, 54) }
                    toolRow(card)
                }
            }
            .borderedCard()
            .padding(.top, 10)
            .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
        // Free players: what Premium gets them, under their own cards
        if !premium.isPremium {
            Button { showsPremium = true } label: {
                HStack(spacing: 12) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(Color.accentDMZ))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("mw4.ui.premium.title".localized()).font(.hitmarker(16)).foregroundStyle(Color.appInk)
                        Text("mw4.ui.premium.subtitle".localized()).font(.caption).foregroundStyle(Color.appInkMuted)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Color.appInkMuted)
                }
            }
            .hajinCardButton(accent: .accentDMZ)
            .sheet(isPresented: $showsPremium) { PremiumView() }
        }
        Button { if premium.isPremium { customising = true } else { showsPremium = true } } label: {
            Label("mw4.ui.hajin.mine_customise".localized(), systemImage: premium.isPremium ? "slider.horizontal.3" : "lock.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.accentDMZ)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderless)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .sheet(isPresented: $customising) { HajinMineCustomise(orderRaw: $orderRaw, hiddenRaw: $hiddenRaw) }
    }

    /// A tracked guide section as a tile: its ring, title and x/y.
    @ViewBuilder private func progressTile(_ card: HajinMineCard, wide: Bool = false) -> some View {
        if card == .blueprints {
            let progress = store.findProgress
            open(openBlueprints, .blueprints) { HajinBlueprintsView() } label: {
                HajinProgressTile(title: card.title, symbol: card.symbol,
                                  fraction: Double(progress.found) / Double(max(progress.total, 1)),
                                  count: "\(progress.found)/\(progress.total)", wide: wide)
            }
        } else if let id = card.section, let section = store.guide?.guide.first(where: { $0.id == id }) {
            // A row's tick: its own, or a Gunsmith weapon's manual (starter
            // weapons have none)
            let keys = section.rows.compactMap { row -> String? in
                if let key = row.check { return key }
                if let weapon = row.weapon, !(row.subtitle?.values["en"]?.hasPrefix("Starter") ?? false) { return "manual-\(weapon)" }
                return nil
            }
            let done = keys.filter(store.checked.contains).count
            open(openSection.map { open in { open(section) } }, .section(section.id)) {
                GuideSectionView(section: section)
            } label: {
                HajinProgressTile(title: card.title, symbol: card.symbol,
                                  // Prestige has no ticks: how many operators are tracked
                                  fraction: keys.isEmpty ? nil : Double(done) / Double(max(keys.count, 1)),
                                  count: keys.isEmpty ? "\(store.operators.count)" : "\(done)/\(keys.count)", wide: wide)
            }
        }
    }

    @ViewBuilder private func toolRow(_ card: HajinMineCard) -> some View {
        switch card {
        case .shopping: open(openShopping, .shopping, plain: true) { HajinShoppingListView() } label: { HajinShoppingEntry() }
        case .stash: open(openStash, .stash, plain: true) { HajinStashView() } label: { HajinStashEntry() }
        case .keepSell: open(openKeepSell, .keepSell, plain: true) { HajinKeepSellView() } label: { HajinKeepSellEntry() }
        default: EmptyView()
        }
    }

    /// Opens a screen from a tile or a row in the tools card: the iPad
    /// panel's closure, else pushed by value (iPhone), else a link.
    @ViewBuilder private func open<D: View, L: View>(_ action: (() -> Void)?, _ screen: HajinScreen, plain: Bool = false, @ViewBuilder destination: @escaping () -> D, @ViewBuilder label: @escaping () -> L) -> some View {
        let row = {
            HStack(spacing: 8) {
                label()
                if plain { Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Color.appInkMuted) }
            }
            .padding(plain ? 12 : 0)
            .contentShape(Rectangle())
        }
        if let action = action ?? push.map({ push in { push(screen) } }) {
            Button(action: action, label: row).buttonStyle(HajinPressStyle())
        } else {
            NavigationLink(destination: destination, label: row).buttonStyle(HajinPressStyle())
        }
    }

}

/// A card that opens a screen: pushed by value onto the tab's path where
/// there is one (iPhone), else an ordinary navigation link.
struct HajinPushLink<D: View, L: View>: View {
    let screen: HajinScreen
    @ViewBuilder let destination: () -> D
    @ViewBuilder let label: () -> L
    @Environment(\.hajinPush) private var push

    var body: some View {
        if let push {
            Button { push(screen) } label: {
                HStack {
                    label()
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Color.appInkMuted)
                }
            }
            .hajinCardButton()
        } else {
            NavigationLink(destination: destination, label: label).hajinCard()
        }
    }
}

/// Reorder the My DMZ cards by dragging, and switch any off.
struct HajinMineCustomise: View {
    @Binding var orderRaw: String
    @Binding var hiddenRaw: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let order = HajinMineCard.order(orderRaw)
        let hidden = Set(hiddenRaw.split(separator: ",").map(String.init))
        NavigationStack {
            List {
                Section {
                    ForEach(order) { card in
                        Toggle(isOn: Binding(
                            get: { !hidden.contains(card.rawValue) },
                            set: { on in
                                var h = hidden
                                if on { h.remove(card.rawValue) } else { h.insert(card.rawValue) }
                                hiddenRaw = h.sorted().joined(separator: ",")
                            })) {
                            Label(card.title, systemImage: card.symbol)
                        }
                        .tint(.accentDMZ)
                    }
                    .onMove { from, to in
                        var o = order
                        o.move(fromOffsets: from, toOffset: to)
                        orderRaw = o.map(\.rawValue).joined(separator: ",")
                    }
                } footer: {
                    Text("mw4.ui.hajin.mine_customise_hint".localized())
                }
                Section {
                    Button("mw4.ui.hajin.mine_reset".localized()) { orderRaw = ""; hiddenRaw = "" }
                        .foregroundStyle(Color.accentDMZ)
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("mw4.ui.hajin.mine_customise".localized())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("mw4.ui.hajin.done".localized()) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
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
                CachedAsyncImage(url: url) { phase in
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
    /// iPad portrait: how much of the map's foot the guide covers, to keep
    /// the legend and the marker card above it.
    var bottomInset: CGFloat = 0

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
                    .padding(.bottom, bottomInset)
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
                        .padding(.bottom, bottomInset)
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
/// portrait, where the guide drags up over the map (or down) for more
/// room. Picking a place in the guide flies the map to it.
struct HajinWideLayout: View {
    @EnvironmentObject private var store: HajinStore
    @State private var selection: HajinSelection?
    @State private var focus: HajinMapView.Focus?
    /// The screen's size without the keyboard: typing into a field shrinks
    /// the height, which mustn't flip portrait to landscape.
    @State private var fullSize: CGSize = .zero
    /// Portrait: how far down the guide's top edge sits, as a share of the height.
    @AppStorage("mw4.hajin.mapShare") private var mapShare = 0.6
    /// Mid-drag: where the edge is now, and where it started.
    @State private var liveShare: Double?
    @State private var dragFrom: Double?

    private static let defaultShare = 0.6
    private static let shares = 0.12...0.85

    var body: some View {
        GeometryReader { geo in
            let size = fullSize == .zero ? geo.size : fullSize
            let landscape = size.width > size.height
            let height = geo.size.height
            let share = liveShare ?? mapShare
            // One layout either way, so turning the iPad (or the keyboard)
            // never rebuilds the guide and loses the page it's on. Portrait
            // stacks the guide over the map: the map keeps one size, so a
            // drag only slides the guide rather than redrawing the map
            let layout = landscape ? AnyLayout(HStackLayout(spacing: 0)) : AnyLayout(ZStackLayout(alignment: .top))
            layout {
                HajinMapPane(selection: $selection, focus: $focus, inline: true,
                             bottomInset: landscape ? 0 : height * (Self.shares.upperBound - mapShare))
                    .frame(height: landscape ? nil : height * Self.shares.upperBound)
                if landscape {
                    Rectangle().fill(Color.appInkMuted.opacity(0.15)).frame(width: 1)
                }
                HajinGuidePanel(pick: fly(to:)).environment(\.hajinShowMarker, fly(to:))
                    // Mid-drag the guide keeps its tallest size and only moves
                    .frame(width: landscape ? 380 : nil,
                           height: landscape ? nil : height * (1 - (liveShare == nil ? share : Self.shares.lowerBound)))
                    .overlay(alignment: .top) { if !landscape { grabber(height: height) } }
                    .offset(y: landscape ? 0 : height * share)
            }
            .frame(width: geo.size.width, height: height, alignment: .top)
            .clipped()
        }
        .background(GeometryReader { geo in
            Color.clear
                .onAppear { fullSize = geo.size }
                .onChange(of: geo.size) { fullSize = $0 }
        }.ignoresSafeArea(.keyboard))
    }

    /// The guide's top edge, with a handle: drag it up over the map for more
    /// guide, down for more map; a tap switches between halfway and up.
    private func grabber(height: CGFloat) -> some View {
        Rectangle().fill(Color.appInkMuted.opacity(0.15)).frame(height: 1)
            .overlay {
                Capsule().fill(Color.appInkMuted.opacity(0.6))
                    .frame(width: 44, height: 5)
                    // Narrow, so the back button under its left end still takes taps
                    .frame(width: 140, height: 30)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 2, coordinateSpace: .global)
                            .onChanged { drag in
                                let from = dragFrom ?? mapShare
                                if dragFrom == nil { dragFrom = from }
                                let share = from + drag.translation.height / max(height, 1)
                                liveShare = min(max(share, Self.shares.lowerBound), Self.shares.upperBound)
                            }
                            .onEnded { _ in
                                // Saved once, at the end, rather than every frame
                                if let liveShare { mapShare = liveShare }
                                liveShare = nil
                                dragFrom = nil
                            }
                    )
                    .onTapGesture {
                        Haptics.step()
                        withAnimation(.snappy) {
                            mapShare = abs(mapShare - Self.defaultShare) < 0.05 ? Self.shares.lowerBound : Self.defaultShare
                        }
                    }
                    .accessibilityElement()
                    .accessibilityLabel("mw4.ui.hajin.resize".localized())
                    .accessibilityAdjustableAction { direction in
                        let step = direction == .increment ? -0.15 : 0.15
                        mapShare = min(max(mapShare + step, Self.shares.lowerBound), Self.shares.upperBound)
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
    @AppStorage(HajinPage.key) private var page = HajinPage.mine.rawValue

    private enum Page: Hashable {
        case section(HajinGuide.Section)
        case item(String)
        case order(String)
        case stash
        case keepSell
        case shopping
        case blueprints
    }

    private var open: HajinGuide.Section? {
        if case .section(let section) = stack.last { return section }
        return nil
    }

    var body: some View {
        VStack(spacing: 0) {
            // A back row only once something is open; at the top the search
            // row carries level and cash
            if !stack.isEmpty {
            HStack(spacing: 8) {
                if let page = stack.last {
                    // The chevron and the title together, at a full tap size
                    Button { withAnimation(.snappy) { _ = stack.popLast(); query = "" } } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "chevron.left").font(.body.weight(.semibold))
                            Text(title(page)).font(.headline).foregroundStyle(Color.appInk).lineLimit(1)
                        }
                        .frame(minWidth: 44, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentDMZ)
                    .accessibilityLabel("mw4.ui.hajin.guide".localized())
                }
                Spacer()
            }
            .frame(minHeight: 44)
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 2)
            }

            if case .item(let id) = stack.last {
                HajinItemView(id: id)
                    .id(id)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else if case .order(let check) = stack.last {
                HajinOrderView(check: check)
                    .id(check)
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
            // Level and cash beside the search at the top (the app's own bar
            // is the Weapons / DMZ / Stats switcher here, not a title bar)
            .modifier(HajinTrailing(show: stack.isEmpty) { HajinNumbersChip(standalone: true) })
            .padding(.horizontal, 12)
            .padding(.top, stack.isEmpty ? 10 : 0)
            .padding(.bottom, 6)

            if stack.last == .stash {
                HajinStashView(embeddedQuery: query)
            } else if stack.last == .keepSell {
                HajinKeepSellView(embeddedQuery: query)
            } else if stack.last == .shopping {
                HajinShoppingListView(embeddedQuery: query)
            } else if stack.last == .blueprints {
                HajinBlueprintsView(embeddedQuery: query)
            } else if let section = open, section.id == "prestige" {
                List {
                    HajinPrestigeTracker()
                    GroupedGuideRows(rows: section.rows)
                }
                .scrollContentBackground(.hidden)
                .listStyle(.plain)
            } else if let section = open, section.id == "ops" {
                let needle = query.lowercased()
                List { HajinOrdersList(rows: needle.isEmpty ? section.rows : section.rows.filter { $0.matches(needle) }) }
                    .scrollContentBackground(.hidden)
                    .listStyle(.plain)
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
                                          openShopping: { withAnimation(.snappy) { stack = [.shopping]; query = "" } },
                                          openBlueprints: { withAnimation(.snappy) { stack = [.blueprints]; query = "" } },
                                          openSection: { section in withAnimation(.snappy) { stack = [.section(section)]; query = "" } })
                        } else {
                        ForEach(guide.guide.filter { !HajinGuide.trackedSections.contains($0.id) }) { section in
                            Button { withAnimation(.snappy) { stack = [.section(section)] } } label: {
                                HStack {
                                    SectionRow(section: section)
                                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Color.appInkMuted)
                                }
                            }
                            .hajinCardButton()
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
        .environment(\.hajinOpenOrder) { check in withAnimation(.snappy) { stack.append(.order(check)) } }
        #if DEBUG
        // SS_PANEL=stash, keep, shop, blueprints, item:<id> or a section opens that page in the panel for screenshots
        .onAppear {
            switch ProcessInfo.processInfo.environment["SS_PANEL"] {
            case "stash": stack = [.stash]
            case "keep": stack = [.keepSell]
            case "shop": stack = [.shopping]
            case "blueprints": stack = [.blueprints]
            case let target? where target.hasPrefix("item:"): stack = [.item(String(target.dropFirst(5)))]
            case let target?:
                // SS_PANEL=<section id>: that guide section
                if let section = store.guide?.guide.first(where: { $0.id == target }) { stack = [.section(section)] }
            default: break
            }
        }
        #endif
    }

    private func title(_ page: Page) -> String {
        switch page {
        case .section(let section): return section.title.resolved
        case .item(let id): return store.guide?.item(id)?.name.resolved ?? ""
        case .order(let check): return store.guide?.guide.first { $0.id == "ops" }?.rows.first { $0.check == check }?.title.resolved ?? ""
        case .stash: return "mw4.ui.hajin.stash".localized()
        case .keepSell: return "mw4.ui.keep.title".localized()
        case .shopping: return "mw4.ui.hajin.shop".localized()
        case .blueprints: return "mw4.ui.hajin.blueprints".localized()
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
/// Missions & Orders: Story Missions, then each DMZ Orders page in the
/// game's order. A page folds away once it's all ticked, shows its progress
/// and its reward, and the first unfinished one is marked Up next.
struct HajinOrdersList: View {
    let rows: [HajinGuide.Row]
    @EnvironmentObject private var store: HajinStore
    @AppStorage("mw4_hajin_orders_hide_done") private var hideDone = false
    /// Pages opened or closed against their default (open until finished).
    @State private var flipped: Set<String> = []

    private var pages: [(title: String, rows: [HajinGuide.Row])] {
        var out: [(title: String, rows: [HajinGuide.Row])] = []
        for row in rows {
            let title = row.group?.resolved ?? ""
            if let last = out.indices.last, out[last].title == title { out[last].rows.append(row) } else { out.append((title, [row])) }
        }
        return out
    }

    private func isDone(_ row: HajinGuide.Row) -> Bool { row.check.map(store.checked.contains) ?? false }

    var body: some View {
        let pages = pages
        let upNext = pages.first { $0.title.hasPrefix("DMZ Orders") && !$0.rows.allSatisfy(isDone) }?.title
        Toggle("mw4.ui.hajin.hide_done".localized(), isOn: $hideDone)
            .font(.subheadline.weight(.semibold))
            .tint(.accentDMZ)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        ForEach(pages, id: \.title) { page in
            let done = page.rows.filter(isDone).count
            let finished = done == page.rows.count
            let open = finished ? flipped.contains(page.title) : !flipped.contains(page.title)
            if !(hideDone && finished) {
                header(page.title, done: done, total: page.rows.count, open: open, upNext: page.title == upNext,
                       reward: page.rows.lazy.compactMap(\.pageReward).first?.resolved)
                if open {
                    ForEach(page.rows.filter { !(hideDone && isDone($0)) }, id: \.self) { row in
                        GuideRowView(row: row).hajinCard()
                    }
                }
            }
        }
    }

    private func header(_ title: String, done: Int, total: Int, open: Bool, upNext: Bool, reward: String?) -> some View {
        Button {
            Haptics.step()
            withAnimation(.snappy) { if flipped.contains(title) { flipped.remove(title) } else { flipped.insert(title) } }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(Color.appInkMuted)
                        .rotationEffect(.degrees(open ? 90 : 0))
                    Text(title.hasPrefix("DMZ Orders: ") ? String(title.dropFirst("DMZ Orders: ".count)) : title)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(Color.appInk)
                        .multilineTextAlignment(.leading)
                    if upNext {
                        Text("mw4.ui.hajin.up_next".localized().uppercased())
                            .font(.system(size: 10, weight: .heavy))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(Color.accentDMZ))
                    }
                    Spacer(minLength: 8)
                    Text("\(done)/\(total)")
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(done == total ? Color.accentDMZ : Color.appInkMuted)
                }
                if let reward {
                    Label(reward, systemImage: "gift.fill")
                        .font(.caption)
                        .foregroundStyle(Color.appInkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.leading, 22)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets(top: 14, leading: 16, bottom: 4, trailing: 16))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }
}

/// The player's operators: each one's Prestige, what the next costs (against
/// the cash they've entered) and the Prestige traits it holds.
struct HajinPrestigeTracker: View {
    @EnvironmentObject private var store: HajinStore
    @State private var newName = ""

    /// The guide's Prestige rows ("Prestige 1", "2", "3 and later").
    private var tiers: [HajinGuide.Row] {
        store.guide?.guide.first { $0.id == "prestige" }?.rows.filter { $0.title.resolved.hasPrefix("Prestige ") } ?? []
    }
    private var proTraits: [HajinGuide.Row] {
        store.guide?.guide.first { $0.id == "traits" }?.rows.filter { $0.group?.resolved == "Prestige traits" } ?? []
    }

    var body: some View {
        HajinHeading(title: "mw4.ui.opprestige.operators".localized())
        ForEach(store.operators, id: \.name) { op in
            card(op.name, op.level).hajinCard()
                .contextMenu {
                    Button(role: .destructive) { store.removeOperator(op.name) } label: {
                        Label("mw4.ui.opprestige.remove".localized(), systemImage: "trash")
                    }
                }
        }
        HStack(spacing: 8) {
            TextField("mw4.ui.opprestige.name".localized(), text: $newName)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .onSubmit(add)
            Button("mw4.ui.opprestige.add".localized(), action: add)
                .font(.subheadline.weight(.semibold))
                .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .hajinCard()
    }

    private func add() {
        Haptics.step()
        store.addOperator(newName)
        newName = ""
    }

    private func card(_ name: String, _ level: Int) -> some View {
        let next = tiers.isEmpty ? nil : tiers[min(level, tiers.count - 1)]
        let held = store.prestigeTraits(of: name)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text(name).font(.hitmarker(16)).foregroundStyle(Color.appInk)
                Spacer(minLength: 8)
                Button { Haptics.step(); store.setPrestige(level - 1, of: name) } label: {
                    Image(systemName: "minus.circle").font(.title3).foregroundStyle(Color.accentDMZ)
                }
                .buttonStyle(.borderless)
                .disabled(level == 0)
                Text(String(format: "mw4.ui.opprestige.level".localized(), level))
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(level > 0 ? Color.accentDMZ : Color.appInkMuted)
                Button { Haptics.step(); store.setPrestige(level + 1, of: name) } label: {
                    Image(systemName: "plus.circle").font(.title3).foregroundStyle(Color.accentDMZ)
                }
                .buttonStyle(.borderless)
            }
            if let next {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(String(format: "mw4.ui.opprestige.next".localized(), level + 1).uppercased())
                            .font(.system(size: 11, weight: .bold)).tracking(0.8)
                            .foregroundStyle(Color.appInkMuted)
                        if let cost = next.value?.resolved { cashBadge(cost) }
                    }
                    if let needs = next.subtitle {
                        Text(needs.resolved).font(.caption).foregroundStyle(Color.appInkMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("mw4.ui.opprestige.traits".localized().uppercased() + " \(held.count)/\(HajinStore.maxPrestigeTraits)")
                    .font(.system(size: 11, weight: .bold)).tracking(0.8)
                    .foregroundStyle(Color.appInkMuted)
                HajinWrap(spacing: 6) {
                    ForEach(held, id: \.self) { trait in
                        Button { store.togglePrestigeTrait(trait, of: name) } label: {
                            HStack(spacing: 4) {
                                Text(trait).font(.caption.weight(.semibold)).foregroundStyle(Color.appInk)
                                Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).foregroundStyle(Color.appInkMuted)
                            }
                            .padding(.horizontal, 8).padding(.vertical, 5)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color.accentDMZ.opacity(0.18)))
                        }
                        .buttonStyle(.borderless)
                    }
                    if held.count < HajinStore.maxPrestigeTraits {
                        Menu {
                            ForEach(proTraits.filter { !held.contains($0.title.resolved) }, id: \.self) { row in
                                Button(row.title.resolved) { store.togglePrestigeTrait(row.title.resolved, of: name) }
                            }
                        } label: {
                            Label("mw4.ui.opprestige.add_trait".localized(), systemImage: "plus")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.accentDMZ)
                                .padding(.horizontal, 8).padding(.vertical, 5)
                                .background(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.accentDMZ.opacity(0.5), lineWidth: 1))
                        }
                    }
                }
            }
        }
    }

    /// The next Prestige's cash, ticked when the cash entered covers it.
    @ViewBuilder private func cashBadge(_ cost: String) -> some View {
        let needed = Int(cost.filter(\.isNumber)) ?? 0
        HStack(spacing: 4) {
            HajinValueBadge(text: cost)
            if store.cash > 0, needed > 0 {
                if store.cash >= needed {
                    Image(systemName: "checkmark.circle.fill").font(.caption).foregroundStyle(HajinStore.printableGreen)
                } else {
                    HajinCashShort(price: needed)
                }
            }
        }
    }
}

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

/// A tile or row that dims while pressed, nothing more.
struct HajinPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.6 : 1)
    }
}

/// The photo reader: one card for the stash and the backpack after a
/// match. Which one a photo shows is worked out from its text, so the card
/// lists both rather than asking. (A 3D Printer screen still reads, as the
/// fallback when it's neither.)
@available(iOS 17.0, *)
struct HajinReaderTile: View {
    @ObservedObject private var flow = HajinScanFlow.shared

    var body: some View {
        Button { flow.requestScan() } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Color.accentDMZ)
                        .frame(width: 38, height: 38)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.accentDMZ.opacity(0.16)))
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 8) {
                            Text("mw4.ui.hajin.grid_scan".localized())
                                .font(.hitmarker(16))
                                .foregroundStyle(Color.appInk)
                            // Still learning the game's screens
                            Text("mw4.ui.hajin.beta".localized())
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(Color.accentDMZ)
                                .padding(.horizontal, 7).padding(.vertical, 3)
                                .overlay(Capsule().strokeBorder(Color.accentDMZ.opacity(0.6), lineWidth: 1))
                        }
                        Text("mw4.ui.hajin.read_auto".localized())
                            .font(.caption)
                            .foregroundStyle(Color.appInkMuted)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    if flow.sorting { ProgressView() }
                }
                // What it can read, each with the screen's own symbol
                HStack(spacing: 6) {
                    kind("square.grid.3x3.fill", "mw4.ui.hajin.read_as_stash")
                    kind("bag.fill", "mw4.ui.hajin.read_as_backpack")
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .borderedCard()
        }
        .buttonStyle(HajinPressStyle())
        .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private func kind(_ symbol: String, _ key: String) -> some View {
        Label(key.localized(), systemImage: symbol)
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.appInk)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 7).fill(Color.appSurface2))
    }
}

/// DMZ Level and DMZ Cash in one card, side by side: the two numbers
/// everything else is weighed against. Tap either to type it in.
struct HajinNumbersCard: View {
    private enum Field { case level, cash }
    @EnvironmentObject private var store: HajinStore
    @State private var editing: Field?
    @State private var text = ""

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            level
            Rectangle().fill(Color.appSurface2).frame(width: 1)
            cash
        }
        .alert(editing == .cash ? "mw4.ui.hajin.cash_title".localized() : "mw4.ui.hajin.dmz_level".localized(),
               isPresented: Binding(get: { editing != nil }, set: { if !$0 { editing = nil } })) {
            TextField(editing == .cash ? "0" : "1–\(HajinStore.maxLevel)", text: $text).keyboardType(.numberPad)
            Button("mw4.ui.hajin.save".localized()) {
                let n = Int(text.filter(\.isNumber))
                if editing == .cash { store.setCash(n ?? 0) } else if let n { store.setLevel(n) }
            }
            Button("mw4.ui.hajin.cancel".localized(), role: .cancel) {}
        }
    }

    private func label(_ key: String) -> some View {
        Text(key.localized()).font(.caption.weight(.semibold)).foregroundStyle(Color.appInkMuted)
    }

    private var level: some View {
        let level = store.dmzLevel
        return VStack(alignment: .leading, spacing: 8) {
            label("mw4.ui.hajin.dmz_level")
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Button { text = level > 0 ? "\(level)" : ""; editing = .level } label: {
                    if level > 0 {
                        (Text("\(level)").font(.hitmarker(30)).foregroundColor(Color.appInk)
                         + Text(" /\(HajinStore.maxLevel)").font(.hitmarker(15)).foregroundColor(Color.appInkMuted))
                            .contentTransition(.numericText())
                    } else {
                        Text("mw4.ui.hajin.dmz_level_button".localized()).font(.hitmarker(18)).foregroundStyle(Color.accentDMZ)
                    }
                }
                .buttonStyle(.borderless)
                Spacer(minLength: 4)
                if level > 0 {
                    HStack(spacing: 6) {
                        stepButton(systemName: "minus", enabled: true, size: 24, accent: .accentDMZ) { store.setLevel(level - 1) }
                        stepButton(systemName: "plus", enabled: level < HajinStore.maxLevel, size: 24, accent: .accentDMZ) { store.setLevel(level + 1) }
                    }
                }
            }
            ProgressBar(fraction: Double(level) / Double(HajinStore.maxLevel), accent: .accentDMZ)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var cash: some View {
        VStack(alignment: .leading, spacing: 8) {
            label("mw4.ui.hajin.cash_title")
            Button { text = store.cash > 0 ? "\(store.cash)" : ""; editing = .cash } label: {
                Text(store.cash > 0 ? "$\(store.cash.formatted())" : "mw4.ui.hajin.cash_add".localized())
                    .font(.hitmarker(store.cash > 0 ? 30 : 18))
                    .foregroundStyle(store.cash > 0 ? Color.appInk : Color.accentDMZ)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .contentTransition(.numericText())
            }
            .buttonStyle(.borderless)
            Text((store.cash > 0 ? "mw4.ui.hajin.cash_set" : "mw4.ui.hajin.cash_hint").localized())
                .font(.caption2).foregroundStyle(Color.appInkMuted)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Something beside a view, when `show`.
struct HajinTrailing<T: View>: ViewModifier {
    let show: Bool
    @ViewBuilder let trailing: () -> T
    func body(content: Content) -> some View {
        HStack(spacing: 8) {
            content
            if show { trailing() }
        }
    }
}

/// DMZ Level and Cash in the title bar, on every DMZ page: tap for the
/// card that sets them.
struct HajinNumbersChip: View {
    /// Not in a toolbar, so no glass behind it: draw its own capsule
    var standalone = false
    @EnvironmentObject private var store: HajinStore
    @State private var open = false

    var body: some View {
        Button { open = true } label: {
            HStack(spacing: 8) {
                Text("Lv ").font(.hitmarker(11)).foregroundColor(Color.appInkMuted)
                    + Text(store.dmzLevel > 0 ? "\(store.dmzLevel)" : "–").foregroundColor(Color.appInk)
                Rectangle().fill(Color.appInkMuted.opacity(0.4)).frame(width: 1, height: 14)
                Text(store.cash > 0 ? "$" + Self.short(store.cash) : "$–")
                    .foregroundStyle(Color.accentDMZ)
            }
            .font(.hitmarker(15))
            .padding(.horizontal, 6)
            // iOS 26 sets toolbar items on glass; before it, a capsule of our own
            .padding(.vertical, standalone ? 7 : 0)
            .padding(.horizontal, standalone ? 6 : 0)
            .background {
                if standalone {
                    Capsule().fill(Color.appSurface).overlay(Capsule().strokeBorder(Color.appSurface2, lineWidth: 1))
                } else if #unavailable(iOS 26.0) {
                    Capsule().fill(Color.appSurface).padding(.vertical, -5)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\("mw4.ui.hajin.dmz_level".localized()) \(store.dmzLevel), \("mw4.ui.hajin.cash_title".localized()) $\(store.cash)")
        .popover(isPresented: $open) {
            let card = HajinNumbersCard().padding(16).frame(minWidth: 320).environmentObject(store)
            if #available(iOS 16.4, *) { card.presentationCompactAdaptation(.popover) } else { card }
        }
    }

    /// 33,050 -> 33K, 1,250,000 -> 1.25M
    static func short(_ n: Int) -> String {
        if n >= 1_000_000 { return (Double(n) / 1_000_000).formatted(.number.precision(.fractionLength(0...2))) + "M" }
        if n >= 10_000 { return "\(n / 1000)K" }
        return n.formatted()
    }
}

/// The guide's sections as a two-column grid of tiles, like My DMZ's
/// Progress: an odd one out at the end takes the full width.
struct HajinGuideTiles: View {
    let sections: [HajinGuide.Section]
    @Environment(\.hajinPush) private var push

    var body: some View {
        let paired = sections.count.isMultiple(of: 2) ? sections : Array(sections.dropLast())
        VStack(spacing: 10) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(paired) { tile($0, wide: false) }
            }
            if paired.count < sections.count, let last = sections.last { tile(last, wide: true) }
        }
        .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    @ViewBuilder private func tile(_ section: HajinGuide.Section, wide: Bool) -> some View {
        let label = HajinGuideTile(section: section, wide: wide)
        if let push {
            Button { push(.section(section.id)) } label: { label }.buttonStyle(HajinPressStyle())
        } else {
            NavigationLink { GuideSectionView(section: section) } label: { label }.buttonStyle(HajinPressStyle())
        }
    }
}

struct HajinGuideTile: View {
    let section: HajinGuide.Section
    var wide = false

    var body: some View {
        Group {
            if wide {
                HStack(spacing: 12) { icon; title; Spacer(minLength: 4); count }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top) { icon; Spacer(minLength: 4); count }
                    title.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(12)
        // The full height of its grid row, so a row's tiles match
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .contentShape(Rectangle())
        .borderedCard()
    }

    private var icon: some View {
        Image(systemName: section.symbol)
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(Color.accentDMZ)
            .frame(width: 36, height: 36)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.accentDMZ.opacity(0.16)))
    }

    private var title: some View {
        Text(section.title.resolved)
            .font(.hitmarker(15))
            .foregroundStyle(Color.appInk)
            .multilineTextAlignment(.leading)
            .lineLimit(2)
    }

    private var count: some View {
        Text("\(section.rows.count)")
            .font(.system(size: 12, weight: .semibold, design: .monospaced))
            .foregroundStyle(Color.appInkMuted)
    }
}

/// A tracked guide section on My DMZ: its symbol in a ring of how much is
/// ticked, the title, and the count.
struct HajinProgressTile: View {
    let title: String
    let symbol: String
    /// nil: nothing to tick (prestige), so a plain symbol
    let fraction: Double?
    let count: String
    /// The full width, as a row: an odd tile out at the end
    var wide = false

    var body: some View {
        Group {
            if wide {
                HStack(spacing: 12) {
                    ring
                    titleText
                    Spacer(minLength: 4)
                    countText
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top) {
                        ring
                        Spacer(minLength: 4)
                        countText
                    }
                    titleText.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .borderedCard()
    }

    private var ring: some View {
        ZStack {
            // Nothing ticked yet: the bare track, not a dot of progress
            if let fraction, fraction > 0 {
                ProgressRing(fraction: fraction, accent: .accentDMZ, lineWidth: 4, size: 40, showsPercentage: false)
            } else {
                Circle().stroke(Color.appSurface2, lineWidth: 4).frame(width: 40, height: 40)
            }
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color.accentDMZ)
        }
    }

    private var titleText: some View {
        Text(title)
            .font(.hitmarker(15))
            .foregroundStyle(Color.appInk)
            .multilineTextAlignment(.leading)
            .lineLimit(2)
    }

    private var countText: some View {
        Text(count)
            .font(.system(size: 12, weight: .semibold, design: .monospaced))
            .foregroundStyle(fraction == 1 ? Color.accentDMZ : Color.appInkMuted)
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
                if row.check != nil {
                    HajinTick(done: done, label: row.title.resolved) { store.toggle(key) }
                }
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
            // An order's prints and the ingredients it wants extracted
            let needs = (row.prints ?? []) + (row.extracts ?? [])
            if !needs.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("mw4.ui.hajin.needs".localized().uppercased())
                        .font(.system(size: 11, weight: .bold))
                        .tracking(0.8)
                        .foregroundStyle(Color.appInkMuted)
                    HajinLinkChips(ids: needs.map(\.item), amounts: Dictionary(needs.map { ($0.item, $0.qty) }, uniquingKeysWith: +))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 36)
            }
            if let tips = row.tips, !tips.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(tips.indices, id: \.self) { i in
                        Label(tips[i].resolved, systemImage: "lightbulb.fill")
                            .font(.caption)
                            .foregroundStyle(Color.appInkMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
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
