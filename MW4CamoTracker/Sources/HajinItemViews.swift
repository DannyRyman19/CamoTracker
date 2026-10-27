import SwiftUI

/// The game's rarity colours, Common grey to Ultra red.
enum HajinRarity {
    static func color(_ rarity: String?) -> Color {
        switch rarity {
        case "Uncommon": return Color(red: 0.42, green: 0.80, blue: 0.36)
        case "Rare": return Color(red: 0.36, green: 0.62, blue: 0.98)
        case "Epic": return Color(red: 0.66, green: 0.45, blue: 0.98)
        case "Legendary": return Color(red: 0.96, green: 0.66, blue: 0.24)
        case "Ultra": return Color(red: 0.93, green: 0.32, blue: 0.30)
        default: return Color(white: 0.62)
        }
    }
}

/// An item's picture in a dark tile with a rarity stripe across the top,
/// like the printer's ingredient icons.
struct HajinItemTile: View {
    let item: HajinGuide.Item?
    var size: CGFloat = 44
    /// Draw it on blueprint paper (the blueprint checklist).
    var blueprint = false

    var body: some View {
        let tint = HajinRarity.color(item?.rarity)
        ZStack {
            if blueprint {
                HajinBlueprintPaper(size: size)
            } else {
                LinearGradient(colors: [tint.opacity(0.22), Color.black.opacity(0.55)], startPoint: .bottom, endPoint: .top)
            }
            if let image = item?.image, let url = URL(string: image) {
                CachedAsyncImage(url: url) { phase in
                    if let picture = phase.image { picture.resizable().scaledToFit().padding(size * 0.08) } else { Color.clear }
                }
            } else if let symbol = item?.symbol {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.4, weight: .semibold))
                    .foregroundStyle(item?.rarity == nil ? Color.appInk : tint)
            } else {
                Image(systemName: "shippingbox")
                    .font(.system(size: size * 0.36))
                    .foregroundStyle(Color.appInkMuted.opacity(0.6))
            }
        }
        .frame(width: size, height: size)
        .overlay(alignment: .top) { Rectangle().fill(tint).frame(height: max(2, size / 22)) }
        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(tint.opacity(0.45), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

/// Blueprint paper: deep blue with a fine grid and a heavier line every
/// few squares, drawn rather than an image so it stays crisp at any size.
struct HajinBlueprintPaper: View {
    let size: CGFloat

    var body: some View {
        Canvas { ctx, area in
            ctx.fill(Path(CGRect(origin: .zero, size: area)), with: .linearGradient(Gradient(colors: [Color(red: 0.10, green: 0.30, blue: 0.58), Color(red: 0.05, green: 0.18, blue: 0.40)]),
                                                         startPoint: .zero, endPoint: CGPoint(x: area.width, y: area.height)))
            let step = max(4, area.width / 8)
            var fine = Path(), heavy = Path()
            for (i, x) in stride(from: 0, through: area.width, by: step).enumerated() {
                var line = Path()
                line.move(to: CGPoint(x: x, y: 0)); line.addLine(to: CGPoint(x: x, y: area.height))
                if i % 4 == 0 { heavy.addPath(line) } else { fine.addPath(line) }
            }
            for (i, y) in stride(from: 0, through: area.height, by: step).enumerated() {
                var line = Path()
                line.move(to: CGPoint(x: 0, y: y)); line.addLine(to: CGPoint(x: area.width, y: y))
                if i % 4 == 0 { heavy.addPath(line) } else { fine.addPath(line) }
            }
            ctx.stroke(fine, with: .color(.white.opacity(0.12)), lineWidth: 0.5)
            ctx.stroke(heavy, with: .color(.white.opacity(0.28)), lineWidth: 0.8)
        }
        .frame(width: size, height: size)
    }
}

/// "◆ EPIC  CONSUMABLES", the game's rarity line.
struct HajinRarityLine: View {
    let item: HajinGuide.Item
    var size: CGFloat = 12
    var showsKind = true

    var body: some View {
        HStack(spacing: 6) {
            if let rarity = item.rarity {
                Image(systemName: "diamond.fill")
                    .font(.system(size: size * 0.8))
                    .foregroundStyle(HajinRarity.color(rarity))
                Text(rarity.uppercased())
                    .font(.system(size: size, weight: .heavy))
                    .foregroundStyle(HajinRarity.color(rarity))
            }
            if showsKind {
                Text(item.kind.uppercased())
                    .font(.system(size: size, weight: .semibold))
                    .foregroundStyle(Color.appInkMuted)
            }
        }
        .lineLimit(1)
        .tracking(0.6)
    }
}

extension View {
    /// The app's card: each row its own outlined 8pt card in a plain list,
    /// as on the Weapons and Stats tabs.
    func hajinCard(accent: Color? = nil) -> some View {
        padding(12)
            .borderedCard(accent: accent)
            .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }
}

/// "Can print": the stash covers this recipe.
struct HajinCanPrintTag: View {
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "printer.fill").font(.system(size: 9, weight: .bold))
            Text("mw4.ui.hajin.can_print".localized().uppercased())
        }
        .font(.system(size: 10, weight: .heavy))
        .tracking(0.5)
        .foregroundStyle(Color.black.opacity(0.85))
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(RoundedRectangle(cornerRadius: 4).fill(HajinStore.printableGreen))
        .fixedSize()
    }
}

