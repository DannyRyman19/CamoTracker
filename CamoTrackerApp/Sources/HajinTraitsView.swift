import SwiftUI

/// The trait trees drawn like the game's Traits screen: each tree a tall
/// panel in its colour, rows of nodes (two big fixed choices or three
/// smaller random ones) joined by a spine, the emblem at the foot. Tap a
/// node for what it does. All three side by side when there's room,
/// otherwise one at a time.
struct HajinTraitsView: View {
    let trees: [HajinGuide.TraitTree]
    @EnvironmentObject private var store: HajinStore
    @State private var shownTree = "scout"
    @State private var selected: String?
    @State private var width: CGFloat = 0

    private var wide: Bool { width >= 700 }

    var body: some View {
        VStack(spacing: 0) {
            if !wide {
                Picker("mw4.ui.hajin.traits".localized(), selection: $shownTree) {
                    ForEach(trees) { Text($0.name.resolved).tag($0.id) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            ScrollView {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(trees.filter { wide || $0.id == shownTree }) { tree in
                        TreePanel(tree: tree, selected: $selected)
                            .frame(maxWidth: wide ? 260 : 340)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, selected == nil ? 24 : 190)
            }
        }
        .readingWidth($width)
        .overlay(alignment: .bottom) {
            if let id = selected {
                TraitTooltip(id: id, trees: trees) { selected = nil }
                    .padding(12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.22), value: selected)
        .onAppear {
            #if DEBUG
            if let id = ProcessInfo.processInfo.environment["SS_TRAIT"] { selected = id }
            #endif
        }
    }
}

private struct TreePanel: View {
    let tree: HajinGuide.TraitTree
    @Binding var selected: String?

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(tree.rows.enumerated()), id: \.offset) { index, row in
                let major = row.count == 2
                HStack(spacing: major ? 40 : 14) {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, id in
                        TraitNode(id: id, tree: tree, size: major ? 62 : 44, selected: $selected)
                    }
                }
                .frame(maxWidth: .infinity)
                // Which rows are the same for everyone and which differ per
                // operator, written down the side
                .overlay(alignment: .leading) {
                    Text((major ? "mw4.ui.hajin.trait_fixed" : "mw4.ui.hajin.trait_random").localized().uppercased())
                        .font(.system(size: 8, weight: .heavy))
                        .tracking(0.8)
                        .foregroundStyle(major ? tree.tint : Color.appInkMuted)
                        .fixedSize()
                        .rotationEffect(.degrees(-90))
                        .frame(width: 14)
                        .padding(.leading, 6)
                }
                .padding(.vertical, major ? 12 : 6)
                .padding(.top, index == 0 ? 14 : 0)
                // A gap above each fixed row, like the game's sections
                .padding(.top, major && index > 0 ? 10 : 0)
            }
            if let emblem = tree.emblem {
                TraitNode(id: emblem, tree: tree, size: 50, selected: $selected)
                    .padding(.top, 16)
            }
            Text(tree.name.resolved.uppercased())
                .font(.caption.weight(.heavy))
                .tracking(1.4)
                .foregroundStyle(tree.tint)
                .padding(.top, 10)
                .padding(.bottom, 14)
        }
        .frame(maxWidth: .infinity)
        .background(
            Rectangle().fill(tree.tint.opacity(0.35)).frame(width: 2).padding(.vertical, 40)
        )
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(LinearGradient(colors: [tree.tint.opacity(0.16), tree.tint.opacity(0.04)], startPoint: .top, endPoint: .bottom))
                .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(tree.tint.opacity(0.35), lineWidth: 1))
        )
    }
}

/// One node: the tree's shape, the trait's icon (or "?" for an unrevealed
/// random slot), lit up when selected.
private struct TraitNode: View {
    let id: String?
    let tree: HajinGuide.TraitTree
    let size: CGFloat
    @Binding var selected: String?
    @EnvironmentObject private var store: HajinStore

    private var key: String { id ?? "random-\(tree.id)" }
    private var isSelected: Bool { selected == key }

