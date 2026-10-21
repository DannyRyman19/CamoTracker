import SwiftUI

/// One ingredient on the shopping list: how many the chosen upgrades need in
/// all, how many the stash has, and which upgrades want it.
struct HajinShoppingLine: Identifiable {
    let item: HajinGuide.Item
    let need: Int
    let have: Int
    let users: [(item: HajinGuide.Item, qty: Int)]

    var id: String { item.id }
    var missing: Int { max(0, need - have) }
}

extension HajinStore {
    enum ShoppingScope: String { case upgrades, tracked }

    /// What the scope still asks for: every FOB upgrade not ticked as done,
    /// or just what's tracked.
    func shoppingTargets(_ scope: ShoppingScope) -> [HajinGuide.Item] {
        guard let guide else { return [] }
        switch scope {
        case .upgrades:
            return (guide.items ?? []).filter { $0.kind == "FOB Upgrade" && !checked.contains("upgrade-\($0.id)") }
        case .tracked:
            return tracked.compactMap { guide.item($0) }
        }
    }

    /// Every ingredient the targets need, added up and set against the stash,
    /// most still to find first.
    func shoppingList(_ scope: ShoppingScope) -> [HajinShoppingLine] {
        guard let guide else { return [] }
        var need: [String: Int] = [:]
        var users: [String: [(item: HajinGuide.Item, qty: Int)]] = [:]
        for target in shoppingTargets(scope) {
            for part in target.cost ?? [] {
                need[part.item, default: 0] += part.qty
                users[part.item, default: []].append((target, part.qty))
            }
        }
        return need.compactMap { id, qty in
            guard let item = guide.item(id) else { return nil }
            return HajinShoppingLine(item: item, need: qty, have: count(of: id), users: users[id] ?? [])
        }
        .sorted { ($0.missing, $1.item.name.resolved) > ($1.missing, $0.item.name.resolved) }
    }
}

/// Everything the unfinished upgrades (or tracked items) still need, minus
/// what's in the stash, with a stepper on each line to update the stash.
struct HajinShoppingListView: View {
    /// Set when shown inside the iPad guide panel, which has its own search
    /// field and header.
    var embeddedQuery: String? = nil
    @EnvironmentObject private var store: HajinStore
    @AppStorage("mw4_hajin_shop_scope") private var scopeRaw = HajinStore.ShoppingScope.upgrades.rawValue
    @State private var ownQuery = ""
    @State private var width: CGFloat = 0
    private var query: String { embeddedQuery ?? ownQuery }
    private var scope: HajinStore.ShoppingScope { HajinStore.ShoppingScope(rawValue: scopeRaw) ?? .upgrades }

    private var lines: [HajinShoppingLine] {
        let needle = query.lowercased()
        return store.shoppingList(scope).filter { needle.isEmpty || $0.item.name.resolved.lowercased().contains(needle) }
    }

    var body: some View {
        if embeddedQuery != nil {
            content
        } else {
            content
                .searchable(text: $ownQuery, placement: .navigationBarDrawer(displayMode: .always), prompt: "mw4.ui.hajin.search_section".localized())
                .navigationTitle("mw4.ui.hajin.shop".localized())
                .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var content: some View {
        let all = lines
        let short = all.filter { $0.missing > 0 }
        let covered = all.filter { $0.missing == 0 }
        return ZStack {
            if embeddedQuery == nil { AppBackground(accent: .accentDMZ) }
            if width >= 700 {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        header(short: short).frame(maxWidth: 720, alignment: .leading)
                        grid("mw4.ui.hajin.shop_still_need".localized(), short)
                        grid("mw4.ui.hajin.shop_got_enough".localized(), covered)
                    }
                    .padding(16)
                }
            } else {
                List {
                    header(short: short)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    if !short.isEmpty {
                        HajinHeading(title: "mw4.ui.hajin.shop_still_need".localized())
                        ForEach(short) { line in HajinShoppingRow(line: line).hajinCard() }
                    }
                    if !covered.isEmpty {
                        HajinHeading(title: "mw4.ui.hajin.shop_got_enough".localized())
                        ForEach(covered) { line in HajinShoppingRow(line: line).hajinCard() }
                    }
                }
                .scrollContentBackground(.hidden)
                .listStyle(.plain)
            }
        }
        .readingWidth($width)
    }