/// The app's tick: an empty circle, then a filled accent circle with a
/// check, as on the camo challenges.
struct HajinTick: View {
    let done: Bool
    let label: String
    let toggle: () -> Void

    var body: some View {
        Button {
            Haptics.step()
            toggle()
        } label: {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 21))
                .foregroundStyle(done ? Color.accentDMZ : Color.appInkMuted)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(label)
        .accessibilityAddTraits(done ? .isSelected : [])
    }
}

/// A row's figure (price, level, grid square, "Find"), in one neutral
/// style everywhere so money never reads as a warning.
struct HajinValueBadge: View {
    let text: String
    var locked = false

    var body: some View {
        HStack(spacing: 4) {
            if locked { Image(systemName: "lock.fill").font(.system(size: 9, weight: .bold)) }
            Text(text)
        }
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundStyle(locked ? Color.appInkMuted : Color.appInk.opacity(0.9))
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 4).fill(Color.appSurface2)
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.appInkMuted.opacity(0.3), lineWidth: 1))
            )
    }
}

/// Lays chips out left to right, wrapping onto new lines instead of
/// running off the edge.
struct HajinWrap: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width { x = 0; y += row + spacing; row = 0 }
            x += size.width + spacing
            row = max(row, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: min(widest, width), height: y + row)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, row: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX { x = bounds.minX; y += row + spacing; row = 0 }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            row = max(row, size.height)
        }
    }
}

// MARK: - Links

/// On iPad the guide lives in a side panel with its own back stack, so links
/// there push into the panel; on iPhone they're ordinary navigation links.
private struct OpenItemKey: EnvironmentKey {
    static let defaultValue: (@MainActor (String) -> Void)? = nil
}

private struct ShowMarkerKey: EnvironmentKey {
    static let defaultValue: (@MainActor (HajinGuide.Marker) -> Void)? = nil
}

extension EnvironmentValues {
    var hajinOpenItem: (@MainActor (String) -> Void)? {
        get { self[OpenItemKey.self] }
        set { self[OpenItemKey.self] = newValue }
    }

    var hajinShowMarker: (@MainActor (HajinGuide.Marker) -> Void)? {
        get { self[ShowMarkerKey.self] }
        set { self[ShowMarkerKey.self] = newValue }
    }
}

/// An item pushed onto the Hajin tab's navigation stack.
struct HajinItemRoute: Hashable {
    let id: String
}

/// Opens an item's screen, however the current layout navigates.
struct HajinItemLink<Label: View>: View {
    let id: String
    @ViewBuilder let label: () -> Label
    @Environment(\.hajinOpenItem) private var openItem

    var body: some View {
        if let openItem {
            Button { openItem(id) } label: { label().contentShape(Rectangle()) }
                // Borderless, so a link inside a list row (or inside another
                // link) is its own tap target rather than the whole row
                .buttonStyle(.borderless)
        } else {
            NavigationLink { HajinItemView(id: id) } label: { label() }
                .buttonStyle(.plain)
        }
    }
}

// MARK: - Rows

