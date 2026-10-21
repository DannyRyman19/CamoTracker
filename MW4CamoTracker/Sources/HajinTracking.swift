import SwiftUI

/// − count + for one stash entry, tap the number to type it.
struct HajinStashStepper: View {
    let id: String
    @EnvironmentObject private var store: HajinStore
    @State private var entering = false
    @State private var text = ""

    var body: some View {
        let count = store.count(of: id)
        HStack(spacing: 8) {
            stepButton(systemName: "minus", enabled: count > 0, size: 24, accent: .accentDMZ) { store.setCount(count - 1, of: id) }
            Button {
                text = count > 0 ? "\(count)" : ""
                entering = true
            } label: {
                Text("\(count)")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(count > 0 ? Color.accentDMZ : Color.appInkMuted)
                    .contentTransition(.numericText())
                    .frame(minWidth: 40)
            }
            .buttonStyle(.borderless)
            stepButton(systemName: "plus", enabled: true, size: 24, accent: .accentDMZ) { store.setCount(count + 1, of: id) }
        }
        .alert(store.guide?.item(id)?.name.resolved ?? "", isPresented: $entering) {
            TextField("0", text: $text).keyboardType(.numberPad)
            Button("mw4.ui.hajin.save".localized()) { store.setCount(Int(text) ?? 0, of: id) }
            Button("mw4.ui.hajin.cancel".localized(), role: .cancel) {}
        }
    }
}

/// Track button for a recipe or upgrade's screen: up to five at once.
struct HajinTrackButton: View {
    let id: String
    @EnvironmentObject private var store: HajinStore

    var body: some View {
        let on = store.isTracked(id)
        let full = !on && store.tracked.count >= HajinStore.maxTracked
        Button {
            Haptics.step()
            store.toggleTracked(id)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: on ? "scope" : "plus.viewfinder")
                Text(on ? "mw4.ui.hajin.tracking".localized()
                        : full ? String(format: "mw4.ui.hajin.track_full".localized(), HajinStore.maxTracked)
                        : "mw4.ui.hajin.track".localized())
                Spacer()
                Text("\(store.tracked.count)/\(HajinStore.maxTracked)")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(on ? Color.black.opacity(0.7) : Color.appInkMuted)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(on ? Color.black.opacity(0.85) : full ? Color.appInkMuted : Color.appInk)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 8).fill(on ? Color.accentDMZ : Color.appSurface)
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.appInkMuted.opacity(on ? 0 : 0.25), lineWidth: 1))
            )
        }
        .buttonStyle(.borderless)
        .disabled(full)
    }
}

/// The Hajin home card: everything tracked, how close each is with what's
/// in the stash, and what to look out for on the next drop.
struct HajinTrackingCard: View {
    @EnvironmentObject private var store: HajinStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("mw4.ui.hajin.tracking".localized()).font(.hitmarker(16)).foregroundStyle(Color.appInk)
                Spacer()
                Text("\(store.tracked.count)/\(HajinStore.maxTracked)")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.appInkMuted)
            }
            if let guide = store.guide {
                if store.tracked.isEmpty {
                    Text("mw4.ui.hajin.tracking_empty".localized())
                        .font(.caption)
                        .foregroundStyle(Color.appInkMuted)
                } else {
                    ForEach(store.tracked, id: \.self) { id in
                        if let item = guide.item(id) { TrackedRow(item: item) }
                    }
                    let short = store.shortfall(in: guide)
                    if short.isEmpty {
                        Label("mw4.ui.hajin.all_ready".localized(), systemImage: "checkmark.circle.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color(red: 0.42, green: 0.80, blue: 0.36))
                    } else {
                        Text("mw4.ui.hajin.look_out_for".localized().uppercased())
                            .font(.system(size: 11, weight: .bold))
                            .tracking(0.8)
                            .foregroundStyle(Color.appInkMuted)
                            .padding(.top, 2)
                        HajinLinkChips(ids: short.map(\.item.id), amounts: Dictionary(short.map { ($0.item.id, $0.missing) }, uniquingKeysWith: +))
                    }
                }
            }
        }
    }
}

/// One tracked item: its name (opens it), each ingredient as have/need
/// (green once covered), and a remove button.
private struct TrackedRow: View {
    let item: HajinGuide.Item
    @EnvironmentObject private var store: HajinStore

