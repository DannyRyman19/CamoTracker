import SwiftUI

/// Whether a looted item is worth keeping, worked out from every known
/// recipe and FOB upgrade that needs it, and the DMZ Orders that print with
/// it, minus the upgrades and orders the player has ticked as done.
struct HajinVerdict {
    /// Only loot you'd weigh up selling gets a verdict: materials,
    /// and valuables. Loadout items and keys are simply used.
    static func applies(to item: HajinGuide.Item) -> Bool {
        ["Ingredient", "Valuable"].contains(item.kind)
    }

    enum Kind: Hashable { case keep, crafting, sell, use, resource }

    let kind: Kind
    /// Unfinished upgrades that need it, with amounts.
    let upgrades: [(item: HajinGuide.Item, qty: Int)]
    /// Recipes that use it.
    let recipes: [(item: HajinGuide.Item, qty: Int)]
    /// Unticked DMZ Orders that need it, with amounts.
    let orders: [(order: HajinGuide.Row, qty: Int)]
    let value: Int?
    let itemKind: String

    init(item: HajinGuide.Item, guide: HajinGuide, done: Set<String>) {
        let users = guide.usedIn(item.id).map { user in (item: user, qty: user.cost?.first { $0.item == item.id }?.qty ?? 0) }
        upgrades = users.filter { $0.item.kind == "FOB Upgrade" && !done.contains("upgrade-\($0.item.id)") }
        recipes = users.filter { $0.item.kind != "FOB Upgrade" }
        var orders: [(order: HajinGuide.Row, qty: Int)] = []
        for need in guide.orderNeeds(done: done) where need.item == item.id {
            if let i = orders.firstIndex(where: { $0.order == need.order }) { orders[i].qty += need.qty } else { orders.append((need.order, need.qty)) }
        }
        self.orders = orders
        value = item.value
        itemKind = item.kind
        if item.kind == "Resource" {
            kind = .resource
        } else if !upgrades.isEmpty || !orders.isEmpty {
            kind = .keep
        } else if !recipes.isEmpty {
            kind = .crafting
        } else if item.kind == "Key" || !["Ingredient", "Valuable"].contains(item.kind) {
            kind = .use
        } else {
            kind = .sell
        }
    }

    var title: String {
        switch kind {
        case .keep: return "mw4.ui.keep.keep".localized()
        case .crafting: return "mw4.ui.keep.crafting".localized()
        case .sell: return "mw4.ui.keep.sell".localized()
        case .use: return "mw4.ui.keep.use".localized()
        case .resource: return "mw4.ui.keep.resource".localized()
        }
    }

    static let sellColor = Color(red: 0.42, green: 0.80, blue: 0.36)

    var color: Color {
        switch kind {
        case .keep: return Color(red: 0.96, green: 0.66, blue: 0.24)
        case .crafting: return Color(red: 0.36, green: 0.62, blue: 0.98)
        case .sell: return Self.sellColor
        case .use, .resource: return Color(white: 0.7)
        }
    }

    var symbol: String {
        switch kind {
        case .keep: return "lock.fill"
        case .crafting: return "printer.fill"
        case .sell: return "dollarsign.circle.fill"
        case .use: return "hand.point.up.left.fill"
        case .resource: return "arrow.3.trianglepath"
        }
    }

    /// The banner's line when the chips below it name what needs the item:
    /// for a Keep, how many are needed against how many the stash has.
    func summary(have: Int) -> String {
        switch kind {
        case .keep:
            let total = upgrades.reduce(0) { $0 + $1.qty } + orders.reduce(0) { $0 + $1.qty }
            if have >= total { return String(format: "mw4.ui.keep.keep_covered".localized(), total, have) }
            return String(format: "mw4.ui.keep.keep_left".localized(), total, have, total - have)
        case .crafting: return "mw4.ui.keep.crafting_short".localized()
        default: return reason
        }
    }

