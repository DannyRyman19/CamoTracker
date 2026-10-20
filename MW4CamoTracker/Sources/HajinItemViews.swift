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

    var body: some View {
        let tint = HajinRarity.color(item?.rarity)
        ZStack {
            LinearGradient(colors: [tint.opacity(0.22), Color.black.opacity(0.55)], startPoint: .bottom, endPoint: .top)
            if let image = item?.image, let url = URL(string: image) {
                AsyncImage(url: url) { phase in
                    if let picture = phase.image { picture.resizable().scaledToFit().padding(size * 0.08) } else { Color.clear }
                }
            } else if let symbol = item?.symbol {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(Color.appInk)
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

/// "◆ EPIC  CONSUMABLES", the game's rarity line.
struct HajinRarityLine: View {
    let item: HajinGuide.Item
    var size: CGFloat = 12

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
            Text(item.kind.uppercased())
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(Color.appInkMuted)
        }
        .tracking(0.6)
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

/// Opens an item's screen, however the current layout navigates.
struct HajinItemLink<Label: View>: View {
    let id: String
    @ViewBuilder let label: () -> Label
    @Environment(\.hajinOpenItem) private var openItem

    var body: some View {
        if let openItem {
            Button { openItem(id) } label: { label().contentShape(Rectangle()) }
                .buttonStyle(.plain)
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
        HajinItemLink(id: item.id) {
            HStack(alignment: .top, spacing: 12) {
                HajinItemTile(item: item, size: 48)
                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(item.name.resolved)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Color.appInk)
                        Spacer(minLength: 6)
                        if let value = row.value {
                            Text(value.resolved)
                                .font(.footnote.weight(.semibold).monospacedDigit())
                                .foregroundStyle(Color.accentDMZ)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(Color.accentDMZ.opacity(0.15)))
                        }
                    }
                    if item.rarity != nil { HajinRarityLine(item: item, size: 10) }
                    if let cost = item.cost, !cost.isEmpty {
                        CostChips(cost: cost, cash: item.cash)
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
            HStack(spacing: 6) {
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
                Text("×\(part.qty)")
                    .font(.system(.body, design: .monospaced).weight(.semibold))
                    .foregroundStyle(Color.appInk)
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
    @EnvironmentObject private var store: HajinStore
    @Environment(\.hajinShowMarker) private var showMarker

    var body: some View {
        ZStack {
            AppBackground(accent: .accentDMZ)
            if let guide = store.guide, let item = guide.item(id) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        header(item)
                        if let cost = item.cost, !cost.isEmpty { recipe(item, cost) }
                        facts(item)
                        if let markerID = item.marker, let marker = guide.marker(markerID) { mapButton(marker) }
                        let users = guide.usedIn(item.id)
                        if !users.isEmpty { usedIn(users) }
                    }
                    .padding(16)
                    .frame(maxWidth: 640, alignment: .leading)
                    .frame(maxWidth: .infinity)
                }
            } else {
                Text("mw4.ui.hajin.no_results".localized()).foregroundStyle(Color.appInkMuted)
            }
        }
        .navigationTitle(store.guide?.item(id)?.name.resolved ?? "")
        .navigationBarTitleDisplayMode(.inline)
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
            if let unlock = item.unlock {
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
                    HajinItemLink(id: user.id) {
                        HStack(spacing: 12) {
                            HajinItemTile(item: user, size: 40)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(user.name.resolved).font(.subheadline.weight(.medium)).foregroundStyle(Color.appInk)
                                HajinRarityLine(item: user, size: 9)
                            }
                            Spacer()
                            if let qty = user.cost?.first(where: { $0.item == id })?.qty {
                                Text("×\(qty)")
                                    .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                                    .foregroundStyle(Color.appInkMuted)
                            }
                            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Color.appInkMuted.opacity(0.6))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                    }
                    if index < users.count - 1 { Divider().overlay(Color.appInkMuted.opacity(0.2)).padding(.leading, 64) }
                }
            }
            .background(panel)
        }
    }

    private func panelTitle(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.caption.weight(.heavy))
            .tracking(1.2)
            .foregroundStyle(Color.appInkMuted)
    }

    private var panel: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color.appSurface.opacity(0.9))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.appInkMuted.opacity(0.2), lineWidth: 1))
    }
}