    /// Scope picker, a line on what's counted, and the totals.
    private func header(short: [HajinShoppingLine]) -> some View {
        let targets = store.shoppingTargets(scope)
        let cash = targets.reduce(0) { $0 + ($1.cash ?? 0) }
        return VStack(alignment: .leading, spacing: 12) {
            Picker("", selection: $scopeRaw) {
                Text("mw4.ui.hajin.shop_all".localized()).tag(HajinStore.ShoppingScope.upgrades.rawValue)
                Text("mw4.ui.hajin.shop_tracked".localized()).tag(HajinStore.ShoppingScope.tracked.rawValue)
            }
            .pickerStyle(.segmented)
            Text((scope == .upgrades ? "mw4.ui.hajin.shop_intro" : "mw4.ui.hajin.shop_intro_tracked").localized())
                .font(.subheadline)
                .foregroundStyle(Color.appInkMuted)
            if targets.isEmpty {
                Text((scope == .tracked ? "mw4.ui.hajin.shop_empty_tracked" : "mw4.ui.hajin.build_next_done").localized())
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.appInk)
            } else {
                HStack(spacing: 10) {
                    stat("mw4.ui.hajin.shop_to_find".localized(), "\(short.reduce(0) { $0 + $1.missing })")
                    stat("mw4.ui.hajin.shop_for".localized(), "\(targets.count)")
                    stat("mw4.ui.hajin.shop_cash".localized(), "$\(cash.formatted())")
                }
                if short.isEmpty && query.isEmpty {
                    Label("mw4.ui.hajin.shop_done".localized(), systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(HajinStore.printableGreen)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(size: 18, weight: .bold, design: .monospaced)).foregroundStyle(Color.appInk)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(title.uppercased()).font(.system(size: 10, weight: .bold)).tracking(0.6).foregroundStyle(Color.appInkMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.appSurface))
    }

    @ViewBuilder private func grid(_ title: String, _ lines: [HajinShoppingLine]) -> some View {
        if !lines.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(title.uppercased()).font(.caption.weight(.heavy)).tracking(1.2).foregroundStyle(Color.appInkMuted)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12, alignment: .top), GridItem(.flexible(), spacing: 12, alignment: .top)],
                          alignment: .leading, spacing: 12) {
                    ForEach(lines) { line in
                        HajinShoppingRow(line: line)
                            .padding(12)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            .borderedCard()
                    }
                }
            }
        }
    }
}

/// One shopping line: the ingredient (opens it), have/need with a bar, a
/// stash stepper, and the upgrades that want it as chips.
struct HajinShoppingRow: View {
    let line: HajinShoppingLine

    var body: some View {
        let done = line.missing == 0
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                HajinItemLink(id: line.item.id) {
                    HStack(spacing: 12) {
                        HajinItemTile(item: line.item, size: 36)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(line.item.name.resolved).font(.hitmarker(15)).foregroundStyle(Color.appInk)
                                .multilineTextAlignment(.leading)
                            Text(done ? String(format: "mw4.ui.hajin.shop_have".localized(), line.have, line.need)
                                      : String(format: "mw4.ui.hajin.shop_missing".localized(), line.missing, line.need))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(done ? HajinStore.printableGreen : Color.accentDMZ)
                        }
                        Spacer(minLength: 0)
                    }
                }
                HajinStashStepper(id: line.item.id)
            }
            ProgressBar(fraction: line.need == 0 ? 1 : min(1, Double(line.have) / Double(line.need)),
                        accent: done ? HajinStore.printableGreen : .accentDMZ)
                .padding(.leading, 48)
            HajinLinkChips(ids: line.users.map(\.item.id),
                           amounts: Dictionary(line.users.map { ($0.item.id, $0.qty) }, uniquingKeysWith: +))
                .padding(.leading, 48)
        }
        .padding(.vertical, 2)
    }
}

/// The guide's entry to the shopping list, styled like the other tool rows.
struct HajinShoppingEntry: View {
    @EnvironmentObject private var store: HajinStore
    @AppStorage("mw4_hajin_shop_scope") private var scopeRaw = HajinStore.ShoppingScope.upgrades.rawValue

    var body: some View {
        let missing = store.shoppingList(HajinStore.ShoppingScope(rawValue: scopeRaw) ?? .upgrades).reduce(0) { $0 + $1.missing }
        HStack(spacing: 12) {
            Image(systemName: "list.bullet.clipboard.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(Circle().fill(Color.accentDMZ))
            VStack(alignment: .leading, spacing: 2) {
                Text("mw4.ui.hajin.shop".localized()).font(.hitmarker(16)).foregroundStyle(Color.appInk)
                Text("mw4.ui.hajin.shop_subtitle".localized()).font(.caption).foregroundStyle(Color.appInkMuted)
            }
            Spacer()
            if missing > 0 {
                Text("\(missing)")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.appInkMuted)
            }
        }
    }
}