    /// One line on why: what needs it, or what it sells for.
    var reason: String {
        switch kind {
        case .keep:
            var lines: [String] = []
            if !upgrades.isEmpty {
                let total = upgrades.reduce(0) { $0 + $1.qty }
                let names = upgrades.map { "\($0.item.name.resolved) ×\($0.qty)" }.joined(separator: ", ")
                lines.append(String(format: "mw4.ui.keep.keep_reason".localized(), total, names))
            }
            if !orders.isEmpty {
                let total = orders.reduce(0) { $0 + $1.qty }
                let names = orders.map { "\($0.order.title.resolved) ×\($0.qty)" }.joined(separator: ", ")
                lines.append(String(format: "mw4.ui.keep.orders_reason".localized(), total, names))
            }
            return lines.joined(separator: " ")
        case .crafting:
            return String(format: "mw4.ui.keep.crafting_reason".localized(), recipes.map { $0.item.name.resolved }.joined(separator: ", "))
        case .sell:
            if let value { return String(format: "mw4.ui.keep.sell_reason".localized(), "$\(value.formatted())") }
            return "mw4.ui.keep.sell_reason_novalue".localized()
        case .use:
            switch itemKind {
            case "Key": return "mw4.ui.keep.use_key".localized()
            case "Consumables": return "mw4.ui.keep.use_consumable".localized()
            default: return "mw4.ui.keep.use_reason".localized()
            }
        case .resource: return "mw4.ui.keep.resource_reason".localized()
        }
    }
}

/// The verdict as a coloured banner, for the item screen and search.
struct HajinVerdictBadge: View {
    let verdict: HajinVerdict
    var compact = false
    /// How many the stash holds, for "x needed, you have y".
    var have = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: verdict.symbol)
                .font(compact ? .footnote.weight(.bold) : .title3.weight(.bold))
                .foregroundStyle(verdict.color)
            VStack(alignment: .leading, spacing: 2) {
                if !compact {
                    Text(verdict.title.uppercased())
                        .font(.system(size: 14, weight: .heavy))
                        .tracking(0.8)
                        .foregroundStyle(verdict.color)
                }
                Text(compact ? verdict.reason : verdict.summary(have: have))
                    .font(compact ? .caption : .subheadline)
                    .foregroundStyle(Color.appInk.opacity(0.85))
                    .lineLimit(compact ? 2 : nil)
                    .fixedSize(horizontal: false, vertical: !compact)
            }
            Spacer(minLength: 0)
        }
        // The full banner links straight to what needs the item, across
        // its whole width so the chips wrap inside it
        if !compact {
            let needs = verdict.kind == .keep ? verdict.upgrades : verdict.kind == .crafting ? verdict.recipes : []
            if !needs.isEmpty {
                HajinLinkChips(ids: needs.map(\.item.id),
                               amounts: verdict.kind == .keep ? Dictionary(needs.map { ($0.item.id, $0.qty) }, uniquingKeysWith: +) : [:],
                               arrows: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if verdict.kind == .keep, !verdict.orders.isEmpty {
                HajinOrderChips(orders: verdict.orders)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        }
        .padding(compact ? 0 : 12)
        .background {
            if !compact {
                RoundedRectangle(cornerRadius: 8).fill(verdict.color.opacity(0.12))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(verdict.color.opacity(0.4), lineWidth: 1))
            }
        }
    }
}

extension HajinStore {
    static let spareTrackedKey = "mw4_hajin_spare_tracked"
    static let spareBufferKey = "mw4_hajin_spare_buffer"
    static let spareRecipesKey = "mw4_hajin_spare_recipes"
    static let spareOrdersKey = "mw4_hajin_spare_orders"