/// A guide row that is an item: rarity tile, name, unlock badge and its
/// ingredients as small chips. Taps through to the item.
struct HajinItemRow: View {
    let item: HajinGuide.Item
    let row: HajinGuide.Row
    @EnvironmentObject private var store: HajinStore
    /// Set on iPad, where the row is a plain button and needs its own
    /// chevron; on iPhone the list's navigation link draws one.
    @Environment(\.hajinOpenItem) private var openItem

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if let key = row.check {
                HajinTick(done: store.checked.contains(key), label: item.name.resolved) { store.toggle(key) }
                    .padding(.top, 12)
            }
            link
        }
    }

    private var link: some View {
        HajinItemLink(id: item.id) {
            linkContent.opacity(store.isLocked(item.requiredLevel ?? row.requiredLevel) ? 0.55 : 1)
        }
    }

    private var linkContent: some View {
        Group {
            HStack(alignment: .top, spacing: 12) {
                HajinItemTile(item: item, size: 48)
                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(item.name.resolved)
                            .font(.hitmarker(15))
                            .foregroundStyle(Color.appInk)
                        Spacer(minLength: 6)
                        if let value = row.value?.resolved, value != item.rarity, value != "Resource" {
                            HajinValueBadge(text: value, locked: store.isLocked(item.requiredLevel ?? row.requiredLevel))
                        }
                    }
                    if item.rarity != nil || store.canPrint(item) {
                        HStack(spacing: 8) {
                            // The tag replaces the kind, which the heading already gives
                            if item.rarity != nil { HajinRarityLine(item: item, size: 10, showsKind: !store.canPrint(item)) }
                            if store.canPrint(item) { HajinCanPrintTag() }
                        }
                    }
                    if let cost = item.cost, !cost.isEmpty {
                        // The row's badge already shows the cash for upgrades
                        CostChips(cost: cost, cash: row.value == nil ? item.cash : nil)
                    } else if let effect = item.effect ?? item.note {
                        Text(effect.resolved).font(.subheadline).foregroundStyle(Color.appInkMuted).lineLimit(2)
                    } else if row.subtitle?.values["en"]?.contains("not confirmed") ?? false {
                        Text(row.subtitle!.resolved).font(.subheadline).italic().foregroundStyle(Color.appInkMuted.opacity(0.7))
                    }
                }
                if openItem != nil {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.appInkMuted.opacity(0.6))
                        .padding(.top, 4)
                }
            }
            .padding(.vertical, 3)
        }
    }

    /// Ingredient icons with their amounts, in one wrapping row.
    private struct CostChips: View {
        let cost: [HajinGuide.Item.Cost]
        let cash: Int?
        @EnvironmentObject private var store: HajinStore

        var body: some View {
            // One line: a recipe has at most four parts, and a wrapping
            // layout inside a row broke early
            HStack(spacing: 8) {
                if let cash {
                    Text("$\(cash.formatted())")
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(Color.appInk)
                }
                ForEach(cost, id: \.item) { part in
                    let item = store.guide?.item(part.item)
                    HStack(spacing: 3) {
                        HajinItemTile(item: item, size: 22)
                        Text("\(part.qty)")
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .foregroundStyle(Color.appInk)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(part.qty) \(item?.name.resolved ?? part.item)")
                }
            }
        }
    }
}

/// One ingredient line on an item's recipe, like the printer: icon, name,
/// amount. Taps through to that ingredient.
private struct CostLine: View {
    let part: HajinGuide.Item.Cost
    @EnvironmentObject private var store: HajinStore

    var body: some View {
        let item = store.guide?.item(part.item)
        HajinItemLink(id: part.item) {
            HStack(spacing: 12) {
                HajinItemTile(item: item, size: 40)
                VStack(alignment: .leading, spacing: 1) {
                    Text(item?.name.resolved ?? part.item)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.appInk)
                    if let rarity = item?.rarity {
                        Text(rarity).font(.caption2.weight(.semibold)).foregroundStyle(HajinRarity.color(rarity))
                    }
                }
                Spacer()
                let have = store.count(of: part.item)
                // With some in the stash: have/need, green once covered
                Text(have > 0 ? "\(have)/\(part.qty)" : "×\(part.qty)")
                    .font(.system(.body, design: .monospaced).weight(.semibold))
                    .foregroundStyle(have >= part.qty ? Color(red: 0.42, green: 0.80, blue: 0.36) : Color.appInk)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Color.appInkMuted.opacity(0.6))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }
}

// MARK: - Item screen

/// An item laid out like the game's printer panel: big tile, name, rarity
/// line and effect, then the recipe, what uses it, and where it is.
struct HajinItemView: View {
    let id: String
    /// Another tier of the same upgrade, swapped in place by the tier strip
    /// rather than pushed as a new page.
    @State private var tierShown: String?
    private var shownId: String { tierShown ?? id }
    @EnvironmentObject private var store: HajinStore
    @Environment(\.hajinShowMarker) private var showMarker
    @State private var width: CGFloat = 0

