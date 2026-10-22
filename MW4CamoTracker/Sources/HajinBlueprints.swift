import SwiftUI

extension HajinStore {
    static func blueprintKey(_ id: String) -> String { "blueprint-\(id)" }
    func hasBlueprint(_ id: String) -> Bool { checked.contains(Self.blueprintKey(id)) }
    /// Every recipe you find in Hajin, printer tab by printer tab.
    var blueprints: [HajinGuide.Item] { (guide?.items ?? []).filter { $0.blueprint == true } }
}

/// "Still to find": every blueprint (a recipe found in Hajin and extracted),
/// to tick off as they're found. Grouped by printer tab, still-to-find
/// first; found ones drop to the bottom of their tab.
struct HajinBlueprintsView: View {
    /// Set when shown inside the iPad guide panel, which has its own search
    /// field and header.
    var embeddedQuery: String? = nil
    @EnvironmentObject private var store: HajinStore
    @State private var ownQuery = ""
    @AppStorage("mw4_hajin_blueprints_hide_found") private var hideFound = false
    private var query: String { embeddedQuery ?? ownQuery }

    private var groups: [(kind: String, items: [HajinGuide.Item])] {
        let needle = query.lowercased()
        let all = store.blueprints.filter { needle.isEmpty || $0.name.resolved.lowercased().contains(needle) }
            .filter { !hideFound || !store.hasBlueprint($0.id) }
        var order: [String] = []
        for item in all where !order.contains(item.kind) { order.append(item.kind) }
        return order.map { kind in
            (kind, all.filter { $0.kind == kind }.sorted {
                (store.hasBlueprint($0.id) ? 1 : 0, $0.name.resolved) < (store.hasBlueprint($1.id) ? 1 : 0, $1.name.resolved)
            })
        }
    }

    var body: some View {
        if embeddedQuery != nil {
            content
        } else {
            content
                .searchable(text: $ownQuery, placement: .navigationBarDrawer(displayMode: .always), prompt: "mw4.ui.hajin.search_section".localized())
                .navigationTitle("mw4.ui.hajin.blueprints".localized())
                .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var content: some View {
        let all = store.blueprints
        let found = all.filter { store.hasBlueprint($0.id) }.count
        return ZStack {
            if embeddedQuery == nil { AppBackground(accent: .accentDMZ) }
            List {
                VStack(alignment: .leading, spacing: 10) {
                    Text("mw4.ui.hajin.blueprints_intro".localized())
                        .font(.subheadline)
                        .foregroundStyle(Color.appInkMuted)
                    HStack {
                        Text(String(format: "mw4.ui.hajin.blueprints_progress".localized(), found, all.count))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.appInk)
                        Spacer()
                        Toggle("mw4.ui.hajin.blueprints_hide".localized(), isOn: $hideFound)
                            .toggleStyle(.button)
                            .font(.caption.weight(.semibold))
                            .tint(.accentDMZ)
                    }
                    ProgressBar(fraction: all.isEmpty ? 0 : Double(found) / Double(all.count), accent: .accentDMZ)
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                ForEach(groups, id: \.kind) { group in
                    let have = group.items.filter { store.hasBlueprint($0.id) }.count
                    HajinHeading(title: "\(group.kind)  \(have)/\(store.blueprints.filter { $0.kind == group.kind }.count)")
                    ForEach(group.items) { item in
                        HajinBlueprintRow(item: item).hajinCard()
                    }
                }
                if groups.isEmpty && hideFound && found == all.count && !all.isEmpty {
                    Label("mw4.ui.hajin.blueprints_all".localized(), systemImage: "checkmark.seal.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(HajinStore.printableGreen)
                        .listRowBackground(Color.clear)
                }
            }
            .scrollContentBackground(.hidden)
            .listStyle(.plain)
        }
    }
}

/// One blueprint: a tick, its picture and name (opens it), and its cost.
struct HajinBlueprintRow: View {
    let item: HajinGuide.Item
    @EnvironmentObject private var store: HajinStore

    var body: some View {
        let done = store.hasBlueprint(item.id)
        HStack(spacing: 12) {
            HajinTick(done: done, label: item.name.resolved) {
                Haptics.step()
                store.toggle(HajinStore.blueprintKey(item.id))
            }
            HajinItemLink(id: item.id) {
                HStack(spacing: 12) {
                    HajinItemTile(item: item, size: 36)
                        .opacity(done ? 0.55 : 1)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.name.resolved)
                            .font(.hitmarker(15))
                            .foregroundStyle(done ? Color.appInkMuted : Color.appInk)
                            .strikethrough(done, color: Color.appInkMuted)
                            .multilineTextAlignment(.leading)
                        if let rarity = item.rarity {
                            Text(rarity).font(.caption).foregroundStyle(HajinRarity.color(rarity))
                        }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Color.appInkMuted.opacity(0.6))
                }
            }
        }
        .padding(.vertical, 2)
    }
}

/// The guide's entry to the blueprint list, styled like the other tool rows.
struct HajinBlueprintsEntry: View {
    @EnvironmentObject private var store: HajinStore

    var body: some View {
        let all = store.blueprints
        let found = all.filter { store.hasBlueprint($0.id) }.count
        HStack(spacing: 12) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(Circle().fill(Color.accentDMZ))
            VStack(alignment: .leading, spacing: 2) {
                Text("mw4.ui.hajin.blueprints".localized()).font(.hitmarker(16)).foregroundStyle(Color.appInk)
                Text("mw4.ui.hajin.blueprints_subtitle".localized()).font(.caption).foregroundStyle(Color.appInkMuted)
            }
            Spacer()
            Text("\(found)/\(all.count)")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.appInkMuted)
        }
    }
}