    /// What the stash holds beyond what the unfinished FOB upgrades still
    /// need (and, as the player chooses, one print of every recipe they
    /// have, what tracked items need and a buffer of each), with its sell
    /// value: most valuable first.
    func spare() -> (lines: [(item: HajinGuide.Item, count: Int, worth: Int)], total: Int) {
        guard let guide else { return ([], 0) }
        let need = keepNeeds()
        let lines = stash.compactMap { id, have -> (item: HajinGuide.Item, count: Int, worth: Int)? in
            guard let item = guide.item(id), let value = item.value, value > 0 else { return nil }
            let extra = have - (need[id] ?? 0)
            return extra > 0 ? (item, extra, extra * value) : nil
        }
        .sorted { $0.worth > $1.worth }
        return (lines, lines.reduce(0) { $0 + $1.worth })
    }

    /// How many of each item to hold on to, by the Spare to sell options:
    /// what unfinished upgrades need, one print of each recipe the player
    /// has, what tracked items need, and the buffer on each ingredient.
    func keepNeeds() -> [String: Int] {
        guard let guide else { return [:] }
        let keepTracked = UserDefaults.standard.object(forKey: Self.spareTrackedKey) as? Bool ?? true
        let buffer = UserDefaults.standard.integer(forKey: Self.spareBufferKey)
        let keepRecipes = UserDefaults.standard.object(forKey: Self.spareRecipesKey) as? Bool ?? true
        let keepOrders = UserDefaults.standard.object(forKey: Self.spareOrdersKey) as? Bool ?? true
        var need: [String: Int] = [:]
        for line in shoppingList(.upgrades) { need[line.item.id] = line.need }
        // What the DMZ Orders not yet ticked print with or want extracted
        if keepOrders {
            for order in guide.orderNeeds(done: checked) { need[order.item, default: 0] += order.qty }
        }
        // Recipes to keep the makings of: one print of each one the player
        // has (found, at their level, or unlocked by Ingredient Printing)
        var recipes = Set<String>()
        if keepRecipes {
            for item in guide.items ?? [] where item.kind != "FOB Upgrade" && !(item.cost ?? []).isEmpty && hasRecipe(item) {
                recipes.insert(item.id)
            }
        }
        // Tracked upgrades are already in the list above; add tracked recipes
        if keepTracked {
            for id in tracked where guide.item(id)?.kind != "FOB Upgrade" { recipes.insert(id) }
        }
        for id in recipes {
            for part in guide.item(id)?.cost ?? [] { need[part.item, default: 0] += part.qty }
        }
        if buffer > 0 {
            for item in guide.items ?? [] where item.kind == "Ingredient" { need[item.id, default: 0] += buffer }
        }
        return need
    }
}

/// "Spare to sell": the stash's worth beyond what unfinished upgrades need,
/// and the items that make it up.
struct HajinSpareCard: View {
    @EnvironmentObject private var store: HajinStore
    @AppStorage(HajinStore.spareTrackedKey) private var keepTracked = true
    @AppStorage(HajinStore.spareBufferKey) private var buffer = 0
    @AppStorage(HajinStore.spareRecipesKey) private var keepRecipes = true
    @AppStorage(HajinStore.spareOrdersKey) private var keepOrders = true