    var body: some View {
        ZStack {
            AppBackground(accent: .accentDMZ)
            if let guide = store.guide, let item = guide.item(shownId) {
                ScrollView {
                    if width >= 760 {
                        // Wide: the item and its recipe on the left, what uses
                        // it and where to get it on the right
                        HStack(alignment: .top, spacing: 20) {
                            VStack(alignment: .leading, spacing: 18) { primary(item, guide) }
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                            VStack(alignment: .leading, spacing: 18) { secondary(item, guide) }
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                        }
                        .padding(20)
                        .frame(maxWidth: 1100)
                        .frame(maxWidth: .infinity)
                    } else {
                        VStack(alignment: .leading, spacing: 18) {
                            primary(item, guide)
                            secondary(item, guide)
                        }
                        .padding(16)
                        .frame(maxWidth: 640, alignment: .leading)
                        .frame(maxWidth: .infinity)
                    }
                }
            } else {
                Text("mw4.ui.hajin.no_results".localized()).foregroundStyle(Color.appInkMuted)
            }
        }
        .readingWidth($width)
        .navigationTitle(store.guide?.item(shownId)?.name.resolved ?? "")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder private func primary(_ item: HajinGuide.Item, _ guide: HajinGuide) -> some View {
        header(item)
        if HajinVerdict.applies(to: item) {
            HajinVerdictBadge(verdict: HajinVerdict(item: item, guide: guide, done: store.checked))
        }
        // Blueprints: tick once found (the "Still to find" list)
        if item.blueprint == true {
            let found = store.hasBlueprint(item.id)
            HStack(spacing: 10) {
                HajinTick(done: found, label: item.name.resolved) { store.toggle(HajinStore.blueprintKey(item.id)) }
                Text((found ? "mw4.ui.hajin.blueprint_found" : "mw4.ui.hajin.blueprint_missing").localized())
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(found ? Color.accentDMZ : Color.appInk)
                Spacer()
                Image(systemName: "doc.text.magnifyingglass").foregroundStyle(found ? Color.accentDMZ : Color.appInkMuted)
            }
            .padding(12)
            .background(statusPanel(nil))
        }
        // One status row: Printed / Ready to print (stash covers it) / tick
        // once printed. Recipes have no tick, so they only show Ready.
        if item.kind == "FOB Upgrade" {
            let key = "upgrade-\(item.id)"
            let done = store.checked.contains(key)
            let ready = !done && store.canPrint(item)
            HStack(spacing: 10) {
                HajinTick(done: done, label: item.name.resolved) { store.toggle(key) }
                VStack(alignment: .leading, spacing: 2) {
                    Text(done ? "mw4.ui.hajin.printed".localized() : ready ? "mw4.ui.hajin.can_print_title".localized() : "mw4.ui.hajin.not_printed".localized())
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(done ? Color.accentDMZ : ready ? HajinStore.printableGreen : Color.appInk)
                    if ready {
                        Text("mw4.ui.hajin.ready_tick".localized()).font(.caption).foregroundStyle(Color.appInkMuted)
                    }
                }
                Spacer()
                if ready { Image(systemName: "printer.fill").foregroundStyle(HajinStore.printableGreen) }
            }
            .padding(12)
            .background(statusPanel(ready ? HajinStore.printableGreen : nil))
        } else if store.canPrint(item) {
            let locked = store.isLocked(item.requiredLevel)
            HStack(spacing: 10) {
                Image(systemName: locked ? "lock.fill" : "printer.fill")
                    .foregroundStyle(locked ? Color.appInkMuted : HajinStore.printableGreen)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(locked ? "mw4.ui.hajin.have_all".localized() : "mw4.ui.hajin.can_print_title".localized())
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(locked ? Color.appInk : HajinStore.printableGreen)
                    Text(locked ? String(format: "mw4.ui.hajin.unlocks_at".localized(), item.requiredLevel ?? 0) : "mw4.ui.hajin.can_print_detail".localized())
                        .font(.caption).foregroundStyle(Color.appInkMuted)
                }
                Spacer()
            }
            .padding(12)
            .background(statusPanel(locked ? nil : HajinStore.printableGreen))
        }
        // Recipes and upgrades can be tracked; what My stash counts shows it
        if !(item.cost ?? []).isEmpty || item.kind == "FOB Upgrade" {
            HajinTrackButton(id: item.id)
        }
        if HajinStore.inStash(item) {
            HStack {
                Text("mw4.ui.hajin.in_stash".localized().uppercased())
                    .font(.caption.weight(.semibold))
                    .tracking(0.6)
                    .foregroundStyle(Color.appInkMuted)
                Spacer()
                HajinStashStepper(id: item.id)
            }
            .padding(12)
            .background(panel)
        }
        let tiers = guide.tiers(of: item)
        if tiers.count > 1 { tierStrip(item, tiers) }
        if !(item.cost ?? []).isEmpty || item.cash != nil { recipe(item, item.cost ?? []) }
        facts(item)
        if let markerID = item.marker, let marker = guide.marker(markerID) { mapButton(marker) }
    }

    @ViewBuilder private func secondary(_ item: HajinGuide.Item, _ guide: HajinGuide) -> some View {
        let users = guide.usedIn(item.id)
        // Level rows are unlocks (recipe) or rewards; everything else
        // (bosses, missions, stations) is where to find it
        let mentions = guide.mentions(item.id)
        let levels = mentions.filter { $0.section.id == "levels" }
        let found = mentions.filter { $0.section.id != "levels" }
        let showsWhere = !found.isEmpty || item.found != nil
        // Ingredients with a known location lead with where to look
        if showsWhere, item.found != nil { whereFrom(found, title: "mw4.ui.hajin.where_find".localized(), inGame: item.found?.resolved, places: (item.foundPlaces ?? []).compactMap { guide.marker($0) }) }
        if !users.isEmpty { usedIn(users) }
        if showsWhere, item.found == nil { whereFrom(found, title: "mw4.ui.hajin.where_find".localized()) }
        if !levels.isEmpty || item.requiredLevel != nil { unlocks(item, levels) }
    }