    var body: some View {
        let cost = item.cost ?? []
        let ready = !cost.isEmpty && cost.allSatisfy { store.count(of: $0.item) >= $0.qty }
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                HajinItemLink(id: item.id) {
                    HStack(spacing: 10) {
                        HajinItemTile(item: item, size: 32)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.name.resolved).font(.subheadline.weight(.semibold)).foregroundStyle(Color.appInk)
                            if ready { HajinCanPrintTag() }
                        }
                        Spacer(minLength: 0)
                    }
                }
                Button {
                    Haptics.step()
                    store.toggleTracked(item.id)
                } label: {
                    Image(systemName: "xmark.circle.fill").font(.body).symbolRenderingMode(.hierarchical).foregroundStyle(Color.appInkMuted)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("mw4.ui.hajin.untrack".localized())
            }
            HStack(spacing: 10) {
                ForEach(cost, id: \.item) { part in
                    let have = store.count(of: part.item)
                    let enough = have >= part.qty
                    HajinItemLink(id: part.item) {
                        HStack(spacing: 3) {
                            HajinItemTile(item: store.guide?.item(part.item), size: 22)
                            Text("\(min(have, part.qty))/\(part.qty)")
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundStyle(enough ? Color(red: 0.42, green: 0.80, blue: 0.36) : Color.appInk)
                        }
                    }
                }
            }
            .padding(.leading, 42)
        }
        .padding(.vertical, 2)
    }
}

/// Every ingredient and resource with a stepper: what the player has.
struct HajinStashView: View {
    @EnvironmentObject private var store: HajinStore
    @State private var query = ""

    private var groups: [(title: String, items: [HajinGuide.Item])] {
        guard let guide = store.guide else { return [] }
        let needle = query.lowercased()
        let all = (guide.items ?? []).filter { ["Resource", "Ingredient"].contains($0.kind) && $0.id != "commanders" }
            .filter { needle.isEmpty || $0.name.resolved.lowercased().contains(needle) }
        // Needed for something tracked first, then resources, then the rest
        let short = Set(store.shortfall(in: guide).map(\.item.id))
        let neededIds = Set(store.tracked.flatMap { guide.item($0)?.cost?.map(\.item) ?? [] })
        let needed = all.filter { neededIds.contains($0.id) }.sorted { (short.contains($0.id) ? 0 : 1, $0.name.resolved) < (short.contains($1.id) ? 0 : 1, $1.name.resolved) }
        let resources = all.filter { $0.kind == "Resource" && !neededIds.contains($0.id) }
        let rest = all.filter { $0.kind != "Resource" && !neededIds.contains($0.id) }.sorted { $0.name.resolved < $1.name.resolved }
        return [("mw4.ui.hajin.for_tracked".localized(), needed), ("mw4.ui.hajin.resources".localized(), resources), ("mw4.ui.hajin.ingredients".localized(), rest)]
            .filter { !$0.items.isEmpty }
    }

    var body: some View {
        ZStack {
            AppBackground(accent: .accentDMZ)
            List {
                if query.isEmpty {
                    Text("mw4.ui.hajin.stash_intro".localized())
                        .font(.subheadline)
                        .foregroundStyle(Color.appInkMuted)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
                ForEach(groups, id: \.title) { group in
                    HajinHeading(title: group.title)
                    ForEach(group.items) { item in
                        HStack(spacing: 12) {
                            HajinItemLink(id: item.id) {
                                HStack(spacing: 12) {
                                    HajinItemTile(item: item, size: 36)
                                    Text(item.name.resolved).font(.hitmarker(15)).foregroundStyle(Color.appInk)
                                    Spacer(minLength: 0)
                                }
                            }
                            HajinStashStepper(id: item.id)
                        }
                        .hajinCard()
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .listStyle(.plain)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "mw4.ui.hajin.search_section".localized())
        }
        .navigationTitle("mw4.ui.hajin.stash".localized())
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// The guide's entry to My stash, styled like the other tool rows.
struct HajinStashEntry: View {
    @EnvironmentObject private var store: HajinStore

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "shippingbox.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(Circle().fill(Color.accentDMZ))
            VStack(alignment: .leading, spacing: 2) {
                Text("mw4.ui.hajin.stash".localized()).font(.hitmarker(16)).foregroundStyle(Color.appInk)
                Text("mw4.ui.hajin.stash_subtitle".localized()).font(.caption).foregroundStyle(Color.appInkMuted)
            }
            Spacer()
            Text("\(store.stash.values.reduce(0, +))")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.appInkMuted)
        }
    }
}