    var body: some View {
        // Read so the card redraws when either setting changes
        let _ = (keepTracked, buffer, keepRecipes, keepOrders)
        let spare = store.spare()
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Label("mw4.ui.keep.spare_title".localized(), systemImage: "dollarsign.circle.fill")
                    .font(.hitmarker(16))
                    .foregroundStyle(Color.appInk)
                Spacer()
                Text("$\(spare.total.formatted())")
                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                    .foregroundStyle(spare.total > 0 ? Color(red: 0.42, green: 0.80, blue: 0.36) : Color.appInkMuted)
                options
            }
            Text(detail)
                .font(.caption)
                .foregroundStyle(Color.appInkMuted)
            if !spare.lines.isEmpty {
                HajinLinkChips(ids: spare.lines.prefix(8).map(\.item.id),
                               amounts: Dictionary(spare.lines.map { ($0.item.id, $0.count) }, uniquingKeysWith: +))
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.appSurface))
    }

    private var options: some View {
        Menu {
            Toggle("mw4.ui.keep.spare_keep_recipes".localized(), isOn: $keepRecipes)
            Toggle("mw4.ui.keep.spare_keep_tracked".localized(), isOn: $keepTracked)
            Toggle("mw4.ui.keep.spare_keep_orders".localized(), isOn: $keepOrders)
            Picker("mw4.ui.keep.spare_buffer".localized(), selection: $buffer) {
                Text("mw4.ui.keep.spare_buffer_none".localized()).tag(0)
                Text(String(format: "mw4.ui.keep.spare_buffer_n".localized(), 5)).tag(5)
                Text(String(format: "mw4.ui.keep.spare_buffer_n".localized(), 10)).tag(10)
            }
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.accentDMZ)
                .padding(.leading, 6)
        }
        .accessibilityLabel("mw4.ui.keep.spare_options".localized())
    }

    /// What the total leaves out, as set in the options.
    private var detail: String {
        guard !store.stash.isEmpty else { return "mw4.ui.keep.spare_empty".localized() }
        var text = "mw4.ui.keep.spare_detail".localized()
        if keepTracked { text += " " + "mw4.ui.keep.spare_detail_tracked".localized() }
        if keepOrders { text += " " + "mw4.ui.keep.spare_detail_orders".localized() }
        if buffer > 0 { text += " " + String(format: "mw4.ui.keep.spare_detail_buffer".localized(), buffer) }
        return text
    }
}

/// Search anything you've looted and see whether to keep or sell it.
struct HajinKeepSellView: View {
    /// Set when shown inside the iPad guide panel, which has its own search
    /// field and header.
    var embeddedQuery: String? = nil
    @EnvironmentObject private var store: HajinStore
    @State private var ownQuery = ""
    @State private var width: CGFloat = 0
    private var query: String { embeddedQuery ?? ownQuery }

    /// Lootables grouped by verdict, Keep first. Gear and keys only show
    /// when searched for: there's nothing to decide about them.
    fileprivate func groups(_ guide: HajinGuide) -> [(kind: HajinVerdict.Kind, rows: [(HajinGuide.Item, HajinVerdict)])] {
        let needle = query.lowercased()
        let rows = (guide.items ?? [])
            .filter(HajinVerdict.applies)
            .filter { needle.isEmpty || $0.name.resolved.lowercased().contains(needle) }
            .sorted { $0.name.resolved < $1.name.resolved }
            .map { ($0, HajinVerdict(item: $0, guide: guide, done: store.checked)) }

        let order: [HajinVerdict.Kind] = [.keep, .crafting, .sell, .use]
        return order.compactMap { kind in
            let matching = rows.filter { $0.1.kind == kind }
            return matching.isEmpty ? nil : (kind, matching)
        }
    }