    /// When a recipe unlocks, or which levels hand the item out.
    private func unlocks(_ item: HajinGuide.Item, _ levels: [(section: HajinGuide.Section, row: HajinGuide.Row)]) -> some View {
        let craftable = !(item.cost ?? []).isEmpty
        var rows: [(level: Int, text: String)] = levels.compactMap { mention in
            guard let level = mention.row.level else { return nil }
            return (level, craftable ? "mw4.ui.hajin.unlock_recipe".localized() : "mw4.ui.hajin.unlock_reward".localized())
        }
        if let needed = item.requiredLevel, !rows.contains(where: { $0.level == needed }) {
            rows.insert((needed, "mw4.ui.hajin.unlock_recipe".localized()), at: 0)
        }
        rows.sort { $0.level < $1.level }
        return VStack(alignment: .leading, spacing: 8) {
            panelTitle("mw4.ui.hajin.unlocks".localized())
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    let locked = store.isLocked(row.level)
                    HStack(spacing: 12) {
                        Image(systemName: store.dmzLevel == 0 ? "chart.bar.fill" : locked ? "lock.fill" : "checkmark.circle.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(store.dmzLevel > 0 && !locked ? Color.accentDMZ : Color.appInkMuted)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(String(format: "mw4.ui.hajin.dmz_level_n".localized(), row.level))
                                .font(.subheadline.weight(.semibold)).foregroundStyle(Color.appInk)
                            Text(row.text).font(.caption).foregroundStyle(Color.appInkMuted)
                        }
                        Spacer()
                    }
                    .padding(12)
                    if index < rows.count - 1 { Divider().overlay(Color.appInkMuted.opacity(0.2)) }
                }
            }
            .background(panel)
        }
    }

    private func header(_ item: HajinGuide.Item) -> some View {
        HStack(alignment: .top, spacing: 16) {
            HajinItemTile(item: item, size: 104)
            VStack(alignment: .leading, spacing: 8) {
                Text(item.name.resolved.uppercased())
                    .font(.hitmarker(26))
                    .foregroundStyle(Color.appInk)
                    .fixedSize(horizontal: false, vertical: true)
                HajinRarityLine(item: item)
                if let effect = item.effect {
                    Text(effect.resolved)
                        .font(.subheadline.italic())
                        .foregroundStyle(Color.appInk.opacity(0.85))
                }
            }
        }
    }

    private func recipe(_ item: HajinGuide.Item, _ cost: [HajinGuide.Item.Cost]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            panelTitle(item.kind == "FOB Upgrade" ? "mw4.ui.hajin.cost".localized() : "mw4.ui.hajin.recipe".localized())
            VStack(spacing: 0) {
                if let cash = item.cash {
                    HStack(spacing: 12) {
                        Image(systemName: "dollarsign")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(Color.appInk)
                            .frame(width: 40, height: 40)
                        Text("mw4.ui.hajin.cash".localized()).font(.subheadline.weight(.medium)).foregroundStyle(Color.appInk)
                        Spacer()
                        Text("$\(cash.formatted())")
                            .font(.system(.body, design: .monospaced).weight(.semibold))
                            .foregroundStyle(Color.appInk)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    Divider().overlay(Color.appInkMuted.opacity(0.2))
                }
                ForEach(Array(cost.enumerated()), id: \.offset) { index, part in
                    CostLine(part: part)
                    if index < cost.count - 1 { Divider().overlay(Color.appInkMuted.opacity(0.2)).padding(.leading, 64) }
                }
            }
            .background(panel)
            if let unlock = item.unlock, item.requiredLevel == nil {
                Text(unlock.resolved)
                    .font(.footnote)
                    .foregroundStyle(Color(red: 0.86, green: 0.82, blue: 0.55))
            }
        }
    }

    @ViewBuilder private func facts(_ item: HajinGuide.Item) -> some View {
        let lines: [(String, String)] = [
            item.cost == nil ? item.unlock.map { ("mw4.ui.hajin.unlock".localized(), $0.resolved) } : nil,
            item.grid.map { ("mw4.ui.hajin.grid".localized(), $0) },
            item.value.map { ("mw4.ui.hajin.sells_for".localized(), "$\($0.formatted())") },
            item.note.map { ("mw4.ui.hajin.notes".localized(), $0.resolved) },
        ].compactMap { $0 }
        if !lines.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(line.0.uppercased())
                            .font(.caption.weight(.semibold))
                            .tracking(0.6)
                            .foregroundStyle(Color.appInkMuted)
                            .frame(width: 92, alignment: .leading)
                        Text(line.1).font(.subheadline).foregroundStyle(Color.appInk)
                        Spacer(minLength: 0)
                    }
                    .padding(12)
                    if index < lines.count - 1 { Divider().overlay(Color.appInkMuted.opacity(0.2)) }
                }
            }
            .background(panel)
        }
    }

    /// A named place in the item's location text; opens the Tac Map on it.
    @ViewBuilder private func placeChip(_ marker: HajinGuide.Marker) -> some View {
        let label = HStack(spacing: 5) {
            Image(systemName: "map.fill").font(.caption2.weight(.semibold))
            Text(marker.name.resolved).font(.caption.weight(.semibold)).lineLimit(1)
        }
        .foregroundStyle(Color.accentDMZ)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.accentDMZ.opacity(0.15)))
        if let showMarker {
            Button { showMarker(marker) } label: { label }.buttonStyle(.borderless)
        } else {
            NavigationLink { HajinMapScreen(startAt: marker) } label: { label }.buttonStyle(.borderless)
        }
    }

    @ViewBuilder private func mapButton(_ marker: HajinGuide.Marker) -> some View {
        let label = Label("mw4.ui.hajin.show_on_map".localized(), systemImage: "map.fill")
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.accentDMZ.opacity(0.18)))
            .foregroundStyle(Color.accentDMZ)
        if let showMarker {
            Button { showMarker(marker) } label: { label }.buttonStyle(.plain)
        } else {
            NavigationLink { HajinMapScreen(startAt: marker) } label: { label }.buttonStyle(.plain)
        }
    }

    private func usedIn(_ users: [HajinGuide.Item]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            panelTitle("mw4.ui.hajin.used_in".localized())
            VStack(spacing: 0) {
                ForEach(Array(users.enumerated()), id: \.element.id) { index, user in
                    HStack(spacing: 0) {
                    if user.kind == "FOB Upgrade" {
                        let key = "upgrade-\(user.id)"
                        HajinTick(done: store.checked.contains(key), label: user.name.resolved) { store.toggle(key) }
                            .padding(.leading, 12)
                    }
                    HajinItemLink(id: user.id) {
                        HStack(spacing: 12) {
                            HajinItemTile(item: user, size: 40)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(user.name.resolved).font(.subheadline.weight(.medium)).foregroundStyle(Color.appInk)
                                HajinRarityLine(item: user, size: 9)
                            }
                            Spacer()
                            if let qty = user.cost?.first(where: { $0.item == shownId })?.qty {
                                Text("×\(qty)")
                                    .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                                    .foregroundStyle(Color.appInkMuted)
                            }
                            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Color.appInkMuted.opacity(0.6))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                    }
                    }
                    if index < users.count - 1 { Divider().overlay(Color.appInkMuted.opacity(0.2)).padding(.leading, 64) }
                }
            }
            .background(panel)
        }
    }

    /// Rows that mention the item: the boss that drops it, the mission that
    /// rewards it, the level that hands it out.
    private func whereFrom(_ mentions: [(section: HajinGuide.Section, row: HajinGuide.Row)], title: String, inGame: String? = nil, places: [HajinGuide.Marker] = []) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            panelTitle(title)
            VStack(alignment: .leading, spacing: 0) {
                if let inGame {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "mappin.and.ellipse")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.accentDMZ)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(inGame).font(.subheadline.weight(.semibold)).foregroundStyle(Color.appInk)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("mw4.ui.hajin.found_in_game".localized()).font(.caption).foregroundStyle(Color.appInkMuted)
                            if !places.isEmpty {
                                HajinWrap(spacing: 6) {
                                    ForEach(places, id: \.id) { placeChip($0) }
                                }
                                .padding(.top, 6)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(12)
                    if !mentions.isEmpty { Divider().overlay(Color.appInkMuted.opacity(0.2)) }
                }
                ForEach(Array(mentions.enumerated()), id: \.offset) { index, mention in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: mention.section.symbol)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.accentDMZ)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(mention.row.title.resolved).font(.subheadline.weight(.semibold)).foregroundStyle(Color.appInk)
                                Spacer()
                                if let value = mention.row.value { HajinValueBadge(text: value.resolved) }
                            }
                            Text(mention.section.title.resolved).font(.caption).foregroundStyle(Color.appInkMuted)
                        }
                    }
                    .padding(12)
                    if index < mentions.count - 1 { Divider().overlay(Color.appInkMuted.opacity(0.2)) }
                }
            }
            .background(panel)
        }
    }

    /// Every tier of the upgrade side by side, this one lit; tap another to
    /// jump to it. Ticked tiers show a check. More than five (the Bank's
    /// nine) scroll sideways at a fixed width, onto the one shown.
    private func tierStrip(_ item: HajinGuide.Item, _ tiers: [HajinGuide.Item]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            panelTitle("mw4.ui.hajin.tiers".localized())
            if tiers.count > 5 {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) { tierTiles(item, tiers, width: 64) }
                    }
                    .onAppear { proxy.scrollTo(item.id, anchor: .center) }
                    .onChange(of: item.id) { id in withAnimation(.snappy) { proxy.scrollTo(id, anchor: .center) } }
                }
            } else {
                HStack(spacing: 8) { tierTiles(item, tiers, width: nil) }
            }
        }
    }

    @ViewBuilder private func tierTiles(_ item: HajinGuide.Item, _ tiers: [HajinGuide.Item], width: CGFloat?) -> some View {
        ForEach(tiers) { tier in
            let current = tier.id == item.id
            let done = store.checked.contains("upgrade-\(tier.id)")
            let label = VStack(spacing: 3) {
                HStack(spacing: 4) {
                    Text(Self.roman(tier.tier ?? 1))
                        .font(.hitmarker(18))
                    if done { Image(systemName: "checkmark.circle.fill").font(.caption) }
                }
                .foregroundStyle(current ? Color.black.opacity(0.85) : Color.appInk)
                // "$500K" rather than "$500,000", so nine tiers still read
                Text(tier.cash.map { "$" + $0.formatted(.number.notation(.compactName)) } ?? "–")
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(current ? Color.black.opacity(0.7) : Color.appInkMuted)
            }
            .frame(width: width)
            .frame(maxWidth: width == nil ? .infinity : nil)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(current ? Color.accentDMZ : Color.appSurface)
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.appInkMuted.opacity(current ? 0 : 0.25), lineWidth: 1))
            )
            Group {
                if current {
                    label
                } else {
                    Button {
                        Haptics.step()
                        withAnimation(.snappy) { tierShown = tier.id == id ? nil : tier.id }
                    } label: { label }
                    .buttonStyle(.borderless)
                }
            }
            .id(tier.id)
        }
    }

    private static func roman(_ n: Int) -> String {
        HajinUpgradeFamilyCard.roman(n)
    }

    private func panelTitle(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.caption.weight(.heavy))
            .tracking(1.2)
            .foregroundStyle(Color.appInkMuted)
    }

    /// The panel, outlined in a colour when it has something to say.
    private func statusPanel(_ tint: Color?) -> some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(tint?.opacity(0.08) ?? Color.appSurface.opacity(0.9))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(tint?.opacity(0.7) ?? Color.appInkMuted.opacity(0.2), lineWidth: 1))
    }

    private var panel: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color.appSurface.opacity(0.9))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.appInkMuted.opacity(0.2), lineWidth: 1))
    }
}

