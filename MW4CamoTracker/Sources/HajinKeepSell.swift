import SwiftUI

/// Whether a looted item is worth keeping, worked out from every known
/// recipe and FOB upgrade that needs it, minus the upgrades the player has
/// ticked as done.
struct HajinVerdict {
    enum Kind: Hashable { case keep, crafting, sell, use, resource }

    let kind: Kind
    /// Unfinished upgrades that need it, with amounts.
    let upgrades: [(item: HajinGuide.Item, qty: Int)]
    /// Recipes that use it.
    let recipes: [(item: HajinGuide.Item, qty: Int)]
    let value: Int?
    let itemKind: String

    init(item: HajinGuide.Item, guide: HajinGuide, done: Set<String>) {
        let users = guide.usedIn(item.id).map { user in (item: user, qty: user.cost?.first { $0.item == item.id }?.qty ?? 0) }
        upgrades = users.filter { $0.item.kind == "FOB Upgrade" && !done.contains("upgrade-\($0.item.id)") }
        recipes = users.filter { $0.item.kind != "FOB Upgrade" }
        value = item.value
        itemKind = item.kind
        if item.kind == "Resource" {
            kind = .resource
        } else if !upgrades.isEmpty {
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

    var color: Color {
        switch kind {
        case .keep: return Color(red: 0.96, green: 0.66, blue: 0.24)
        case .crafting: return Color(red: 0.36, green: 0.62, blue: 0.98)
        case .sell: return Color(red: 0.42, green: 0.80, blue: 0.36)
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

    /// One line on why: what needs it, or what it sells for.
    var reason: String {
        switch kind {
        case .keep:
            let total = upgrades.reduce(0) { $0 + $1.qty }
            let names = upgrades.map { "\($0.item.name.resolved) ×\($0.qty)" }.joined(separator: ", ")
            return String(format: "mw4.ui.keep.keep_reason".localized(), total, names)
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
                Text(verdict.reason)
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
                               amounts: verdict.kind == .keep ? Dictionary(needs.map { ($0.item.id, $0.qty) }, uniquingKeysWith: +) : [:])
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

/// Search anything you've looted and see whether to keep or sell it.
struct HajinKeepSellView: View {
    @EnvironmentObject private var store: HajinStore
    @State private var query = ""
    @State private var width: CGFloat = 0

    /// Lootables grouped by verdict, Keep first. Gear and keys only show
    /// when searched for: there's nothing to decide about them.
    fileprivate func groups(_ guide: HajinGuide) -> [(kind: HajinVerdict.Kind, rows: [(HajinGuide.Item, HajinVerdict)])] {
        let needle = query.lowercased()
        let rows = (guide.items ?? [])
            .filter { !["Resource", "FOB Upgrade"].contains($0.kind) }
            .filter { needle.isEmpty || $0.name.resolved.lowercased().contains(needle) }
            .sorted { $0.name.resolved < $1.name.resolved }
            .map { ($0, HajinVerdict(item: $0, guide: guide, done: store.checked)) }
            .filter { !needle.isEmpty || $0.1.kind != .use }
        let order: [HajinVerdict.Kind] = [.keep, .crafting, .sell, .use]
        return order.compactMap { kind in
            let matching = rows.filter { $0.1.kind == kind }
            return matching.isEmpty ? nil : (kind, matching)
        }
    }

    var body: some View {
        ZStack {
            AppBackground(accent: .accentDMZ)
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
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "mw4.ui.keep.search".localized())
        .navigationTitle("mw4.ui.keep.title".localized())
        .navigationBarTitleDisplayMode(.inline)
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

    private var needs: [(item: HajinGuide.Item, qty: Int)] {
        verdict.kind == .keep ? verdict.upgrades : verdict.kind == .crafting ? verdict.recipes : []
    }

    private var line: String {
        switch verdict.kind {
        case .keep:
            return String(format: "mw4.ui.keep.keep_short".localized(), verdict.upgrades.reduce(0) { $0 + $1.qty })
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
                               amounts: verdict.kind == .keep ? Dictionary(needs.map { ($0.item.id, $0.qty) }, uniquingKeysWith: +) : [:])
                    .padding(.leading, 56)
            }
        }
        .padding(.vertical, 2)
    }
}

/// The guide's entry to the tool, styled like a section row.
struct HajinKeepSellEntry: View {
    var body: some View {
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
        }
        .padding(.vertical, 4)
    }
}