    var body: some View {
        if embeddedQuery != nil {
            content
        } else {
            content
                .searchable(text: $ownQuery, placement: .navigationBarDrawer(displayMode: .always), prompt: "mw4.ui.keep.search".localized())
                .navigationTitle("mw4.ui.keep.title".localized())
                .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var content: some View {
        ZStack {
            if embeddedQuery == nil { AppBackground(accent: .accentDMZ) }
            if width >= 700, let guide = store.guide {
                columns(guide)
            } else {
            List {
                if query.isEmpty {
                    Text("mw4.ui.keep.intro".localized())
                        .font(.subheadline)
                        .foregroundStyle(Color.appInkMuted)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    HajinSpareCard()
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
                if let guide = store.guide {
                    ForEach(groups(guide), id: \.kind) { group in
                        if let first = group.rows.first { HajinHeading(title: first.1.title) }
                        ForEach(group.rows, id: \.0.id) { item, verdict in
                            HajinKeepSellRow(item: item, verdict: verdict)
                                .hajinCard()
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .listStyle(.plain)
            }
        }
        .readingWidth($width)
    }
}

extension HajinKeepSellView {
    /// Wide screens: each verdict group as two columns of cards.
    func columns(_ guide: HajinGuide) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if query.isEmpty {
                    Text("mw4.ui.keep.intro".localized()).font(.subheadline).foregroundStyle(Color.appInkMuted)
                        .frame(maxWidth: 720, alignment: .leading)
                    HajinSpareCard().frame(maxWidth: 720, alignment: .leading)
                }
                ForEach(groups(guide), id: \.kind) { group in
                    VStack(alignment: .leading, spacing: 8) {
                        if let first = group.rows.first {
                            Text(first.1.title.uppercased())
                                .font(.caption.weight(.heavy)).tracking(1.2).foregroundStyle(first.1.color)
                        }
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12, alignment: .top), GridItem(.flexible(), spacing: 12, alignment: .top)],
                                  alignment: .leading, spacing: 12) {
                            ForEach(group.rows, id: \.0.id) { item, verdict in
                                HajinKeepSellRow(item: item, verdict: verdict)
                                    .padding(12)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                                    .borderedCard()
                            }
                        }
                    }
                }
            }
            .padding(16)
        }
    }
}

/// One item in Keep or sell: its name links to it, and what needs it
/// (upgrades or recipes) shows as chips that link to those instead of a
/// sentence.
struct HajinKeepSellRow: View {
    let item: HajinGuide.Item
    let verdict: HajinVerdict
    @EnvironmentObject private var store: HajinStore

    private var needs: [(item: HajinGuide.Item, qty: Int)] {
        verdict.kind == .keep ? verdict.upgrades : verdict.kind == .crafting ? verdict.recipes : []
    }

    private var line: String {
        switch verdict.kind {
        case .keep: return verdict.summary(have: store.count(of: item.id))
        case .crafting: return "mw4.ui.keep.crafting_short".localized()
        default: return verdict.reason
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HajinItemLink(id: item.id) {
                HStack(spacing: 12) {
                    HajinItemTile(item: item, size: 44)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.name.resolved).font(.hitmarker(15)).foregroundStyle(Color.appInk)
                            .multilineTextAlignment(.leading)
                        HStack(alignment: .firstTextBaseline, spacing: 5) {
                            Image(systemName: verdict.symbol).font(.caption2.weight(.bold)).foregroundStyle(verdict.color)
                            Text(line).font(.caption).foregroundStyle(Color.appInk.opacity(0.85)).lineLimit(2)
                                .multilineTextAlignment(.leading)
                        }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Color.appInkMuted.opacity(0.6))
                }
            }
            if !needs.isEmpty {
                HajinLinkChips(ids: needs.map(\.item.id),
                               amounts: verdict.kind == .keep ? Dictionary(needs.map { ($0.item.id, $0.qty) }, uniquingKeysWith: +) : [:],
                               arrows: true)
                    .padding(.leading, 56)
            }
            if verdict.kind == .keep, !verdict.orders.isEmpty {
                HajinOrderChips(orders: verdict.orders)
                    .padding(.leading, 56)
            }
        }
        .padding(.vertical, 2)
    }
}

/// The guide's entry to the tool, styled like a section row.
struct HajinKeepSellEntry: View {
    @EnvironmentObject private var store: HajinStore

    var body: some View {
        let spare = store.spare().total
        HStack(spacing: 12) {
            Image(systemName: "arrow.left.arrow.right")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(Circle().fill(Color.accentDMZ))
            VStack(alignment: .leading, spacing: 2) {
                Text("mw4.ui.keep.title".localized()).font(.hitmarker(16)).foregroundStyle(Color.appInk)
                Text("mw4.ui.keep.row_subtitle".localized()).font(.caption).foregroundStyle(Color.appInkMuted)
            }
            Spacer()
            if spare > 0 {
                Text(String(format: "mw4.ui.keep.spare_short".localized(), "$\(spare.formatted())"))
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color(red: 0.42, green: 0.80, blue: 0.36))
            }
        }
        .padding(.vertical, 4)
    }
}