// MARK: - Mentions and weapons

/// The items a plain row mentions, as tappable chips: a boss's drop, a
/// mission's reward, a level's unlocks.
struct HajinLinkChips: View {
    let ids: [String]
    /// Optional amount per id, shown as "×20" on the chip.
    var amounts: [String: Int] = [:]
    @EnvironmentObject private var store: HajinStore

    var body: some View {
        HajinWrap(spacing: 6) {
                ForEach(ids, id: \.self) { id in
                    if let item = store.guide?.item(id) {
                        HajinItemLink(id: id) {
                            HStack(spacing: 6) {
                                HajinItemTile(item: item, size: 22)
                                Text(item.name.resolved)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Color.appInk)
                                    .lineLimit(1)
                                if let qty = amounts[id] {
                                    Text("×\(qty)")
                                        .font(.caption.weight(.bold).monospacedDigit())
                                        .foregroundStyle(Color.appInkMuted)
                                }
                            }
                            .padding(3)
                            .padding(.trailing, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 6).fill(Color.appSurface2)
                                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(HajinRarity.color(item.rarity).opacity(0.5), lineWidth: 1))
                            )
                        }
                    }
                }
        }
    }
}

/// A Gunsmith price with the weapon's picture from the camo catalog,
/// linking to that weapon's camos.
struct HajinWeaponRow: View {
    let row: HajinGuide.Row
    let weaponId: Int
    @EnvironmentObject private var viewModel: TrackerViewModel
    @EnvironmentObject private var store: HajinStore