    var body: some View {
        let trait = id.flatMap { store.guide?.trait($0) }
        Button {
            Haptics.step()
            selected = isSelected ? nil : key
        } label: {
            ZStack {
                shape.fill(isSelected ? tree.tint : Color.black.opacity(0.55))
                shape.stroke(tree.tint.opacity(isSelected ? 1 : 0.55), lineWidth: isSelected ? 2.5 : 1.2)
                if let icon = trait?.icon, let url = URL(string: icon) {
                    CachedAsyncImage(url: url) { phase in
                        if let image = phase.image {
                            image.renderingMode(.template).resizable().scaledToFit()
                        } else {
                            Color.clear
                        }
                    }
                    .foregroundStyle(isSelected ? Color.black.opacity(0.85) : tree.tint)
                    .padding(size * 0.22)
                } else {
                    Text("?")
                        .font(.system(size: size * 0.42, weight: .bold))
                        .foregroundStyle(isSelected ? Color.black.opacity(0.8) : tree.tint.opacity(0.6))
                }
            }
            .frame(width: size, height: size)
            .shadow(color: isSelected ? tree.tint.opacity(0.7) : .clear, radius: 8)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(trait?.name?.resolved ?? "mw4.ui.hajin.random_trait".localized())
    }

    private var shape: AnyShape {
        switch tree.shape {
        case "hexagon": return AnyShape(Hexagon())
        case "square": return AnyShape(RoundedRectangle(cornerRadius: size * 0.14))
        default: return AnyShape(Circle())
        }
    }
}

private struct Hexagon: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        var p = Path()
        p.move(to: CGPoint(x: w * 0.25, y: 0))
        p.addLine(to: CGPoint(x: w * 0.75, y: 0))
        p.addLine(to: CGPoint(x: w, y: h * 0.5))
        p.addLine(to: CGPoint(x: w * 0.75, y: h))
        p.addLine(to: CGPoint(x: w * 0.25, y: h))
        p.addLine(to: CGPoint(x: 0, y: h * 0.5))
        p.closeSubpath()
        return p
    }
}

/// The game-style tooltip for the selected node.
private struct TraitTooltip: View {
    let id: String
    let trees: [HajinGuide.TraitTree]
    let dismiss: () -> Void
    @EnvironmentObject private var store: HajinStore

    var body: some View {
        let random = id.hasPrefix("random-")
        let trait = random ? nil : store.guide?.trait(id)
        let treeID = random ? String(id.dropFirst(7)) : trait?.tree?.lowercased()
        let tree = trees.first { $0.id == treeID }
        let tint = tree?.tint ?? .appInk
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text((trait?.name?.resolved ?? (random ? "mw4.ui.hajin.random_trait".localized() : "mw4.ui.hajin.unknown_trait".localized())).uppercased())
                    .font(.hitmarker(20))
                    .foregroundStyle(Color.appInk)
                if let tree {
                    Text(tree.name.resolved.uppercased())
                        .font(.caption2.weight(.heavy))
                        .tracking(1.2)
                        .foregroundStyle(tint)
                }
                Text(trait?.effect?.resolved ?? (random ? "mw4.ui.hajin.random_trait_detail".localized() : "mw4.ui.hajin.unknown_trait_detail".localized()))
                    .font(.subheadline.italic())
                    .foregroundStyle(Color.appInk.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Button(action: dismiss) {
                Image(systemName: "xmark.circle.fill").font(.title3).symbolRenderingMode(.hierarchical).foregroundStyle(Color.appInkMuted)
            }
            .accessibilityLabel("mw4.ui.hajin.done".localized())
        }
        .padding(16)
        .frame(maxWidth: 520)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.black.opacity(0.88))
                .overlay(alignment: .leading) { Rectangle().fill(tint).frame(width: 3) }
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(tint.opacity(0.45), lineWidth: 1))
                .shadow(color: .black.opacity(0.5), radius: 12, y: 4)
        )
    }
}