    /// Starter weapons are on sale from the start; the rest need their
    /// Manual extracted once.
    private var needsManual: Bool { !(row.subtitle?.values["en"]?.hasPrefix("Starter") ?? false) }
    private var manualKey: String { "manual-\(weaponId)" }
    private var manualDone: Bool { store.checked.contains(manualKey) }

    var body: some View {
        let weapon = viewModel.weapon(id: weaponId)
        let content = HStack(spacing: 12) {
            if needsManual {
                HajinTick(done: manualDone, label: row.title.resolved) { store.toggle(manualKey) }
            }
            WeaponThumbnail(urlString: weapon?.imageURL, size: 72, inset: 6)
                .frame(width: 96, height: 54)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.appSurface2))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 3) {
                Text(row.title.resolved)
                    .font(.hitmarker(15))
                    .foregroundStyle(Color.appInk)
                if needsManual {
                    Text(manualDone ? "mw4.ui.hajin.manual_done".localized() : "mw4.ui.hajin.manual_needed".localized())
                        .font(.system(size: 11, weight: .bold))
                        .textCase(.uppercase)
                        .foregroundStyle(manualDone ? Color.accentDMZ : Color.appInkMuted)
                } else if let subtitle = row.subtitle {
                    Text(subtitle.resolved)
                        .font(.system(size: 11, weight: .bold))
                        .textCase(.uppercase)
                        .foregroundStyle(Color.appInkMuted)
                }
            }
            Spacer(minLength: 6)
            if let value = row.value { HajinValueBadge(text: value.resolved) }
        }
        .padding(.vertical, 2)
        if let weapon {
            NavigationLink { WeaponDetailView(mode: .dmz, weapon: weapon) } label: { content }
        } else {
            content
        }
    }
}

/// One FOB upgrade family as a single card: I / II / III tabs (the same
/// segmented control as the weapon screen), the picked tier's cost, and
/// its tick. Opens on the first tier not yet ticked.
struct HajinUpgradeFamilyCard: View {
    let tiers: [HajinGuide.Item]
    @EnvironmentObject private var store: HajinStore
    @State private var picked: String?

    private var shown: HajinGuide.Item {
        tiers.first { $0.id == picked }
            ?? tiers.first { !store.checked.contains("upgrade-\($0.id)") }
            ?? tiers.last!
    }

    static func roman(_ n: Int) -> String {
        let all = ["I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX"]
        return all.indices.contains(n - 1) ? all[n - 1] : "\(n)"
    }

    var body: some View {
        let item = shown
        let key = "upgrade-\(item.id)"
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                HajinItemTile(item: item, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.family ?? item.name.resolved).font(.hitmarker(15)).foregroundStyle(Color.appInk)
                    Text("\(tiers.filter { store.checked.contains("upgrade-\($0.id)") }.count)/\(tiers.count) " + "mw4.ui.hajin.tiers".localized())
                        .font(.system(size: 11, weight: .bold))
                        .textCase(.uppercase)
                        .foregroundStyle(Color.appInkMuted)
                }
                Spacer(minLength: 0)
            }
            if tiers.count > 5 {
                // Too many for a segmented control (the Bank's nine): chips
                // that scroll, onto the one shown
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(tiers) { tier in
                                let on = tier.id == item.id
                                Button {
                                    Haptics.step()
                                    withAnimation(.snappy) { picked = tier.id }
                                } label: {
                                    Text((store.checked.contains("upgrade-\(tier.id)") ? "✓ " : "") + Self.roman(tier.tier ?? 1))
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(on ? Color.black.opacity(0.85) : Color.appInk)
                                        .frame(minWidth: 34)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(Capsule().fill(on ? Color.accentDMZ : Color.appSurface2))
                                }
                                .buttonStyle(.plain)
                                .id(tier.id)
                            }
                        }
                    }
                    .onAppear { proxy.scrollTo(item.id, anchor: .center) }
                    .onChange(of: item.id) { id in withAnimation(.snappy) { proxy.scrollTo(id, anchor: .center) } }
                }
            } else {
                Picker("mw4.ui.hajin.tiers".localized(), selection: Binding(get: { item.id }, set: { Haptics.step(); picked = $0 })) {
                    ForEach(tiers) { tier in
                        Text((store.checked.contains("upgrade-\(tier.id)") ? "✓ " : "") + Self.roman(tier.tier ?? 1)).tag(tier.id)
                    }
                }
                .pickerStyle(.segmented)
            }
            HStack(alignment: .top, spacing: 10) {
                HajinTick(done: store.checked.contains(key), label: item.name.resolved) {
                    store.toggle(key)
                    // Ticked: move on to the next tier still to print
                    if store.checked.contains(key) { withAnimation(.snappy) { picked = nil } }
                }
                HajinItemLink(id: item.id) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(item.name.resolved).font(.subheadline.weight(.semibold)).foregroundStyle(Color.appInk)
                            Spacer(minLength: 6)
                            if let cash = item.cash { HajinValueBadge(text: "$\(cash.formatted())") }
                            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Color.appInkMuted.opacity(0.6))
                        }
                        if let cost = item.cost, !cost.isEmpty {
                            HStack(spacing: 8) {
                                ForEach(cost, id: \.item) { part in
                                    let ingredient = store.guide?.item(part.item)
                                    HStack(spacing: 3) {
                                        HajinItemTile(item: ingredient, size: 22)
                                        Text("\(part.qty)").font(.system(size: 12, weight: .semibold, design: .monospaced)).foregroundStyle(Color.appInk)
                                    }
                                }
                            }
                        } else if let note = item.note {
                            Text(note.resolved).font(.caption).foregroundStyle(Color.appInkMuted)
                        }
                        if let effect = item.effect {
                            Text(effect.resolved).font(.caption).italic().foregroundStyle(Color.appInkMuted)
                        }
                    }
                }
            }
        }
    }
}
